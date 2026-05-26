import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-501 — Argument parser parsing test
// SPEC: REQ-502 — CollectionOrchestrator parallel run & lifecycle verification
// SPEC: REQ-503 — JSON & Markdown serialization / formatting structures
// SPEC: REQ-504 — CLI stdout / file writing, localized error handling & exit codes
// SPEC: REQ-505 — Swift 6 strict concurrency (Sendable) and E2E integration tests

// MARK: - Binary Locator Helper

private func locateCLIBinary() -> URL? {
    let fm = FileManager.default
    let buildDir = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build")

    guard let enumerator = fm.enumerator(
        at: buildDir,
        includingPropertiesForKeys: [.isExecutableKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    while let fileURL = enumerator.nextObject() as? URL {
        if fileURL.lastPathComponent == "forensic-kit",
           let attrs = try? fileURL.resourceValues(forKeys: [.isExecutableKey]),
           attrs.isExecutable == true,
           !fileURL.path.contains(".dSYM") {
            return fileURL
        }
    }
    return nil
}

// MARK: - Orchestrator Tests (REQ-502)

@Test("CollectionOrchestrator aggregates events concurrently and sorts them")
func testOrchestratorExecution() async throws {
    // We use real services since they are local and fast
    let services: [any CollectionService] = [
        ProcessTreeService(),
        NetworkMonitorService()
    ]

    let orchestrator = CollectionOrchestrator(services: services)
    let events = try await orchestrator.run(memoryDuration: 0.1)

    // SPEC: REQ-502 — Must successfully aggregate events
    #expect(events.isEmpty == false)

    // Verify chronological sorting (timestamp of each event >= previous event)
    for i in 1..<events.count {
        #expect(events[i].timestamp >= events[i-1].timestamp,
                "Events are not sorted chronologically: \(events[i].timestamp) < \(events[i-1].timestamp)")
    }
}

// MARK: - Reporter Tests (REQ-503)

@Test("ForensicReporter formats events to valid JSON")
func testReporterJSON() throws {
    let events = [
        ForensicEvent(
            severity: .info,
            source: .process,
            payload: .process(pid: 1, name: "launchd")
        )
    ]

    let reporter = ForensicReporter()
    let jsonString = try reporter.generateJSON(events: events)

    // Verify JSON is decodable back into ForensicEvent array
    let data = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([ForensicEvent].self, from: data)

    #expect(decoded.count == 1)
    #expect(decoded[0].payload.metadata["pid"] == "1")
    #expect(decoded[0].payload.metadata["name"] == "launchd")
}

@Test("ForensicReporter formats events to premium Markdown with all sections")
func testReporterMarkdown() {
    let events = [
        ForensicEvent(
            severity: .info,
            source: .process,
            payload: .process(pid: 1, name: "launchd")
        ),
        ForensicEvent(
            severity: .info,
            source: .memory,
            payload: .memory(rssBytes: 1024, vmBytes: 4096)
        ),
        ForensicEvent(
            severity: .info,
            source: .network,
            payload: EventPayload(kind: .network, metadata: [
                "interface": "lo0", "family": "IPv4", "address": "127.0.0.1",
                "isLoopback": "true", "isUp": "true", "flags": "8049"
            ])
        ),
        ForensicEvent(
            severity: .info,
            source: .filesystem,
            payload: .filesystem(path: "/bin/ls", sha256: "abc", permissions: "0755")
        )
    ]

    let reporter = ForensicReporter()
    let markdown = reporter.generateMarkdown(events: events, targetScanned: "Test Target")

    // SPEC: REQ-503 — Markdown layout must contain all required subsystem headers
    #expect(markdown.contains("# 🔍 Forensic Audit Report"))
    #expect(markdown.contains("## 📊 Collection Summary"))
    #expect(markdown.contains("### 1. Process tree"))
    #expect(markdown.contains("### 2. Memory usage"))
    #expect(markdown.contains("### 3. Network interface mapping"))
    #expect(markdown.contains("### 4. File system snapshot"))

    // Verify metadata presence
    #expect(markdown.contains("launchd"))
    #expect(markdown.contains("127.0.0.1"))
    #expect(markdown.contains("/bin/ls"))
}

// MARK: - E2E Integration CLI Tests (REQ-504 & REQ-505)

@Test("E2E: CLI help options are valid and exit with 0")
func testCLIHelp() throws {
    guard let binaryURL = locateCLIBinary() else {
        Issue.record("Failed to locate compiled CLI binary.")
        return
    }

    let process = Process()
    process.executableURL = binaryURL
    process.arguments = ["--help"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)

    let output = String(decoding: outputData, as: UTF8.self)

    #expect(output.contains("USAGE: forensic-kit"))
    #expect(output.contains("OPTIONS:"))
}

@Test("E2E: CLI rejects invalid output formats or services and exits with 1")
func testCLIInvalidFormat() throws {
    guard let binaryURL = locateCLIBinary() else {
        Issue.record("Failed to locate compiled CLI binary.")
        return
    }

    let process = Process()
    process.executableURL = binaryURL
    // Pass invalid output format
    process.arguments = ["--services", "process", "-f", "invalid"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    // SPEC: REQ-504 — Must fail and exit with non-zero code on validation errors
    #expect(process.terminationStatus == 1)

    let errorOutput = String(decoding: errData, as: UTF8.self)

    #expect(errorOutput.contains("Error:"), "Expected error output but got: \(errorOutput)")
}

@Test("E2E: CLI successfully runs process and network collection and generates JSON")
func testCLISuccessfulRun() throws {
    guard let binaryURL = locateCLIBinary() else {
        Issue.record("Failed to locate compiled CLI binary.")
        return
    }

    let process = Process()
    process.executableURL = binaryURL
    // Run only process and network (which are fast and local) to generate JSON
    process.arguments = ["--services", "process,network", "-f", "json"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    // SPEC: REQ-505 — standard run exits with 0
    #expect(process.terminationStatus == 0)

    let output = String(decoding: outputData, as: UTF8.self)

    // Output must be valid JSON array
    let data = Data(output.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([ForensicEvent].self, from: data)

    #expect(decoded.isEmpty == false)
    #expect(decoded.allSatisfy { $0.source == .process || $0.source == .network })
}
