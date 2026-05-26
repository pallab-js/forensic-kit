import Foundation
import ForensicKit

extension ForensicEvent {
    public var pidValue: Int { Int(payload.metadata["pid"] ?? "") ?? 0 }
    public var parentPidValue: Int { Int(payload.metadata["parentPid"] ?? "") ?? 0 }
    public var processName: String { payload.metadata["name"] ?? "" }
    public var interfaceName: String { payload.metadata["interface"] ?? "" }
    public var networkFamily: String { payload.metadata["family"] ?? "" }
    public var networkAddress: String { payload.metadata["address"] ?? "" }
    public var rssMB: Double {
        guard let rss = payload.metadata["rssBytes"], let bytes = Int64(rss) else { return 0 }
        return Double(bytes) / 1_048_576
    }
    public var vmMB: Double {
        guard let vm = payload.metadata["vmBytes"], let bytes = Int64(vm) else { return 0 }
        return Double(bytes) / 1_048_576
    }
    public var fileTypeValue: String { payload.metadata["fileType"] ?? "" }
    public var pathValue: String { payload.metadata["path"] ?? "" }
    public var sizeBytesValue: Int64 { Int64(payload.metadata["sizeBytes"] ?? "") ?? 0 }
    public var permissionsValue: String { payload.metadata["permissions"] ?? "" }
    public var sha256Value: String { payload.metadata["sha256"] ?? "" }

    public func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return payload.metadata.values.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
