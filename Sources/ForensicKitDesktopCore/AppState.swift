import Observation
import Foundation
import OSLog
import ForensicKit

@Observable
public final class AppState {

    private static let log = Logger(subsystem: "com.forensickit", category: "appstate")

    // MARK: - Configuration

    public var runProcessService = true
    public var runMemoryService = false
    public var runNetworkService = true
    public var runFileSystemService = false

    public var outputFormat: ReportFormat = .markdown
    public var fsTargetPath = "."
    public var fsRecursive = true
    public var memoryLimitBytes = 1_610_612_736
    public var memoryIntervalMS = 50
    public var memoryDurationSec = 1.0

    public enum ReportFormat: String, CaseIterable, Sendable {
        case markdown = "Markdown"
        case json = "JSON"
    }

    // MARK: - Presets

    private static let presetsKey = "com.forensickit.presets"

    public private(set) var presets: [Preset] = [] {
        didSet { savePresets() }
    }
    public var selectedPresetID: Preset.ID?

    public var selectedPreset: Preset? {
        guard let id = selectedPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    public struct Preset: Codable, Hashable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var runProcessService: Bool
        public var runMemoryService: Bool
        public var runNetworkService: Bool
        public var runFileSystemService: Bool
        public var fsTargetPath: String
        public var fsRecursive: Bool
        public var memoryLimitBytes: Int
        public var memoryIntervalMS: Int
        public var memoryDurationSec: Double

        public init(
            id: UUID = UUID(),
            name: String,
            runProcessService: Bool = true,
            runMemoryService: Bool = false,
            runNetworkService: Bool = true,
            runFileSystemService: Bool = false,
            fsTargetPath: String = ".",
            fsRecursive: Bool = true,
            memoryLimitBytes: Int = 1_610_612_736,
            memoryIntervalMS: Int = 50,
            memoryDurationSec: Double = 1.0
        ) {
            self.id = id
            self.name = name
            self.runProcessService = runProcessService
            self.runMemoryService = runMemoryService
            self.runNetworkService = runNetworkService
            self.runFileSystemService = runFileSystemService
            self.fsTargetPath = fsTargetPath
            self.fsRecursive = fsRecursive
            self.memoryLimitBytes = memoryLimitBytes
            self.memoryIntervalMS = memoryIntervalMS
            self.memoryDurationSec = memoryDurationSec
        }

        public static let builtins: [Preset] = [
            Preset(name: "Quick System Scan", runProcessService: true, runNetworkService: true),
            Preset(
                name: "Full Forensic Audit",
                runProcessService: true, runMemoryService: true,
                runNetworkService: true, runFileSystemService: true,
                fsRecursive: true
            ),
            Preset(
                name: "Memory Diagnostic",
                runProcessService: false, runMemoryService: true,
                runNetworkService: false, runFileSystemService: false,
                memoryDurationSec: 5.0
            ),
        ]
    }

    // MARK: - Navigation

    public var selectedPanel: Panel? = .collection

    // MARK: - Execution State

    public internal(set) var isRunning = false
    public internal(set) var events: [ForensicEvent] = []
    public internal(set) var errorMessages: [String] = []

    public var hasResults: Bool { !events.isEmpty }

    // MARK: - Computed Filters

    public var processEvents: [ForensicEvent] { events.filter { $0.source == .process } }
    public var memoryEvents: [ForensicEvent] { events.filter { $0.source == .memory } }
    public var networkEvents: [ForensicEvent] { events.filter { $0.source == .network } }
    public var filesystemEvents: [ForensicEvent] { events.filter { $0.source == .filesystem } }

    public var activeServiceCount: Int {
        [runProcessService, runMemoryService, runNetworkService, runFileSystemService].filter { $0 }.count
    }

    // MARK: - Init

    public init() {
        loadPresets()
    }

    // MARK: - Presets

    public func applyPreset(_ preset: Preset) {
        selectedPresetID = preset.id
        runProcessService = preset.runProcessService
        runMemoryService = preset.runMemoryService
        runNetworkService = preset.runNetworkService
        runFileSystemService = preset.runFileSystemService
        fsTargetPath = preset.fsTargetPath
        fsRecursive = preset.fsRecursive
        memoryLimitBytes = preset.memoryLimitBytes
        memoryIntervalMS = preset.memoryIntervalMS
        memoryDurationSec = preset.memoryDurationSec
    }

