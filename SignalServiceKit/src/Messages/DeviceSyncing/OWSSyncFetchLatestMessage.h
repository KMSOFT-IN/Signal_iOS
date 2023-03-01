//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncFetchType) {
    OWSSyncFetchType_Unknown,
    OWSSyncFetchType_LocalProfile,
    OWSSyncFetchType_StorageManifest,
    OWSSyncFetchType_SubscriptionStatus
};

@interface OWSSyncFetchLatestMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp
                           thread:(TSThread *)thread
                      transaction:(SDSAnyReadTransaction *)transaction NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                     fetchType:(OWSSyncFetchType)requestType
                   transaction:(SDSAnyReadTransaction *)transaction NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
