// SPEC: REQ-501 — CLI argument parser integration with all options
// SPEC: REQ-504 — stdout/file output, error formatting on stderr with exit 1
// SPEC: REQ-505 — Swift 6 concurrency compliance, Sendable execution flow

import ArgumentParser
import Foundation
import ForensicKit

@main
// SPEC: REQ-501 — CLI command conforming to ParsableCommand
struct ForensicKitCLI: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "forensic-kit",
        abstract: "ForensicKit — macOS system forensic observation and collection utility.",
        version: ForensicKit.version
    )

    // MARK: - CLI Arguments & Options

    // SPEC: REQ-501 — services selection option
    @Option(
        name: .shortAndLong,
        help: "Comma-separated list of services to execute (process, memory, network, filesystem)."
    )
    var services: String = "process,memory,network,filesystem"

    // SPEC: REQ-501 — output format option
    @Option(
        name: .customShort("f"),
        help: "Output report format (json | markdown)."
    )
    var outputFormat: String = "markdown"

    // SPEC: REQ-501 — output file path option
    @Option(
        name: .customShort("o"),
        help: "Optional file path to write the formatted report. Prints to stdout if omitted."
    )
    var outputPath: String?

    // SPEC: REQ-501 — filesystem target path
    @Option(
        name: .customShort("p"),
        help: "Absolute or relative target directory path for file system forensics."
    )
    var fsTarget: String = "."

    // SPEC: REQ-501 — recursive scanning flag (default: true, disable with --no-fs-recursive)
    @Flag(
        name: .customLong("no-fs-recursive"),
        help: "Disable recursive directory scanning."
    )
    var noFsRecursive: Bool = false

    var fsRecursive: Bool { !noFsRecursive }

    // SPEC: REQ-501 — memory limit in bytes
    @Option(
        name: .shortAndLong,
        help: "Memory monitor RSS limit ceiling in bytes."
    )
    var memoryLimit: Int = 1_610_612_736 // 1.5GiB

    // SPEC: REQ-501 — memory polling interval
    @Option(
        name: .long,
        help: "Memory monitoring polling interval in milliseconds."
    )
    var memoryInterval: Int = 50

    // SPEC: REQ-501 — memory monitoring duration
    @Option(
        name: .long,
        help: "Duration in seconds to run memory monitoring."
    )
    var memoryDuration: Double = 1.0

    // MARK: - Run Execution Loop

    // SPEC: REQ-505 — async execution entry point
    func run() async throws {
        do {
            // 1. Validate output format
            let format = outputFormat.lowercased()
            guard format == "json" || format == "markdown" else {
                throw ValidationError("Invalid output format '\(outputFormat)'. Must be 'json' or 'markdown'.")
            }

            // 2. Parse and validate selected services
            let selectedServiceNames = services.lowercased()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            guard !selectedServiceNames.isEmpty else {
                throw ValidationError("At least one service must be specified in --services.")
            }

            var collectionServices: [any CollectionService] = []

            for name in selectedServiceNames {
                switch name {
                case "process":
                    collectionServices.append(ProcessTreeService())
                case "memory":
                    collectionServices.append(
                        MemoryLogger(
                            interval: .milliseconds(memoryInterval),
                            memoryLimitBytes: memoryLimit
                        )
                    )
                case "network":
                    collectionServices.append(NetworkMonitorService())
                case "filesystem":
                    // Resolve target path to ensure absolute correctness
                    let fm = FileManager.default
                    let absolutePath = fsTarget == "." ? fm.currentDirectoryPath : URL(fileURLWithPath: fsTarget).path
                    collectionServices.append(
                        FileSystemService(
                            targetPath: absolutePath,
                            recursive: fsRecursive
                        )
                    )
                default:
                    throw ValidationError("Unsupported service: '\(name)'. Supported services: process, memory, network, filesystem.")
                }
            }

            // 3. Orchestrate concurrent collection
            // SPEC: REQ-502 — orchestrate in parallel
            let orchestrator = CollectionOrchestrator(services: collectionServices)
            let events = try await orchestrator.run(memoryDuration: memoryDuration)

            // 4. Generate report
            // SPEC: REQ-503 — JSON & Markdown formatting
            let reporter = ForensicReporter()
            let report: String
            
            if format == "json" {
                report = try reporter.generateJSON(events: events)
            } else {
                let targetScanned = selectedServiceNames.contains("filesystem") ? fsTarget : "macOS Host system"
                report = reporter.generateMarkdown(events: events, targetScanned: targetScanned)
            }

            // 5. Output / Write Report
            // SPEC: REQ-504 — stdout vs file path writing
            if let path = outputPath {
                let writeURL = URL(fileURLWithPath: path)
                try report.write(to: writeURL, atomically: true, encoding: .utf8)
            } else {
                print(report)
            }

        } catch {
            // SPEC: REQ-504 — Format errors on stderr and exit with non-zero code
            let stderr = FileHandle.standardError
            let errorMessage = "❌ Error: \(error.localizedDescription)\n"
            if let errorData = errorMessage.data(using: .utf8) {
                stderr.write(errorData)
            }
            throw ExitCode(1)
        }
    }
}
