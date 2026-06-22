import AppKit
import Foundation

extension PanelController {

    // MARK: - Position / Account Calculations

    func effectiveOrderCount() -> Int {
        return workingOrders().count
    }

    func effectivePositionCount() -> Int {
        return realtimeOpenPositionCount ?? lastSnapshot?.openPositionCount ?? 0
    }

    func activePosition() -> [String: Any]? {
        // Strictly scope to the currently selected symbol's contract.
        // This prevents showing e.g. MNQ position + PnL when viewing NQ.
        if let targetCid = activeContractId() {
            return realtimePositions.values.first { ($0["contractId"] as? String) == targetCid }
        }
        return nil
    }

    func activeContractId() -> String? {
        return realtimeContractId ?? lastSnapshot?.contractId ?? contracts[selectedSymbol]?.id
    }

    func officialSubmissionContractId() throws -> String {
        guard let contractId = lastSnapshot?.contractId else {
            throw ProjectXError.api("official contractId not confirmed")
        }
        guard realtimeContractId == contractId else {
            throw ProjectXError.api("market stream not synced to official contract")
        }
        return contractId
    }

    // Resolve tick/tickValue for a given contractId (from position or snapshot).
    // Falls back to selectedSymbol's spec. This ensures correct PnL calc even if
    // position contract differs from viewed symbol during transitions.
    func contractSpec(for contractId: String?) -> (tick: Double, tickValue: Double)? {
        guard let cid = contractId else { return nil }
        // exact id match (from runtime resolution)
        for (_, c) in contracts {
            if c.id == cid { return (c.tick, c.tickValue) }
        }
        // Parse symbol from contractId like "CON.F.US.MNQ.U25" or "CON.F.US.ENQ.V25"
        // Split by "." and match exact symbol component to avoid "MNQ".contains("NQ")
        let parts = cid.split(separator: ".").map { String($0) }
        for (sym, c) in contracts {
            if parts.contains(sym) {
                return (c.tick, c.tickValue)
            }
        }
        return nil
    }

    func positionSizeText() -> Int {
        if let position = activePosition() {
            return abs(position["size"] as? Int ?? (position["size"] as? NSNumber)?.intValue ?? 0)
        }
        return 0
    }

    func positionSideText() -> String {
        guard let position = activePosition() else { return "FLAT" }
        let type = position["type"] as? Int ?? (position["type"] as? NSNumber)?.intValue
        if type == 2 { return "SHORT" }
        if type == 1 { return "LONG" }
        let size = position["size"] as? Int ?? (position["size"] as? NSNumber)?.intValue ?? 0
        return size < 0 ? "SHORT" : "LONG"
    }

    func positionEntrySide() -> String? {
        let side = positionSideText()
        if side == "LONG" { return "BUY" }
        if side == "SHORT" { return "SELL" }
        return nil
    }

    func isOppositeOpenPositionOrder(side: String) -> Bool {
        guard let entrySide = positionEntrySide() else { return false }
        return side != entrySide
    }

    func isMarketableExitLimit(side: String, price: Double) -> Bool {
        guard isOppositeOpenPositionOrder(side: side), orderType == "LIMIT" else { return false }
        if side == "BUY", let ask = displayAskPrice() {
            return price >= ask
        }
        if side == "SELL", let bid = displayBidPrice() {
            return price <= bid
        }
        return false
    }

    func averagePriceText() -> String {
        guard let position = activePosition(),
              let avg = position["averagePrice"] as? Double ?? (position["averagePrice"] as? NSNumber)?.doubleValue else {
            return "--"
        }
        return number2(avg)
    }

    func positionPnlValue() -> Double? {
        if let position = activePosition(),
           let value = numberValue(position["unrealizedPnl"]) ?? numberValue(position["unrealizedPnL"]) {
            return value
        }
        if let value = markToMarketUnrealizedPnl() {
            return value
        }
        return officialUnrealizedPnl
    }

    func markToMarketUnrealizedPnl() -> Double? {
        guard let position = activePosition(),
              let avg = numberValue(position["averagePrice"]),
              let current = positionMarkPrice() else { return nil }
        let size = abs(position["size"] as? Int ?? (position["size"] as? NSNumber)?.intValue ?? 0)
        guard size > 0 else { return nil }
        // Use the contract spec matching this position's contractId (not blindly selectedSymbol).
        // This prevents using NQ tickValue (5) for MNQ position (0.5) etc.
        let posCid = position["contractId"] as? String
        let spec = contractSpec(for: posCid) ?? (contracts[selectedSymbol]!.tick, contracts[selectedSymbol]!.tickValue)
        let type = position["type"] as? Int ?? (position["type"] as? NSNumber)?.intValue
        let direction = type == 2 ? -1.0 : 1.0
        let ticks = (current - avg) / spec.0
        return ticks * spec.1 * Double(size) * direction
    }

    func positionMarkPrice() -> Double? {
        guard let position = activePosition() else { return nil }
        let type = position["type"] as? Int ?? (position["type"] as? NSNumber)?.intValue
        if type == 2 {
            return displayAskPrice() ?? midPrice() ?? price
        }
        return displayBidPrice() ?? midPrice() ?? price
    }

