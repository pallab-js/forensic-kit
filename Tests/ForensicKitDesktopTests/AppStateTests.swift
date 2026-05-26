import Testing
import Foundation
@testable import ForensicKitDesktopCore
import ForensicKit

// MARK: - Mock Service

final class MockCollectionService: CollectionService, @unchecked Sendable {
    let id: String
    let events: [ForensicEvent]
    let failOnStart: Bool
    let failOnStream: Bool

    init(id: String = "mock-test-service",
         events: [ForensicEvent] = [],
         failOnStart: Bool = false,
         failOnStream: Bool = false) {
        self.id = id
        self.events = events
        self.failOnStart = failOnStart
        self.failOnStream = failOnStream
    }

    private var started = false

    func start() async throws {
        if failOnStart { throw ForensicError.collectionFailed("mock start failed") }
        started = true
    }

    func stop() async {
        started = false
    }

    func stream() -> AsyncThrowingStream<ForensicEvent, any Error> {
        AsyncThrowingStream { continuation in
            guard started else {
                continuation.finish(throwing: ForensicError.serviceNotRunning(serviceId: id))
                return
            }
            if failOnStream {
                continuation.finish(throwing: ForensicError.collectionFailed("mock stream failed"))
                return
            }
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

// MARK: - AppState Tests

final class AppStateTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "com.forensickit.presets")
    }

    @Test("clearResults resets events, errors, and navigates to collection")
    func clearResults() {
        let state = AppState()
        state.events = [ForensicEvent(severity: .info, source: .system, payload: .system(event: "test"))]
        state.errorMessages = ["something went wrong"]
        state.selectedPanel = .processes

        state.clearResults()

        #expect(state.events.isEmpty)
        #expect(state.errorMessages.isEmpty)
        #expect(state.selectedPanel == .collection)
    }

    @Test("hasResults is true only when events are non-empty")
    func hasResults() {
        let state = AppState()
        #expect(!state.hasResults)

        state.events = [ForensicEvent(severity: .info, source: .system, payload: .system(event: "test"))]
        #expect(state.hasResults)
    }

    @Test("activeServiceCount reflects enabled services")
    func activeServiceCount() {
        let state = AppState()
        state.runProcessService = true
        state.runMemoryService = false
        state.runNetworkService = true
        state.runFileSystemService = false
        #expect(state.activeServiceCount == 2)
    }
}

// MARK: - Presets Tests

final class PresetTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "com.forensickit.presets")
    }

    @Test("init loads builtin presets")
    func builtinPresets() {
        let state = AppState()
        #expect(state.presets.count == 3)
        #expect(state.presets[0].name == "Quick System Scan")
        #expect(state.presets[1].name == "Full Forensic Audit")
        #expect(state.presets[2].name == "Memory Diagnostic")
    }

    @Test("applyPreset updates all configuration fields")
    func applyPreset() {
        let state = AppState()
        let preset = AppState.Preset(
            name: "Custom",
            runProcessService: false,
            runMemoryService: true,
            runNetworkService: false,
            runFileSystemService: true,
            fsTargetPath: "/tmp/test",
            fsRecursive: false,
            memoryLimitBytes: 999,
            memoryIntervalMS: 100,
            memoryDurationSec: 2.5
        )

        state.applyPreset(preset)

        #expect(!state.runProcessService)
        #expect(state.runMemoryService)
        #expect(!state.runNetworkService)
        #expect(state.runFileSystemService)
        #expect(state.fsTargetPath == "/tmp/test")
        #expect(!state.fsRecursive)
        #expect(state.memoryLimitBytes == 999)
        #expect(state.memoryIntervalMS == 100)
        #expect(state.memoryDurationSec == 2.5)
        #expect(state.selectedPresetID == preset.id)
    }

    @Test("saveCurrentAsPreset captures current config and adds to presets")
    func savePreset() {
        let state = AppState()
        let initialCount = state.presets.count

        state.runMemoryService = true
        state.memoryDurationSec = 10
        state.saveCurrentAsPreset(name: "My Preset")

        #expect(state.presets.count == initialCount + 1)
        guard let saved = state.presets.last else { return }
        #expect(saved.name == "My Preset")
        #expect(saved.runMemoryService)
        #expect(saved.memoryDurationSec == 10)
    }

    @Test("deletePreset removes preset and clears selection")
    func deletePreset() {
        let state = AppState()
        state.saveCurrentAsPreset(name: "Temp")
        let savedID = state.selectedPresetID

        state.deletePreset(savedID!)

        #expect(!state.presets.contains(where: { $0.id == savedID }))
        #expect(state.selectedPresetID == nil)
    }
}

