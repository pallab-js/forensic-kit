import Testing
@testable import ForensicKit

// SPEC: REQ-000 — Library version is accessible (scaffold smoke test)

@Test("ForensicKit version is accessible and non-empty")
func testVersionExists() {
    #expect(ForensicKit.version.isEmpty == false)
    #expect(ForensicKit.version == "0.3.0-phase3")
}