    func realizedPnlFromTrades(_ trades: [[String: Any]]) -> Double? {
        guard !trades.isEmpty else { return nil }
        var total = 0.0
        var sawValue = false
        for trade in trades {
            if trade["voided"] as? Bool == true { continue }
            if let pnl = numberValue(trade["profitAndLoss"]) {
                total += pnl
                sawValue = true
            }
            total -= numberValue(trade["fees"]) ?? 0
            total -= numberValue(trade["commissions"]) ?? 0
        }
        return sawValue ? total : nil
    }

    func positionPnlText() -> String {
        guard let pnl = positionPnlValue() else { return "--" }
        if pnl == 0 { return "0.00" }
        return "\(pnl > 0 ? "+" : "-")\(number2(abs(pnl)))"
    }

    func positionPnlColor() -> NSColor {
        guard let pnl = positionPnlValue() else { return palette.muted }
        if pnl > 0 { return palette.green }
        if pnl < 0 { return palette.red }
        return palette.muted
    }

    func officialDayNetText() -> String {
        guard let value = officialRealizedDayPnl else { return "--" }
        if value == 0 { return "0.00" }
        return "\(value > 0 ? "+" : "-")\(number2(abs(value)))"
    }

    func officialDayNetColor() -> NSColor {
        guard let value = officialRealizedDayPnl else { return palette.muted }
        if value > 0 { return palette.green }
        if value < 0 { return palette.red }
        return palette.muted
    }

    func protectionStatusText() -> String {
        // Scope strictly to the current selected symbol's position (after symbol switch fixes).
        // Previously used global effectivePositionCount and all account orders,
        // so MNQ's SL/TP protections would leak and show when viewing NQ/ES/etc.
        guard activePosition() != nil else { return "None" }
        let exitSide = positionSideText() == "SHORT" ? "BUY" : "SELL"
        let currentCid = activeContractId()
        let exitOrders = workingOrders().filter { order in
            orderSideText(order) == exitSide &&
            (currentCid == nil ||
             (order["contractId"] as? String) == currentCid ||
             (order["contractId"] as? String) == nil)
        }
        let hasTP = exitOrders.contains { intValue($0["type"]) == 1 }
        let hasSL = exitOrders.contains { intValue($0["type"]) == 4 || intValue($0["type"]) == 3 || intValue($0["type"]) == 5 }
        if hasTP && hasSL { return "TP/SL" }
        if hasTP { return "TP" }
        if hasSL { return "SL" }
        return "None"
    }

    func tradeStatusText(accountId: Int?, apiCanTrade: Bool?) -> String {
        return apiCanTrade == true ? "CAN TRADE" : "NO TRADE"
    }

    func selectedAccountInfo() -> AccountInfo? {
        guard let selectedAccountId else { return nil }
        return activeAccounts.first { $0.id == selectedAccountId }
    }

    func accountTypeText() -> String {
        return accountTypeText(for: selectedAccountInfo(), fallbackName: accountName)
    }

    func accountTypeText(for account: AccountInfo?, fallbackName: String = "") -> String {
        let name = (account?.name ?? fallbackName).uppercased()
        if name.contains("PRAC") || name.contains("PRACTICE") || account?.simulated == true {
            return "PRACTICE"
        }
        if name.contains("XFA") || name.contains("EXPRESS") || name.contains("FUNDED") {
            return "XFA"
        }
        if name.contains("LIVE") {
            return "LIVE"
        }
        if name.contains("COMBINE") || name.contains("TC") || name.contains("DLL") {
            return "COMBINE"
        }
        if let id = account?.id,
           apiClient?.config.practiceAccountIds?.contains(id) == true {
            return "PRACTICE"
        }
        return "ACCOUNT"
    }

    func accountTypeColor(_ type: String) -> NSColor {
        switch type {
        case "PRACTICE":
            return palette.blue
        case "XFA":
            return NSColor.systemYellow
        case "LIVE":
            return palette.green
        case "COMBINE":
            return palette.text
        default:
            return palette.muted
        }
    }

    func applyManualRoleAndRisk(accountId: Int?) {
        guard let config = apiClient?.config else {
            accountRoleText = "LEAD UNSET"
            return
        }
        if let accountId, config.leadAccountId == accountId {
            accountRoleText = "LEADER"
        } else if let accountId, config.followerAccountIds?.contains(accountId) == true {
            accountRoleText = "FOLLOWER"
        } else if let accountId, config.practiceAccountIds?.contains(accountId) == true {
            accountRoleText = "PRACTICE"
        } else {
            accountRoleText = config.leadAccountId == nil ? "LEAD UNSET" : "UNMAPPED"
        }

        if let risk = config.manualRisk {
            if let used = risk.dllUsed, let limit = risk.dllLimit {
                dllText = "\(money(used)) / \(money(limit))"
            }
            if let mll = risk.mll {
                mllText = money(mll)
            }
            if let used = risk.pdptUsed, let limit = risk.pdptLimit {
                pdptText = "PDPT \(money(used))/\(money(limit))"
            }
            riskLineText = "Manual TopstepX risk values"
        }
    }

}
