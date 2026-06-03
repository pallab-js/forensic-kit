# ForensicKit

> macOS forensic data collection framework, CLI tool & desktop app — built entirely with Swift Package Manager.

ForensicKit collects live forensic data from a running macOS system: process listings, memory usage snapshots, network interface information, and filesystem directory snapshots with SHA-256 hashing. Results stream as structured `ForensicEvent` objects and can be exported as JSON, Markdown reports, or CSV.

---

## Features

- **Process Tree** — `sysctl(KERN_PROC_ALL)` snapshot of all running processes (PID, name, parent PID, path) with **automatic code signature verification** using macOS Security framework (detects `valid`, `unsigned`, or `invalid` signatures)
- **Memory Logger** — continuous memory monitoring via `MACH_TASK_BASIC_INFO` with configurable interval, duration, and alert thresholds
- **Network Monitor** — `getifaddrs(3)` listing of IPv4, IPv6, and MAC addresses with family classification and safe variable-length address extraction
- **File System Scanner** — directory snapshots using POSIX `lstat` to capture regular files, directories, and **symbolic links** (records link targets without following them) with SHA-256 integrity hashing
- **Robust Exception Handling** — emits graceful `.warning` events on streams for unreadable items (e.g. SIP protected files) instead of silently skipping them
- **CLI** — `swift-argument-parser` interface with JSON and Markdown report output
- **Desktop App** — SwiftUI `NavigationSplitView` with live streaming charts, configuration presets, sortable tables with code signature status badges and symlink target visualizations, search/filter, and CSV export
- **98 tests** across all phases — Swift Testing with >0.190s typical runtime

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

- **Collection View** — service cards with individual toggles, run button with live progress, real-time error/warning banners, and system health status diagnostics
- **Data Views** — sortable tables for Processes (featuring colored code signature verification badges), Network, Memory, and Filesystem (featuring symbolic link destination arrows) with row counts and search
- **Live Chart** — real-time memory usage LineMark chart with configurable threshold
- **Configuration Presets** — 3 built-in presets (Quick Scan, Full Investigation, Memory Only); save/delete custom presets
- **Inspector** — per-row metadata sheet with copy buttons and nested raw dictionary views
- **Export** — CSV export per data view via `.fileExporter()` and plain text / JSON report formatting

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

## License

MIT
