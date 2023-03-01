//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSAccountManager.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "HTTPUtils.h"
#import "OWSError.h"
#import "OWSRequestFactory.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "TSPreKeyManager.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSNotificationName const NSNotificationNameRegistrationStateDidChange = @"NSNotificationNameRegistrationStateDidChange";
NSNotificationName const NSNotificationNameOnboardingStateDidChange = @"NSNotificationNameOnboardingStateDidChange";
NSString *const TSRemoteAttestationAuthErrorKey = @"TSRemoteAttestationAuth";
NSNotificationName const NSNotificationNameLocalNumberDidChange = @"NSNotificationNameLocalNumberDidChange";

NSString *const TSAccountManager_RegisteredNumberKey = @"TSStorageRegisteredNumberKey";
NSString *const TSAccountManager_RegistrationDateKey = @"TSAccountManager_RegistrationDateKey";
NSString *const TSAccountManager_RegisteredUUIDKey = @"TSStorageRegisteredUUIDKey";
NSString *const TSAccountManager_RegisteredPNIKey = @"TSAccountManager_RegisteredPNIKey";
NSString *const TSAccountManager_IsDeregisteredKey = @"TSAccountManager_IsDeregisteredKey";
NSString *const TSAccountManager_ReregisteringPhoneNumberKey = @"TSAccountManager_ReregisteringPhoneNumberKey";
NSString *const TSAccountManager_ReregisteringUUIDKey = @"TSAccountManager_ReregisteringUUIDKey";
NSString *const TSAccountManager_IsOnboardedKey = @"TSAccountManager_IsOnboardedKey";
NSString *const TSAccountManager_IsTransferInProgressKey = @"TSAccountManager_IsTransferInProgressKey";
NSString *const TSAccountManager_WasTransferredKey = @"TSAccountManager_WasTransferredKey";
NSString *const TSAccountManager_HasPendingRestoreDecisionKey = @"TSAccountManager_HasPendingRestoreDecisionKey";
NSString *const TSAccountManager_IsDiscoverableByPhoneNumberKey = @"TSAccountManager_IsDiscoverableByPhoneNumber";
NSString *const TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey
    = @"TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey";

NSString *const TSAccountManager_UserAccountCollection = @"TSStorageUserAccountCollection";
NSString *const TSAccountManager_ServerAuthTokenKey = @"TSStorageServerAuthToken";
NSString *const TSAccountManager_ServerSignalingKey = @"TSStorageServerSignalingKey";
NSString *const TSAccountManager_ManualMessageFetchKey = @"TSAccountManager_ManualMessageFetchKey";

NSString *const TSAccountManager_DeviceNameKey = @"TSAccountManager_DeviceName";
NSString *const TSAccountManager_DeviceIdKey = @"TSAccountManager_DeviceId";

NSString *NSStringForOWSRegistrationState(OWSRegistrationState value)
{
    switch (value) {
        case OWSRegistrationState_Unregistered:
            return @"Unregistered";
        case OWSRegistrationState_PendingBackupRestore:
            return @"PendingBackupRestore";
        case OWSRegistrationState_Registered:
            return @"Registered";
        case OWSRegistrationState_Deregistered:
            return @"Deregistered";
        case OWSRegistrationState_Reregistering:
            return @"Reregistering";
    }
}

#pragma mark -

// We use @synchronized and db transactions often within this class.
// There's a risk of deadlock if we try to @synchronize within a transaction
// while another thread is trying to open a transaction while @synchronized.
// To avoid deadlocks, we follow these guidelines:
//
// * Don't use either unless necessary.
// * Only use one if possible.
// * If both must be used, only @synchronize within a transaction.
//   _Never_ open a transaction within a @synchronized(self) block.
// * If you update any account state in the database, reload the cache
//   immediately.
@interface TSAccountManager () <DatabaseChangeDelegate>

@end

#pragma mark -

@implementation TSAccountManager

