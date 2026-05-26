import SwiftUI
import UniformTypeIdentifiers
import Charts
import ForensicKit
import ForensicKitDesktopCore

// MARK: - Process List

struct ProcessListView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder: [KeyPathComparator<ForensicEvent>] = [.init(\.pidValue, order: .forward)]
    @State private var searchText = ""
    @State private var inspectEvent: ForensicEvent?
    @State private var showCSV = false

    private var filtered: [ForensicEvent] {
        state.processEvents
            .sorted(using: sortOrder)
            .filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        if state.processEvents.isEmpty {
            ContentUnavailableView("No Process Events", systemImage: "terminal",
                description: Text("Run collection with Process Tree enabled."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Processes — \(state.processEvents.count) entries")
                        .font(.title3.bold())
                    Spacer()
                    Button("Export CSV", systemImage: "doc.text") { showCSV = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "processes") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("PID", value: \.pidValue) { event in
                        Text(event.payload.metadata["pid"] ?? "-").monospaced()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(70)
                    TableColumn("Name", value: \.processName) { event in
                        Text(event.payload.metadata["name"] ?? "-")
                    }
                    TableColumn("Parent PID", value: \.parentPidValue) { event in
                        Text(event.payload.metadata["parentPid"] ?? "-").monospaced()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(100)
                    TableColumn("Path", value: \.pathValue) { event in
                        Text(event.payload.metadata["path"] ?? "-").monospaced().foregroundStyle(.secondary)
                    }
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.plain).controlSize(.mini)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText)
                .alternatingRowBackgrounds()
            }
            .sheet(item: $inspectEvent) { InspectorView(event: $0) }
        }
    }
}

// MARK: - Network List

struct NetworkListView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder: [KeyPathComparator<ForensicEvent>] = [.init(\.interfaceName, order: .forward)]
    @State private var searchText = ""
    @State private var inspectEvent: ForensicEvent?
    @State private var showCSV = false

    private var filtered: [ForensicEvent] {
        state.networkEvents
            .sorted(using: sortOrder)
            .filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        if state.networkEvents.isEmpty {
            ContentUnavailableView("No Network Events", systemImage: "network",
                description: Text("Run collection with Network Interfaces enabled."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Network Interfaces — \(state.networkEvents.count) entries")
                        .font(.title3.bold())
                    Spacer()
                    Button("Export CSV", systemImage: "doc.text") { showCSV = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "network") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Interface", value: \.interfaceName) { event in
                        Text(event.payload.metadata["interface"] ?? "-").monospaced()
                    }
                    TableColumn("Family", value: \.networkFamily) { event in
                        Text(event.payload.metadata["family"] ?? "-")
                    }.width(70)
                    TableColumn("Address", value: \.networkAddress) { event in
                        Text(event.payload.metadata["address"] ?? "-").monospaced()
                    }
                    TableColumn("Loopback") { event in
                        Text(event.payload.metadata["isLoopback"] ?? "-")
                    }.width(90)
                    TableColumn("Up") { event in
                        Text(event.payload.metadata["isUp"] ?? "-")
                    }.width(60)
                    TableColumn("Flags") { event in
                        Text(event.payload.metadata["flags"] ?? "-").monospaced().foregroundStyle(.secondary)
                    }.width(90)
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.plain).controlSize(.mini)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText)
                .alternatingRowBackgrounds()
            }
            .sheet(item: $inspectEvent) { InspectorView(event: $0) }
        }
    }
}

// MARK: - Memory List

struct MemoryListView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder: [KeyPathComparator<ForensicEvent>] = [.init(\.timestamp, order: .forward)]
    @State private var searchText = ""
    @State private var inspectEvent: ForensicEvent?
    @State private var showCSV = false

    private var filtered: [ForensicEvent] {
        state.memoryEvents
            .sorted(using: sortOrder)
            .filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        if state.memoryEvents.isEmpty && !state.isRunning {
            ContentUnavailableView("No Memory Events", systemImage: "memorychip",
                description: Text("Run collection with Memory Monitor enabled."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Memory Monitor — \(state.memoryEvents.count) snapshot\(state.memoryEvents.count == 1 ? "" : "s")")
                        .font(.title3.bold())
                    Spacer()
                    Button("Export CSV", systemImage: "doc.text") { showCSV = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "memory") { _ in }

                if state.memoryEvents.count >= 2 {
                    MemoryChartView(events: state.memoryEvents)
                        .frame(height: 220)
                        .padding(.vertical, 4)
                }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Time", value: \.timestamp) { event in
                        Text(event.timestamp, style: .time).monospaced()
                    }
                    TableColumn("RSS (MB)", value: \.rssMB) { event in
                        Text(String(format: "%.1f", event.rssMB)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(100)
                    TableColumn("VM (MB)", value: \.vmMB) { event in
                        Text(String(format: "%.1f", event.vmMB)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(100)
                    TableColumn("Severity", value: \.severity.rawValue) { event in
                        Text(event.severity.rawValue)
                            .foregroundStyle(event.severity == .warning ? .orange : .primary)
                    }.width(90)
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.plain).controlSize(.mini)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText)
                .alternatingRowBackgrounds()
            }
            .sheet(item: $inspectEvent) { InspectorView(event: $0) }
        }
    }
}

// MARK: - Memory Chart

private struct MemoryChartView: View {
    let events: [ForensicEvent]

    var body: some View {
        Chart {
            ForEach(events, id: \.id) { event in
                LineMark(
                    x: .value("Time", event.timestamp),
                    y: .value("RSS (MB)", event.rssMB)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                AreaMark(
                    x: .value("Time", event.timestamp),
                    y: .value("RSS (MB)", event.rssMB)
                )
                .foregroundStyle(.blue.opacity(0.08))
            }

            if let threshold = events.first.map({ event in
                let limit = Int(event.payload.metadata["rssBytes"] ?? "0") ?? 0
                return Double(limit) > 0 ? Double(limit) / 1_048_576 : 0
            }), threshold > 0 {
                RuleMark(y: .value("Limit", threshold))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [4, 4]))
            }
        }
        .chartXAxis(.automatic)
        .chartYAxisLabel("RSS (MB)")
        .chartLegend(.hidden)
    }
}

