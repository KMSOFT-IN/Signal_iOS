//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public enum SSKWebSocketState: UInt {
    case open, connecting, disconnected
}

// MARK: -

extension SSKWebSocketState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .open:
            return "SSKWebSocketState.open"
        case .connecting:
            return "SSKWebSocketState.connecting"
        case .disconnected:
            return "SSKWebSocketState.disconnected"
        }
    }
}

// MARK: -

public protocol SSKWebSocket: AnyObject {

    init?(request: WebSocketRequest, signalService: OWSSignalServiceProtocol, callbackQueue: DispatchQueue)

    var delegate: SSKWebSocketDelegate? { get set }

    var id: UInt { get }

    var state: SSKWebSocketState { get }

    func connect()
    func disconnect()

    func write(data: Data)

    func writePing()
}

// MARK: -

public enum WebSocketError: Error {
    // From RFC 6455: https://www.rfc-editor.org/rfc/rfc6455#section-7.4.1
    public static let normalClosure: Int = 1000

    case httpError(statusCode: Int, retryAfter: Date?)
    case closeError(statusCode: Int, closeReason: Data?)
}

// MARK: -

public extension SSKWebSocket {
    func sendResponse(for request: WebSocketProtoWebSocketRequestMessage,
                      status: UInt32,
                      message: String) throws {
        let responseBuilder = WebSocketProtoWebSocketResponseMessage.builder(requestID: request.requestID,
                                                                             status: status)
        responseBuilder.setMessage(message)
        let response = try responseBuilder.build()

        let messageBuilder = WebSocketProtoWebSocketMessage.builder()
        messageBuilder.setType(.response)
        messageBuilder.setResponse(response)

        let messageData = try messageBuilder.buildSerializedData()

        write(data: messageData)
    }
}

// MARK: -

public protocol SSKWebSocketDelegate: AnyObject {
    func websocketDidConnect(socket: SSKWebSocket)

    func websocketDidDisconnectOrFail(socket: SSKWebSocket, error: Error)

    func websocket(_ socket: SSKWebSocket, didReceiveData data: Data)
}

// MARK: -

public struct WebSocketRequest {
    /// The Signal service associated with this request.
    public let signalService: SignalServiceType

    public let urlPath: String
    public let urlQueryItems: [URLQueryItem]?

    /// Extra headers that should be sent along with the request.
    public let extraHeaders: [String: String]

    public func build(for endpoint: OWSURLSessionEndpoint) -> URLRequest? {
        var urlComponents = URLComponents()
        urlComponents.path = urlPath
        urlComponents.queryItems = urlQueryItems
        guard let urlString = urlComponents.string else {
            owsFailBeta("Couldn't build URL for web socket: \(urlPath)")
            return nil
        }
        do {
            return try endpoint.buildRequest(
                urlString,
                overrideUrlScheme: "wss",
                method: .get,
                headers: extraHeaders
            )
        } catch {
            Logger.warn("Couldn't build web socket request: \(error)")
            return nil
        }
    }
}

public protocol WebSocketFactory {
    var canBuildWebSocket: Bool { get }

    func buildSocket(request: WebSocketRequest, callbackQueue: DispatchQueue) -> SSKWebSocket?
}

// MARK: -

#if TESTABLE_BUILD

@objc
public class WebSocketFactoryMock: NSObject, WebSocketFactory {

    public var canBuildWebSocket: Bool { false }

    public func buildSocket(request: WebSocketRequest, callbackQueue: DispatchQueue) -> SSKWebSocket? {
        owsFailDebug("Cannot build websocket.")
        return nil
    }
}

#endif

// MARK: -

@objc
public class WebSocketFactoryNative: NSObject, WebSocketFactory {
    public var canBuildWebSocket: Bool {
        if FeatureFlags.canUseNativeWebsocket, #available(iOS 13, *) {
            return true
        } else {
            return false
        }
    }

    public func buildSocket(request: WebSocketRequest, callbackQueue: DispatchQueue) -> SSKWebSocket? {
        guard FeatureFlags.canUseNativeWebsocket, #available(iOS 13, *) else {
            return nil
        }
        return SSKWebSocketNative(request: request, signalService: signalService, callbackQueue: callbackQueue)
    }
}

// MARK: -

@available(iOS 13, *)
public class SSKWebSocketNative: SSKWebSocket {

    private static let idCounter = AtomicUInt()
    public let id = SSKWebSocketNative.idCounter.increment()

    private let requestUrl: URL
    private let callbackQueue: DispatchQueue
    private let urlSession: OWSURLSessionProtocol

    public required init?(
        request: WebSocketRequest,
        signalService: OWSSignalServiceProtocol,
        callbackQueue: DispatchQueue
    ) {
        let signalServiceInfo = request.signalService.signalServiceInfo()

        let endpoint = signalService.buildUrlEndpoint(for: signalServiceInfo)

        guard let urlRequest = request.build(for: endpoint) else {
            return nil
        }

        let configuration = OWSURLSession.defaultConfigurationWithoutCaching

        // For some reason, `URLSessionWebSocketTask` will only respect the proxy
        // configuration if started with a URL and not a URLRequest. As a temporary
        // workaround, port header information from the request to the session.
        configuration.httpAdditionalHeaders = urlRequest.allHTTPHeaderFields

        self.urlSession = signalService.buildUrlSession(
            for: signalServiceInfo,
            endpoint: endpoint,
            configuration: configuration
        )
        self.requestUrl = urlRequest.url!
        self.callbackQueue = callbackQueue
    }

    // MARK: - SSKWebSocket

    public weak var delegate: SSKWebSocketDelegate?

    private var lock = UnfairLock()

