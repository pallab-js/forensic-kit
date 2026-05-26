// SPEC: REQ-103 — ForensicError: Sendable Error enum with all required cases
// SPEC: REQ-105 — Sendable conformance for Swift 6 strict concurrency

import Foundation

/// All errors that can be thrown by ForensicKit collection services.
///
/// Each case carries structured context to support precise error handling,
/// logging, and report generation in Phase 5.
// SPEC: REQ-103
public enum ForensicError: Error, Sendable {

    /// The process lacked the required entitlements or privileges.
    ///
    /// - Parameter reason: Human-readable description of the missing permission.
    // SPEC: REQ-103 — permissionDenied
    case permissionDenied(String)

    /// Data collection failed for a non-permission reason.
    ///
    /// - Parameter reason: Description of the failure.
    // SPEC: REQ-103 — collectionFailed
    case collectionFailed(String)

    /// Memory usage exceeded the configured ceiling (default: 1.5 GB).
    ///
    /// - Parameters:
    ///   - usedBytes:  Current RSS/VM usage in bytes.
    ///   - limitBytes: Configured memory ceiling in bytes.
    // SPEC: REQ-103 — memoryLimitExceeded
    case memoryLimitExceeded(usedBytes: Int, limitBytes: Int)

    /// An operation was attempted on a service that has not been started.
    ///
    /// - Parameter serviceId: The `CollectionService.id` of the dormant service.
    // SPEC: REQ-103 — serviceNotRunning
    case serviceNotRunning(serviceId: String)

    /// A collection operation exceeded its time budget.
    ///
    /// - Parameter after: The elapsed `Duration` before the timeout was triggered.
    // SPEC: REQ-103 — timeout
    case timeout(after: Duration)

    /// The host platform does not support the requested forensic capability.
    ///
    /// - Parameter reason: Description of the unsupported feature or OS version.
    // SPEC: REQ-103 — unsupportedPlatform
    case unsupportedPlatform(String)
}

// MARK: - CustomStringConvertible

extension ForensicError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        case .collectionFailed(let reason):
            return "Collection failed: \(reason)"
        case .memoryLimitExceeded(let used, let limit):
            let usedMB  = used  / (1024 * 1024)
            let limitMB = limit / (1024 * 1024)
            return "Memory limit exceeded: \(usedMB) MB used, limit is \(limitMB) MB"
        case .serviceNotRunning(let sid):
            return "Service '\(sid)' is not running — call start() first"
        case .timeout(let d):
            return "Operation timed out after \(d)"
        case .unsupportedPlatform(let reason):
            return "Unsupported platform: \(reason)"
        }
    }
}

// MARK: - LocalizedError

extension ForensicError: LocalizedError {
    public var errorDescription: String? { description }
}

// MARK: - Equatable (for testing)

extension ForensicError: Equatable {
    public static func == (lhs: ForensicError, rhs: ForensicError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied(let l),   .permissionDenied(let r)):   return l == r
        case (.collectionFailed(let l),   .collectionFailed(let r)):   return l == r
        case (.memoryLimitExceeded(let lu, let ll), .memoryLimitExceeded(let ru, let rl)):
            return lu == ru && ll == rl
        case (.serviceNotRunning(let l),  .serviceNotRunning(let r)):  return l == r
        case (.timeout(let l),            .timeout(let r)):            return l == r
        case (.unsupportedPlatform(let l),.unsupportedPlatform(let r)):return l == r
        default: return false
        }
    }
}