// MARK: - File System List

struct FileSystemListView: View {
    @Environment(AppState.self) private var state
    @State private var sortOrder: [KeyPathComparator<ForensicEvent>] = [.init(\.pathValue, order: .forward)]
    @State private var searchText = ""
    @State private var inspectEvent: ForensicEvent?
    @State private var showCSV = false

    private var filtered: [ForensicEvent] {
        state.filesystemEvents
            .sorted(using: sortOrder)
            .filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        if state.filesystemEvents.isEmpty {
            ContentUnavailableView("No File System Events", systemImage: "folder",
                description: Text("Run collection with File System Scan enabled."))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("File System — \(state.filesystemEvents.count) entries")
                        .font(.title3.bold())
                    Spacer()
                    Button("Export CSV", systemImage: "doc.text") { showCSV = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "filesystem") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Type", value: \.fileTypeValue) { event in
                        Text(event.payload.metadata["fileType"] ?? "-")
                    }.width(80)
                    TableColumn("Permissions", value: \.permissionsValue) { event in
                        Text(event.payload.metadata["permissions"] ?? "-").monospaced()
                    }.width(100)
                    TableColumn("Size (B)", value: \.sizeBytesValue) { event in
                        Text(event.payload.metadata["sizeBytes"] ?? "-")
                            .monospaced()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.width(90)
                    TableColumn("SHA-256") { event in
                        let sha = event.payload.metadata["sha256"] ?? "-"
                        Text(sha.count > 16 ? String(sha.prefix(16)) + "…" : sha).monospaced()
                    }
                    TableColumn("Path", value: \.pathValue) { event in
                        Text(event.payload.metadata["path"] ?? "-").monospaced()
                    }
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.plain).controlSize(.mini)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText)
                .alternatingRowBackgrounds()
            }
            .sheet(item: $inspectEvent) { InspectorView(event: $0) }
        }
    }
}

// MARK: - Inspector

private struct InspectorView: View {
    let event: ForensicEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Event Inspector")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("ID", value: event.id.uuidString)
                    LabeledContent("Timestamp", value: event.timestamp.formatted(date: .numeric, time: .standard))
                    LabeledContent("Source", value: event.source.rawValue)
                    LabeledContent("Severity", value: event.severity.rawValue)
                }
                .padding(6)
            }

            GroupBox("Payload Metadata") {
                if event.payload.metadata.isEmpty {
                    Text("No metadata").foregroundStyle(.secondary).padding(6)
                } else {
                    Table(of: MetaRow.self) {
                        TableColumn("Key", value: \.key).width(140)
                        TableColumn("Value", value: \.value)
                    } rows: {
                        ForEach(sortedMeta) { TableRow($0) }
                    }
                    .frame(minHeight: 200)
                    .alternatingRowBackgrounds()
                }
            }
        }
        .padding()
        .frame(width: 520, height: 400)
    }

    private var sortedMeta: [MetaRow] {
        event.payload.metadata.sorted { $0.key < $1.key }.map { MetaRow(key: $0.key, value: $0.value) }
    }

    private struct MetaRow: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }
}

// MARK: - Report

struct ReportView: View {
    @Environment(AppState.self) private var state
    @State private var showSaveDialog = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            if state.hasResults {
                HStack {
                    Text("Forensic Audit Report")
                        .font(.title2.bold())
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        copyToClipboard()
                    }
                    .buttonStyle(.bordered)
                    Button("Export…", systemImage: "square.and.arrow.down") {
                        showSaveDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                }

                let report = state.exportReport() ?? ""

                ScrollView {
                    Text(report)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))

            } else {
                ContentUnavailableView("No Report", systemImage: "doc.text",
                    description: Text("Run a collection first to generate a report."))
            }
        }
        .overlay(alignment: .bottom) {
            if copied {
                Text("Copied")
                    .font(.caption)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fileExporter(isPresented: $showSaveDialog,
            document: ReportDocument(report: state.exportReport() ?? ""),
            contentType: state.outputFormat == .json ? .json : .plainText,
            defaultFilename: "forensic-report") { result in
                if case .failure(let error) = result { print("Export failed: \(error)") }
            }
        .animation(.default, value: copied)
    }

    private func copyToClipboard() {
        guard let report = state.exportReport() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }
}

// MARK: - CSV Document Helper

private func csvDoc(events: [ForensicEvent]) -> CSVDocument {
    CSVDocument(events: events)
}

private struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let events: [ForensicEvent]

    init(events: [ForensicEvent]) { self.events = events }

    init(configuration: ReadConfiguration) throws {
        events = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let csv = AppState.exportCSV(events: events)
        return FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}

// MARK: - Report Document

struct ReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }

    var report: String

    init(report: String) { self.report = report }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        report = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(report.utf8))
    }
}
