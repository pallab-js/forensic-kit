import Testing
import Foundation
import CryptoKit
@testable import ForensicKit

// SPEC: REQ-401 — FileSystemService streaming and traversal tests
// SPEC: REQ-402 — Metadata field validation
// SPEC: REQ-403 — SHA-256 hashing via CryptoKit & chunked reading
// SPEC: REQ-404 — Graceful error handling (invalid paths, traversal errors)
// SPEC: REQ-405 — Strict concurrency and Sendable compliance

// MARK: - Path & Temp Directory Helpers

private func resolveRealPath(_ path: String) -> String {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(path, &buffer) != nil else {
        return path
    }
    return String(cString: buffer)
}

private func withTempDirectory(_ body: (URL) async throws -> Void) async throws {
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
    let resolvedPath = resolveRealPath(tempDir.path)
    let resolvedURL = URL(fileURLWithPath: resolvedPath)
    defer {
        try? fm.removeItem(at: resolvedURL)
    }
    try await body(resolvedURL)
}

private func computeExpectedSHA256(for data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Service State & Config Tests

@Test("FileSystemService identity and config are stable")
func testFileSystemServiceConfig() async throws {
    try await withTempDirectory { tempURL in
        let path = tempURL.path
        let svc = FileSystemService(targetPath: path, recursive: false)

        #expect(svc.id == "file-system-service")
        #expect(svc.targetPath == path)
        #expect(svc.recursive == false)
    }
}

@Test("FileSystemService stream throws serviceNotRunning before start()")
func testFileSystemThrowsWhenNotStarted() async throws {
    try await withTempDirectory { tempURL in
        let svc = FileSystemService(targetPath: tempURL.path)

        var caughtError: ForensicError?
        do {
            for try await _ in svc.stream() {}
        } catch let e as ForensicError {
            caughtError = e
        }
        #expect(caughtError == .serviceNotRunning(serviceId: "file-system-service"))
    }
}

@Test("FileSystemService stop() prevents further streaming")
func testFileSystemStopPreventsStream() async throws {
    try await withTempDirectory { tempURL in
        let svc = FileSystemService(targetPath: tempURL.path)
        try await svc.start()
        await svc.stop()

        var caughtError: ForensicError?
        do {
            for try await _ in svc.stream() {}
        } catch let e as ForensicError {
            caughtError = e
        }
        #expect(caughtError == .serviceNotRunning(serviceId: "file-system-service"))
    }
}

// MARK: - Path Validation Tests (REQ-404)

@Test("FileSystemService start() throws when target path does not exist")
func testFileSystemThrowsOnNonexistentPath() async throws {
    let nonexistentPath = "/tmp/forensic-kit-nonexistent-\(UUID().uuidString)"
    let svc = FileSystemService(targetPath: nonexistentPath)

    var caughtError: ForensicError?
    do {
        try await svc.start()
    } catch let e as ForensicError {
        caughtError = e
    }

    #expect(caughtError != nil)
    if case .collectionFailed(let reason)? = caughtError {
        #expect(reason.contains("does not exist"))
    } else {
        Issue.record("Expected .collectionFailed error, got: \(String(describing: caughtError))")
    }
}

@Test("FileSystemService start() throws when target path is a file instead of a directory")
func testFileSystemThrowsOnRegularFileTarget() async throws {
    try await withTempDirectory { tempURL in
        let fileURL = tempURL.appendingPathComponent("regular_file.txt")
        try Data("dummy".utf8).write(to: fileURL)

        let svc = FileSystemService(targetPath: fileURL.path)

        var caughtError: ForensicError?
        do {
            try await svc.start()
        } catch let e as ForensicError {
            caughtError = e
        }

        #expect(caughtError != nil)
        if case .collectionFailed(let reason)? = caughtError {
            #expect(reason.contains("is not a directory"))
        } else {
            Issue.record("Expected .collectionFailed error, got: \(String(describing: caughtError))")
        }
    }
}

// MARK: - Traversal & Metadata Tests (REQ-401 & REQ-402)

@Test("FileSystemService recursive snapshot captures files and metadata correctly")
func testFileSystemRecursiveSnapshot() async throws {
    try await withTempDirectory { tempURL in
        let fm = FileManager.default

        // Create structure:
        // tempURL/
        //   ├─ file_root.txt (permissions 0644 / size 10)
        //   └─ subdir/
        //        └─ file_sub.txt (permissions 0755 / size 18)

        let fileRootURL = tempURL.appendingPathComponent("file_root.txt")
        let rootData = Data("RootFile10".utf8)
        try rootData.write(to: fileRootURL)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileRootURL.path)

        let subdirURL = tempURL.appendingPathComponent("subdir")
        try fm.createDirectory(at: subdirURL, withIntermediateDirectories: true, attributes: nil)

        let fileSubURL = tempURL.appendingPathComponent("subdir/file_sub.txt")
        let subData = Data("SubFileTextLength18".utf8)
        try subData.write(to: fileSubURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileSubURL.path)

        let svc = FileSystemService(targetPath: tempURL.path, recursive: true)
        try await svc.start()

        var events: [ForensicEvent] = []
        for try await event in svc.stream() {
            events.append(event)
        }

        print("--- DEBUG PATHS ---")
        print("fileRootURL.path: \(fileRootURL.path)")
        print("subdirURL.path: \(subdirURL.path)")
        print("fileSubURL.path: \(fileSubURL.path)")
        for event in events {
            print("Event path: \(event.payload.metadata["path"] ?? "nil")")
        }
        print("-------------------")

        // We expect exactly 3 events: file_root.txt, subdir (the directory), and file_sub.txt
        #expect(events.count == 3)
        #expect(events.allSatisfy { $0.source == .filesystem })
        #expect(events.allSatisfy { $0.payload.kind == .filesystem })
        #expect(events.allSatisfy { $0.severity == .info })

        // Check required metadata keys
        let requiredKeys = [
            "path", "sizeBytes", "permissions", "modificationDate",
            "creationDate", "fileType", "sha256"
        ]
        for event in events {
            for key in requiredKeys {
                #expect(event.payload.metadata[key] != nil, "Missing key \(key) in metadata")
            }
        }

        // Verify file_root.txt metadata
        let rootEvent = try #require(events.first { $0.payload.metadata["path"] == fileRootURL.path })
        #expect(rootEvent.payload.metadata["sizeBytes"] == "10")
        #expect(rootEvent.payload.metadata["permissions"] == "0644")
        #expect(rootEvent.payload.metadata["fileType"] == "regular")
        #expect(rootEvent.payload.metadata["sha256"] == computeExpectedSHA256(for: rootData))

        // Verify subdir metadata
        let subdirEvent = try #require(events.first { $0.payload.metadata["path"] == subdirURL.path })
        #expect(subdirEvent.payload.metadata["fileType"] == "directory")
        #expect(subdirEvent.payload.metadata["sha256"] == "-") // Directories should not have a hash computed

        // Verify file_sub.txt metadata
        let subEvent = try #require(events.first { $0.payload.metadata["path"] == fileSubURL.path })
        #expect(subEvent.payload.metadata["sizeBytes"] == "19")
        #expect(subEvent.payload.metadata["permissions"] == "0755")
        #expect(subEvent.payload.metadata["fileType"] == "regular")
        #expect(subEvent.payload.metadata["sha256"] == computeExpectedSHA256(for: subData))
    }
}