// MARK: - CSV Export Tests

final class CSVExportTests {
    @Test("exportCSV with single event produces valid header and row")
    func singleEvent() {
        let events = [
            ForensicEvent(
                severity: .info,
                source: .process,
                payload: .process(pid: 100, name: "Finder")
            )
        ]
        let csv = AppState.exportCSV(events: events)
        #expect(csv.hasPrefix("source,severity,timestamp,"))
        #expect(csv.contains("process"))
        #expect(csv.contains("info"))
        #expect(csv.contains("100"))
        #expect(csv.contains("Finder"))
    }

    @Test("exportCSV with multiple events includes all rows")
    func multipleEvents() {
        let events = [
            ForensicEvent(
                severity: .info,
                source: .network,
                payload: .network(interface: "en0", family: "IPv4", address: "127.0.0.1", isLoopback: true, isUp: true, flags: "8049")
            ),
            ForensicEvent(
                severity: .info,
                source: .network,
                payload: .network(interface: "en1", family: "IPv4", address: "0.0.0.0", isLoopback: false, isUp: false, flags: "8049")
            ),
        ]
        let csv = AppState.exportCSV(events: events)
        let rows = csv.split(separator: "\n")
        #expect(rows.count == 3) // header + 2 events
        #expect(rows[1].contains("127.0.0.1"))
        #expect(rows[2].contains("0.0.0.0"))
    }

    @Test("exportCSV with empty array returns empty string")
    func emptyCSV() {
        #expect(AppState.exportCSV(events: []) == "")
    }

    @Test("exportCSV escapes commas in values")
    func csvEscapesCommas() {
        let events = [
            ForensicEvent(
                severity: .info,
                source: .filesystem,
                payload: EventPayload(
                    kind: .filesystem,
                    metadata: ["path": "/Users/test/Downloads,File.pdf"]
                )
            )
        ]
        let csv = AppState.exportCSV(events: events)
        #expect(csv.contains("\"/Users/test/Downloads,File.pdf\""))
    }
}

// MARK: - Event Filter Tests

final class EventFilterTests {
    @Test("processEvents returns only process events")
    func filtersProcessEvents() {
        let state = AppState()
        state.events = [
            ForensicEvent(severity: .info, source: .process, payload: .process(pid: 1, name: "launchd")),
            ForensicEvent(severity: .info, source: .network, payload: .network(interface: "en0", family: "IPv4", address: "10.0.0.1", isLoopback: false, isUp: true, flags: "8049")),
            ForensicEvent(severity: .info, source: .process, payload: .process(pid: 2, name: "kernel_task")),
        ]
        #expect(state.processEvents.count == 2)
        #expect(state.networkEvents.count == 1)
        #expect(state.memoryEvents.isEmpty)
        #expect(state.filesystemEvents.isEmpty)
    }
}

// MARK: - Panel Tests

final class PanelTests {
    @Test("all panels have unique raw values")
    func uniqueRawValues() {
        let panels = Panel.allCases
        #expect(Set(panels.map(\.rawValue)).count == panels.count)
    }

    @Test("each panel has a non-empty icon")
    func nonEmptyIcons() {
        for panel in Panel.allCases {
            #expect(!panel.icon.isEmpty)
        }
    }
}

// MARK: - Sorting Extension Tests

final class SortingTests {
    @Test("pidValue parses from metadata")
    func pidValue() {
        let event = ForensicEvent(
            severity: .info, source: .process,
            payload: .process(pid: 42, name: "test")
        )
        #expect(event.pidValue == 42)
    }

    @Test("rssMB converts bytes to megabytes")
    func rssMB() {
        let event = ForensicEvent(
            severity: .info, source: .memory,
            payload: .memory(rssBytes: 1_048_576, vmBytes: 2_097_152)
        )
        #expect(event.rssMB == 1.0)
        #expect(event.vmMB == 2.0)
    }

    @Test("matchesSearch checks all metadata values")
    func matchesSearch() {
        let event = ForensicEvent(
            severity: .info, source: .process,
            payload: .process(pid: 999, name: "Safari")
        )
        #expect(event.matchesSearch("Safari"))
        #expect(event.matchesSearch("999"))
        #expect(!event.matchesSearch("Chrome"))
        #expect(event.matchesSearch("")) // empty matches all
    }
}
