import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-201 — ProcessTreeService tests
// SPEC: REQ-202 — Metadata field verification

// MARK: - Service State Tests

@Test("ProcessTreeService stream throws serviceNotRunning before start()")
func testProcessTreeStreamThrowsWhenNotStarted() async throws {
    let svc = ProcessTreeService()
    // Deliberately do NOT call start()

    var caughtError: ForensicError?
    do {
        for try await _ in svc.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "process-tree-service"))
}

@Test("ProcessTreeService id is stable")
func testProcessTreeServiceID() {
    let svc = ProcessTreeService()
    #expect(svc.id == "process-tree-service")
    #expect(svc.id == svc.id) // stable
}

// MARK: - Integration: sysctl snapshot

@Test("ProcessTreeService stream emits at least one process event")
func testProcessTreeStreamEmitsEvents() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() {
        events.append(event)
    }

    // Stream must finish naturally (single snapshot)
    #expect(events.isEmpty == false)
}

@Test("ProcessTreeService all events have source=.process")
func testProcessTreeAllEventsHaveCorrectSource() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-202 — source=.process
    #expect(events.allSatisfy { $0.source == .process })
}

@Test("ProcessTreeService all events have payload.kind=.process")
func testProcessTreePayloadKind() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-202 — payload.kind=.process
    #expect(events.allSatisfy { $0.payload.kind == .process })
}

@Test("ProcessTreeService events have required metadata keys")
func testProcessTreeMetadataKeys() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-202 — pid, name, parentPid present
    for event in events {
        #expect(event.payload.metadata["pid"] != nil,
                "Missing 'pid' in event: \(event.payload.metadata)")
        #expect(event.payload.metadata["name"] != nil,
                "Missing 'name' in event: \(event.payload.metadata)")
        #expect(event.payload.metadata["parentPid"] != nil,
                "Missing 'parentPid' in event: \(event.payload.metadata)")
    }
}

@Test("ProcessTreeService stream includes launchd (pid=1)")
func testProcessTreeIncludesLaunchd() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // launchd (pid=1) is always present on macOS
    // SPEC: REQ-201 — KERN_PROC_ALL captures all processes
    let hasPid1 = events.contains { $0.payload.metadata["pid"] == "1" }
    #expect(hasPid1, "Expected pid=1 (launchd) in process snapshot")
}

@Test("ProcessTreeService all pid metadata values are numeric")
func testProcessTreePidsAreNumeric() async throws {
    let svc = ProcessTreeService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    for event in events {
        if let pidStr = event.payload.metadata["pid"] {
            #expect(Int(pidStr) != nil, "pid '\(pidStr)' is not numeric")
        }
    }
}

@Test("ProcessTreeService captureSnapshot is idempotent — two calls both return results")
func testProcessTreeCaptureSnapshotIdempotent() throws {
    let first  = try ProcessTreeService.captureSnapshot()
    let second = try ProcessTreeService.captureSnapshot()

    #expect(first.isEmpty  == false)
    #expect(second.isEmpty == false)
}

@Test("ProcessTreeService stop() prevents further streaming")
func testProcessTreeStopPreventsStream() async throws {
    let svc = ProcessTreeService()
    try await svc.start()
    await svc.stop()

    var caughtError: ForensicError?
    do {
        for try await _ in svc.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "process-tree-service"))
}

@Test("ProcessTreeService signatureStatus is correct for current process")
func testProcessTreeSignatureStatus() {
    let pid = ProcessInfo.processInfo.processIdentifier
    let sig = ProcessTreeService.signatureStatus(for: Int32(pid))
    #expect(sig == "valid" || sig == "unsigned")
}
