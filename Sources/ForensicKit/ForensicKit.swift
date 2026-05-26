// SPEC: REQ-000 — ForensicKit library root; re-exports all public API
// SPEC: REQ-101 — ForensicEvent          (Models/ForensicEvent.swift)
// SPEC: REQ-102 — CollectionService      (Protocols/CollectionService.swift)
// SPEC: REQ-103 — ForensicError          (Errors/ForensicError.swift)
// SPEC: REQ-104 — EventPayload           (Models/EventPayload.swift)
// SPEC: REQ-105 — Sendable compliance    (all files)
// SPEC: REQ-201 — ProcessTreeService     (Services/ProcessTreeService.swift)
// SPEC: REQ-203 — MemoryLogger           (Services/MemoryLogger.swift)
// SPEC: REQ-301 — NetworkMonitorService  (Services/NetworkMonitorService.swift)
// SPEC: REQ-401 — FileSystemService      (Services/FileSystemService.swift)
// SPEC: REQ-502 — CollectionOrchestrator (Services/CollectionOrchestrator.swift)
// SPEC: REQ-503 — ForensicReporter      (Reporting/ForensicReporter.swift)

/// ForensicKit — macOS forensic data collection framework.
/// Built with Swift Package Manager. No Xcode required.
public enum ForensicKit {
    /// Semantic version of the library.
    public static let version = "0.5.0-phase5"
}
