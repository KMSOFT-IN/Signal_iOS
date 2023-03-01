//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension RegistrationCoordinatorImpl {

    enum Service {

        enum KBSAuthCheckResponse {
            case success(RegistrationServiceResponses.KBSAuthCheckResponse)
            case networkError
            case genericError
        }

        static func makeKBSAuthCheckRequest(
            e164: String,
            candidateCredentials: [KBSAuthCredential],
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers
        ) -> Guarantee<KBSAuthCheckResponse> {
            let request = RegistrationRequestFactory.kbsAuthCredentialCheckRequest(
                e164: e164,
                credentials: candidateCredentials
            )
            return makeRequest(
                request,
                signalService: signalService,
                schedulers: schedulers,
                handler: self.handleKBSAuthCheckResponse(statusCode:retryAfterHeader:bodyData:),
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleKBSAuthCheckResponse(
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> KBSAuthCheckResponse {
            let statusCode = RegistrationServiceResponses.KBSAuthCheckResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty KBS auth check response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.KBSAuthCheckResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse KBS auth check response from response")
                    return .genericError
                }

                return .success(response)
            case .malformedRequest, .invalidJSON:
                Logger.error("Malformed kbs auth check request")
                return .genericError
            case .none, .unexpectedError:
                return .genericError
            }
        }

        static func makeCreateAccountRequest(
            _ method: RegistrationRequestFactory.VerificationMethod,
            e164: String,
            accountAttributes: RegistrationRequestFactory.AccountAttributes,
            skipDeviceTransfer: Bool,
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers
        ) -> Guarantee<AccountResponse> {
            let request = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: method,
                e164: e164,
                accountAttributes: accountAttributes,
                skipDeviceTransfer: skipDeviceTransfer
            )
            return makeRequest(
                request,
                signalService: signalService,
                schedulers: schedulers,
                handler: {
                    self.handleCreateAccountResponse(
                        authToken: accountAttributes.authKey,
                        statusCode: $0,
                        retryAfterHeader: $1,
                        bodyData: $2
                    )
                },
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleCreateAccountResponse(
            authToken: String,
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> AccountResponse {
            let statusCode = RegistrationServiceResponses.AccountCreationResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.AccountIdentityResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse Account identity from response")
                    return .genericError
                }
                return .success(AccountIdentity(response: response, authToken: authToken))

            case .deviceTransferPossible:
                return .deviceTransferPossible

            case .regRecoveryPasswordRejected:
                Logger.warn("Reg recovery password rejected when creating account.")
                return .rejectedVerificationMethod

            case .reglockFailed:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: bodyData
                ) else {
                    Logger.warn("Unable to parse ReglockFailure from response")
                    return .genericError
                }
                return .reglockFailure(response)

            case .retry:
                let retryAfter: TimeInterval
                if
                    let retryAfterHeader,
                    let retryAfterTime = TimeInterval(retryAfterHeader)
                {
                    retryAfter = retryAfterTime
                } else {
                    Logger.warn("Missing retry-after header from server; falling back to default.")
                    retryAfter = Constants.defaultRetryTime
                }
                return .retryAfter(retryAfter)

            case .unauthorized:
                Logger.warn("Got unauthorized response for create account")
                return .rejectedVerificationMethod

            case .invalidArgument:
                Logger.warn("Got invalid argument response for create account")
                return .genericError

            case .malformedRequest:
                Logger.warn("Got malformed request response for create account")
                return .genericError

            case .none, .unexpectedError:
                return .genericError
            }
        }

        static func makeChangeNumberRequest(
            _ method: RegistrationRequestFactory.VerificationMethod,
            e164: String,
            reglockToken: String?,
            authToken: String,
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers
        ) -> Guarantee<AccountResponse> {
            let request = RegistrationRequestFactory.changeNumberRequest(
                verificationMethod: method,
                e164: e164,
                reglockToken: reglockToken
            )
            return makeRequest(
                request,
                signalService: signalService,
                schedulers: schedulers,
                handler: {
                    return self.handleChangeNumberResponse(authToken: authToken, statusCode: $0, retryAfterHeader: $1, bodyData: $2)
                },
                fallbackError: .genericError,
                networkFailureError: .networkError
            )
        }

        private static func handleChangeNumberResponse(
            authToken: String,
            statusCode: Int,
            retryAfterHeader: String?,
            bodyData: Data?
        ) -> AccountResponse {
            let statusCode = RegistrationServiceResponses.ChangeNumberResponseCodes(rawValue: statusCode)
            switch statusCode {
            case .success:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(RegistrationServiceResponses.AccountIdentityResponse.self, from: bodyData) else {
                    Logger.warn("Unable to parse Account identity from response")
                    return .genericError
                }
                return .success(AccountIdentity(response: response, authToken: authToken))

            case .reglockFailed:
                guard let bodyData else {
                    Logger.warn("Got empty create account response")
                    return .genericError
                }
                guard let response = try? JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: bodyData
                ) else {
                    Logger.warn("Unable to parse ReglockFailure from response")
                    return .genericError
                }
                return .reglockFailure(response)

            case .retry:
                let retryAfter: TimeInterval
                if
                    let retryAfterHeader,
                    let retryAfterTime = TimeInterval(retryAfterHeader)
                {
                    retryAfter = retryAfterTime
                } else {
                    Logger.warn("Missing retry-after header from server; falling back to default.")
                    retryAfter = Constants.defaultRetryTime
                }
                return .retryAfter(retryAfter)

            case .unauthorized, .regRecoveryPasswordRejected:
                return .rejectedVerificationMethod

            case .malformedRequest:
                Logger.error("Got malformed request for change number")
                return .genericError

            case .invalidArgument:
                Logger.error("Got invalid argument for change number")
                return .genericError

            case .mismatchedDevicesToNotify, .mismatchedDevicesToNotifyRegistrationIds:
                // TODO[PNP]: What should be done about this category of error?
                Logger.error("Got mismatched device list information for change number")
                return .genericError

            case .none, .unexpectedError:
                return .genericError
            }
        }

        public static func makeEnableReglockRequest(
            reglockToken: String,
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers,
            retriesLeft: Int = RegistrationCoordinatorImpl.Constants.networkErrorRetries
        ) -> Promise<Void> {
            let request = OWSRequestFactory.enableRegistrationLockV2Request(token: reglockToken)
            return signalService.urlSessionForMainSignalService().promiseForTSRequest(request).asVoid()
                .recover(on: schedulers.sync) { error in
                    if error.isNetworkConnectivityFailure, retriesLeft > 0 {
                        return makeEnableReglockRequest(
                            reglockToken: reglockToken,
                            signalService: signalService,
                            schedulers: schedulers,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .init(error: error)
                }
        }

        /// Returns nil error if success.
        public static func makeUpdateAccountAttributesRequest(
            _ attributes: RegistrationRequestFactory.AccountAttributes,
            authUsername: String,
            authPassword: String,
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers,
            retriesLeft: Int = RegistrationCoordinatorImpl.Constants.networkErrorRetries
        ) -> Guarantee<Error?> {
            let request = RegistrationRequestFactory.updatePrimaryDeviceAccountAttributesRequest(
                attributes,
                authUsername: authUsername,
                authPassword: authPassword
            )
            return signalService.urlSessionForMainSignalService().promiseForTSRequest(request)
                .map(on: schedulers.sync) { response in
                    guard response.responseStatusCode == 200 else {
                        // TODO[Registration]: what other error codes can come up here?
                        return OWSAssertionError("Got unexpected response code from update attributes request.")
                    }
                    return nil
                }
                .recover(on: schedulers.sync) { error in
                    if error.isNetworkConnectivityFailure, retriesLeft > 0 {
                        return makeUpdateAccountAttributesRequest(
                            attributes,
                            authUsername: authUsername,
                            authPassword: authPassword,
                            signalService: signalService,
                            schedulers: schedulers,
                            retriesLeft: retriesLeft - 1
                        )
                    }
                    return .value(error)
                }
        }

        private static func makeRequest<ResponseType>(
            _ request: TSRequest,
            signalService: OWSSignalServiceProtocol,
            schedulers: Schedulers,
            handler: @escaping (_ statusCode: Int, _ retryAfterHeader: String?, _ bodyData: Data?) -> ResponseType,
            fallbackError: ResponseType,
            networkFailureError: ResponseType
        ) -> Guarantee<ResponseType> {
            return signalService.urlSessionForMainSignalService().promiseForTSRequest(request)
                .map(on: schedulers.sharedBackground) { (response: HTTPResponse) -> ResponseType in
                    return handler(
                        response.responseStatusCode,
                        response.responseHeaders[Constants.retryAfterHeader],
                        response.responseBodyData
                    )
                }
                .recover(on: schedulers.sharedBackground) { (error: Error) -> Guarantee<ResponseType> in
                    if error.isNetworkConnectivityFailure {
                        return .value(networkFailureError)
                    }
                    guard let error = error as? OWSHTTPError else {
                        return .value(fallbackError)
                    }
                    let response = handler(
                        error.responseStatusCode,
                        error.responseHeaders?.value(forHeader: Constants.retryAfterHeader),
                        error.httpResponseData
                    )
                    return .value(response)
                }
        }

        enum Constants {
            static let defaultRetryTime: TimeInterval = 3

            static let retryAfterHeader = "retry-after"
        }
    }
}
