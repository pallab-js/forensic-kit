// SPEC: REQ-104 — EventPayload: Sendable, Codable struct with PayloadKind + metadata
// SPEC: REQ-105 — Sendable conformance for Swift 6 strict concurrency

import Foundation

/// Structured payload attached to every `ForensicEvent`.
///
/// `EventPayload` uses a flat, `Codable`-friendly design:
/// a `kind` discriminator plus a `metadata` key-value dictionary
/// that each collection service populates with domain-specific fields.
///
/// This avoids enum-with-associated-values Codable complexity while
/// remaining fully extensible across all collection phases.
public struct EventPayload: Sendable, Codable, Hashable {

    // MARK: - Properties

    /// The category of forensic event this payload describes.
    // SPEC: REQ-104 — all five PayloadKind cases
    public let kind: PayloadKind

    /// Domain-specific key-value metadata.
    ///
    /// Each collection service documents the keys it populates.
    /// Examples: `["pid": "1234", "name": "launchd"]` for a process event.
    public let metadata: [String: String]

    // MARK: - Init

    /// Creates a new `EventPayload`.
    ///
    /// - Parameters:
    ///   - kind: The payload category.
    ///   - metadata: Key-value metadata specific to the event kind.
    public init(kind: PayloadKind, metadata: [String: String] = [:]) {
        self.kind = kind
        self.metadata = metadata
    }
}

// MARK: - PayloadKind

extension EventPayload {

    /// Discriminator indicating which forensic subsystem produced the payload.
    // SPEC: REQ-104 — process | memory | network | filesystem | system
    public enum PayloadKind: String, Sendable, Codable, CaseIterable, Hashable {
        /// A process-tree observation (PID, parent, name, path).
        case process
        /// A memory usage snapshot (RSS, VM size, checkpoint).
        case memory
        /// A network connection record (local/remote addr, state, proto).
        case network
        /// A file system metadata observation (path, hash, permissions).
        case filesystem
        /// An OS-level system event (boot, shutdown, login, kext load).
        case system
    }
}

// MARK: - Convenience Factories

extension EventPayload {

    /// Creates a process-event payload.
    public static func process(
        pid: Int,
        name: String,
        parentPid: Int? = nil,
        path: String? = nil,
        extra: [String: String] = [:]
    ) -> EventPayload {
        var meta: [String: String] = [
            "pid": String(pid),
            "name": name
        ]
        if let pp = parentPid { meta["parentPid"] = String(pp) }
        if let p  = path      { meta["path"] = p }
        meta.merge(extra) { _, new in new }
        return EventPayload(kind: .process, metadata: meta)
    }

    /// Creates a memory-event payload.
    public static func memory(
        rssBytes: Int,
        vmBytes: Int,
        extra: [String: String] = [:]
    ) -> EventPayload {
        var meta: [String: String] = [
            "rssBytes": String(rssBytes),
            "vmBytes": String(vmBytes)
        ]
        meta.merge(extra) { _, new in new }
        return EventPayload(kind: .memory, metadata: meta)
    }

    /// Creates a network-interface event payload.
    /// Matches the schema emitted by `NetworkMonitorService`.
    public static func network(
        interface: String,
        family: String,
        address: String,
        isLoopback: Bool,
        isUp: Bool,
        flags: String,
        extra: [String: String] = [:]
    ) -> EventPayload {
        var meta: [String: String] = [
            "interface": interface,
            "family": family,
            "address": address,
            "isLoopback": isLoopback ? "true" : "false",
            "isUp": isUp ? "true" : "false",
            "flags": flags
        ]
        meta.merge(extra) { _, new in new }
        return EventPayload(kind: .network, metadata: meta)
    }

    /// Creates a filesystem-event payload.
    public static func filesystem(
        path: String,
        sha256: String? = nil,
        permissions: String? = nil,
        extra: [String: String] = [:]
    ) -> EventPayload {
        var meta: [String: String] = ["path": path]
        if let h = sha256       { meta["sha256"] = h }
        if let p = permissions  { meta["permissions"] = p }
        meta.merge(extra) { _, new in new }
        return EventPayload(kind: .filesystem, metadata: meta)
    }

    /// Creates a system-event payload.
    public static func system(
        event: String,
        extra: [String: String] = [:]
    ) -> EventPayload {
        var meta: [String: String] = ["event": event]
        meta.merge(extra) { _, new in new }
        return EventPayload(kind: .system, metadata: meta)
    }
}
