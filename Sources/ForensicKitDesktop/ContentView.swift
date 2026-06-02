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
            VStack(alignment: .leading, spacing: 20) {
                header
                presetsSection
                
                Divider()
                    .padding(.vertical, 4)
                
                Label("Subsystem Collector Services", systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                serviceCards
                
                Divider()
                    .padding(.vertical, 4)
                
                optionsSection
                
                Divider()
                    .padding(.vertical, 4)
                
                runButton
                
                if state.hasResults {
                    resultsSummary
                }
            }
            .padding(24)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("System Forensic Collector")
                    .font(.system(.title, design: .rounded).bold())
                Text("Configure and execute real-time macOS forensic collection services.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            Text("ENTERPRISE EDITION")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    // MARK: Presets

    private var presetsSection: some View {
        HStack {
            Label("Audit Configuration Profile:", systemImage: "slider.horizontal.2.gobackward")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            Picker("", selection: Bindable(state).selectedPresetID) {
                Text("Custom Configuration").tag(nil as AppState.Preset.ID?)
                Divider()
                ForEach(state.presets) { preset in
                    Text(preset.name).tag(preset.id as AppState.Preset.ID?)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            .onChange(of: state.selectedPresetID) { _, newID in
                if let id = newID, let preset = state.presets.first(where: { $0.id == id }) {
                    state.applyPreset(preset)
                }
            }
            
            Button(action: {
                newPresetName = ""
                showSavePreset = true
            }) {
                Label("Save Profile…", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            if let id = state.selectedPresetID {
                Button(role: .destructive, action: {
                    state.deletePreset(id)
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor).opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showSavePreset) {
            VStack(spacing: 16) {
                Text("Save Preset Profile")
                    .font(.headline)
                TextField("Profile Name", text: $newPresetName)
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
            ForEach(services, id: \.id) { svc in
                ServiceCardView(
                    icon: svc.icon,
                    name: svc.name,
                    description: svc.description,
                    isOn: Bindable(state)[dynamicMember: svc.bind]
                )
            }
        }
    }

    // MARK: Options

    @ViewBuilder
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Configuration Options", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.bottom, 2)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    if state.runFileSystemService {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("File System Scan", systemImage: "folder.badge.gearshape")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.accentColor)
                            
                            HStack(spacing: 12) {
                                TextField("Target Path", text: Bindable(state).fsTargetPath)
                                    .monospaced()
                                    .textFieldStyle(.roundedBorder)
                                
                                Button(action: selectFileSystemPath) {
                                    Label("Browse…", systemImage: "ellipsis")
                                }
                                .buttonStyle(.bordered)
                                
                                Toggle("Recursive", isOn: Bindable(state).fsRecursive)
                                    .toggleStyle(.checkbox)
                            }
                        }
                        if state.runMemoryService { Divider() }
                    }

                    if state.runMemoryService {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Memory Monitor Settings", systemImage: "memorychip.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.accentColor)
                            
                            HStack(spacing: 24) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RSS Ceiling Limit").font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        TextField("Bytes", value: Bindable(state).memoryLimitBytes, format: .number)
                                            .frame(width: 110)
                                            .textFieldStyle(.roundedBorder)
                                        Text("\((Double(state.memoryLimitBytes) / 1_073_741_824.0), specifier: "%.2f") GiB")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Polling Interval").font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        TextField("ms", value: Bindable(state).memoryIntervalMS, format: .number)
                                            .frame(width: 60)
                                            .textFieldStyle(.roundedBorder)
                                        Text("ms").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Log Duration").font(.caption).foregroundStyle(.secondary)
                                    HStack(spacing: 4) {
                                        TextField("sec", value: Bindable(state).memoryDurationSec, format: .number)
                                            .frame(width: 60)
                                            .textFieldStyle(.roundedBorder)
                                        Text("s").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if state.runFileSystemService || state.runMemoryService {
                        Divider()
                    }

                    HStack {
                        Label("Export Format", systemImage: "doc.plaintext")
                            .font(.subheadline.bold())
                        Spacer()
                        Picker("", selection: Bindable(state).outputFormat) {
                            ForEach(AppState.ReportFormat.allCases, id: \.self) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                .padding(12)
            }
        }
    }

    private func selectFileSystemPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Select File System Scan Target"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                state.fsTargetPath = url.path
            }
        }
    }

    // MARK: Run Button

    private var runButton: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await state.runCollection() } }) {
                HStack(spacing: 8) {
                    if state.isRunning {
                        ProgressView().scaleEffect(0.8).controlSize(.small)
                        Text("Collecting Forensic Data…")
                    } else {
                        Image(systemName: "play.shield.fill").font(.body)
                        Text("Start Audit Collection").font(.body.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isRunning || state.activeServiceCount == 0)
            .controlSize(.large)
            .tint(Color.blue)

            if !state.errorMessages.isEmpty {
                ForEach(state.errorMessages, id: \.self) { err in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        Text(err).foregroundStyle(.red).font(.callout)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.red.opacity(0.2), lineWidth: 1)
                    )
                }
            }

            if state.isRunning {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Gathering observations from \(state.activeServiceCount) active subsystem\(state.activeServiceCount == 1 ? "" : "s")…")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
        }
    }

    // MARK: Results Summary

    @ViewBuilder
    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Collection Completed Successfully", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button(role: .destructive, action: { state.clearResults() }) {
                    Label("Clear Results", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.subheadline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                resultCard(icon: "terminal.fill", label: "Processes Discovered", count: state.processEvents.count, panel: .processes, color: .purple)
                resultCard(icon: "network", label: "Interfaces Audited", count: state.networkEvents.count, panel: .network, color: .blue)
                resultCard(icon: "memorychip.fill", label: "Memory Snapshots", count: state.memoryEvents.count, panel: .memory, color: .orange)
                resultCard(icon: "folder.fill.badge.gearshape", label: "Files Cataloged", count: state.filesystemEvents.count, panel: .filesystem, color: .teal)
            }
        }
        .padding(16)
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
        )
    }

    private func resultCard(icon: String, label: String, count: Int, panel: Panel, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(count > 0 ? color : Color.secondary)
                .font(.title2)
                .frame(width: 32, height: 32)
                .background(count > 0 ? color.opacity(0.1) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            Spacer()
            if count > 0 {
                Button("View Details") { state.selectedPanel = panel }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor).opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Service Card

private struct ServiceCardView: View {
    let icon: String
    let name: String
    let description: String
    @Binding var isOn: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isOn ? .white : Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(isOn ? Color.accentColor : Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Spacer()
                    
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 32, alignment: .topLeading)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Color.accentColor.opacity(0.04) : Color(.windowBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color.accentColor : Color(.separatorColor).opacity(0.5), lineWidth: isOn ? 1.5 : 1)
            )
            .shadow(color: Color.black.opacity(isHovered ? 0.05 : 0.01), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