@synthesize phoneNumberAwaitingVerification = _phoneNumberAwaitingVerification;
@synthesize uuidAwaitingVerification = _uuidAwaitingVerification;
@synthesize pniAwaitingVerification = _pniAwaitingVerification;

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _keyValueStore = [[SDSKeyValueStore alloc] initWithCollection:TSAccountManager_UserAccountCollection];

    OWSSingletonAssert();

    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        if (!CurrentAppContext().isMainApp) {
            [self.databaseStorage appendDatabaseChangeDelegate:self];
        }
    });
    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self updateAccountAttributesIfNecessary]; });

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged)
                                                 name:SSKReachability.owsReachabilityDidChange
                                               object:nil];

    return self;
}

#pragma mark -

- (void)warmCaches
{
    OWSAssertDebug(GRDBSchemaMigrator.areMigrationsComplete);

    TSAccountState *accountState = [self loadAccountStateWithSneakyTransaction];

    [accountState log];
}

- (nullable NSString *)phoneNumberAwaitingVerification
{
    @synchronized(self) {
        return _phoneNumberAwaitingVerification;
    }
}

- (nullable NSUUID *)uuidAwaitingVerification
{
    @synchronized(self) {
        return _uuidAwaitingVerification;
    }
}

- (nullable NSUUID *)pniAwaitingVerification
{
    @synchronized(self) {
        return _pniAwaitingVerification;
    }
}

- (void)setPhoneNumberAwaitingVerification:(NSString *_Nullable)phoneNumberAwaitingVerification
{
    @synchronized(self) {
        _phoneNumberAwaitingVerification = phoneNumberAwaitingVerification;
    }

    [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameLocalNumberDidChange
                                                             object:nil
                                                           userInfo:nil];
}

- (void)setUuidAwaitingVerification:(NSUUID *_Nullable)uuidAwaitingVerification
{
    @synchronized(self) {
        _uuidAwaitingVerification = uuidAwaitingVerification;
    }
}

- (void)setPniAwaitingVerification:(NSUUID *_Nullable)pniAwaitingVerification
{
    @synchronized(self) {
        _pniAwaitingVerification = pniAwaitingVerification;
    }
}

- (void)updateLocalPhoneNumber:(NSString *)phoneNumber
                           aci:(NSUUID *)uuid
                           pni:(NSUUID *_Nullable)pni
    shouldUpdateStorageService:(BOOL)shouldUpdateStorageService
                   transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(phoneNumber.isStructurallyValidE164);
    OWSAssertDebug([NSObject isNullableObject:self.localUuid equalTo:uuid]);

    [self storeLocalNumber:phoneNumber aci:uuid pni:pni transaction:transaction];

    [transaction addAsyncCompletionOffMain:^{
        [self updateAccountAttributes].catch(^(NSError *error) { OWSLogError(@"Error: %@.", error); });

        if (shouldUpdateStorageService) {
            [self.storageServiceManager recordPendingLocalAccountUpdates];
        }

        [ChangePhoneNumber updateLocalPhoneNumber];

        [self postRegistrationStateDidChangeNotification];

        [[NSNotificationCenter defaultCenter] postNotificationNameAsync:NSNotificationNameLocalNumberDidChange
                                                                 object:nil
                                                               userInfo:nil];
    }];
}

- (OWSRegistrationState)registrationState
{
    TSAccountState *state = [self getOrLoadAccountStateWithSneakyTransaction];
    return [self registrationStateWithState:state];
}

- (OWSRegistrationState)registrationStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    TSAccountState *state = [self loadAccountStateWithTransaction:transaction];
    return [self registrationStateWithState:state];
}

- (OWSRegistrationState)registrationStateWithState:(TSAccountState *)state
{
    if (!state.isRegistered) {
        return OWSRegistrationState_Unregistered;
    } else if ([self isDeregisteredWithState:state]) {
        if (state.isReregistering) {
            return OWSRegistrationState_Reregistering;
        } else {
            return OWSRegistrationState_Deregistered;
        }
    } else {
        return OWSRegistrationState_Registered;
    }
}

