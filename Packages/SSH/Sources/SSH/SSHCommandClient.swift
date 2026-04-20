import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import NIOTransportServices

public struct SSHCommandResult: Sendable, Equatable {
    public var stdout: String
    public var stderr: String
    public var exitStatus: Int

    public init(
        stdout: String = "",
        stderr: String = "",
        exitStatus: Int = 0
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
    }
}

public actor SSHCommandClient {
    public typealias HostKeyValidator = SSHHostKeyValidator

    public init() {}

    public func run(
        configuration: SSHConnectionConfiguration,
        command: String,
        hostKeyValidator: HostKeyValidator? = nil
    ) async throws -> SSHCommandResult {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SSHCommandResult()
        }

        let group = NIOTSEventLoopGroup()
        do {
            let rootChannel = try await makeRootChannel(
                group: group,
                configuration: configuration,
                hostKeyValidator: hostKeyValidator
            )
            let result = try await runCommand(
                rootChannel: rootChannel,
                command: command
            )
            try? await rootChannel.close().get()
            await shutdown(group)
            return result
        } catch {
            await shutdown(group)
            throw error
        }
    }
}

private extension SSHCommandClient {
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

    func runCommand(
        rootChannel: Channel,
        command: String
    ) async throws -> SSHCommandResult {
        let childChannelPromise = rootChannel.eventLoop.makePromise(of: Channel.self)
        let resultPromise = rootChannel.eventLoop.makePromise(of: SSHCommandResult.self)

        rootChannel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { result in
            switch result {
            case .success(let sshHandler):
                sshHandler.createChannel(childChannelPromise, channelType: .session) { channel, channelType in
                    guard case .session = channelType else {
                        return channel.eventLoop.makeFailedFuture(SSHTerminalError.failedToOpenShellChannel)
                    }

                    let handler = SSHExecHandler(
                        command: command,
                        resultPromise: resultPromise
                    )
                    return channel.pipeline.addHandler(handler)
                }
            case .failure(let error):
                childChannelPromise.fail(error)
                resultPromise.fail(error)
            }
        }

        let channel = try await childChannelPromise.futureResult.get()
        _ = channel
        return try await resultPromise.futureResult.get()
    }

    func shutdown(_ group: NIOTSEventLoopGroup) async {
        await withCheckedContinuation { continuation in
            group.shutdownGracefully { _ in
                continuation.resume()
            }
        }
    }
}

private final class SSHExecHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let command: String
    private let resultPromise: EventLoopPromise<SSHCommandResult>
    private var stdout = Data()
    private var stderr = Data()
    private var exitStatus = 0
    private var didComplete = false

    init(
        command: String,
        resultPromise: EventLoopPromise<SSHCommandResult>
    ) {
        self.command = command
        self.resultPromise = resultPromise
    }

    func channelActive(context: ChannelHandlerContext) {
        let execRequest = SSHChannelRequestEvent.ExecRequest(
            command: command,
            wantReply: true
        )
        context.triggerUserOutboundEvent(execRequest).whenComplete { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.fail(error)
            }
        }
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        guard case .byteBuffer(let bytes) = payload.data else { return }
        let chunk = Data(bytes.readableBytesView)
        guard !chunk.isEmpty else { return }

        switch payload.type {
        case .channel:
            stdout.append(chunk)
        case .stdErr:
            stderr.append(chunk)
        default:
            break
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exit as SSHChannelRequestEvent.ExitStatus:
            exitStatus = Int(exit.exitStatus)
        case let signal as SSHChannelRequestEvent.ExitSignal:
            fail(SSHTerminalError.failedToOpenShellChannel)
            context.close(promise: nil)
            _ = signal
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        succeedIfNeeded()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        fail(error)
        context.close(promise: nil)
    }

    private func succeedIfNeeded() {
        guard !didComplete else { return }
        didComplete = true
        resultPromise.succeed(
            SSHCommandResult(
                stdout: String(data: stdout, encoding: .utf8) ?? "",
                stderr: String(data: stderr, encoding: .utf8) ?? "",
                exitStatus: exitStatus
            )
        )
    }

    private func fail(_ error: Error) {
        guard !didComplete else { return }
        didComplete = true
        resultPromise.fail(error)
    }
}
