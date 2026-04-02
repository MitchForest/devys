import CryptoKit
import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import NIOTransportServices

enum SSHInteractiveClientEvent: Sendable {
    case output(Data)
    case stderr(Data)
    case exitStatus(Int)
    case disconnected
    case failure(String)
}

actor SSHInteractiveClient {
    typealias HostKeyValidator = @MainActor @Sendable (
        SSHHostKeyValidationContext
    ) async -> SSHHostKeyValidationDecision
    typealias EventSink = @Sendable (SSHInteractiveClientEvent) -> Void

    private var group: NIOTSEventLoopGroup?
    private var rootChannel: Channel?
    private var sessionChannel: Channel?

    func connect(
        configuration: SSHConnectionConfiguration,
        cols: Int,
        rows: Int,
        term: String = "xterm-256color",
        hostKeyValidator: HostKeyValidator?,
        eventSink: @escaping EventSink
    ) async throws {
        try Self.validateConnectInput(configuration: configuration, cols: cols, rows: rows)
        await shutdownResources()

        let group = NIOTSEventLoopGroup()
        do {
            let rootChannel = try await makeRootChannel(
                group: group,
                configuration: configuration,
                hostKeyValidator: hostKeyValidator
            )
            let sessionChannel = try await makeShellChannel(
                rootChannel: rootChannel,
                cols: cols,
                rows: rows,
                term: term,
                eventSink: eventSink
            )
            activateConnection(
                group: group,
                rootChannel: rootChannel,
                sessionChannel: sessionChannel,
                eventSink: eventSink
            )
        } catch {
            await Self.shutdown(group)
            throw error
        }
    }

    func send(data: Data) async throws {
        guard let sessionChannel, sessionChannel.isActive else {
            throw SSHTerminalError.notConnected
        }
        guard !data.isEmpty else { return }

        var buffer = sessionChannel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await sessionChannel.writeAndFlush(buffer).get()
    }

    func resize(cols: Int, rows: Int) async throws {
        guard let sessionChannel, sessionChannel.isActive else {
            throw SSHTerminalError.notConnected
        }
        guard cols > 0, rows > 0 else {
            throw SSHTerminalError.invalidTerminalDimensions
        }

        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        try await sessionChannel.triggerUserOutboundEvent(request).get()
    }

    func disconnect() async {
        await shutdownResources()
    }
}

private extension SSHInteractiveClient {
    static func validateConnectInput(configuration: SSHConnectionConfiguration, cols: Int, rows: Int) throws {
        guard !configuration.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SSHTerminalError.invalidHost
        }
        guard (1...65535).contains(configuration.port) else {
            throw SSHTerminalError.invalidPort
        }
        guard cols > 0, rows > 0 else {
            throw SSHTerminalError.invalidTerminalDimensions
        }
    }

    func makeRootChannel(
        group: NIOTSEventLoopGroup,
        configuration: SSHConnectionConfiguration,
        hostKeyValidator: HostKeyValidator?
    ) async throws -> Channel {
        let authDelegate = try SSHUserAuthenticationDelegate(configuration: configuration)
        let serverAuthDelegate = SSHServerAuthenticationDelegate(
            host: configuration.host,
            port: configuration.port,
            validator: hostKeyValidator
        )

        let bootstrap = NIOTSConnectionBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let handler = NIOSSHHandler(
                        role: .client(
                            .init(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: serverAuthDelegate
                            )
                        ),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                    try channel.pipeline.syncOperations.addHandler(handler)
                }
            }
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)

        return try await bootstrap.connect(host: configuration.host, port: configuration.port).get()
    }

    func makeShellChannel(
        rootChannel: Channel,
        cols: Int,
        rows: Int,
        term: String,
        eventSink: @escaping EventSink
    ) async throws -> Channel {
        let childChannelPromise = rootChannel.eventLoop.makePromise(of: Channel.self)
        let shellReadyPromise = rootChannel.eventLoop.makePromise(of: Void.self)
        rootChannel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { result in
            switch result {
            case .success(let sshHandler):
                sshHandler.createChannel(childChannelPromise, channelType: .session) { channel, channelType in
                    guard case .session = channelType else {
                        return channel.eventLoop.makeFailedFuture(SSHTerminalError.failedToOpenShellChannel)
                    }

                    let shellHandler = SSHInteractiveShellHandler(
                        initialCols: cols,
                        initialRows: rows,
                        term: term,
                        readyPromise: shellReadyPromise,
                        eventSink: eventSink
                    )
                    return channel.pipeline.addHandler(shellHandler)
                }
            case .failure(let error):
                childChannelPromise.fail(error)
                shellReadyPromise.fail(error)
            }
        }

        let sessionChannel = try await childChannelPromise.futureResult.get()
        try await shellReadyPromise.futureResult.get()
        return sessionChannel
    }

    func activateConnection(
        group: NIOTSEventLoopGroup,
        rootChannel: Channel,
        sessionChannel: Channel,
        eventSink: @escaping EventSink
    ) {
        self.group = group
        self.rootChannel = rootChannel
        self.sessionChannel = sessionChannel
        sessionChannel.closeFuture.whenComplete { _ in
            eventSink(.disconnected)
        }
    }

    func shutdownResources() async {
        let sessionChannel = self.sessionChannel
        let rootChannel = self.rootChannel
        let group = self.group

        self.sessionChannel = nil
        self.rootChannel = nil
        self.group = nil

        if let sessionChannel {
            try? await sessionChannel.close().get()
        }
        if let rootChannel {
            try? await rootChannel.close().get()
        }
        if let group {
            await Self.shutdown(group)
        }
    }

    static func shutdown(_ group: NIOTSEventLoopGroup) async {
        await withCheckedContinuation { continuation in
            group.shutdownGracefully { _ in
                continuation.resume()
            }
        }
    }
}

