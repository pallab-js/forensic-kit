import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-203 — MemoryLogger streaming tests (mock provider)
// SPEC: REQ-204 — Memory limit exceeded + .warning severity tests

// MARK: - Helpers

/// A `@Sendable` mock that always returns a fixed RSS/VM pair.
private func fixedProvider(rss: Int, vm: Int) -> MemoryLogger.MemoryProvider {
    { (rss: rss, vm: vm) }
}

// MARK: - Service State Tests

@Test("MemoryLogger stream throws serviceNotRunning before start()")
func testMemoryLoggerThrowsWhenNotStarted() async throws {
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 2_000_000_000,
        memoryProvider: fixedProvider(rss: 100_000, vm: 200_000)
    )
    // Deliberately do NOT call start()

    var caughtError: ForensicError?
    do {
        for try await _ in logger.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "memory-logger"))
}

@Test("MemoryLogger id is stable")
func testMemoryLoggerID() {
    let logger = MemoryLogger()
    #expect(logger.id == "memory-logger")
}

// MARK: - Streaming with Mock Provider

@Test("MemoryLogger emits events with correct source and payload kind")
func testMemoryLoggerEventsHaveCorrectSourceAndKind() async throws {
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 2_000_000_000,
        memoryProvider: fixedProvider(rss: 512_000, vm: 1_024_000)
    )
    try await logger.start()

    var events: [ForensicEvent] = []
    for try await event in logger.stream() {
        events.append(event)
        if events.count >= 3 { break }  // break → onTermination cancels the task
    }
    await logger.stop()

    // SPEC: REQ-203 — source=.memory
    #expect(events.count == 3)
    #expect(events.allSatisfy { $0.source    == .memory })
    #expect(events.allSatisfy { $0.payload.kind == .memory })
}

@Test("MemoryLogger events carry rssBytes and vmBytes metadata")
func testMemoryLoggerMetadataFields() async throws {
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 2_000_000_000,
        memoryProvider: fixedProvider(rss: 512_000, vm: 1_024_000)
    )
    try await logger.start()

    var first: ForensicEvent?
    for try await event in logger.stream() {
        first = event
        break
    }
    await logger.stop()

    let event = try #require(first)
    // SPEC: REQ-203 — metadata populated by EventPayload.memory factory
    #expect(event.payload.metadata["rssBytes"] == "512000")
    #expect(event.payload.metadata["vmBytes"]  == "1024000")
}

@Test("MemoryLogger events have .info severity under 90% threshold")
func testMemoryLoggerInfoSeverityBelowThreshold() async throws {
    // Limit = 2_000_000, RSS = 1_000_000 (50% — under 90% threshold)
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 2_000_000,
        memoryProvider: fixedProvider(rss: 1_000_000, vm: 2_000_000)
    )
    try await logger.start()

    var first: ForensicEvent?
    for try await event in logger.stream() {
        first = event
        break
    }
    await logger.stop()

    let event = try #require(first)
    // SPEC: REQ-204 — .info when RSS < 90% of limit
    #expect(event.severity == .info)
}

@Test("MemoryLogger events have .warning severity above 90% threshold")
func testMemoryLoggerWarningSeverityAboveThreshold() async throws {
    // Limit = 1_000_000, RSS = 950_000 (95% — above 90% threshold)
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 1_000_000,
        memoryProvider: fixedProvider(rss: 950_000, vm: 2_000_000)
    )
    try await logger.start()

    var first: ForensicEvent?
    for try await event in logger.stream() {
        first = event
        break
    }
    await logger.stop()

    let event = try #require(first)
    // SPEC: REQ-204 — .warning when RSS > 90% of limit
    #expect(event.severity == .warning)
}

// MARK: - Memory Limit Tests

@Test("MemoryLogger throws memoryLimitExceeded when RSS exceeds limit")
func testMemoryLoggerThrowsLimitExceeded() async throws {
    // RSS = 200_000 > limit = 100_000 — should throw immediately
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 100_000,
        memoryProvider: fixedProvider(rss: 200_000, vm: 400_000)
    )
    try await logger.start()

    var caughtError: ForensicError?
    do {
        for try await _ in logger.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }

    // SPEC: REQ-204 — must throw .memoryLimitExceeded
    guard case .memoryLimitExceeded(let used, let limit) = caughtError else {
        Issue.record("Expected .memoryLimitExceeded, got: \(String(describing: caughtError))")
        return
    }
    #expect(used  == 200_000)
    #expect(limit == 100_000)
}

@Test("MemoryLogger memoryLimitExceeded carries correct byte counts")
func testMemoryLoggerLimitExceededByteValues() async throws {
    let logger = MemoryLogger(
        interval: .milliseconds(1),
        memoryLimitBytes: 50_000,
        memoryProvider: fixedProvider(rss: 99_999, vm: 0)
    )
    try await logger.start()

    var caughtError: ForensicError?
    do {
        for try await _ in logger.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }

    if case .memoryLimitExceeded(let used, let limit) = caughtError {
        #expect(used  == 99_999)
        #expect(limit == 50_000)
    } else {
        Issue.record("Wrong error: \(String(describing: caughtError))")
    }
}

// MARK: - Stop Tests

@Test("MemoryLogger stop() terminates the stream")
func testMemoryLoggerStopTerminatesStream() async throws {
    let logger = MemoryLogger(
        interval: .milliseconds(5),
        memoryLimitBytes: 2_000_000_000,
        memoryProvider: fixedProvider(rss: 100_000, vm: 200_000)
    )
    try await logger.start()

    var count = 0
    for try await _ in logger.stream() {
        count += 1
        if count == 2 { await logger.stop() }
        // After stop(), Task is cancelled, stream finishes
    }

    // Should have received exactly the events before stop signalled
    #expect(count >= 2)
}

// MARK: - System Memory Provider Smoke Test

@Test("MemoryLogger.systemMemoryUsage() returns positive values")
func testSystemMemoryUsageReturnsPositive() throws {
    // SPEC: REQ-203 — default provider reads real mach task_info
    let (rss, vm) = try MemoryLogger.systemMemoryUsage()
    #expect(rss > 0, "RSS should be > 0 bytes")
    #expect(vm  > 0, "VM  should be > 0 bytes")
    #expect(vm >= rss, "VM should be >= RSS")
}
