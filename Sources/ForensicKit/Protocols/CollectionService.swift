// SPEC: REQ-102 — CollectionService: Sendable protocol with AsyncThrowingStream lifecycle
// SPEC: REQ-105 — Sendable conformance for Swift 6 strict concurrency

import Foundation

/// The core protocol every forensic collection service must conform to.
///
/// A `CollectionService` produces a continuous stream of `ForensicEvent` values
/// via Swift Concurrency's `AsyncThrowingStream`. Conforming types are responsible
/// for platform-level data acquisition (process trees, memory snapshots, etc.)
/// and must operate **without network calls**.
///
/// ## Lifecycle
/// ```
/// let svc: any CollectionService = MyService()
/// try await svc.start()
/// for try await event in svc.stream() { /* handle */ }
/// await svc.stop()
/// ```
///
/// ## Threading
/// All methods may be called from any concurrency domain; conforming types
/// must guarantee their own thread-safety (hence `Sendable` requirement).
// SPEC: REQ-102
public protocol CollectionService: Sendable {

    /// A stable, unique identifier for this service instance.
    ///
    /// Used for logging, spec traceability, and report attribution.
    /// Must be non-empty and stable across equal instances.
    var id: String { get }

    /// Returns an asynchronous stream of forensic events.
    ///
    /// The stream terminates naturally when the service has no more events to emit,
    /// or throws if an unrecoverable error occurs during collection.
    ///
    /// - Returns: An `AsyncThrowingStream` of `ForensicEvent` values.
    // SPEC: REQ-102 — AsyncThrowingStream streaming
    func stream() -> AsyncThrowingStream<ForensicEvent, Error>

    /// Prepares and starts the underlying data collection.
    ///
    /// Must be called before iterating the stream. Throws `ForensicError` on failure.
    // SPEC: REQ-102 — start() lifecycle
    func start() async throws

    /// Gracefully stops data collection and releases acquired resources.
    ///
    /// After `stop()` returns, the stream returned by `stream()` should finish.
    // SPEC: REQ-102 — stop() lifecycle
    func stop() async
}

// MARK: - Service Registry

/// A type-erased wrapper for any `CollectionService`.
///
/// Provides a concrete, `Sendable` box around protocol existentials,
/// enabling heterogeneous collections of services.
public struct AnyCollectionService: CollectionService {

    // MARK: - Stored Closures

    public let id: String
    private let _stream: @Sendable () -> AsyncThrowingStream<ForensicEvent, Error>
    private let _start:  @Sendable () async throws -> Void
    private let _stop:   @Sendable () async -> Void

    // MARK: - Init

    /// Wraps any `CollectionService` in a type-erased container.
    public init<S: CollectionService>(_ service: S) {
        self.id      = service.id
        self._stream = { service.stream() }
        self._start  = { try await service.start() }
        self._stop   = { await service.stop() }
    }

    // MARK: - CollectionService

    public func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        _stream()
    }

    public func start() async throws {
        try await _start()
    }

    public func stop() async {
        await _stop()
    }
}
