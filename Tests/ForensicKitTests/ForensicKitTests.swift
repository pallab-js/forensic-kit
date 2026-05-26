import Testing
@testable import ForensicKit

// SPEC: REQ-000 — Scaffold smoke test: library resolves and version is accessible

@Test("ForensicKit version is accessible")
func testVersionExists() {
    #expect(ForensicKit.version.isEmpty == false)
}
