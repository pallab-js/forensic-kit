// SPEC: REQ-502 — CollectionOrchestrator runs services in parallel and manages lifecycle
// SPEC: REQ-505 — Actor, Sendable compliance, Swift 6 strict concurrency

import Foundation

/// Orchestrates the execution of a heterogeneous set of forensic collection services.
///
/// Runs selected services in parallel using Swift Concurrency's `TaskGroup`, safely
/// aggregates their events, manages task cancellation, and invokes their lifecycle methods.
// SPEC: REQ-502
public actor CollectionOrchestrator {

    // MARK: - Properties

    private let services: [any CollectionService]
    private var isRunning = false

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
    // SPEC: REQ-502 — TaskGroup, parallel streams iteration, lifecycle management, memory monitor stop
    public func run(memoryDuration: Double = 1.0) async throws -> [ForensicEvent] {
        guard !isRunning else {
            throw ForensicError.collectionFailed("Orchestrator is already running")
        }
        isRunning = true
        defer { isRunning = false }

        // Start all services concurrently or sequentially
        for service in services {
            try await service.start()
        }

        var allEvents: [ForensicEvent] = []

        // Process streams concurrently using a throwing task group
        try await withThrowingTaskGroup(of: [ForensicEvent].self) { group in
            // Spin up an async reader task for each service stream
            for service in services {
                group.addTask {
                    var serviceEvents: [ForensicEvent] = []
                    do {
                        for try await event in service.stream() {
                            serviceEvents.append(event)
                        }
                    } catch {
                        // Throw out of the task to propagate up
                        throw error
                    }
                    return serviceEvents
                }
            }

            // Spin up a helper task to cancel/stop MemoryLogger after memoryDuration
            if let memoryLogger = services.first(where: { $0.id == "memory-logger" }) {
                group.addTask {
                    let nanos = UInt64(memoryDuration * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanos)
                    await memoryLogger.stop()
                    return []
                }
            }

            // Aggregate events from all completing streams
            while let serviceEvents = try await group.next() {
                allEvents.append(contentsOf: serviceEvents)
            }
        }

        // Stop all services to guarantee resources are clean
        for service in services {
            await service.stop()
        }

        // Sort events chronologically to present a coherent timeline
        allEvents.sort { $0.timestamp < $1.timestamp }

        return allEvents
    }
}