- (TSAccountState *)loadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSLogVerbose(@"");

    // This method should only be called while @synchronized on self.
    TSAccountState *accountState = [[TSAccountState alloc] initWithTransaction:transaction
                                                                 keyValueStore:self.keyValueStore];
    self.cachedAccountState = accountState;
    return accountState;
}

- (TSAccountState *)getOrLoadAccountStateWithSneakyTransaction
{
    @synchronized (self) {
        if (self.cachedAccountState != nil) {
            return self.cachedAccountState;
        }
    }

    return [self loadAccountStateWithSneakyTransaction];
}

- (TSAccountState *)loadAccountStateWithSneakyTransaction
{
    // We avoid opening a transaction while @synchronized.
    __block TSAccountState *accountState;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        @synchronized(self) {
            accountState = [self loadAccountStateWithTransaction:transaction];
        }
    } file:__FILE__ function:__FUNCTION__ line:__LINE__];

    OWSAssertDebug(accountState != nil);
    return accountState;
}

- (TSAccountState *)getOrLoadAccountStateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    @synchronized(self) {
        if (self.cachedAccountState != nil) {
            return self.cachedAccountState;
        }

        [self loadAccountStateWithTransaction:transaction];

        OWSAssertDebug(self.cachedAccountState != nil);

        return self.cachedAccountState;
    }
}

- (BOOL)isRegistered
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isRegistered;
}

- (BOOL)isRegisteredWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey transaction:transaction];
}

- (BOOL)isRegisteredAndReady
{
    return self.registrationState == OWSRegistrationState_Registered;
}

- (BOOL)isRegisteredAndReadyWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self registrationStateWithTransaction:transaction] == OWSRegistrationState_Registered;
}

- (void)didRegister
{
    OWSLogInfo(@"");
    NSString *phoneNumber;
    NSUUID *aci;
    NSUUID *pni;
    NSString *authToken;
    @synchronized(self) {
        phoneNumber = self.phoneNumberAwaitingVerification;
        aci = self.uuidAwaitingVerification;
        pni = self.pniAwaitingVerification;
        authToken = self.storedServerAuthToken;
    }

    if (!phoneNumber) {
        OWSFail(@"phoneNumber was unexpectedly nil");
    }

    if (!aci) {
        OWSFail(@"uuid was unexpectedly nil");
    }

    // Allow the PNI to be nil.

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self storeLocalNumber:phoneNumber aci:aci pni:pni transaction:transaction];
    });

    [self postRegistrationStateDidChangeNotification];
}

- (void)didRegisterPrimaryWithE164:(NSString *)e164
                               aci:(NSUUID *)aci
                               pni:(nullable NSUUID *)pni
                         authToken:(NSString *)authToken
                       transaction:(SDSAnyWriteTransaction *)transaction
{
    [self storeLocalNumber:e164 aci:aci pni:pni transaction:transaction];
    [self setStoredServerAuthToken:authToken deviceId:OWSDevicePrimaryDeviceId transaction:transaction];
    [transaction addSyncCompletion:^{ [self postRegistrationStateDidChangeNotification]; }];
}

- (void)recordUuidForLegacyUser:(NSUUID *)uuid
{
    OWSAssert(self.localUuid == nil);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setString:uuid.UUIDString
                                      key:TSAccountManager_RegisteredUUIDKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });
}

+ (nullable NSString *)localNumber
{
    return [[self shared] localNumber];
}

- (nullable NSString *)localNumber
{
    return [self localNumberWithAccountState:[self getOrLoadAccountStateWithSneakyTransaction]];
}

- (nullable NSString *)localNumberWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self localNumberWithAccountState:[self getOrLoadAccountStateWithTransaction:transaction]];
}

