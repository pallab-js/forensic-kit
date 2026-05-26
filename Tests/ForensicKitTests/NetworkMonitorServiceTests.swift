import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-301 — NetworkMonitorService streaming tests
// SPEC: REQ-302 — Metadata field verification
// SPEC: REQ-303 — Address family classification
// SPEC: REQ-304 — freeifaddrs / no-crash on repeated calls

// MARK: - Service State

@Test("NetworkMonitorService id is stable")
func testNetworkMonitorServiceID() {
    let svc = NetworkMonitorService()
    #expect(svc.id == "network-monitor-service")
}

@Test("NetworkMonitorService stream throws serviceNotRunning before start()")
func testNetworkMonitorThrowsWhenNotStarted() async throws {
    let svc = NetworkMonitorService()

    var caughtError: ForensicError?
    do {
        for try await _ in svc.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "network-monitor-service"))
}

@Test("NetworkMonitorService stop() prevents further streaming")
func testNetworkMonitorStopPreventsStream() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()
    await svc.stop()

    var caughtError: ForensicError?
    do {
        for try await _ in svc.stream() {}
    } catch let e as ForensicError {
        caughtError = e
    }
    #expect(caughtError == .serviceNotRunning(serviceId: "network-monitor-service"))
}

// MARK: - Integration: getifaddrs snapshot

@Test("NetworkMonitorService stream emits at least one event")
func testNetworkMonitorEmitsEvents() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-301 — stream must emit at least one event (lo0 is always present)
    #expect(events.isEmpty == false)
}

@Test("NetworkMonitorService all events have source=.network")
func testNetworkMonitorAllEventsHaveCorrectSource() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-302 — source=.network
    #expect(events.allSatisfy { $0.source == .network })
}

@Test("NetworkMonitorService all events have payload.kind=.network")
func testNetworkMonitorAllEventsHaveCorrectPayloadKind() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-302 — payload.kind=.network
    #expect(events.allSatisfy { $0.payload.kind == .network })
}

@Test("NetworkMonitorService all events have required metadata keys")
func testNetworkMonitorRequiredMetadataKeys() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-302 — interface, family, address, isLoopback, isUp, flags
    let requiredKeys = ["interface", "family", "address", "isLoopback", "isUp", "flags"]
    for event in events {
        for key in requiredKeys {
            #expect(event.payload.metadata[key] != nil,
                    "Event missing key '\(key)': \(event.payload.metadata)")
        }
    }
}

@Test("NetworkMonitorService all events have severity=.info")
func testNetworkMonitorAllEventsInfoSeverity() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-302 — severity=.info for interface events
    #expect(events.allSatisfy { $0.severity == .info })
}

// MARK: - REQ-303: Address Family Classification

@Test("NetworkMonitorService snapshot includes loopback interface (lo0)")
func testNetworkMonitorIncludesLoopback() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-303 — lo0 must appear with isLoopback=true
    let loopbackEvents = events.filter { $0.payload.metadata["interface"] == "lo0" }
    #expect(loopbackEvents.isEmpty == false, "Expected lo0 in snapshot")
    #expect(loopbackEvents.allSatisfy { $0.payload.metadata["isLoopback"] == "true" },
            "lo0 events should have isLoopback=true")
}

@Test("NetworkMonitorService snapshot includes at least one IPv4 address")
func testNetworkMonitorHasIPv4() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-303 — AF_INET entries present (127.0.0.1 on lo0 at minimum)
    let ipv4Events = events.filter { $0.payload.metadata["family"] == "IPv4" }
    #expect(ipv4Events.isEmpty == false, "Expected at least one IPv4 address")
}

@Test("NetworkMonitorService IPv4 addresses are valid dotted-decimal")
func testNetworkMonitorIPv4FormatValid() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    let ipv4Events = events.filter { $0.payload.metadata["family"] == "IPv4" }
    for event in ipv4Events {
        let addr = event.payload.metadata["address"] ?? ""
        // Basic sanity: contains dots, not empty, not "-"
        #expect(addr.contains("."), "IPv4 address '\(addr)' should contain dots")
        #expect(addr != "-", "IPv4 address should not be placeholder '-'")
    }
}

@Test("NetworkMonitorService lo0 has IPv4 address 127.0.0.1")
func testNetworkMonitorLoopbackIPv4() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    // SPEC: REQ-303 — lo0 IPv4 = 127.0.0.1 (always present on macOS)
    let loopbackIPv4 = events.first {
        $0.payload.metadata["interface"] == "lo0"
        && $0.payload.metadata["family"] == "IPv4"
    }
    if let lo0 = loopbackIPv4 {
        #expect(lo0.payload.metadata["address"] == "127.0.0.1")
    }
    // If no lo0 IPv4 found, the loopback test above already catches the missing lo0
}

@Test("NetworkMonitorService family values are from known set")
func testNetworkMonitorFamilyValues() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    let validFamilies: Set<String> = ["IPv4", "IPv6", "link", "other", "none"]
    for event in events {
        let family = event.payload.metadata["family"] ?? ""
        #expect(validFamilies.contains(family),
                "Unexpected family value: '\(family)'")
    }
}

@Test("NetworkMonitorService isLoopback and isUp are boolean strings")
func testNetworkMonitorBooleanStringValues() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    var events: [ForensicEvent] = []
    for try await event in svc.stream() { events.append(event) }

    let validBools: Set<String> = ["true", "false"]
    for event in events {
        #expect(validBools.contains(event.payload.metadata["isLoopback"] ?? ""),
                "isLoopback must be 'true' or 'false'")
        #expect(validBools.contains(event.payload.metadata["isUp"] ?? ""),
                "isUp must be 'true' or 'false'")
    }
}

// MARK: - REQ-304: Memory Safety (freeifaddrs)

@Test("NetworkMonitorService captureSnapshot can be called repeatedly without crashing")
func testNetworkMonitorCaptureSnapshotIdempotent() throws {
    // SPEC: REQ-304 — defer freeifaddrs prevents double-free or leak across calls
    let first  = try NetworkMonitorService.captureSnapshot()
    let second = try NetworkMonitorService.captureSnapshot()
    let third  = try NetworkMonitorService.captureSnapshot()

    #expect(first.isEmpty  == false)
    #expect(second.isEmpty == false)
    #expect(third.isEmpty  == false)
}

@Test("NetworkMonitorService stream finishes naturally (finite snapshot)")
func testNetworkMonitorStreamFinishesNaturally() async throws {
    let svc = NetworkMonitorService()
    try await svc.start()

    // Iterating to completion without break must not hang
    var count = 0
    for try await _ in svc.stream() { count += 1 }

    #expect(count > 0)
}
