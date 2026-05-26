import Foundation

public enum Panel: String, CaseIterable, Hashable, Sendable {
    case collection = "Collection"
    case processes  = "Processes"
    case network    = "Network"
    case memory     = "Memory"
    case filesystem = "Filesystem"
    case report     = "Report"

    public var icon: String {
        switch self {
        case .collection: "gearshape"
        case .processes:  "terminal"
        case .network:    "network"
        case .memory:     "memorychip"
        case .filesystem: "folder"
        case .report:     "doc.text"
        }
    }
}