    private var webSocketTask: URLSessionWebSocketTask?
    private var hasEverConnected = false
    private var isConnected = false
    private var shouldReportError = true
    private var hasUnansweredPing = false

    // This method is thread-safe.
    public var state: SSKWebSocketState {
        lock.withLock {
            if isConnected {
                return .open
            }
            if hasEverConnected {
                return .disconnected
            }
            return .connecting
        }
    }

    public func connect() {
        var taskToResume: URLSessionWebSocketTask?
        lock.withLock {
            owsAssertDebug(webSocketTask == nil && !hasEverConnected, "Must connect only once.")
            guard webSocketTask == nil else {
                return
            }
            webSocketTask = urlSession.webSocketTask(
                requestUrl: requestUrl,
                didOpenBlock: { [weak self] _ in self?.didOpen() },
                didCloseBlock: { [weak self] error in self?.didClose(error: error) }
            )
            taskToResume = webSocketTask
        }
        taskToResume?.resume()
    }

    private func didOpen() {
        lock.withLock {
            isConnected = true
            hasEverConnected = true

            callbackQueue.async {
                self.delegate?.websocketDidConnect(socket: self)
            }
        }
        listenForNextMessage()
    }

    private func didClose(error: Error) {
        lock.withLock {
            isConnected = false
            webSocketTask = nil
            reportErrorWithLock(error, context: "close")
        }
    }

    private func listenForNextMessage() {
        DispatchQueue.global().async {
            self.lock.withLock { self.webSocketTask }?.receive { [weak self] result in
                self?.receivedMessage(result)
            }
        }
    }

    private func receivedMessage(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .data(let data):
                callbackQueue.async {
                    self.delegate?.websocket(self, didReceiveData: data)
                }
            case .string:
                owsFailDebug("We only expect binary frames.")
            @unknown default:
                owsFailDebug("We only expect binary frames.")
            }
            listenForNextMessage()

        case .failure(let error):
            // For some sockets, we read messages until the server closes the
            // connection (and we inspect the close code to determine whether or not
            // it's a graceful teardown). As a result, we expect to receive the final
            // message and close frame in quick succession.
            //
            // We receive messages by repeatedly calling `receive` until we get an
            // error. Unfortunately, this process might see that the stream has been
            // closed before we've had a chance to process the real close frame.
            //
            // The Good Case:
            //   - receivedMessage(<final message>)
            //   - didClose(<close reason>)
            //   - receivedMessage(<socket closed error>)
            //
            // The Bad Case:
            //   - receivedMessage(<final message>)
            //   - receivedMessage(<socket closed error>)
            //   - didClose(<close reason>)
            //
            // (Note that the underlying web socket processes the incoming frames in
            // order, so it's not possible to receive didClose before the final
            // message. The didClose frame waits until the callback for the final
            // message has finished executing.)
            //
            // In theory, we should be able to drop this `receive` error on the floor
            // -- we always expect to learn that the socket has been closed via one of
            // the other URLSession callbacks. However, to guard against the
            // possibility that those might not happen, report the error after a short
            // delay. The delay should be long enough that it never jumps in front of
            // the close callback -- it's a last resort.
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.reportReceivedMessageError(error)
            }

            // Don't try to listen again.
        }
    }

    private func reportReceivedMessageError(_ error: Error) {
        lock.withLock {
            owsAssertDebug(!shouldReportError, "We shouldn't learn that the socket has closed from a receive error.")
            reportErrorWithLock(error, context: "read")
        }
    }

    public func disconnect() {
        var taskToCancel: URLSessionWebSocketTask?
        lock.withLock {
            // The user requested a cancellation, so don't report an error
            shouldReportError = false
            taskToCancel = webSocketTask
            webSocketTask = nil
        }
        taskToCancel?.cancel()
    }

    public func write(data: Data) {
        var taskToSendTo: URLSessionWebSocketTask?
        lock.withLock {
            owsAssertDebug(hasEverConnected, "Must connect before sending to web socket.")
            guard let webSocketTask else {
                reportErrorWithLock(OWSGenericError("Missing webSocketTask."), context: "write")
                return
            }
            taskToSendTo = webSocketTask
        }
        taskToSendTo?.send(.data(data)) { [weak self] error in
            self?.reportError(error, context: "write")
        }
    }

    public func writePing() {
        var taskToPing: URLSessionWebSocketTask?
        lock.withLock {
            owsAssertDebug(hasEverConnected, "Must connect before sending a ping.")
            guard let webSocketTask else {
                reportErrorWithLock(OWSGenericError("Missing webSocketTask."), context: "ping")
                return
            }
            guard !hasUnansweredPing else {
                reportErrorWithLock(OWSGenericError("Ping didn't get a response."), context: "ping")
                return
            }
            hasUnansweredPing = true
            taskToPing = webSocketTask
        }
        taskToPing?.sendPing(pongReceiveHandler: { [weak self] error in
            self?.receivedPong(error)
        })
    }

    private func receivedPong(_ error: Error?) {
        lock.withLock {
            hasUnansweredPing = false
            reportErrorWithLock(error, context: "pong")
        }
    }

    private func reportError(_ error: Error?, context: String) {
        lock.withLock {
            reportErrorWithLock(error, context: context)
        }
    }

    private func reportErrorWithLock(_ error: Error?, context: String) {
        lock.assertOwner()

        guard let error else {
            return
        }

        guard shouldReportError else {
            Logger.verbose("[\(id), context: \(context)] Ignoring error: \(error)")
            return
        }
        shouldReportError = false

        callbackQueue.async {
            Logger.warn("[\(self.id), context: \(context)] Socket error: \(error)")
            self.delegate?.websocketDidDisconnectOrFail(socket: self, error: error)
        }
    }
}
