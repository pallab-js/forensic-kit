// SPEC: REQ-301 — NetworkMonitorService: actor, getifaddrs(3) snapshot stream
// SPEC: REQ-302 — Metadata: interface, family, address, isLoopback, isUp, flags
// SPEC: REQ-303 — AF_INET / AF_INET6 / AF_LINK / other classification
// SPEC: REQ-304 — freeifaddrs via defer in all exit paths
// SPEC: REQ-305 — Actor, nonisolated let id, mutable state actor-isolated

import Darwin
import Foundation
import OSLog

/// Enumerates all network interfaces and their addresses using `getifaddrs(3)` and
/// emits one `ForensicEvent` per address entry as a finite `AsyncThrowingStream`.
///
/// This is a **point-in-time snapshot** — the stream yields all discovered interface
/// addresses and then finishes. No network calls are made; `getifaddrs` is a local
/// kernel interface (equivalent to `ifconfig -a`).
///
/// ## Emitted metadata keys (per event)
/// | Key          | Example value        |
/// |---|---|
/// | `interface`  | `"en0"`, `"lo0"`    |
/// | `family`     | `"IPv4"`, `"IPv6"`, `"link"`, `"other"` |
/// | `address`    | `"192.168.1.1"`, `"fe80::1"`, `"a4:83:e7:xx:xx:xx"` |
/// | `isLoopback` | `"true"` / `"false"` |
/// | `isUp`       | `"true"` / `"false"` |
/// | `flags`      | hex string of `ifa_flags` |
// SPEC: REQ-301
public actor NetworkMonitorService: CollectionService {

    private static let log = Logger(subsystem: "com.forensickit", category: "network")

    // MARK: - Identity

    public nonisolated let id = "network-monitor-service"

    // MARK: - Actor-Isolated State

    private var isRunning = false

    // MARK: - Init

    public init() {}

    // MARK: - CollectionService Lifecycle

    // SPEC: REQ-301 — start() lifecycle
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
    }

    // SPEC: REQ-301 — stop() lifecycle
    public func stop() async {
        isRunning = false
    }

    // MARK: - CollectionService Streaming

    /// Returns a finite snapshot stream of network interface address events.
    ///
    /// Throws `ForensicError.serviceNotRunning` if called before `start()`.
    /// Throws `ForensicError.collectionFailed` if `getifaddrs` fails.
    // SPEC: REQ-301 — AsyncThrowingStream snapshot
    public nonisolated func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        let svcId = self.id   // nonisolated let — safe
        return AsyncThrowingStream { continuation in
            Task {
                guard await self.isRunning else {
                    continuation.finish(
                        throwing: ForensicError.serviceNotRunning(serviceId: svcId)
                    )
                    return
                }
                do {
                    let events = try NetworkMonitorService.captureSnapshot()
                    for event in events {
                        guard !Task.isCancelled else { break }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Snapshot Implementation

    /// Calls `getifaddrs(3)`, walks the linked list, and maps each entry to a
    /// `ForensicEvent`. Always calls `freeifaddrs` via `defer`.
    // SPEC: REQ-301 — getifaddrs enumeration
    // SPEC: REQ-304 — defer freeifaddrs in all exit paths
    internal static func captureSnapshot() throws -> [ForensicEvent] {
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil

        guard getifaddrs(&ifap) == 0 else {
            throw ForensicError.collectionFailed(
                "getifaddrs failed — errno \(errno): \(String(cString: strerror(errno)))"
            )
        }
        // SPEC: REQ-304 — unconditional defer, covers all code paths below
        defer { freeifaddrs(ifap) }

        var events: [ForensicEvent] = []
        var cursor = ifap

        while let ifa = cursor {
            if let event = makeEvent(from: ifa) {
                events.append(event)
            }
            cursor = ifa.pointee.ifa_next
        }

        log.debug("captured \(events.count) interface addresses")
        return events
    }

    // MARK: - Per-Interface Event Builder

    /// Converts a single `ifaddrs` entry into a `ForensicEvent`.
    // SPEC: REQ-302 — all metadata keys
    // SPEC: REQ-303 — address family classification
    private static func makeEvent(
        from ifa: UnsafeMutablePointer<ifaddrs>
    ) -> ForensicEvent? {
        let ifaName  = ifa.pointee.ifa_name
        let name     = ifaName != nil ? String(cString: ifaName!) : "unknown"
        let flags    = ifa.pointee.ifa_flags
        // SPEC: REQ-302 — isLoopback, isUp from ifa_flags
        let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
        let isUp       = (flags & UInt32(IFF_UP)) != 0

        guard let addr = ifa.pointee.ifa_addr else {
            // No address — still emit a record so the interface is visible
            return ForensicEvent(
                severity: .info,
                source: .network,
                payload: EventPayload(kind: .network, metadata: [
                    "interface":  name,
                    "family":     "none",
                    "address":    "-",
                    "isLoopback": isLoopback ? "true" : "false",
                    "isUp":       isUp ? "true" : "false",
                    "flags":      String(flags, radix: 16, uppercase: false)
                ])
            )
        }

        // SPEC: REQ-303 — classify by sa_family
        let saFamily = Int32(addr.pointee.sa_family)
        let family:  String
        let address: String

        switch saFamily {
        case AF_INET:
            // SPEC: REQ-303 — IPv4 via inet_ntop
            family  = "IPv4"
            address = ipv4String(from: addr) ?? "-"

        case AF_INET6:
            // SPEC: REQ-303 — IPv6 via inet_ntop
            family  = "IPv6"
            address = ipv6String(from: addr) ?? "-"

        case AF_LINK:
            // SPEC: REQ-303 — link-layer MAC from sockaddr_dl
            family  = "link"
            address = macString(from: addr) ?? "-"

        default:
            // SPEC: REQ-303 — other address families
            family  = "other"
            address = "-"
        }

        // SPEC: REQ-302 — build event with all required metadata keys
        return ForensicEvent(
            severity: .info,
            source: .network,
            payload: EventPayload(kind: .network, metadata: [
                "interface":  name,
                "family":     family,
                "address":    address,
                "isLoopback": isLoopback ? "true" : "false",
                "isUp":       isUp ? "true" : "false",
                "flags":      String(flags, radix: 16, uppercase: false)
            ])
        )
    }

    // MARK: - Address Formatting Helpers

    /// Converts a `sockaddr` (AF_INET) to a dotted-decimal IPv4 string via `inet_ntop`.
    // SPEC: REQ-303 — AF_INET
    private static func ipv4String(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var inAddr = sin.pointee.sin_addr
            guard inet_ntop(AF_INET, &inAddr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buf)
        }
    }

    /// Converts a `sockaddr` (AF_INET6) to a colon-hex IPv6 string via `inet_ntop`.
    // SPEC: REQ-303 — AF_INET6
    private static func ipv6String(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        return addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
            var in6Addr = sin6.pointee.sin6_addr
            guard inet_ntop(AF_INET6, &in6Addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buf)
        }
    }

    /// Extracts the MAC address from a `sockaddr` (AF_LINK / `sockaddr_dl`).
    ///
    /// The `sdl_data` field contains `sdl_nlen` bytes of interface name
    /// followed by `sdl_alen` bytes of link-layer address.
    // SPEC: REQ-303 — AF_LINK
    private static func macString(from addr: UnsafeMutablePointer<sockaddr>) -> String? {
        return addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl in
            let nlen = Int(sdl.pointee.sdl_nlen)  // interface name bytes
            let alen = Int(sdl.pointee.sdl_alen)  // address bytes

            // Only handle standard 6-byte (Ethernet) MACs
            guard alen == 6 else { return nil }

            // sdl_data is a 12-byte CChar tuple; MAC starts at offset nlen
            var dataCopy = sdl.pointee.sdl_data
            return withUnsafeBytes(of: &dataCopy) { rawBytes -> String? in
                guard nlen + alen <= rawBytes.count else { return nil }
                return (0 ..< alen)
                    .map { String(format: "%02x", rawBytes[nlen + $0]) }
                    .joined(separator: ":")
            }
        }
    }
}