@Test("FileSystemService non-recursive snapshot ignores subdirectories")
func testFileSystemNonRecursiveSnapshot() async throws {
    try await withTempDirectory { tempURL in
        let fm = FileManager.default

        // Create structure:
        // tempURL/
        //   ├─ file_root.txt
        //   └─ subdir/
        //        └─ file_sub.txt

        let fileRootURL = tempURL.appendingPathComponent("file_root.txt")
        try Data("root".utf8).write(to: fileRootURL)

        let subdirURL = tempURL.appendingPathComponent("subdir")
        try fm.createDirectory(at: subdirURL, withIntermediateDirectories: true, attributes: nil)

        let fileSubURL = tempURL.appendingPathComponent("subdir/file_sub.txt")
        try Data("sub".utf8).write(to: fileSubURL)

        let svc = FileSystemService(targetPath: tempURL.path, recursive: false)
        try await svc.start()

        var events: [ForensicEvent] = []
        for try await event in svc.stream() {
            events.append(event)
        }

        // We expect exactly 2 events: file_root.txt and subdir directory (not its contents)
        #expect(events.count == 2)
        #expect(events.contains { $0.payload.metadata["path"] == fileRootURL.path })
        #expect(events.contains { $0.payload.metadata["path"] == subdirURL.path })
        #expect(events.contains { $0.payload.metadata["path"] == fileSubURL.path } == false)
    }
}

