@testable import MacClientAppFeatures
import XCTest

final class LocalPortsClientTests: XCTestCase {
    func testParseListeningPortsReadsLsofFieldOutput() {
        let output = """
        p42
        cnode
        n*:5173 (LISTEN)
        n127.0.0.1:5173 (LISTEN)
        p43
        cpython
        n[::1]:8000 (LISTEN)
        n/var/run/not-a-port
        """

        let records = LocalPortsClient.parseListeningPorts(output)

        XCTAssertEqual(
            records,
            [
                ListeningPortRecord(processID: 42, processName: "node", port: 5173),
                ListeningPortRecord(processID: 43, processName: "python", port: 8000)
            ]
        )
    }

    func testParseParentProcessMapIgnoresMalformedRows() {
        let output = """
        42 10
        invalid row
        10 1
        """

        XCTAssertEqual(
            LocalPortsClient.parseParentProcessMap(output),
            [42: 10, 10: 1]
        )
    }

    func testParseWorkingDirectoriesKeepsOnlyAllowedProcessIDs() {
        let rootURL = URL(fileURLWithPath: "/Users/devys/project")
        let output = """
        p10
        n/Users/devys/project
        p99
        n/Users/devys/other
        """

        XCTAssertEqual(
            LocalPortsClient.parseWorkingDirectories(output, allowedProcessIDs: [10]),
            [10: rootURL]
        )
    }

    func testDetectPortsMatchesAncestorWorkingDirectoryToProjectRoot() {
        let rootURL = URL(fileURLWithPath: "/Users/devys/project")
        let listeningOutput = """
        p42
        cnode
        n*:5173 (LISTEN)
        p43
        cpython
        n*:8000 (LISTEN)
        """
        let parentOutput = """
        42 10
        43 1
        10 1
        """
        let workingDirectoryOutput = """
        p10
        n/Users/devys/project
        p43
        n/Users/devys/other
        """

        let ports = LocalPortsClient.detectPorts(
            projectRootURL: rootURL,
            listeningOutput: listeningOutput,
            parentProcessOutput: parentOutput,
            workingDirectoryOutput: workingDirectoryOutput
        )

        XCTAssertEqual(
            ports,
            [
                LocalPort(
                    port: 5173,
                    processID: 42,
                    processName: "node",
                    workingDirectory: rootURL
                )
            ]
        )
    }

    func testDetectPortsSortsAndDeduplicatesPorts() {
        let rootURL = URL(fileURLWithPath: "/Users/devys/project")
        let listeningOutput = """
        p42
        cnode
        n*:5173 (LISTEN)
        p43
        cvite
        n127.0.0.1:5173 (LISTEN)
        p44
        cserver
        n*:3000 (LISTEN)
        """
        let parentOutput = """
        42 1
        43 1
        44 1
        """
        let workingDirectoryOutput = """
        p42
        n/Users/devys/project
        p43
        n/Users/devys/project
        p44
        n/Users/devys/project
        """

        let ports = LocalPortsClient.detectPorts(
            projectRootURL: rootURL,
            listeningOutput: listeningOutput,
            parentProcessOutput: parentOutput,
            workingDirectoryOutput: workingDirectoryOutput
        )

        XCTAssertEqual(ports.map(\.port), [3000, 5173])
        XCTAssertEqual(ports.map(\.processName), ["server", "node"])
    }
}
