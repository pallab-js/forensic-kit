// SPEC: REQ-201 — ProcessTreeService: actor-based, sysctl(KERN_PROC_ALL) snapshot stream
// SPEC: REQ-202 — Each event carries pid, name, parentPid metadata
// SPEC: REQ-205 — Actor with nonisolated let id; mutable state actor-isolated

import Darwin
import Foundation
import OSLog
import Security

/// Enumerates all running macOS processes via `sysctl(KERN_PROC_ALL)` and
/// emits one `ForensicEvent` per process as a finite `AsyncThrowingStream`.
public actor ProcessTreeService: CollectionService {

    private static let log = Logger(subsystem: "com.forensickit", category: "process")

    // MARK: - CollectionService Identity

    /// Stable service identifier.
    // SPEC: REQ-205 — nonisolated let, accessible without await
    public nonisolated let id = "process-tree-service"

    // MARK: - Actor-Isolated State

    private var isRunning = false

    // MARK: - Init

    public init() {}

    // MARK: - CollectionService Lifecycle

    // SPEC: REQ-201 — start() lifecycle
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
    }

    // SPEC: REQ-201 — stop() lifecycle
    public func stop() async {
        isRunning = false
    }

    // MARK: - CollectionService Streaming

    /// Returns a finite stream of `ForensicEvent` values — one per running process.
    ///
    /// Throws `ForensicError.serviceNotRunning` if called before `start()`.
    /// Throws `ForensicError.collectionFailed` if `sysctl` fails.
    // SPEC: REQ-201 — AsyncThrowingStream snapshot
    public nonisolated func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        let serviceId = self.id   // nonisolated let — safe to access here
        return AsyncThrowingStream { continuation in
            Task {
                // Validate service state (actor-isolated access)
                guard await self.isRunning else {
                    continuation.finish(
                        throwing: ForensicError.serviceNotRunning(serviceId: serviceId)
                    )
                    return
                }

                do {
                    let events = try ProcessTreeService.captureSnapshot()
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

    /// Returns the full executable path for a PID via `proc_pidpath`.
    /// Returns `nil` if the path cannot be resolved (permission denied, zombie, etc.).
    // SPEC: REQ-202 — executable path via proc_pidpath
    internal static func executablePath(for pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE = 4096 on macOS
        let bufSize = 4096
        var buffer = [CChar](repeating: 0, count: bufSize)
        let ret = proc_pidpath(pid, &buffer, UInt32(bufSize))
        guard ret > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Retrieves the code signature status of a process using the macOS Security framework.
    internal static func signatureStatus(for pid: Int32) -> String {
        // For special processes like kernel_task or Mock PIDs in tests, Security framework may not check
        guard pid > 0 else { return "unsigned" }
        
        var guest: SecCode?
        let attributes: [CFString: Any] = [
            kSecGuestAttributePid: pid
        ]
        
        let status = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, [], &guest)
        guard status == errSecSuccess, let guestCode = guest else {
            return "unsigned"
        }
        
        let validityStatus = SecCodeCheckValidity(guestCode, SecCSFlags(rawValue: 0), nil)
        if validityStatus == errSecSuccess {
            return "valid"
        } else if validityStatus == -67062 { // errSecCSUnsigned (-67062)
            return "unsigned"
        } else {
            return "invalid"
        }
    }

    /// Enumerates all processes using `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)`.
    ///
    /// This is a `static` (non-isolated) function so it can be called from both
    /// actor-isolated and nonisolated contexts without data races.
    // SPEC: REQ-201 — sysctl KERN_PROC_ALL
    // SPEC: REQ-202 — pid, name, parentPid metadata
    internal static func captureSnapshot() throws -> [ForensicEvent] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        var procs: [kinfo_proc] = []
        var actualSize = 0
        
        let maxRetries = 3
        var retryCount = 0
        var success = false
        
        while !success && retryCount < maxRetries {
            // ── Step 1: Query required buffer size ──────────────────────────────
            var bufferSize = 0
            guard sysctl(&mib, 4, nil, &bufferSize, nil, 0) == 0 else {
                throw ForensicError.collectionFailed(
                    "sysctl size query failed — errno \(errno): \(String(cString: strerror(errno)))"
                )
            }
            
            // Add an increasing safety margin per retry (16, 64, 256) to handle process count fluctuations
            let margin = 16 << (retryCount * 2)
            let capacity = (bufferSize / MemoryLayout<kinfo_proc>.stride) + margin
            procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
            actualSize = bufferSize + (margin * MemoryLayout<kinfo_proc>.stride)
            
            // ── Step 2: Fetch process data ──────────────────────────────────────
            if sysctl(&mib, 4, &procs, &actualSize, nil, 0) == 0 {
                success = true
            } else {
                if errno == ENOMEM {
                    retryCount += 1
                    log.debug("sysctl failed with ENOMEM, retrying \(retryCount)/\(maxRetries) with larger capacity")
                } else {
                    throw ForensicError.collectionFailed(
                        "sysctl data fetch failed — errno \(errno): \(String(cString: strerror(errno)))"
                    )
                }
            }
        }
        
        guard success else {
            throw ForensicError.collectionFailed("sysctl data fetch failed after \(maxRetries) retries due to rapid process listing changes.")
        }

        let count = actualSize / MemoryLayout<kinfo_proc>.stride
        log.debug("captured \(count) process entries from sysctl")

        // ── Step 3: Map kinfo_proc → ForensicEvent ──────────────────────────
        return procs.prefix(count).compactMap { kproc -> ForensicEvent? in
            let pid  = Int(kproc.kp_proc.p_pid)
            let ppid = Int(kproc.kp_eproc.e_ppid)

            // kp_proc.p_comm is a C fixed-length char array (MAXCOMLEN + 1 = 17 bytes)
            var comm = kproc.kp_proc.p_comm
            let name: String = withUnsafeBytes(of: &comm) { rawBytes in
                let cStrBytes = rawBytes.bindMemory(to: CChar.self)
                let prefix = cStrBytes.prefix(while: { $0 != 0 })
                return String(decoding: prefix.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }

            // Filter out zombie/empty entries (pid 0 with no name)
            guard pid > 0 || !name.isEmpty else { return nil }

            // SPEC: REQ-202 — full executable path via proc_pidpath
            let execPath = executablePath(for: Int32(pid))
            
            // Get code signature status using Apple Security framework
            let sigStatus = signatureStatus(for: Int32(pid))

            // SPEC: REQ-202 — ForensicEvent with source=.process, required metadata
            return ForensicEvent(
                severity: .info,
                source: .process,
                payload: .process(pid: pid, name: name.isEmpty ? "(unknown)" : name, parentPid: ppid, path: execPath, extra: ["signature": sigStatus])
            )
        }
    }
}