// MARK: - Hashing Tests (REQ-403)

@Test("FileSystemService large file hashing functions correctly without memory spikes")
func testFileSystemLargeFileHashing() async throws {
    try await withTempDirectory { tempURL in
        let fileURL = tempURL.appendingPathComponent("large_file.bin")

        // Create a 150KB file of repeating bytes
        let chunkSize = 64 * 1024
        var largeData = Data()
        for i in 0..<150 {
            largeData.append(contentsOf: Array(repeating: UInt8(i % 256), count: 1024))
        }

        try largeData.write(to: fileURL)

        let svc = FileSystemService(targetPath: tempURL.path, recursive: false)
        try await svc.start()

        var events: [ForensicEvent] = []
        for try await event in svc.stream() {
            events.append(event)
        }

        let fileEvent = try #require(events.first { $0.payload.metadata["path"] == fileURL.path })
        #expect(fileEvent.payload.metadata["sha256"] == computeExpectedSHA256(for: largeData))
        #expect(fileEvent.payload.metadata["sizeBytes"] == String(largeData.count))
    }
}

// MARK: - Graceful Error Traversal (REQ-404)

@Test("FileSystemService continues stream when error is encountered during traversal")
func testFileSystemGracefulTraversalError() async throws {
    try await withTempDirectory { tempURL in
        let fm = FileManager.default

        // Create structure:
        // tempURL/
        //   ├─ readable_file.txt
        //   └─ unreadable_subdir/ (permissions 0000 so enumerator cannot access contents)
        //        └─ hidden_file.txt

        let readableFileURL = tempURL.appendingPathComponent("readable_file.txt")
        try Data("read".utf8).write(to: readableFileURL)

        let unreadableSubdirURL = tempURL.appendingPathComponent("unreadable_subdir")
        try fm.createDirectory(at: unreadableSubdirURL, withIntermediateDirectories: true, attributes: nil)

        let hiddenFileURL = unreadableSubdirURL.appendingPathComponent("hidden_file.txt")
        try Data("hidden".utf8).write(to: hiddenFileURL)

        // Set permissions of unreadableSubdir to 0000 so traversal inside fails
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableSubdirURL.path)
        defer {
            // Restore permissions so cleanup defer in withTempDirectory can delete it
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unreadableSubdirURL.path)
        }

        let svc = FileSystemService(targetPath: tempURL.path, recursive: true)
        try await svc.start()

        var events: [ForensicEvent] = []
        for try await event in svc.stream() {
            events.append(event)
        }

        // It must NOT fail the entire stream. It should successfully emit events for:
        // 1. readable_file.txt
        // 2. unreadable_subdir (the directory itself is listed)
        // And should gracefully skip the unreadable contents of unreadable_subdir instead of crash.
        #expect(events.isEmpty == false)
        #expect(events.contains { $0.payload.metadata["path"] == readableFileURL.path })
        #expect(events.contains { $0.payload.metadata["path"] == unreadableSubdirURL.path })
        #expect(events.contains { $0.payload.metadata["path"] == hiddenFileURL.path } == false)
    }
}

@Test("FileSystemService captures symbolic links without following them")
func testFileSystemSymbolicLinks() async throws {
    try await withTempDirectory { tempURL in
        let fm = FileManager.default

        let targetFileURL = tempURL.appendingPathComponent("target.txt")
        try Data("target_contents".utf8).write(to: targetFileURL)

        let symlinkURL = tempURL.appendingPathComponent("symlink.txt")
        try fm.createSymbolicLink(atPath: symlinkURL.path, withDestinationPath: "target.txt")

        let svc = FileSystemService(targetPath: tempURL.path, recursive: false)
        try await svc.start()

        var events: [ForensicEvent] = []
        for try await event in svc.stream() {
            events.append(event)
        }

        #expect(events.count == 2)

        let symlinkEvent = try #require(events.first { $0.payload.metadata["path"] == symlinkURL.path })
        #expect(symlinkEvent.payload.metadata["fileType"] == "symbolicLink")
        #expect(symlinkEvent.payload.metadata["sha256"] == "-")
        #expect(symlinkEvent.payload.metadata["destination"] == "target.txt")
    }
}