- (nullable NSString *)localNumberWithAccountState:(TSAccountState *)accountState
{
    @synchronized(self)
    {
        NSString *awaitingVerif = self.phoneNumberAwaitingVerification;
        if (awaitingVerif) {
            return awaitingVerif;
        }
    }

    return accountState.localNumber;
}

- (nullable NSUUID *)localUuid
{
    return [self localUuidWithAccountState:[self getOrLoadAccountStateWithSneakyTransaction]];
}

- (nullable NSUUID *)localUuidWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self localUuidWithAccountState:[self getOrLoadAccountStateWithTransaction:transaction]];
}

- (nullable NSUUID *)localUuidWithAccountState:(TSAccountState *)accountState
{
    @synchronized(self) {
        NSUUID *awaitingVerif = self.uuidAwaitingVerification;
        if (awaitingVerif) {
            return awaitingVerif;
        }
    }

    return accountState.localUuid;
}

- (nullable NSUUID *)localPni
{
    return [self localPniWithAccountState:[self getOrLoadAccountStateWithSneakyTransaction]];
}

- (nullable NSUUID *)localPniWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self localPniWithAccountState:[self getOrLoadAccountStateWithTransaction:transaction]];
}

- (nullable NSUUID *)localPniWithAccountState:(TSAccountState *)accountState
{
    @synchronized(self) {
        NSUUID *awaitingVerif = self.pniAwaitingVerification;
        if (awaitingVerif) {
            return awaitingVerif;
        }
    }

    return accountState.localPni;
}

+ (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self.shared localAddressWithTransaction:transaction];
}

- (nullable SignalServiceAddress *)localAddressWithTransaction:(SDSAnyReadTransaction *)transaction
{
    TSAccountState *accountState = [self getOrLoadAccountStateWithTransaction:transaction];

    if (accountState.localUuid == nil && accountState.localNumber == nil) {
        return nil;
    } else {
        return [[SignalServiceAddress alloc] initWithUuidString:accountState.localUuid.UUIDString
                                                    phoneNumber:accountState.localNumber];
    }
}

+ (nullable SignalServiceAddress *)localAddress
{
    return [[self shared] localAddress];
}

- (nullable SignalServiceAddress *)localAddress
{
    // We extract uuid and local number from a single instance of accountState
    // to avoid races.
    TSAccountState *accountState = [self getOrLoadAccountStateWithSneakyTransaction];
    NSUUID *_Nullable localUuid = [self localUuidWithAccountState:accountState];
    NSString *_Nullable localNumber = [self localNumberWithAccountState:accountState];

    if (localUuid == nil && localNumber == nil) {
        return nil;
    } else {
        return [[SignalServiceAddress alloc] initWithUuid:localUuid phoneNumber:localNumber];
    }
}

