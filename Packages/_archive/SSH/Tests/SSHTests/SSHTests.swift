import Testing
@testable import SSH

@Test func sshTypesExist() async throws {
    let config = SSHConnectionConfiguration(
        host: "localhost",
        port: 22,
        username: "test",
        authentication: .password("test")
    )
    #expect(config.host == "localhost")
    #expect(config.port == 22)
}
