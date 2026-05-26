import SwiftUI
import ForensicKit
import ForensicKitDesktopCore

// MARK: - Root View

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailView
                .padding()
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: Bindable(state).selectedPanel) {
            Section("Controls") {
                NavigationLink(value: Panel.collection) {
                    Label(Panel.collection.rawValue, systemImage: Panel.collection.icon)
                }
            }

            Section("Results") {
                ForEach(resultPanels, id: \.self) { panel in
                    NavigationLink(value: panel) {
                        Label(panel.rawValue, systemImage: panel.icon)
                    }
                    .badge(badge(for: panel))
                    .foregroundStyle(hasData(for: panel) ? .primary : .secondary)
                }
            }

            Section("Output") {
                NavigationLink(value: Panel.report) {
                    Label(Panel.report.rawValue, systemImage: Panel.report.icon)
                }
                .foregroundStyle(state.hasResults ? .primary : .secondary)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private var resultPanels: [Panel] { [.processes, .network, .memory, .filesystem] }

    private func badge(for panel: Panel) -> Int {
        switch panel {
        case .processes:  state.processEvents.count
        case .network:    state.networkEvents.count
        case .memory:     state.memoryEvents.count
        case .filesystem: state.filesystemEvents.count
        default: 0
        }
    }

    private func hasData(for panel: Panel) -> Bool { badge(for: panel) > 0 }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedPanel {
        case .collection: CollectionSettingsView()
        case .processes:  ProcessListView()
        case .network:    NetworkListView()
        case .memory:     MemoryListView()
        case .filesystem: FileSystemListView()
        case .report:     ReportView()
        case nil:         CollectionSettingsView()
        }
    }
}

// MARK: - Collection Settings

struct CollectionSettingsView: View {
    @Environment(AppState.self) private var state
    @State private var showSavePreset = false
    @State private var newPresetName = ""

    private struct ServiceDef {
        let id: String
        let icon: String
        let name: String
        let description: String
        let bind: ReferenceWritableKeyPath<AppState, Bool>
    }