- (void)storeLocalNumber:(NSString *)localNumber
                     aci:(NSUUID *)localAci
                     pni:(NSUUID *_Nullable)localPni
             transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized (self) {
        NSString *_Nullable localNumberOld = [self.keyValueStore getString:TSAccountManager_RegisteredNumberKey
                                                               transaction:transaction];
        if (![NSObject isNullableObject:localNumber equalTo:localNumberOld]) {
            OWSLogInfo(@"localNumber: %@ -> %@", localNumberOld, localNumber);
        }
        [self.keyValueStore setString:localNumber key:TSAccountManager_RegisteredNumberKey transaction:transaction];

        [self.keyValueStore setDate:[NSDate new] key:TSAccountManager_RegistrationDateKey transaction:transaction];

        if (localAci == nil) {
            OWSFail(@"Missing localAci.");
        } else {
            NSString *localAciString = localAci.UUIDString;
            NSString *_Nullable localAciStringOld = [self.keyValueStore getString:TSAccountManager_RegisteredUUIDKey
                                                                      transaction:transaction];
            if (![localAciString isEqual:localAciStringOld]) {
                OWSLogInfo(@"localAci: %@ -> %@", localAciStringOld, localAciString);
            }
            [self.keyValueStore setString:localAciString
                                      key:TSAccountManager_RegisteredUUIDKey
                              transaction:transaction];
        }

        if (localPni) {
            NSString *localPniString = localPni.UUIDString;
            NSString *_Nullable localPniStringOld = [self.keyValueStore getString:TSAccountManager_RegisteredPNIKey
                                                                      transaction:transaction];
            if (![localPniString isEqual:localPniStringOld]) {
                OWSLogInfo(@"localPni: %@ -> %@", localPniStringOld, localPniString);
            }
            [self.keyValueStore setString:localPniString key:TSAccountManager_RegisteredPNIKey transaction:transaction];
        }

        // Update the address cache mapping for the local user.
        [SSKEnvironment.shared.signalServiceAddressCache updateMappingWithUuid:localAci
                                                                   phoneNumber:localNumber
                                                                   transaction:transaction];

        [self.keyValueStore removeValueForKey:TSAccountManager_IsDeregisteredKey transaction:transaction];
        [self.keyValueStore removeValueForKey:TSAccountManager_ReregisteringPhoneNumberKey transaction:transaction];
        [self.keyValueStore removeValueForKey:TSAccountManager_ReregisteringUUIDKey transaction:transaction];

        // Discard sender certificates whenever local phone number changes.
        [self.udManager removeSenderCertificatesWithTransaction:transaction];
        [self.identityManager clearShouldSharePhoneNumberForEveryoneWithTransaction:transaction];

        [self.versionedProfiles clearProfileKeyCredentialsWithTransaction:transaction];

        [self.groupsV2 clearTemporalCredentialsWithTransaction:transaction];

        // PNI TODO: Regenerate our PNI identity key and pre-keys.

        [self loadAccountStateWithTransaction:transaction];

        self.phoneNumberAwaitingVerification = nil;
        self.uuidAwaitingVerification = nil;
        self.pniAwaitingVerification = nil;
    }

    SignalServiceAddress *address = [[SignalServiceAddress alloc] initWithUuid:localAci phoneNumber:localNumber];
    SignalRecipient *recipient = [SignalRecipient fetchOrCreateFor:address
                                                        trustLevel:SignalRecipientTrustLevelHigh
                                                       transaction:transaction];
    [recipient markAsRegisteredWithLocalSourceWithTransaction:transaction];
}

- (nullable NSDate *)registrationDateWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self getOrLoadAccountStateWithTransaction:transaction].registrationDate;
}

- (BOOL)isOnboarded
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isOnboarded;
}

- (BOOL)isOnboardedWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self getOrLoadAccountStateWithTransaction:transaction].isOnboarded;
}

- (void)setIsOnboarded:(BOOL)isOnboarded transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setBool:isOnboarded key:TSAccountManager_IsOnboardedKey transaction:transaction];
        [self loadAccountStateWithTransaction:transaction];
    }
    [self postOnboardingStateDidChangeNotification];
}

#pragma mark Server keying material

// NOTE: We no longer set this for new accounts.
- (nullable NSString *)storedSignalingKey
{
    return [self getOrLoadAccountStateWithSneakyTransaction].serverSignalingKey;
}

- (nullable NSString *)storedServerAuthToken
{
    return [self getOrLoadAccountStateWithSneakyTransaction].serverAuthToken;
}

- (nullable NSString *)storedDeviceName
{
    return [self getOrLoadAccountStateWithSneakyTransaction].deviceName;
}

- (UInt32)storedDeviceId
{
    return [self getOrLoadAccountStateWithSneakyTransaction].deviceId;
}

- (UInt32)storedDeviceIdWithTransaction:(SDSAnyReadTransaction *)transaction
{
    return [self getOrLoadAccountStateWithTransaction:transaction].deviceId;
}

