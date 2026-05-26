# Changelog

All notable changes to ForensicKit follow [Conventional Commits](https://www.conventionalcommits.org/).

---

## [Unreleased]

---

## [Phase 4] — 2026-05-26

### Added
- `Sources/ForensicKit/Services/FileSystemService.swift` — REQ-401–405: actor-based directory snapshot stream (recursive and non-recursive); metadata collection: size, 4-digit octal permissions, modification/creation dates (ISO8601), fileType; secure hex-encoded SHA-256 hash via CryptoKit with stream-based chunking; graceful traversal error handling (skips unreadable elements) and path resolution via `realpath(3)` to avoid symlink discrepancies.
- `Tests/ForensicKitTests/FileSystemServiceTests.swift` — 9 tests: state guards, recursive/non-recursive traversal, metadata verification, SHA-256 check, large file chunked hashing, nonexistent directory error, file instead of directory target error, and traversal error resilience.

### Changed
- `ForensicKit.version` bumped to `0.4.0-phase4`

### Spec Delta
- `specs/phase-4.yaml` status: `draft` → `verified`
- REQ-401, REQ-402, REQ-403, REQ-404, REQ-405: ALL PASS

### Commit
```
feat(phase-4): implement FileSystemService file system forensics per spec
```

### Test Results
```
✔ Test run with 73 tests passed after 0.019 seconds.
```

## [Phase 2] — 2026-05-26

### Added
- `Sources/ForensicKit/Services/ProcessTreeService.swift` — REQ-201/202: actor-based `sysctl(KERN_PROC_ALL)` snapshot stream; extracts `pid`, `name` (`p_comm`), `parentPid` per process
- `Sources/ForensicKit/Services/MemoryLogger.swift` — REQ-203/204: actor-based continuous memory monitor via `MACH_TASK_BASIC_INFO`; injectable `MemoryProvider` for tests; 50ms default interval; 1.5GiB ceiling; `.warning` at 90% threshold
- `Tests/ForensicKitTests/ProcessTreeServiceTests.swift` — 9 tests: not-started guard, integration snapshot, source/kind/metadata/pid=1/numeric-pids/idempotent/stop
- `Tests/ForensicKitTests/MemoryLoggerTests.swift` — 11 tests: not-started guard, mock provider events, severity thresholds, limit exceeded (type + bytes), stop termination, real `systemMemoryUsage()` smoke test

### Spec Delta
- `specs/phase-2.yaml` status: `draft` → `verified`
- REQ-201, REQ-202, REQ-203, REQ-204, REQ-205: ALL PASS

### Commit
```
feat(phase-2): ProcessTreeService (sysctl) and MemoryLogger (mach) per spec
```

### Test Results
```
✔ Test run with 48 tests passed after 0.015 seconds.
```

---

---

## [Phase 1] — 2026-05-26

### Added
- `Sources/ForensicKit/Models/ForensicEvent.swift` — REQ-101: Sendable, Codable, Identifiable, Hashable event struct with Severity + Source nested enums
- `Sources/ForensicKit/Models/EventPayload.swift` — REQ-104: Sendable, Codable payload with 5 PayloadKind cases and factory methods
- `Sources/ForensicKit/Protocols/CollectionService.swift` — REQ-102: AsyncThrowingStream-based protocol + AnyCollectionService type-erasure
- `Sources/ForensicKit/Errors/ForensicError.swift` — REQ-103: Typed error enum (6 cases), Equatable, LocalizedError
- `Tests/ForensicKitTests/ForensicEventTests.swift` — 8 tests covering init, Codable, Hashable, Identifiable
- `Tests/ForensicKitTests/ForensicErrorTests.swift` — 9 tests covering all 6 error cases + Equatable + LocalizedError
- `Tests/ForensicKitTests/CollectionServiceTests.swift` — 11 tests covering mock service, stream lifecycle, EventPayload factories

### Changed
- `ForensicKit.version` bumped to `0.1.0-phase1`

### Spec Delta
- `specs/phase-1.yaml` status: `draft` → `verified`
- REQ-101, REQ-102, REQ-103, REQ-104, REQ-105: ALL PASS

### Commit
```
feat(phase-1): core models, protocols, and errors per spec
```

### Test Results
```
✔ Test run with 28 tests passed after 0.003 seconds.
```

---

## [Phase 0] — 2026-05-26

### Added
- `Package.swift` — multi-target SPM manifest (ForensicKit · ForensicKitCLI · ForensicKitTests)
- `Sources/ForensicKit/ForensicKit.swift` — scaffold library placeholder (v0.0.0-scaffold)
- `Sources/ForensicKitCLI/main.swift` — CLI entry point placeholder
- `Tests/ForensicKitTests/ForensicKitTests.swift` — Swift Testing smoke test
- `specs/00-project-overview.yaml` — project-level spec index
- `specs/phase-0.yaml` — Phase 0 spec (REQ-000)
- `specs/tools/spec-verify.sh` — offline spec validator (yamllint + traceability check)
- `.gitignore` — SPM-appropriate ignores
- `README.md` — SPM build/test/validate documentation

### Spec Delta
- `specs/phase-0.yaml` status: `draft` → `verified`

### Commit
```
chore(phase-0): spm scaffold + spec tooling
```

---

## [Phase 3] — 2026-05-26

### Added
- `Sources/ForensicKit/Services/NetworkMonitorService.swift` — REQ-301–305: actor-based `getifaddrs(3)` snapshot; classifies AF_INET (IPv4 via `inet_ntop`), AF_INET6 (IPv6 via `inet_ntop`), AF_LINK (MAC from `sockaddr_dl`), other; `defer freeifaddrs` in all paths
- `Tests/ForensicKitTests/NetworkMonitorServiceTests.swift` — 14 tests: state guards, source/kind/metadata/severity, lo0 loopback, IPv4 format, 127.0.0.1, family value set, boolean strings, repeated snapshot (memory-safety), stream completion

### Changed
- `ForensicKit.version` bumped to `0.3.0-phase3`

### Spec Delta
- `specs/phase-3.yaml` status: `draft` → `verified`
- REQ-301, REQ-302, REQ-303, REQ-304, REQ-305: ALL PASS

### Commit
```
feat(phase-3): NetworkMonitorService via getifaddrs per spec
```

### Test Results
```
✔ Test run with 64 tests passed after 0.016 seconds.
```