    public func saveCurrentAsPreset(name: String) {
        let preset = Preset(
            name: name,
            runProcessService: runProcessService,
            runMemoryService: runMemoryService,
            runNetworkService: runNetworkService,
            runFileSystemService: runFileSystemService,
            fsTargetPath: fsTargetPath,
            fsRecursive: fsRecursive,
            memoryLimitBytes: memoryLimitBytes,
            memoryIntervalMS: memoryIntervalMS,
            memoryDurationSec: memoryDurationSec
        )
        presets.append(preset)
        selectedPresetID = preset.id
    }

    public func deletePreset(_ id: Preset.ID) {
        presets.removeAll { $0.id == id }
        if selectedPresetID == id { selectedPresetID = nil }
    }

    private func savePresets() {
        let data = try? JSONEncoder().encode(presets)
        UserDefaults.standard.set(data, forKey: Self.presetsKey)
    }

    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = Preset.builtins + decoded
        } else {
            presets = Preset.builtins
        }
    }

    // MARK: - Actions

    public func clearResults() {
        events = []
        errorMessages = []
        selectedPanel = .collection
    }

    // MARK: - Run Collection (Streaming)

    @MainActor
    public func runCollection() async {
        guard !isRunning else { return }
        isRunning = true
        errorMessages = []
        events = []

        let services = buildServices()
        Self.log.debug("collection started with \(services.count) service(s)")

        guard !services.isEmpty else {
            errorMessages.append("Select at least one service.")
            isRunning = false
            return
        }

        for service in services {
            do {
                try await service.start()
            } catch {
                errorMessages.append("Failed to start \(service.id): \(error.localizedDescription)")
                await stopAll(services)
                isRunning = false
                return
            }
        }

        let memDuration = memoryDurationSec
        await withTaskGroup(of: Void.self) { [self] group in
            for service in services {
                group.addTask {
                    do {
                        for try await event in service.stream() {
                            await MainActor.run { self.events.append(event) }
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessages.append("\(service.id): \(error.localizedDescription)")
                        }
                    }
                }
            }

            if services.contains(where: { $0.id == MemoryLogger.serviceID }) {
                group.addTask {
                    try? await Task.sleep(for: .seconds(memDuration))
                    if let mem = services.first(where: { $0.id == MemoryLogger.serviceID }) {
                        await mem.stop()
                    }
                }
            }
        }

        events.sort { $0.timestamp < $1.timestamp }
        await stopAll(services)
        isRunning = false
        Self.log.debug("collection finished — \(self.events.count) total event(s)")
    }

    private func buildServices() -> [any CollectionService] {
        var services: [any CollectionService] = []
        if runProcessService { services.append(ProcessTreeService()) }
        if runMemoryService {
            services.append(
                MemoryLogger(interval: .milliseconds(memoryIntervalMS), memoryLimitBytes: memoryLimitBytes)
            )
        }
        if runNetworkService { services.append(NetworkMonitorService()) }
        if runFileSystemService {
            let fm = FileManager.default
            let absPath = fsTargetPath == "." ? fm.currentDirectoryPath : URL(fileURLWithPath: fsTargetPath).path
            services.append(FileSystemService(targetPath: absPath, recursive: fsRecursive))
        }
        return services
    }

    private func stopAll(_ services: [any CollectionService]) async {
        for service in services { await service.stop() }
    }

    // MARK: - Export

    public func exportReport() -> String? {
        guard hasResults else { return nil }
        let reporter = ForensicReporter()
        if outputFormat == .json {
            return try? reporter.generateJSON(events: events)
        } else {
            return reporter.generateMarkdown(events: events, targetScanned: fsTargetPath)
        }
    }

    public static func exportCSV(events: [ForensicEvent]) -> String {
        guard let first = events.first else { return "" }
        let keys = first.payload.metadata.keys.sorted()
        var csv = "source,severity,timestamp," + keys.joined(separator: ",") + "\n"

        let formatter = ISO8601DateFormatter()
        for event in events {
            let vals = keys.map { csvEscape(event.payload.metadata[$0] ?? "") }
            csv += "\(event.source.rawValue),\(event.severity.rawValue),\(formatter.string(from: event.timestamp)),"
            csv += vals.joined(separator: ",") + "\n"
        }
        return csv
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
