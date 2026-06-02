// SPEC: REQ-401 — FileSystemService: actor, target directory snapshot stream
// SPEC: REQ-402 — Metadata: path, sizeBytes, permissions, modificationDate, creationDate, fileType
// SPEC: REQ-403 — SHA-256 hashing via CryptoKit, streaming for large files
// SPEC: REQ-404 — Graceful error handling, continue on unreadable files/subdirs
// SPEC: REQ-405 — Strict concurrency and Sendable compliance

import Foundation
import CryptoKit
import OSLog

/// A service that scans a target directory and captures metadata for all discovered files
/// and directories, including computing SHA-256 hashes of regular files.
///
/// `FileSystemService` operates as a point-in-time snapshot, yielding events for all items
/// in the target folder and then finishing.
// SPEC: REQ-401
public actor FileSystemService: CollectionService {

    private static let log = Logger(subsystem: "com.forensickit", category: "filesystem")

    // MARK: - Identity and Configuration

    public nonisolated let id = "file-system-service"
    public nonisolated let targetPath: String
    public nonisolated let recursive: Bool

    // MARK: - Actor-Isolated State

    private var isRunning = false

    // MARK: - Init

    /// Creates a new `FileSystemService`.
    ///
    /// - Parameters:
    ///   - targetPath: Absolute path of the target directory to scan.
    ///   - recursive: Whether to traverse subdirectories recursively. Defaults to `true`.
    public init(targetPath: String, recursive: Bool = true) {
        self.targetPath = targetPath
        self.recursive = recursive
    }

    // MARK: - CollectionService Lifecycle

    // SPEC: REQ-401 — start() implementation
    public func start() async throws {
        guard !isRunning else { return }

        let resolved = FileSystemService.resolveRealPath(targetPath)
        // SPEC: REQ-404 — Throw permissionDenied or collectionFailed if the target directory is invalid/unreadable
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolved, isDirectory: &isDir) else {
            throw ForensicError.collectionFailed("Target path does not exist: \(targetPath)")
        }
        guard isDir.boolValue else {
            throw ForensicError.collectionFailed("Target path is not a directory: \(targetPath)")
        }
        guard fm.isReadableFile(atPath: resolved) else {
            throw ForensicError.permissionDenied("Target path is not readable: \(targetPath)")
        }

        isRunning = true
        Self.log.debug("started target=\(resolved) recursive=\(self.recursive)")
    }

    public func stop() async {
        isRunning = false
        Self.log.debug("stopped")
    }

    // MARK: - CollectionService Streaming

    /// Returns a finite snapshot stream of file system forensic events.
    ///
    /// Throws `ForensicError.serviceNotRunning` if called before `start()`.
    // SPEC: REQ-401 — AsyncThrowingStream snapshot
    public nonisolated func stream() -> AsyncThrowingStream<ForensicEvent, Error> {
        let svcId = self.id
        let path = self.targetPath
        let rec = self.recursive

        return AsyncThrowingStream { continuation in
            Task {
                guard await self.isRunning else {
                    continuation.finish(
                        throwing: ForensicError.serviceNotRunning(serviceId: svcId)
                    )
                    return
                }

                do {
                    let events = try FileSystemService.captureSnapshot(targetPath: path, recursive: rec)
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

    /// Scans the directory and maps each file/folder into a `ForensicEvent`.
    // SPEC: REQ-401 — directory enumeration
    // SPEC: REQ-404 — handles traversal errors gracefully by skipping
    internal static func captureSnapshot(targetPath: String, recursive: Bool) throws -> [ForensicEvent] {
        let fm = FileManager.default
        let resolved = resolveRealPath(targetPath)
        let targetURL = URL(fileURLWithPath: resolved)

        var events: [ForensicEvent] = []

        if recursive {
            // SPEC: REQ-401 — recursive traversal using directory enumerator
            guard let enumerator = fm.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { _, _ in
                    // SPEC: REQ-404 — Return true to continue enumerating when encountering errors
                    return true
                }
            ) else {
                throw ForensicError.collectionFailed("Failed to create directory enumerator for path: \(targetPath)")
            }

            while let fileURL = enumerator.nextObject() as? URL {
                do {
                    if let event = try makeEvent(from: fileURL) {
                        events.append(event)
                    }
                } catch {
                    // SPEC: REQ-404 — skip unreadable files and continue by logging/emitting a warning event
                    let warningEvent = ForensicEvent(
                        severity: .warning,
                        source: .filesystem,
                        payload: EventPayload(kind: .filesystem, metadata: [
                            "path": fileURL.path,
                            "error": error.localizedDescription,
                            "status": "unreadable"
                        ])
                    )
                    events.append(warningEvent)
                }
            }
        } else {
            // SPEC: REQ-401 — non-recursive traversal using contentsOfDirectory
            do {
                let contents = try fm.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )
                for fileURL in contents {
                    do {
                        if let event = try makeEvent(from: fileURL) {
                            events.append(event)
                        }
                    } catch {
                        // SPEC: REQ-404 — skip unreadable files and continue by logging/emitting a warning event
                        let warningEvent = ForensicEvent(
                            severity: .warning,
                            source: .filesystem,
                            payload: EventPayload(kind: .filesystem, metadata: [
                                "path": fileURL.path,
                                "error": error.localizedDescription,
                                "status": "unreadable"
                            ])
                        )
                        events.append(warningEvent)
                    }
                }
            } catch {
                throw ForensicError.permissionDenied("Failed to read directory contents: \(error.localizedDescription)")
            }
        }

        Self.log.debug("scanned \(events.count) items")
        return events
    }

    // MARK: - Per-Item Event Builder

    /// Maps a file or directory URL to a `ForensicEvent` carrying attributes and a secure hash.
    // SPEC: REQ-402 — metadata fields (path, sizeBytes, permissions, modificationDate, creationDate, fileType)
    private static func makeEvent(from url: URL) throws -> ForensicEvent? {
        let fm = FileManager.default
        let rawPath = url.path

        var statInfo = Darwin.stat()
        guard lstat(rawPath, &statInfo) == 0 else {
            throw ForensicError.collectionFailed("lstat failed for \(rawPath) — errno \(errno)")
        }

        let size = Int64(statInfo.st_size)
        let permVal = statInfo.st_mode & 0o777
        let permStr = String(format: "%04o", permVal)

        let modDate = Date(timeIntervalSince1970: Double(statInfo.st_mtimespec.tv_sec) + Double(statInfo.st_mtimespec.tv_nsec) / 1_000_000_000.0)
        let creationDate = Date(timeIntervalSince1970: Double(statInfo.st_birthtimespec.tv_sec) + Double(statInfo.st_birthtimespec.tv_nsec) / 1_000_000_000.0)

        let formatter = ISO8601DateFormatter()
        let modDateStr = formatter.string(from: modDate)
        let creationDateStr = formatter.string(from: creationDate)

        let fileMode = statInfo.st_mode & S_IFMT
        let fileType: String
        var isRegular = false

        if fileMode == S_IFREG {
            fileType = "regular"
            isRegular = true
        } else if fileMode == S_IFDIR {
            fileType = "directory"
        } else if fileMode == S_IFLNK {
            fileType = "symbolicLink"
        } else {
            fileType = "other"
        }

        var sha256Str = "-"
        if isRegular {
            // SPEC: REQ-403 — Compute SHA-256 hash using stream-based chunking
            do {
                sha256Str = try computeSHA256(for: URL(fileURLWithPath: rawPath))
            } catch {
                // SPEC: REQ-403 — If unreadable or hashing fails, set to "-"
                sha256Str = "-"
            }
        }

        // Build metadata payload
        var metadata: [String: String] = [
            "path": rawPath,
            "sizeBytes": String(size),
            "permissions": permStr,
            "modificationDate": modDateStr,
            "creationDate": creationDateStr,
            "fileType": fileType,
            "sha256": sha256Str
        ]

        if fileMode == S_IFLNK {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: rawPath) {
                metadata["destination"] = dest
            }
        }

        let payload = EventPayload(kind: .filesystem, metadata: metadata)

        return ForensicEvent(
            severity: .info,
            source: .filesystem,
            payload: payload
        )
    }

    // MARK: - Path Resolution Helper

    /// Resolves all symbolic links and normalizes a file path using realpath(3).
    internal static func resolveRealPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else {
            return path
        }
        return String(cString: buffer)
    }

    // MARK: - SHA-256 Hashing Helper

    /// Computes the SHA-256 hash of a file's contents using CryptoKit and chunked reading.
    // SPEC: REQ-403 — stream-based chunking to prevent high memory usage
    private static func computeSHA256(for url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        let bufferSize = 64 * 1024 // 64 KB chunks

        while let data = try fileHandle.read(upToCount: bufferSize), !data.isEmpty {
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