    private let services: [ServiceDef] = [
        ServiceDef(id: "process", icon: "terminal", name: "Process Tree", description: "Enumerate all running processes via sysctl", bind: \.runProcessService),
        ServiceDef(id: "network", icon: "network", name: "Network Interfaces", description: "List all network interfaces and addresses", bind: \.runNetworkService),
        ServiceDef(id: "memory", icon: "memorychip", name: "Memory Monitor", description: "Monitor RSS and virtual memory usage", bind: \.runMemoryService),
        ServiceDef(id: "filesystem", icon: "folder", name: "File System Scan", description: "Scan directory metadata and compute SHA-256 hashes", bind: \.runFileSystemService),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                presetsSection
                serviceCards
                if state.runMemoryService || state.runFileSystemService { optionsSection }
                runButton
                if state.hasResults { resultsSummary }
            }
            .padding()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Forensic Collection")
                .font(.title2.bold())
            Text("Select services and configure options, then run a collection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Presets

    private var presetsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Presets", systemImage: "bookmark")
                    .font(.headline.weight(.medium))

                HStack {
                    Picker("", selection: Bindable(state).selectedPresetID) {
                        Text("Manual Configuration").tag(nil as AppState.Preset.ID?)
                        ForEach(state.presets) { preset in
                            Text(preset.name).tag(preset.id as AppState.Preset.ID?)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: state.selectedPresetID) { _, newID in
                        if let id = newID, let preset = state.presets.first(where: { $0.id == id }) {
                            state.applyPreset(preset)
                        }
                    }

                    Button("Save Current…", systemImage: "plus") {
                        newPresetName = ""
                        showSavePreset = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let id = state.selectedPresetID {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            state.deletePreset(id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $showSavePreset) {
            VStack(spacing: 16) {
                Text("Save Preset")
                    .font(.headline)
                TextField("Preset Name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                HStack {
                    Button("Cancel") { showSavePreset = false }
                        .keyboardShortcut(.escape)
                    Button("Save") {
                        let name = newPresetName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            state.saveCurrentAsPreset(name: name)
                            showSavePreset = false
                        }
                    }
                    .keyboardShortcut(.return)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    // MARK: Service Cards

    private var serviceCards: some View {
        VStack(spacing: 0) {
            ForEach(services, id: \.id) { svc in
                ServiceCardView(
                    icon: svc.icon,
                    name: svc.name,
                    description: svc.description,
                    isOn: Bindable(state)[dynamicMember: svc.bind]
                )
                if svc.id != services.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Options

    @ViewBuilder
    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if state.runFileSystemService {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("File System", systemImage: "folder")
                            .font(.headline.weight(.medium))
                        HStack {
                            TextField("Target Path", text: Bindable(state).fsTargetPath)
                                .monospaced()
                                .textFieldStyle(.roundedBorder)
                            Toggle("Recursive", isOn: Bindable(state).fsRecursive)
                                .fixedSize()
                        }
                    }
                }

                if state.runMemoryService && state.runFileSystemService { Divider() }

                if state.runMemoryService {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Memory Monitor", systemImage: "memorychip")
                            .font(.headline.weight(.medium))
                        HStack(spacing: 16) {
                            HStack {
                                Text("Limit:")
                                TextField("Bytes", value: Bindable(state).memoryLimitBytes, format: .number)
                                    .frame(width: 100).textFieldStyle(.roundedBorder)
                                Text("(\(state.memoryLimitBytes / (1024*1024)) MB)")
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            HStack {
                                Text("Interval:")
                                TextField("ms", value: Bindable(state).memoryIntervalMS, format: .number)
                                    .frame(width: 70).textFieldStyle(.roundedBorder)
                                Text("ms").foregroundStyle(.secondary).font(.caption)
                            }
                            HStack {
                                Text("Duration:")
                                TextField("sec", value: Bindable(state).memoryDurationSec, format: .number)
                                    .frame(width: 70).textFieldStyle(.roundedBorder)
                                Text("s").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text("Report Format:")
                        .font(.headline.weight(.medium))
                    Picker("", selection: Bindable(state).outputFormat) {
                        ForEach(AppState.ReportFormat.allCases, id: \.self) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .padding(8)
        }
    }

    // MARK: Run Button

    private var runButton: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await state.runCollection() } }) {
                HStack(spacing: 8) {
                    if state.isRunning {
                        ProgressView().scaleEffect(0.8).controlSize(.small)
                        Text("Collecting…")
                    } else {
                        Image(systemName: "play.fill").font(.body)
                        Text("Run Collection").font(.body.weight(.medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning || state.activeServiceCount == 0)
            .controlSize(.large)

            if !state.errorMessages.isEmpty {
                ForEach(state.errorMessages, id: \.self) { err in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err).foregroundStyle(.red).font(.callout)
                    }
                    .padding(8)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if state.isRunning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Collecting from \(state.activeServiceCount) service\(state.activeServiceCount == 1 ? "" : "s")…")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
        }
    }

    // MARK: Results Summary

    @ViewBuilder
    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Collection Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button("Clear Results", role: .destructive) { state.clearResults() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                resultCard(icon: "terminal", label: "Processes", count: state.processEvents.count, panel: .processes)
                resultCard(icon: "network", label: "Network", count: state.networkEvents.count, panel: .network)
                resultCard(icon: "memorychip", label: "Memory", count: state.memoryEvents.count, panel: .memory)
                resultCard(icon: "folder", label: "Filesystem", count: state.filesystemEvents.count, panel: .filesystem)
            }
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func resultCard(icon: String, label: String, count: Int, panel: Panel) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            if count > 0 {
                Button("View") { state.selectedPanel = panel }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Service Card

private struct ServiceCardView: View {
    let icon: String
    let name: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.medium))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