- (void)setStoredServerAuthToken:(NSString *)authToken
                        deviceId:(UInt32)deviceId
                     transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setString:authToken key:TSAccountManager_ServerAuthTokenKey transaction:transaction];
        [self.keyValueStore setUInt32:deviceId key:TSAccountManager_DeviceIdKey transaction:transaction];

        [self loadAccountStateWithTransaction:transaction];
    }
}

- (void)setStoredDeviceName:(NSString *)deviceName transaction:(SDSAnyWriteTransaction *)transaction
{
    @synchronized(self) {
        [self.keyValueStore setString:deviceName key:TSAccountManager_DeviceNameKey transaction:transaction];

        [self loadAccountStateWithTransaction:transaction];
    }
}

#pragma mark - De-Registration

- (BOOL)isDeregistered
{
    TSAccountState *state = [self getOrLoadAccountStateWithSneakyTransaction];
    return [self isDeregisteredWithState:state];
}

- (BOOL)isDeregisteredWithState:(TSAccountState *)state
{
    // An in progress transfer is treated as being deregistered.
    return state.isTransferInProgress || state.wasTransferred || state.isDeregistered;
}

- (void)setIsDeregistered:(BOOL)isDeregistered
{
    if (isDeregistered && !self.isRegisteredAndReady) {
        OWSLogInfo(@"Ignoring; not registered and ready.");
        return;
    }

    if ([self getOrLoadAccountStateWithSneakyTransaction].isDeregistered == isDeregistered) {
        // Skip redundant write.
        return;
    }

    OWSLogWarn(@"Updating isDeregistered: %d", isDeregistered);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            if ([self getOrLoadAccountStateWithTransaction:transaction].isDeregistered == isDeregistered) {
                return;
            }
            [self.keyValueStore setObject:@(isDeregistered)
                                      key:TSAccountManager_IsDeregisteredKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];

            if (isDeregistered) {
                [self.notificationPresenter notifyUserOfDeregistration:transaction];
            }
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

#pragma mark - Re-registration

- (BOOL)resetForReregistration
{
    TSAccountState *oldAccountState = [self getOrLoadAccountStateWithSneakyTransaction];
    NSString *_Nullable localNumber = oldAccountState.localNumber;
    if (!localNumber) {
        OWSFailDebug(@"can't re-register without valid local number.");
        return NO;
    }
    NSUUID *_Nullable localUUID = oldAccountState.localUuid;
    if (!localUUID) {
        OWSFailDebug(@"can't re-register without valid uuid.");
        return NO;
    }
    BOOL wasPrimaryDevice = oldAccountState.deviceId == OWSDevicePrimaryDeviceId;

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            self.phoneNumberAwaitingVerification = nil;
            self.uuidAwaitingVerification = nil;
            self.pniAwaitingVerification = nil;

            [self.keyValueStore removeAllWithTransaction:transaction];

            [[self signalProtocolStoreForIdentity:OWSIdentityACI].sessionStore resetSessionStore:transaction];
            [[self signalProtocolStoreForIdentity:OWSIdentityPNI].sessionStore resetSessionStore:transaction];
            [self.senderKeyStore resetSenderKeyStoreWithTransaction:transaction];

            [self.udManager removeSenderCertificatesWithTransaction:transaction];

            [self.versionedProfiles clearProfileKeyCredentialsWithTransaction:transaction];

            [self.groupsV2 clearTemporalCredentialsWithTransaction:transaction];

            [self.keyValueStore setObject:localNumber
                                      key:TSAccountManager_ReregisteringPhoneNumberKey
                              transaction:transaction];
            [self.keyValueStore setObject:localUUID.UUIDString
                                      key:TSAccountManager_ReregisteringUUIDKey
                              transaction:transaction];

            [self.keyValueStore setBool:NO key:TSAccountManager_IsOnboardedKey transaction:transaction];

            if (wasPrimaryDevice) {
                // Don't reset payments state at this time.
            } else {
                // PaymentsEvents will dispatch this event to the appropriate singletons.
                [self.paymentsEvents clearStateWithTransaction:transaction];
            }

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
    [self postOnboardingStateDidChangeNotification];

    return YES;
}

- (nullable NSString *)reregistrationPhoneNumber
{
    OWSAssertDebug([self isReregistering]);

    return [self getOrLoadAccountStateWithSneakyTransaction].reregistrationPhoneNumber;
}

- (nullable NSUUID *)reregistrationUUID
{
    OWSAssertDebug([self isReregistering]);

    return [self getOrLoadAccountStateWithSneakyTransaction].reregistrationUUID;
}

- (BOOL)isReregistering
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isReregistering;
}

