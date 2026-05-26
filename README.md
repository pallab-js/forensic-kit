# ForensicKit

> macOS forensic data collection framework, CLI tool & desktop app — built entirely with Swift Package Manager.

ForensicKit collects live forensic data from a running macOS system: process listings, memory usage snapshots, network interface information, and filesystem directory snapshots with SHA-256 hashing. Results stream as structured `ForensicEvent` objects and can be exported as JSON, Markdown reports, or CSV.

---

## Features

- **Process Tree** — `sysctl(KERN_PROC_ALL)` snapshot of all running processes with PID, name, parent PID
- **Memory Logger** — continuous memory monitoring via `MACH_TASK_BASIC_INFO` with configurable interval, duration, and alert thresholds
- **Network Monitor** — `getifaddrs(3)` listing of IPv4, IPv6, and MAC addresses with family classification
- **File System Scanner** — recursive/non-recursive directory snapshots with size, permissions, dates, and SHA-256 hashing (CryptoKit)
- **CLI** — `swift-argument-parser` interface with JSON and Markdown report output
- **Desktop App** — SwiftUI `NavigationSplitView` with live streaming charts, configuration presets, sortable tables, search/filter, and CSV export
- **96 tests** across all phases — Swift Testing with >0.190s typical runtime

---

## Requirements

- **Swift 6.3+** (`swift --version`)
- **macOS 14+**
- **No Xcode required**

---

## Build & Run

```bash
# Build all targets
swift build

# Run CLI
swift run forensic-kit

# Run desktop app
swift run forensic-kit-desktop

# Run all tests
swift test

# Build release
swift build -c release
```

### Desktop App (macOS .app bundle)

```bash
# Manual .app bundle
bash build-app.sh
```

The script creates `ForensicKit.app` with Info.plist and hardened entitlements. Drag to `/Applications` or run via Finder.

---

## Project Structure

```
forensic-kit/
├── Package.swift                     # SPM manifest (6 targets)
├── Sources/
│   ├── ForensicKit/                  # Core library (models, protocols, services)
│   │   ├── Models/                   # ForensicEvent, EventPayload
│   │   ├── Protocols/                # CollectionService protocol
│   │   ├── Services/                 # ProcessTreeService, MemoryLogger,
│   │   │                             # NetworkMonitorService, FileSystemService,
│   │   │                             # CollectionOrchestrator
│   │   ├── Reporting/               # ForensicReporter (JSON, Markdown)
│   │   └── Errors/                  # ForensicError
│   ├── ForensicKitCLI/              # CLI executable (swift-argument-parser)
│   ├── ForensicKitDesktop/          # Desktop app executable (SwiftUI)
│   └── ForensicKitDesktopCore/      # Shared library (AppState, Panel, helpers)
├── Tests/
│   ├── ForensicKitTests/            # Core library tests (79)
│   └── ForensicKitDesktopTests/     # Desktop app tests (17)
├── specs/                            # Phase specifications
│   └── tools/spec-verify.sh          # Spec validator
├── build-app.sh                      # .app bundling script
├── CHANGELOG.md
└── README.md
```

---

## CLI Usage

```bash
# Help
swift run forensic-kit --help

# Collect all services, output JSON
swift run forensic-kit --services all --output-format json

# Collect process + network only, generate Markdown report
swift run forensic-kit --services process,network --output-format markdown --output-path report.md

# File system snapshot with custom options
swift run forensic-kit --services filesystem --fs-target /tmp/snapshot --no-fs-recursive

# Memory monitoring with custom limits
swift run forensic-kit --services memory --memory-limit 2048 --memory-interval 100 --memory-duration 30
```

---

## Desktop App

The SwiftUI desktop app (`forensic-kit-desktop`) provides:

- **Collection View** — service cards with individual toggles, run button with live progress, error banners
- **Data Views** — sortable tables for Processes, Network, Memory, Filesystem with row counts and search
- **Live Chart** — real-time memory usage LineMark chart with configurable threshold
- **Configuration Presets** — 3 built-in presets (Quick Scan, Full Investigation, Memory Only); save/delete custom presets
- **Inspector** — per-row metadata sheet with Copy buttons
- **Export** — CSV export per data view via `.fileExporter()`

Uses `@Observable` (iOS 17+ / macOS 14+), `NavigationSplitView`, `Swift Charts`, and `os_log` throughout.

---

## Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter "ProcessTreeServiceTests"
swift test --filter "PresetTests"

# Run with xcodebuild for CI
xcodebuild test -scheme forensic-kit -destination 'platform=macOS'
```

All tests use Swift Testing (no XCTest). Mocks provided via `MockCollectionService` and `MockMemoryProvider` for deterministic service testing.

---

## Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 0 | ✅ | SPM scaffold, spec tooling |
| 1 | ✅ | Core models, protocols, errors (28 tests) |
| 2 | ✅ | ProcessTreeService, MemoryLogger (48 tests) |
| 3 | ✅ | NetworkMonitorService (64 tests) |
| 4 | ✅ | FileSystemService with SHA-256 (73 tests) |
| 5 | ✅ | CLI, CollectionOrchestrator, Reporter (79 tests) |
| 6 | ✅ | Desktop app with SwiftUI (96 tests) |

---

## License

MIT
