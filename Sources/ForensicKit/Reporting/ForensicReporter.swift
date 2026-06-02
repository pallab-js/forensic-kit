// SPEC: REQ-503 — ForensicReporter for formatting ForensicEvents to JSON and Markdown reports
// SPEC: REQ-505 — Sendable compliance and Swift 6 concurrency safety

import Foundation

/// Formats a collection of `ForensicEvent` objects into highly-structured,
/// professional JSON or premium Markdown reports.
// SPEC: REQ-503
public struct ForensicReporter: Sendable {

    /// When `true` (default), Markdown reports use emoji glyphs in headings.
    /// Set to `false` for pure-text output compatible with all terminals and CI logs.
    public let useEmojis: Bool

    // MARK: - Init

    /// Creates a new reporter.
    /// - Parameter useEmojis: Whether Markdown reports include emoji headers. Default `true`.
    public init(useEmojis: Bool = true) {
        self.useEmojis = useEmojis
    }

    // MARK: - Emoji Helpers

    private func emoji(_ e: String, plain: String) -> String {
        useEmojis ? e : plain
    }

    // MARK: - JSON Generation

    /// Serializes forensic events into a standardized pretty-printed JSON array.
    ///
    /// - Parameter events: List of captured forensic events.
    /// - Returns: A pretty-printed JSON string.
    // SPEC: REQ-503 — JSON serialization format
    public func generateJSON(events: [ForensicEvent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Markdown Generation

    /// Formats forensic events into a premium, comprehensive Markdown report.
    ///
    /// - Parameters:
    ///   - events: List of captured forensic events.
    ///   - targetScanned: Contextual target that was audited (e.g., directory scanned).
    /// - Returns: A beautiful human-readable Markdown report.
    // SPEC: REQ-503 — Markdown report formatting structures
    public func generateMarkdown(events: [ForensicEvent], targetScanned: String) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())

        // Count distribution
        let totalCount = events.count
        let processEvents = events.filter { $0.source == .process }
        let memoryEvents = events.filter { $0.source == .memory }
        let networkEvents = events.filter { $0.source == .network }
        let fsEvents = events.filter { $0.source == .filesystem }

        let warningCount = events.filter { $0.severity == .warning }.count
        let criticalCount = events.filter { $0.severity == .critical }.count

        var md = ""
        md += "# \(emoji("🔍 ", plain: ""))Forensic Audit Report\n\n"
        md += "> **Generated on:** `\(timestamp)`\n"
        md += "> **Engine Version:** `ForensicKit v\(ForensicKit.version)`\n"
        md += "> **Target Audited:** `\(targetScanned)`\n\n"

        md += "## \(emoji("📊 ", plain: ""))Collection Summary\n\n"
        md += "| Subsystem | Event Count | Warnings / Critical |\n"
        md += "| :--- | :---: | :---: |\n"
        md += "| **Process Tree** | \(processEvents.count) | \(processEvents.filter { $0.severity != .info }.count) |\n"
        md += "| **Memory Monitor** | \(memoryEvents.count) | \(memoryEvents.filter { $0.severity != .info }.count) |\n"
        md += "| **Network Interfaces** | \(networkEvents.count) | \(networkEvents.filter { $0.severity != .info }.count) |\n"
        md += "| **File System Forensics** | \(fsEvents.count) | \(fsEvents.filter { $0.severity != .info }.count) |\n"
        md += "| **Total Observations** | **\(totalCount)** | **\(warningCount + criticalCount)** |\n\n"

        if warningCount + criticalCount > 0 {
            md += "### \(emoji("⚠️ ", plain: ""))Indicators of Anomaly / Alert Log\n\n"
            md += "| Subsystem | Severity | Details |\n"
            md += "| :--- | :---: | :--- |\n"
            let alertEvents = events.filter { $0.severity != .info }
            for event in alertEvents {
                let details = event.payload.metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                md += "| \(event.source.rawValue.capitalized) | `\(event.severity.rawValue.uppercased())` | \(details) |\n"
            }
            md += "\n"
        }

        // 1. Process tree findings
        md += "## \(emoji("🪵 ", plain: ""))Subsystem Audits\n\n"
        md += "### 1. Process tree (Darwin sysctl)\n\n"
        if processEvents.isEmpty {
            md += "*No process tree observations recorded.*\n\n"
        } else {
            md += "| PID | PPID | Executable Name | Metadata |\n"
            md += "| :---: | :---: | :--- | :--- |\n"
            for event in processEvents {
                let pid = event.payload.metadata["pid"] ?? "-"
                let ppid = event.payload.metadata["parentPid"] ?? "-"
                let name = event.payload.metadata["name"] ?? "unknown"
                let path = event.payload.metadata["path"] ?? "-"
                let sig = event.payload.metadata["signature"] ?? "unsigned"
                md += "| \(pid) | \(ppid) | `\(name)` | path=\(path), signature=\(sig) |\n"
            }
            md += "\n"
        }

        // 2. Memory checkpoints
        md += "### 2. Memory usage (Mach task_info)\n\n"
        if memoryEvents.isEmpty {
            md += "*No memory checkpoints recorded.*\n\n"
        } else {
            md += "| Checkpoint | RSS Bytes | VM Bytes | Severity |\n"
            md += "| :---: | :--- | :--- | :---: |\n"
            for (index, event) in memoryEvents.enumerated() {
                let rss = event.payload.metadata["rssBytes"] ?? "0"
                let vm = event.payload.metadata["vmBytes"] ?? "0"
                let sev = event.severity == .info ? "OK" : event.severity.rawValue.uppercased()
                md += "| \(index + 1) | \(rss) | \(vm) | `\(sev)` |\n"
            }
            md += "\n"
        }

        // 3. Network Interfaces
        md += "### 3. Network interface mapping (getifaddrs)\n\n"
        if networkEvents.isEmpty {
            md += "*No network interfaces mapped.*\n\n"
        } else {
            md += "| Interface | Family | Address | Loopback | Status | Flags |\n"
            md += "| :--- | :---: | :--- | :---: | :---: | :---: |\n"
            for event in networkEvents {
                let interface = event.payload.metadata["interface"] ?? "-"
                let family = event.payload.metadata["family"] ?? "-"
                let address = event.payload.metadata["address"] ?? "-"
                let loopback = event.payload.metadata["isLoopback"] == "true" ? "Yes" : "No"
                let status = event.payload.metadata["isUp"] == "true" ? "UP" : "DOWN"
                let flags = event.payload.metadata["flags"] ?? "-"
                md += "| `\(interface)` | \(family) | `\(address)` | \(loopback) | \(status) | `0x\(flags)` |\n"
            }
            md += "\n"
        }

        // 4. File System
        md += "### 4. File system snapshot\n\n"
        if fsEvents.isEmpty {
            md += "*No filesystem forensic snapshot gathered.*\n\n"
        } else {
            md += "| Type | Perms | Size (Bytes) | SHA-256 Hash | Path |\n"
            md += "| :---: | :---: | :--- | :--- | :--- |\n"
            for event in fsEvents {
                let type = event.payload.metadata["fileType"] ?? "regular"
                let perms = event.payload.metadata["permissions"] ?? "-"
                let size = event.payload.metadata["sizeBytes"] ?? "0"
                let hash = event.payload.metadata["sha256"] ?? "-"
                let path = event.payload.metadata["path"] ?? "-"
                let dest = event.payload.metadata["destination"]
                let pathVal = dest != nil ? "\(path) -> \(dest!)" : path
                md += "| \(type.capitalized) | `\(perms)` | \(size) | `\(hash)` | `\(pathVal)` |\n"
            }
            md += "\n"
        }

        md += "---\n*End of Forensic Audit Report.*\n"

        return md
    }
}
