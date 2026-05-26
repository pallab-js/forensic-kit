// SPEC: REQ-203 — MemoryLogger: actor-based, continuous stream at configurable interval
// SPEC: REQ-204 — Throws .memoryLimitExceeded when RSS > limit; .warning at 90% threshold
// SPEC: REQ-205 — Actor, nonisolated let config, mutable state actor-isolated

import Darwin
import Foundation
import OSLog

/// Continuously monitors the current process's memory usage and emits
/// `ForensicEvent(source: .memory)` at a configurable interval.
///
/// - The default interval is **50 ms**.
/// - The default memory ceiling is **1.5 GiB** (1,610,612,736 bytes).
/// - Events where RSS > 90% of the limit are emitted with `.warning` severity.
/// - When RSS exceeds the limit the stream throws `.memoryLimitExceeded` immediately.
///
/// The `memoryProvider` parameter is injectable for unit testing without
/// needing real Mach calls.
///
/// ## Usage
/// ```swift
/// let logger = MemoryLogger()
/// try await logger.start()
/// for try await event in logger.stream() {
///     print(event.payload.metadata)
/// }
/// ```
// SPEC: REQ-203
public actor MemoryLogger: CollectionService {

    private static let log = Logger(subsystem: "com.forensickit", category: "memory")

    // MARK: - Types

    public typealias MemoryProvider = @Sendable () throws -> (rss: Int, vm: Int)

    // MARK: - Constants (nonisolated)

    /// Stable type-level identifier for programmatic lookups.
    /// Prefer this over string literal comparisons.
    public nonisolated static let serviceID = "memory-logger"
    public nonisolated let id = "memory-logger"

    // Immutable configuration — accessible nonisolated in Swift 6
    // SPEC: REQ-203 — configurable interval
    private let checkInterval: Duration

    // SPEC: REQ-204 — configurable ceiling, default 1.5 GiB
    private let limitBytes: Int

    // SPEC: REQ-203 — injectable provider for testability
    private let memoryProvider: MemoryProvider

    // MARK: - Actor-Isolated State

    private var isRunning = false

    // MARK: - Init

    /// Creates a new `MemoryLogger`.
    ///
    /// - Parameters:
    ///   - interval: Polling interval (default: 50 ms).
    ///   - memoryLimitBytes: RSS ceiling in bytes (default: 1.5 GiB).
    ///   - memoryProvider: Memory source; defaults to `mach task_info`.
    public init(
        interval: Duration = .milliseconds(50),
        memoryLimitBytes: Int = 1_610_612_736,
        memoryProvider: @escaping MemoryProvider = { try MemoryLogger.systemMemoryUsage() }
    ) {
        self.checkInterval  = interval
        self.limitBytes     = memoryLimitBytes
        self.memoryProvider = memoryProvider
    }

    // MARK: - CollectionService Lifecycle

    // SPEC: REQ-203 — start() lifecycle
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        Self.log.debug("started (limit=\(self.limitBytes) interval=\(self.checkInterval))")
    }

    public func stop() async {
        isRunning = false
        Self.log.debug("stopped")
    }

    // MARK: - CollectionService Streaming

    /// Returns a continuous stream of memory snapshot events.
    ///
    /// The stream runs until `stop()` is called or the memory limit is exceeded.
    /// No unstructured `Task` is created — the loop reads actor-isolated `isRunning`
    /// directly, eliminating the TOCTOU race between store-and-cancel.
    // SPEC: REQ-203 — continuous AsyncThrowingStream
    public nonisolated func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        let provider = self.memoryProvider
        let interval = self.checkInterval
        let limit    = self.limitBytes
        let svcId    = self.id

        return AsyncThrowingStream { continuation in
            let loopTask = Task {
                guard await self.isRunning else {
                    continuation.finish(
                        throwing: ForensicError.serviceNotRunning(serviceId: svcId)
                    )
                    return
                }

                while !Task.isCancelled {
                    guard await self.isRunning else {
                        continuation.finish()
                        return
                    }

                    do {
                        let (rss, vm) = try provider()

                        if rss > limit {
                            continuation.finish(
                                throwing: ForensicError.memoryLimitExceeded(
                                    usedBytes: rss,
                                    limitBytes: limit
                                )
                            )
                            await self.markStopped()
                            return
                        }

                        let severity: ForensicEvent.Severity =
                            rss > Int(Double(limit) * 0.9) ? .warning : .info

                        continuation.yield(
                            ForensicEvent(
                                severity: severity,
                                source: .memory,
                                payload: .memory(rssBytes: rss, vmBytes: vm)
                            )
                        )

                        try await Task.sleep(for: interval)

                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch let fe as ForensicError {
                        continuation.finish(throwing: fe)
                        return
                    } catch {
                        continuation.finish(
                            throwing: ForensicError.collectionFailed(error.localizedDescription)
                        )
                        return
                    }
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in loopTask.cancel() }
        }
    }

    // MARK: - Private Actor Helpers

    private func markStopped() {
        isRunning = false
    }

    // MARK: - Default Memory Provider

    /// Reads the current process's memory usage via `MACH_TASK_BASIC_INFO`.
    ///
    /// Returns `(rss: resident_size, vm: virtual_size)` in bytes.
    // SPEC: REQ-203 — default system provider
    public static func systemMemoryUsage() throws -> (rss: Int, vm: Int) {
        var info  = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )

        let kr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { intPtr in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    intPtr,
                    &count
                )
            }
        }

        guard kr == KERN_SUCCESS else {
            throw ForensicError.collectionFailed(
                "task_info(MACH_TASK_BASIC_INFO) returned kern_return \(kr)"
            )
        }

        return (rss: Int(info.resident_size), vm: Int(info.virtual_size))
    }
}
