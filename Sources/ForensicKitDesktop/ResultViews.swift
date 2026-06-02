import SwiftUI
import UniformTypeIdentifiers
import Charts
import ForensicKit
import ForensicKitDesktopCore

// MARK: - Format Helpers

private func formatByteSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

private func parseByteSize(_ bytesStr: String) -> String {
    guard let bytes = Int64(bytesStr) else { return bytesStr }
    return formatByteSize(bytes)
}

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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Processes Tree")
                            .font(.title2.bold())
                        Text("Captured active system processes inside the macOS kernel using sysctl.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showCSV = true }) {
                            Label("Export CSV", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        
                        Text("\(filtered.count) processes filtered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 4)
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "processes") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("PID", value: \.pidValue) { event in
                        Text(event.payload.metadata["pid"] ?? "-").monospaced()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.width(70)
                    
                    TableColumn("Name", value: \.processName) { event in
                        Text(event.payload.metadata["name"] ?? "-")
                            .font(.body.weight(.medium))
                    }.width(180)
                    
                    TableColumn("Parent PID", value: \.parentPidValue) { event in
                        Text(event.payload.metadata["parentPid"] ?? "-").monospaced()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.width(90)
                    
                    TableColumn("Signature", value: \.signatureValue) { event in
                        let sig = event.payload.metadata["signature"] ?? "unsigned"
                        Text(sig.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(
                                sig == "valid" ? Color.green :
                                sig == "invalid" ? Color.red : Color.secondary
                            )
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                sig == "valid" ? Color.green.opacity(0.1) :
                                sig == "invalid" ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }.width(80)
                    
                    TableColumn("Executable Path", value: \.pathValue) { event in
                        Text(event.payload.metadata["path"] ?? "-")
                            .monospaced()
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText, prompt: "Search processes by name, PID, path...")
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network Interfaces")
                            .font(.title2.bold())
                        Text("Active local interface links and bound addresses mapped via getifaddrs.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showCSV = true }) {
                            Label("Export CSV", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        
                        Text("\(filtered.count) entries")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 4)
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "network") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Interface", value: \.interfaceName) { event in
                        Text(event.payload.metadata["interface"] ?? "-").monospaced().bold()
                    }.width(90)
                    
                    TableColumn("Family", value: \.networkFamily) { event in
                        let family = event.payload.metadata["family"] ?? "-"
                        Text(family)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                family == "IPv4" ? Color.blue.opacity(0.1) :
                                family == "IPv6" ? Color.purple.opacity(0.1) :
                                family == "link" ? Color.orange.opacity(0.1) :
                                Color.secondary.opacity(0.1)
                            )
                            .foregroundStyle(
                                family == "IPv4" ? Color.blue :
                                family == "IPv6" ? Color.purple :
                                family == "link" ? Color.orange :
                                Color.secondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }.width(70)
                    
                    TableColumn("Address", value: \.networkAddress) { event in
                        Text(event.payload.metadata["address"] ?? "-")
                            .monospaced()
                            .textSelection(.enabled)
                    }.width(260)
                    
                    TableColumn("Status") { event in
                        let isUp = event.payload.metadata["isUp"] == "true"
                        let isLo = event.payload.metadata["isLoopback"] == "true"
                        
                        HStack(spacing: 6) {
                            Text(isUp ? "ACTIVE" : "INACTIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isUp ? .green : .red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isUp ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            if isLo {
                                Text("LOOP")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }.width(140)
                    
                    TableColumn("Flags") { event in
                        Text("0x" + (event.payload.metadata["flags"] ?? "-"))
                            .monospaced()
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText, prompt: "Search interfaces by name, family, address...")
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

    private var memoryStats: (avg: Double, max: Double, limit: Double) {
        let events = state.memoryEvents
        guard !events.isEmpty else { return (0, 0, Double(state.memoryLimitBytes) / 1_048_576) }
        let rssVals = events.map { $0.rssMB }
        let avgRss = rssVals.reduce(0, +) / Double(events.count)
        let peakRss = rssVals.max() ?? 0
        let limitRss = Double(state.memoryLimitBytes) / 1_048_576
        return (avgRss, peakRss, limitRss)
    }

    var body: some View {
        if state.memoryEvents.isEmpty && !state.isRunning {
            ContentUnavailableView("No Memory Events", systemImage: "memorychip",
                description: Text("Run collection with Memory Monitor enabled."))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Allocations")
                            .font(.title2.bold())
                        Text("Active logging of system memory RSS and VM pages via Mach task_info.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    Button(action: { showCSV = true }) {
                        Label("Export CSV", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 4)
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "memory") { _ in }

                // Stats Dashboard Header
                let stats = memoryStats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryMetricCard(label: "Average Resident Set Size", value: String(format: "%.2f MB", stats.avg), color: .blue, icon: "gauge")
                    summaryMetricCard(label: "Peak Resident Set Size", value: String(format: "%.2f MB", stats.max), color: .orange, icon: "chart.bar.fill")
                    summaryMetricCard(label: "Ceiling Limit Guard", value: String(format: "%.0f MB", stats.limit), color: .red, icon: "shield.fill")
                }
                .padding(.vertical, 2)

                if state.memoryEvents.count >= 2 {
                    MemoryChartView(events: state.memoryEvents)
                        .frame(height: 180)
                        .padding(12)
                        .background(Color(.windowBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 1)
                        )
                }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Time", value: \.timestamp) { event in
                        Text(event.timestamp, style: .time).monospaced().bold()
                    }.width(120)
                    
                    TableColumn("RSS Usage", value: \.rssMB) { event in
                        Text(String(format: "%.2f MB", event.rssMB)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.width(110)
                    
                    TableColumn("Virtual Memory", value: \.vmMB) { event in
                        Text(String(format: "%.2f MB", event.vmMB)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.width(110)
                    
                    TableColumn("Status Check", value: \.severity.rawValue) { event in
                        let isWarn = event.severity == .warning
                        HStack(spacing: 6) {
                            Image(systemName: isWarn ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(isWarn ? .orange : .green)
                            Text(isWarn ? "CEILING WARNING" : "NORMAL")
                                .font(.caption.bold())
                                .foregroundStyle(isWarn ? .orange : .green)
                        }
                    }
                    
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText, prompt: "Search memory log checkpoints...")
                .alternatingRowBackgrounds()
            }
            .sheet(item: $inspectEvent) { InspectorView(event: $0) }
        }
    }

    private func summaryMetricCard(label: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).monospacedDigit()
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Memory Chart

private struct MemoryChartView: View {
    let events: [ForensicEvent]
    @Environment(AppState.self) private var state

    var body: some View {
        Chart {
            ForEach(events, id: \.id) { event in
                LineMark(
                    x: .value("Time", event.timestamp),
                    y: .value("RSS (MB)", event.rssMB)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(
                    x: .value("Time", event.timestamp),
                    y: .value("RSS (MB)", event.rssMB)
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [.blue.opacity(0.15), .blue.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            let threshold = Double(state.memoryLimitBytes) / 1_048_576.0
            RuleMark(y: .value("Safety Ceiling", threshold))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Safety limit guard: \(Int(threshold)) MB")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine().foregroundStyle(Color(.separatorColor).opacity(0.2))
                AxisValueLabel().font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine().foregroundStyle(Color(.separatorColor).opacity(0.2))
                AxisValueLabel().font(.system(size: 9))
            }
        }
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File System Forensics")
                            .font(.title2.bold())
                        Text("Snapshot scan of directory metadata and computed secure SHA-256 integrity hashes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: { showCSV = true }) {
                            Label("Export CSV", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        
                        Text("\(filtered.count) items audited")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 4)
                .fileExporter(isPresented: $showCSV, document: csvDoc(events: filtered),
                    contentType: .commaSeparatedText, defaultFilename: "filesystem") { _ in }

                Table(of: ForensicEvent.self, sortOrder: $sortOrder) {
                    TableColumn("Type", value: \.fileTypeValue) { event in
                        let type = event.payload.metadata["fileType"] ?? "regular"
                        let iconName = type == "directory" ? "folder.fill" :
                                       type == "symbolicLink" ? "link" : "doc.fill"
                        let iconColor = type == "directory" ? Color.orange :
                                        type == "symbolicLink" ? Color.teal : Color.secondary
                        
                        Label(type.capitalized, systemImage: iconName)
                            .foregroundStyle(iconColor)
                            .font(.body.weight(.medium))
                    }.width(90)
                    
                    TableColumn("Perms", value: \.permissionsValue) { event in
                        Text(event.payload.metadata["permissions"] ?? "-")
                            .monospaced()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }.width(70)
                    
                    TableColumn("File Size", value: \.sizeBytesValue) { event in
                        let sizeStr = event.payload.metadata["sizeBytes"] ?? "0"
                        Text(parseByteSize(sizeStr)).monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.width(90)
                    
                    TableColumn("SHA-256 Integrity Hash", value: \.sha256Value) { event in
                        let sha = event.payload.metadata["sha256"] ?? "-"
                        if sha == "-" {
                            Text("-").foregroundStyle(.secondary)
                        } else {
                            Text(sha.count > 16 ? String(sha.prefix(16)) + "…" : sha)
                                .monospaced()
                                .font(.system(size: 11))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }.width(180)
                    
                    TableColumn("Path", value: \.pathValue) { event in
                        let path = event.payload.metadata["path"] ?? "-"
                        let dest = event.payload.metadata["destination"]
                        HStack(spacing: 6) {
                            Text(path)
                                .monospaced()
                                .lineLimit(1)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            if let dest = dest {
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                Text(dest)
                                    .monospaced()
                                    .lineLimit(1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    
                    TableColumn("") { event in
                        Button("Inspect") { inspectEvent = event }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }.width(70)
                } rows: {
                    ForEach(filtered) { TableRow($0) }
                }
                .searchable(text: $searchText, prompt: "Search files by name, path, hash, perms...")
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
    @State private var copiedText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Forensic Event Inspector", systemImage: "magnifyingglass.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Close Window") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            GroupBox("Metadata Attributes") {
                VStack(alignment: .leading, spacing: 8) {
                    inspectorRow(label: "Event ID", value: event.id.uuidString, copyable: true)
                    inspectorRow(label: "Observed At", value: event.timestamp.formatted(date: .numeric, time: .standard) + String(format: ".%03d", Int(event.timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * 1000)), copyable: false)
                    inspectorRow(label: "Source Domain", value: event.source.rawValue.uppercased(), copyable: false)
                    
                    HStack {
                        Text("Severity Severity").font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        Text(event.severity.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(event.severity == .warning ? .orange : (event.severity == .critical ? .red : .green))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(event.severity == .warning ? Color.orange.opacity(0.1) : (event.severity == .critical ? Color.red.opacity(0.1) : Color.green.opacity(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(8)
            }

            GroupBox("Subsystem Raw Dictionary Values") {
                if event.payload.metadata.isEmpty {
                    Text("No payload dictionary key-value data captured.")
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    Table(of: MetaRow.self) {
                        TableColumn("Key Identifier") { row in
                            Text(row.key).bold().monospaced().font(.system(size: 11))
                        }.width(150)
                        
                        TableColumn("Value") { row in
                            HStack {
                                Text(row.value)
                                    .monospaced()
                                    .textSelection(.enabled)
                                    .font(.system(size: 11))
                                    .lineLimit(2)
                                Spacer()
                                Button(action: { copyToClipboard(row.value) }) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Copy value")
                            }
                        }
                    } rows: {
                        ForEach(sortedMeta) { TableRow($0) }
                    }
                    .alternatingRowBackgrounds()
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 440)
        .overlay(alignment: .bottom) {
            if let copied = copiedText {
                Text("Copied: \(copied)")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 60)
            }
        }
        .animation(.default, value: copiedText)
    }

    private var sortedMeta: [MetaRow] {
        event.payload.metadata.sorted { $0.key < $1.key }.map { MetaRow(key: $0.key, value: $0.value) }
    }

    private struct MetaRow: Identifiable {
        let key: String
        let value: String
        var id: String { key }
    }

    private func inspectorRow(label: String, value: String, copyable: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .monospaced()
                .font(.system(size: 11))
                .textSelection(.enabled)
            
            Spacer()
            
            if copyable {
                Button(action: { copyToClipboard(value) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copyToClipboard(_ str: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(str, forType: .string)
        let preview = str.count > 20 ? String(str.prefix(17)) + "..." : str
        copiedText = preview
        Task { try? await Task.sleep(for: .seconds(1.5)); copiedText = nil }
    }
}

// MARK: - Report View

struct ReportView: View {
    @Environment(AppState.self) private var state
    @State private var showSaveDialog = false
    @State private var copied = false

    private var warningCount: Int {
        state.events.filter { $0.severity != .info }.count
    }

    var body: some View {
        VStack(spacing: 16) {
            if state.hasResults {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Forensic Audit Report")
                            .font(.title2.bold())
                        
                        HStack(spacing: 8) {
                            Text(warningCount == 0 ? "SECURE" : "ANOMALIES DETECTED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(warningCount == 0 ? Color.green : Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            Text("\(state.events.count) observations aggregated")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Button(action: copyToClipboard) {
                            Label(copied ? "Copied" : "Copy to Clipboard", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { showSaveDialog = true }) {
                            Label("Export Report…", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.bottom, 2)

                let report = state.exportReport() ?? ""

                ScrollView {
                    Text(report)
                        .font(.system(.body, design: .monospaced))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separatorColor).opacity(0.4), lineWidth: 1)
                )

            } else {
                ContentUnavailableView("No Report Available", systemImage: "doc.text",
                    description: Text("Configure and run a collection sweep first to generate reports."))
            }
        }
        .padding(24)
        .overlay(alignment: .bottom) {
            if copied {
                Text("Copied report to clipboard")
                    .font(.caption)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
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
