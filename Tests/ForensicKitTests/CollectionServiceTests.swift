import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-102 — CollectionService protocol + AnyCollectionService tests
// SPEC: REQ-104 — EventPayload tests

// MARK: - Mock CollectionService

/// A deterministic, synchronous mock that emits a fixed set of events.
private actor MockCollectionService: CollectionService {

    nonisolated let id = "mock-collection-service"

    private var isRunning = false
    private let eventsToEmit: [ForensicEvent]

    init(events: [ForensicEvent]) {
        self.eventsToEmit = events
    }

    nonisolated func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let running = await self.isRunning
                guard running else {
                    continuation.finish(throwing: ForensicError.serviceNotRunning(serviceId: self.id))
                    return
                }
                let events = await self.eventsToEmit
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    func start() async throws {
        guard !isRunning else { return }
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }
}

// MARK: - CollectionService Protocol Tests

@Test("MockCollectionService satisfies CollectionService protocol")
func testMockConformsToProtocol() {
    let svc: any CollectionService = MockCollectionService(events: [])
    #expect(svc.id == "mock-collection-service")
}

@Test("CollectionService streams throw when not started")
func testStreamThrowsWhenNotStarted() async throws {
    let svc = MockCollectionService(events: [
        ForensicEvent(severity: .info, source: .system, payload: .system(event: "boot"))
    ])
    // Do NOT call start() — stream should throw serviceNotRunning
    var caughtError: ForensicError?
    do {
        for try await _ in svc.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "mock-collection-service"))
}

@Test("CollectionService streams all events after start()")
func testStreamEmitsAllEvents() async throws {
    let events = [
        ForensicEvent(severity: .info,    source: .process, payload: .process(pid: 1, name: "launchd")),
        ForensicEvent(severity: .warning, source: .memory,  payload: .memory(rssBytes: 1_000_000, vmBytes: 2_000_000)),
        ForensicEvent(severity: .critical,source: .network, payload: .network(interface: "en0", family: "IPv4", address: "127.0.0.1", isLoopback: false, isUp: true, flags: "8049"))
    ]

    let svc = MockCollectionService(events: events)
    try await svc.start()

    var received: [ForensicEvent] = []
    for try await event in svc.stream() {
        received.append(event)
    }

    #expect(received.count == 3)
    #expect(received[0].source == .process)
    #expect(received[1].source == .memory)
    #expect(received[2].source == .network)
}

@Test("AnyCollectionService wraps and forwards to underlying service")
func testAnyCollectionServiceWrapping() async throws {
    let inner = MockCollectionService(events: [
        ForensicEvent(severity: .info, source: .filesystem, payload: .filesystem(path: "/etc/hosts"))
    ])
    try await inner.start()

    let wrapped = AnyCollectionService(inner)
    #expect(wrapped.id == "mock-collection-service")

    var count = 0
    for try await _ in wrapped.stream() { count += 1 }
    #expect(count == 1)
}

// MARK: - EventPayload Tests  (SPEC: REQ-104)

@Test("EventPayload.process factory populates metadata correctly")
func testProcessPayload() {
    let p = EventPayload.process(pid: 42, name: "Finder", parentPid: 1, path: "/System/Finder")
    #expect(p.kind == .process)
    #expect(p.metadata["pid"]       == "42")
    #expect(p.metadata["name"]      == "Finder")
    #expect(p.metadata["parentPid"] == "1")
    #expect(p.metadata["path"]      == "/System/Finder")
}

@Test("EventPayload.memory factory populates metadata correctly")
func testMemoryPayload() {
    let p = EventPayload.memory(rssBytes: 512_000, vmBytes: 1_024_000)
    #expect(p.kind == .memory)
    #expect(p.metadata["rssBytes"] == "512000")
    #expect(p.metadata["vmBytes"]  == "1024000")
}

@Test("EventPayload.network factory populates metadata correctly")
func testNetworkPayload() {
    let p = EventPayload.network(interface: "en0", family: "IPv4", address: "192.168.1.1", isLoopback: false, isUp: true, flags: "8049")
    #expect(p.kind == .network)
    #expect(p.metadata["interface"]  == "en0")
    #expect(p.metadata["family"]     == "IPv4")
    #expect(p.metadata["address"]    == "192.168.1.1")
    #expect(p.metadata["isLoopback"] == "false")
    #expect(p.metadata["isUp"]       == "true")
    #expect(p.metadata["flags"]      == "8049")
}

@Test("EventPayload.filesystem factory populates metadata correctly")
func testFilesystemPayload() {
    let p = EventPayload.filesystem(path: "/tmp/malware", sha256: "abc123", permissions: "0755")
    #expect(p.kind == .filesystem)
    #expect(p.metadata["path"]        == "/tmp/malware")
    #expect(p.metadata["sha256"]      == "abc123")
    #expect(p.metadata["permissions"] == "0755")
}

@Test("EventPayload.system factory populates metadata correctly")
func testSystemPayload() {
    let p = EventPayload.system(event: "kext-load", extra: ["kext": "com.foo.bar"])
    #expect(p.kind == .system)
    #expect(p.metadata["event"] == "kext-load")
    #expect(p.metadata["kext"]  == "com.foo.bar")
}

@Test("All 5 PayloadKind cases are represented in CaseIterable")
func testAllPayloadKinds() {
    #expect(EventPayload.PayloadKind.allCases.count == 5)
    let expected: [EventPayload.PayloadKind] = [.process, .memory, .network, .filesystem, .system]
    for kind in expected {
        #expect(EventPayload.PayloadKind.allCases.contains(kind))
    }
}

@Test("EventPayload survives JSON encode/decode for all 5 kinds")
func testEventPayloadCodableAllKinds() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    let payloads: [EventPayload] = [
        .process(pid: 1, name: "launchd"),
        .memory(rssBytes: 100, vmBytes: 200),
        .network(interface: "lo0", family: "IPv4", address: "127.0.0.1", isLoopback: true, isUp: true, flags: "8049"),
        .filesystem(path: "/etc"),
        .system(event: "login")
    ]

    for original in payloads {
        let data    = try encoder.encode(original)
        let decoded = try decoder.decode(EventPayload.self, from: data)
        #expect(decoded.kind     == original.kind)
        #expect(decoded.metadata == original.metadata)
    }
}
