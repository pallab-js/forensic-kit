// SPEC: REQ-502 — CollectionOrchestrator runs services in parallel and manages lifecycle
// SPEC: REQ-505 — Actor, Sendable compliance, Swift 6 strict concurrency

import Foundation
import OSLog

/// Orchestrates the execution of a heterogeneous set of forensic collection services.
///
/// Runs selected services in parallel using Swift Concurrency's `TaskGroup`, safely
/// aggregates their events, manages task cancellation, and invokes their lifecycle methods.
///
/// Unlike a throwing task group, this approach catches per-service errors so that
/// partial results from successful services are preserved when another service fails.
// SPEC: REQ-502
public actor CollectionOrchestrator {

    private static let log = Logger(subsystem: "com.forensickit", category: "orchestrator")

    // MARK: - Properties

    private let services: [any CollectionService]
    private var isRunning = false

    /// Errors collected from individual services during the last `run()`.
    /// Cleared at the start of each run. Callers should inspect this after
    /// `run()` returns to check for partial failures.
    public private(set) var serviceErrors: [String] = []

    // MARK: - Init

    /// Creates a new `CollectionOrchestrator`.
    ///
    /// - Parameter services: List of collection services to orchestrate.
    public init(services: [any CollectionService]) {
        self.services = services
    }

    // MARK: - Execution

    /// Runs all configured services in parallel, aggregates their event streams,
    /// and manages the overall lifecycle.
    ///
    /// - Parameter memoryDuration: Optional duration in seconds to run memory monitoring.
    /// - Returns: A unified array of all captured `ForensicEvent` objects.
    ///            Partial results are returned even if individual services fail.
    // SPEC: REQ-502 — TaskGroup, parallel streams iteration, lifecycle management, memory monitor stop
    public func run(memoryDuration: Double = 1.0) async -> [ForensicEvent] {
        self.serviceErrors = []
        guard !isRunning else {
            self.serviceErrors.append("Orchestrator is already running")
            return []
        }
        isRunning = true
        defer { isRunning = false }

        // Start all services — collect start errors per-service instead of throwing
        for service in services {
            do {
                try await service.start()
            } catch {
                let msg = "\(service.id): failed to start — \(error.localizedDescription)"
                Self.log.error("\(msg)")
                serviceErrors.append(msg)
            }
        }

        // Filter to only services that started successfully
        let activeServices = services.filter { svc in
            !serviceErrors.contains(where: { $0.hasPrefix("\(svc.id):") })
        }

        var allEvents: [ForensicEvent] = []

        // Use non-throwing task group so a single service failure doesn't discard all results
        await withTaskGroup(of: [ForensicEvent].self) { group in
            for service in activeServices {
                group.addTask {
                    var serviceEvents: [ForensicEvent] = []
                    do {
                        for try await event in service.stream() {
                            serviceEvents.append(event)
                        }
                    } catch {
                        let msg = "\(service.id): stream error — \(error.localizedDescription)"
                        Self.log.error("\(msg)")
                        return serviceEvents
                    }
                    return serviceEvents
                }
            }

            // Helper task to stop MemoryLogger after the configured duration
            if let memoryLogger = activeServices.first(where: { $0.id == MemoryLogger.serviceID }) {
                group.addTask {
                    let nanos = UInt64(memoryDuration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    await memoryLogger.stop()
                    return []
                }
            }

            while let serviceEvents = await group.next() {
                allEvents.append(contentsOf: serviceEvents)
            }
        }

        for service in services {
            await service.stop()
        }

        allEvents.sort { $0.timestamp < $1.timestamp }
        return allEvents
    }
}
