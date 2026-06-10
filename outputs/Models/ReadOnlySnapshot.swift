import Foundation

struct ReadOnlySnapshot {
    let accountId: Int?
    let accountName: String
    let balance: Double?
    let canTrade: Bool?
    let realizedDayPnl: Double?
    let unrealizedPnl: Double?
    let openOrderCount: Int
    let openPositionCount: Int
    let tradeCount: Int
    let contractId: String?
    let rawAccountKeys: [String]
    let accounts: [AccountInfo]
    let openOrders: [[String: Any]]
    let openPositions: [[String: Any]]
    let trades: [[String: Any]]
}
