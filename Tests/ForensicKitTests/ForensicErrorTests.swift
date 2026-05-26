import Testing
import Foundation
@testable import ForensicKit

// SPEC: REQ-103 — ForensicError unit tests

// MARK: - Throw & Catch Each Case

@Test("permissionDenied can be thrown and caught")
func testPermissionDeniedThrow() async {
    do {
        throw ForensicError.permissionDenied("Missing entitlement: com.apple.security.cs.allow-jit")
    } catch let err as ForensicError {
        #expect(err == .permissionDenied("Missing entitlement: com.apple.security.cs.allow-jit"))
        #expect(err.description.contains("Permission denied"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("collectionFailed can be thrown and caught")
func testCollectionFailedThrow() async {
    do {
        throw ForensicError.collectionFailed("sysctl kern.proc.all returned EINVAL")
    } catch let err as ForensicError {
        #expect(err == .collectionFailed("sysctl kern.proc.all returned EINVAL"))
        #expect(err.description.contains("Collection failed"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("memoryLimitExceeded carries byte counts and formats description")
func testMemoryLimitExceededThrow() async {
    let usedBytes  = 1_600_000_000  // 1.6 GB
    let limitBytes = 1_500_000_000  // 1.5 GB

    do {
        throw ForensicError.memoryLimitExceeded(usedBytes: usedBytes, limitBytes: limitBytes)
    } catch let err as ForensicError {
        guard case .memoryLimitExceeded(let u, let l) = err else {
            Issue.record("Wrong case"); return
        }
        #expect(u == usedBytes)
        #expect(l == limitBytes)
        #expect(err.description.contains("1524 MB") || err.description.contains("1525 MB") || err.description.contains("MB"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("serviceNotRunning carries service ID")
func testServiceNotRunningThrow() async {
    do {
        throw ForensicError.serviceNotRunning(serviceId: "process-tree-service")
    } catch let err as ForensicError {
        guard case .serviceNotRunning(let sid) = err else {
            Issue.record("Wrong case"); return
        }
        #expect(sid == "process-tree-service")
        #expect(err.description.contains("process-tree-service"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("timeout carries Duration")
func testTimeoutThrow() async {
    let d = Duration.seconds(30)
    do {
        throw ForensicError.timeout(after: d)
    } catch let err as ForensicError {
        guard case .timeout(let after) = err else {
            Issue.record("Wrong case"); return
        }
        #expect(after == d)
        #expect(err.description.contains("timed out"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("unsupportedPlatform can be thrown and caught")
func testUnsupportedPlatformThrow() async {
    do {
        throw ForensicError.unsupportedPlatform("Requires macOS 13+")
    } catch let err as ForensicError {
        #expect(err == .unsupportedPlatform("Requires macOS 13+"))
        #expect(err.description.contains("Unsupported platform"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - Equatable

@Test("ForensicError Equatable: same cases are equal")
func testForensicErrorEquatable() {
    #expect(ForensicError.permissionDenied("x")   == ForensicError.permissionDenied("x"))
    #expect(ForensicError.collectionFailed("y")   == ForensicError.collectionFailed("y"))
    #expect(ForensicError.serviceNotRunning(serviceId: "z") == ForensicError.serviceNotRunning(serviceId: "z"))
    #expect(ForensicError.unsupportedPlatform("w") == ForensicError.unsupportedPlatform("w"))
}

@Test("ForensicError Equatable: different cases are not equal")
func testForensicErrorNotEqual() {
    #expect(ForensicError.permissionDenied("a") != ForensicError.collectionFailed("a"))
    #expect(ForensicError.serviceNotRunning(serviceId: "a") != ForensicError.serviceNotRunning(serviceId: "b"))
}

// MARK: - LocalizedError

@Test("ForensicError provides localizedDescription")
func testLocalizedDescription() {
    let err: Error = ForensicError.collectionFailed("disk full")
    let desc = (err as? LocalizedError)?.errorDescription ?? ""
    #expect(desc.contains("Collection failed"))
}