private final class SSHUserAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private var nextOffer: NIOSSHUserAuthenticationOffer?

    init(configuration: SSHConnectionConfiguration) throws {
        switch configuration.authentication {
        case .password(let password):
            nextOffer = NIOSSHUserAuthenticationOffer(
                username: configuration.username,
                serviceName: "",
                offer: .password(.init(password: password))
            )
        case .privateKey(let privateKeyPEM, let passphrase):
            let trimmedPassphrase = passphrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parseResult = SSHPrivateKeyParser.parse(privateKeyPEM: privateKeyPEM)

            let key: NIOSSHPrivateKey
            switch parseResult {
            case .success(let parsed):
                key = parsed
            case .encryptedUnsupported:
                throw SSHTerminalError.encryptedPrivateKeyUnsupported
            case .unsupported:
                if !trimmedPassphrase.isEmpty {
                    throw SSHTerminalError.encryptedPrivateKeyUnsupported
                }
                throw SSHTerminalError.unsupportedPrivateKeyFormat
            }

            nextOffer = NIOSSHUserAuthenticationOffer(
                username: configuration.username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: key))
            )
        }
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard let offer = nextOffer else {
            nextChallengePromise.succeed(nil)
            return
        }

        switch offer.offer {
        case .password where availableMethods.contains(.password):
            nextOffer = nil
            nextChallengePromise.succeed(offer)
        case .privateKey where availableMethods.contains(.publicKey):
            nextOffer = nil
            nextChallengePromise.succeed(offer)
        default:
            nextChallengePromise.succeed(nil)
        }
    }
}

private final class SSHServerAuthenticationDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    typealias HostKeyValidator = SSHInteractiveClient.HostKeyValidator

    private let host: String
    private let port: Int
    private let validator: HostKeyValidator?

    init(host: String, port: Int, validator: HostKeyValidator?) {
        self.host = host
        self.port = port
        self.validator = validator
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        guard let context = makeContext(from: hostKey) else {
            validationCompletePromise.fail(SSHTerminalError.invalidServerHostKey)
            return
        }

        guard let validator else {
            validationCompletePromise.succeed(())
            return
        }

        Task {
            let decision = await validator(context)
            switch decision {
            case .trust:
                validationCompletePromise.succeed(())
            case .reject:
                validationCompletePromise.fail(SSHTerminalError.hostKeyRejected)
            }
        }
    }

    private func makeContext(from hostKey: NIOSSHPublicKey) -> SSHHostKeyValidationContext? {
        let openSSH = String(openSSHPublicKey: hostKey)
        let components = openSSH.split(separator: " ")
        guard components.count >= 2 else { return nil }
        let algorithm = String(components[0])
        guard let fingerprint = Self.sha256Fingerprint(fromOpenSSHKey: openSSH) else { return nil }

        return SSHHostKeyValidationContext(
            host: host,
            port: port,
            algorithm: algorithm,
            openSSHPublicKey: openSSH,
            fingerprintSHA256: fingerprint
        )
    }

    private static func sha256Fingerprint(fromOpenSSHKey key: String) -> String? {
        let components = key.split(separator: " ")
        guard components.count >= 2 else { return nil }
        guard let decoded = Data(base64Encoded: String(components[1])) else { return nil }
        let digest = SHA256.hash(data: decoded)
        let base64 = Data(digest).base64EncodedString().trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return "SHA256:\(base64)"
    }
}

private final class SSHInteractiveShellHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let initialCols: Int
    private let initialRows: Int
    private let term: String
    private let eventSink: SSHInteractiveClient.EventSink
    private var readyPromise: EventLoopPromise<Void>?

    init(
        initialCols: Int,
        initialRows: Int,
        term: String,
        readyPromise: EventLoopPromise<Void>,
        eventSink: @escaping SSHInteractiveClient.EventSink
    ) {
        self.initialCols = initialCols
        self.initialRows = initialRows
        self.term = term
        self.readyPromise = readyPromise
        self.eventSink = eventSink
    }

    func handlerAdded(context: ChannelHandlerContext) {
        _ = context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
    }

    func channelActive(context: ChannelHandlerContext) {
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: initialCols,
            terminalRowHeight: initialRows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:])
        )

        let shellRequest = SSHChannelRequestEvent.ShellRequest(wantReply: true)

        context
            .triggerUserOutboundEvent(ptyRequest)
            .flatMap {
                let context = loopBoundContext.value
                return context.triggerUserOutboundEvent(shellRequest)
            }
            .whenComplete { [weak self] result in
                guard let self, let readyPromise = self.readyPromise else { return }
                self.readyPromise = nil
                switch result {
                case .success:
                    readyPromise.succeed(())
                case .failure(let error):
                    readyPromise.fail(error)
                }
            }

        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        guard case .byteBuffer(let bytes) = payload.data else { return }

        let output = Data(bytes.readableBytesView)
        if output.isEmpty {
            return
        }

        switch payload.type {
        case .channel:
            eventSink(.output(output))
        case .stdErr:
            eventSink(.stderr(output))
        default:
            break
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let bytes = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(bytes))), promise: promise)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exit as SSHChannelRequestEvent.ExitStatus:
            eventSink(.exitStatus(exit.exitStatus))
        case let signal as SSHChannelRequestEvent.ExitSignal:
            eventSink(.failure("Remote shell terminated with signal \(signal.signalName)."))
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        eventSink(.disconnected)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        eventSink(.failure(error.localizedDescription))
        context.close(promise: nil)
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        if let readyPromise {
            self.readyPromise = nil
            readyPromise.fail(SSHTerminalError.failedToOpenShellChannel)
        }
    }
}
