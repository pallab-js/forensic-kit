// SPEC: REQ-201 — ProcessTreeService: actor-based, sysctl(KERN_PROC_ALL) snapshot stream
// SPEC: REQ-202 — Each event carries pid, name, parentPid metadata
// SPEC: REQ-205 — Actor with nonisolated let id; mutable state actor-isolated

import Darwin
import Foundation

/// Enumerates all running macOS processes via `sysctl(KERN_PROC_ALL)` and
/// emits one `ForensicEvent` per process as a finite `AsyncThrowingStream`.
///
/// The stream is a **point-in-time snapshot**: it yields all discovered processes
/// then finishes. Call `stream()` again to take a new snapshot.
///
/// ## Usage
/// ```swift
/// let service = ProcessTreeService()
/// try await service.start()
/// for try await event in service.stream() {
///     print(event.payload.metadata["name"] ?? "?")
/// }
/// ```
// SPEC: REQ-201
public actor ProcessTreeService: CollectionService {

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

    /// Enumerates all processes using `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)`.
    ///
    /// This is a `static` (non-isolated) function so it can be called from both
    /// actor-isolated and nonisolated contexts without data races.
    // SPEC: REQ-201 — sysctl KERN_PROC_ALL
    // SPEC: REQ-202 — pid, name, parentPid metadata
    internal static func captureSnapshot() throws -> [ForensicEvent] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]

        // ── Step 1: Query required buffer size ──────────────────────────────
        var bufferSize = 0
        guard sysctl(&mib, 4, nil, &bufferSize, nil, 0) == 0 else {
            throw ForensicError.collectionFailed(
                "sysctl size query failed — errno \(errno): \(String(cString: strerror(errno)))"
            )
        }

        // Add a safety margin: process count can change between calls
        let capacity = (bufferSize / MemoryLayout<kinfo_proc>.stride) + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var actualSize = bufferSize + (16 * MemoryLayout<kinfo_proc>.stride)

        // ── Step 2: Fetch process data ──────────────────────────────────────
        guard sysctl(&mib, 4, &procs, &actualSize, nil, 0) == 0 else {
            throw ForensicError.collectionFailed(
                "sysctl data fetch failed — errno \(errno): \(String(cString: strerror(errno)))"
            )
        }

        let count = actualSize / MemoryLayout<kinfo_proc>.stride

        // ── Step 3: Map kinfo_proc → ForensicEvent ──────────────────────────
        return procs.prefix(count).compactMap { kproc -> ForensicEvent? in
            let pid  = Int(kproc.kp_proc.p_pid)
            let ppid = Int(kproc.kp_eproc.e_ppid)

            // kp_proc.p_comm is a C fixed-length char array (MAXCOMLEN + 1 = 17 bytes)
            // Extract via pointer rebind. Compute size before taking inout pointer
            // to avoid overlapping-access exclusivity violation.
            // SPEC: REQ-202 — name from p_comm
            var comm = kproc.kp_proc.p_comm
            let commSize = MemoryLayout.size(ofValue: comm)
            let name: String = withUnsafeMutablePointer(to: &comm) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: commSize) { cStr in
                    String(cString: cStr)
                }
            }

            // Filter out zombie/empty entries (pid 0 with no name)
            guard pid > 0 || !name.isEmpty else { return nil }

            // SPEC: REQ-202 — ForensicEvent with source=.process, required metadata
            return ForensicEvent(
                severity: .info,
                source: .process,
                payload: .process(pid: pid, name: name.isEmpty ? "(unknown)" : name, parentPid: ppid)
            )
        }
    }
}
