import Foundation

struct AccountInfo {
    let id: Int
    let name: String
    let balance: Double?
    let canTrade: Bool?
    let simulated: Bool?
    let isVisible: Bool?

    var menuTitle: String {
        let compact = name.replacingOccurrences(of: "-219616-", with: "-")
        return compact.count > 22 ? String(compact.prefix(22)) + "..." : compact
    }
}
