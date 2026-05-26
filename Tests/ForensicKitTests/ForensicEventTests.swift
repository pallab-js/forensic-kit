import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-101 — ForensicEvent unit tests

// MARK: - Creation & Field Assertions

@Test("ForensicEvent fields are set correctly on init")
func testForensicEventFieldsOnInit() {
    let fixedID        = UUID()
    let fixedTimestamp = Date(timeIntervalSince1970: 1_000_000)
    let payload        = EventPayload(kind: .process, metadata: ["pid": "42"])

    let event = ForensicEvent(
        id:        fixedID,
        timestamp: fixedTimestamp,
        severity:  .warning,
        source:    .process,
        payload:   payload
    )

    #expect(event.id        == fixedID)
    #expect(event.timestamp == fixedTimestamp)
    #expect(event.severity  == .warning)
    #expect(event.source    == .process)
    #expect(event.payload   == payload)
}

@Test("ForensicEvent default id and timestamp are non-nil")
func testForensicEventDefaults() {
    let before = Date()
    let event  = ForensicEvent(severity: .info, source: .system, payload: .system(event: "boot"))
    let after  = Date()

    #expect(event.timestamp >= before)
    #expect(event.timestamp <= after)
}

// MARK: - Identifiable

@Test("Two ForensicEvents have different IDs by default")
func testForensicEventUniqueIDs() {
    let e1 = ForensicEvent(severity: .info, source: .memory, payload: .memory(rssBytes: 100, vmBytes: 200))
    let e2 = ForensicEvent(severity: .info, source: .memory, payload: .memory(rssBytes: 100, vmBytes: 200))
    #expect(e1.id != e2.id)
}

// MARK: - Codable Roundtrip

@Test("ForensicEvent survives JSON encode/decode roundtrip")
func testForensicEventCodableRoundtrip() throws {
    let original = ForensicEvent(
        id:        UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        timestamp: Date(timeIntervalSince1970: 0),
        severity:  .critical,
        source:    .network,
        payload:   .network(
            localAddress:  "127.0.0.1:9000",
            remoteAddress: "93.184.216.34:443",
            state:         "ESTABLISHED",
            proto:         "TCP"
        )
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ForensicEvent.self, from: data)

    #expect(decoded.id                         == original.id)
    #expect(decoded.severity                   == original.severity)
    #expect(decoded.source                     == original.source)
    #expect(decoded.payload.kind               == original.payload.kind)
    #expect(decoded.payload.metadata["state"]  == "ESTABLISHED")
}

// MARK: - Hashable

@Test("ForensicEvent is Hashable")
func testForensicEventHashable() {
    let id    = UUID()
    let ts    = Date(timeIntervalSince1970: 500)
    let event = ForensicEvent(id: id, timestamp: ts, severity: .info, source: .system, payload: .system(event: "test"))

    var set = Set<ForensicEvent>()
    set.insert(event)
    set.insert(event) // duplicate
    #expect(set.count == 1)
}

// MARK: - Severity & Source CaseIterable

@Test("Severity has exactly 3 cases")
func testSeverityCases() {
    #expect(ForensicEvent.Severity.allCases.count == 3)
    #expect(ForensicEvent.Severity.allCases.contains(.info))
    #expect(ForensicEvent.Severity.allCases.contains(.warning))
    #expect(ForensicEvent.Severity.allCases.contains(.critical))
}

@Test("Source has exactly 5 cases")
func testSourceCases() {
    #expect(ForensicEvent.Source.allCases.count == 5)
    let expected: [ForensicEvent.Source] = [.process, .memory, .network, .filesystem, .system]
    for s in expected { #expect(ForensicEvent.Source.allCases.contains(s)) }
}