- (BOOL)isTransferInProgress
{
    return [self getOrLoadAccountStateWithSneakyTransaction].isTransferInProgress;
}

- (void)setIsTransferInProgress:(BOOL)transferInProgress
{
    if (transferInProgress == self.isTransferInProgress) {
        return;
    }

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setObject:@(transferInProgress)
                                      key:TSAccountManager_IsTransferInProgressKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)wasTransferred
{
    return [self getOrLoadAccountStateWithSneakyTransaction].wasTransferred;
}

- (void)setWasTransferred:(BOOL)wasTransferred
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        @synchronized(self) {
            [self.keyValueStore setObject:@(wasTransferred)
                                      key:TSAccountManager_WasTransferredKey
                              transaction:transaction];

            [self loadAccountStateWithTransaction:transaction];
        }
    });

    [self postRegistrationStateDidChangeNotification];
}

- (BOOL)isManualMessageFetchEnabled
{
    __block BOOL result;
    [self.databaseStorage readWithBlock:^(
        SDSAnyReadTransaction *transaction) { result = [self isManualMessageFetchEnabled:transaction]; }];
    return result;
}

- (BOOL)isManualMessageFetchEnabled:(SDSAnyReadTransaction *)transaction
{
    return [self.keyValueStore getBool:TSAccountManager_ManualMessageFetchKey defaultValue:NO transaction:transaction];
}

- (void)setIsManualMessageFetchEnabled:(BOOL)value
{
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self setIsManualMessageFetchEnabled:value transaction:transaction];
    });
}

- (void)setIsManualMessageFetchEnabled:(BOOL)value transaction:(SDSAnyWriteTransaction *)transaction
{
    [self.keyValueStore setBool:value key:TSAccountManager_ManualMessageFetchKey transaction:transaction];
}

- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid
{
    [self registerForTestsWithLocalNumber:localNumber uuid:uuid pni:nil];
}

- (void)registerForTestsWithLocalNumber:(NSString *)localNumber uuid:(NSUUID *)uuid pni:(NSUUID *_Nullable)pni
{
    OWSAssertDebug(SSKFeatureFlags.storageMode == StorageModeGrdbTests);
    OWSAssertDebug(CurrentAppContext().isRunningTests);
    OWSAssertDebug(localNumber.length > 0);
    OWSAssertDebug(uuid != nil);

    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self storeLocalNumber:localNumber aci:uuid pni:pni transaction:transaction];
    });
}

- (void)reachabilityChanged {
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{ [self updateAccountAttributesIfNecessary]; });
}

#pragma mark - DatabaseChangeDelegate

- (void)databaseChangesDidUpdateWithDatabaseChanges:(id<DatabaseChanges>)databaseChanges
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    // Do nothing.
}

- (void)databaseChangesDidUpdateExternally
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    OWSLogVerbose(@"");

    // Any database write by the main app might reflect a deregistration,
    // so clear the cached "is registered" state.  This will significantly
    // erode the value of this cache in the SAE.
    [self loadAccountStateWithSneakyTransaction];
}

- (void)databaseChangesDidReset
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(AppReadiness.isAppReady);

    // Do nothing.
}

@end

NS_ASSUME_NONNULL_END
