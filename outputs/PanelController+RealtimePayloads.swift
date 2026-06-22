import AppKit
import Foundation

extension PanelController {

    // MARK: - Realtime Payload Handlers

    func applyMarketQuote(contractId: String, _ quote: [String: Any]) {
        guard contractId == realtimeContractId else { return }
        let nextPrice = numberValue(quote["lastPrice"]) ?? numberValue(quote["price"])
        let nextBid = numberValue(quote["bestBid"]) ?? numberValue(quote["bid"]) ?? numberValue(quote["bidPrice"])
        let nextAsk = numberValue(quote["bestAsk"]) ?? numberValue(quote["ask"]) ?? numberValue(quote["askPrice"])
        guard nextPrice != nil || nextBid != nil || nextAsk != nil else { return }
        if let nextBid {
            bestBidPrice = nextBid
        }
        if let nextAsk {
            bestAskPrice = nextAsk
        }
        lastQuoteAt = Date()
        let wasSyncing = quoteSyncing
        let reference = nextPrice ?? midPrice() ?? price
        let direction = wasSyncing ? 1.0 : (reference >= price ? 1.0 : -1.0)
        if let nextPrice {
            price = nextPrice
        } else if let nextBid, let nextAsk {
            price = (nextBid + nextAsk) / 2
        }
        quoteSyncing = !(bestBidPrice != nil && bestAskPrice != nil)
        marketStatusText = "Market Live"
        dataStatusText = "Data Live"
        lastSyncText = "Last \(timeStamp())"
        updateFooterStatus()
        render(direction: direction)
        if wasSyncing && !quoteSyncing {
            scheduleRebuild()
        }
    }

    func numberValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    func applyRealtimeAccount(_ account: [String: Any]) {
        let payload = accountDataPayload(account)
        let id = payload["id"] as? Int ?? (payload["id"] as? NSNumber)?.intValue
        guard id == selectedAccountId else { return }
        if let balance = numberValue(payload["balance"]) {
            balanceText = money(balance)
        }
        if let realized = numberValue(payload["realizedDayPnl"]) {
            officialRealizedDayPnl = realized
        }
        if let unrealized = numberValue(payload["unrealizedPnl"]) {
            officialUnrealizedPnl = unrealized
        }
        let canTrade = payload["canTrade"] as? Bool
        canTradeText = tradeStatusText(accountId: id, apiCanTrade: canTrade)
        lastSyncText = "Last \(timeStamp())"
        updateFooterStatus()
        rebuild()
    }

    func accountDataPayload(_ account: [String: Any]) -> [String: Any] {
        return account["data"] as? [String: Any] ?? account
    }

    func applyRealtimeOrder(_ order: [String: Any]) {
        let payload = orderDataPayload(order)
        guard realtimeOrderBelongsToSelectedAccount(payload),
              let id = intValue(payload["id"]) else { return }
        hasRealtimeOrderState = true
        let previous = realtimeOrders[id]
        let status = intValue(payload["status"])
        if status == 1 || status == 6 {
            realtimeOrders[id] = payload
            realtimeClosedOrderIds.remove(id)
        } else {
            realtimeOrders.removeValue(forKey: id)
            realtimeClosedOrderIds.insert(id)
            clearEditingOrder(orderId: id)
        }
        // Record type for protection orders so we can decide TP vs SL sound even if fill toast is for protection.
        if protectionOrderGroups[id] != nil {
            if let otype = intValue(payload["type"]) {
                protectionOrderType[id] = otype
            }
        }
        showRealtimeOrderToast(payload, previous: previous)
        handleProtectionOrderUpdate(orderId: id, status: status)
        if let status, status == 2 || status == 3 || status == 4 || status == 5 {
            submittedEntryOrderIds.remove(id)
            protectionOrderKind.removeValue(forKey: id)
            protectionOrderType.removeValue(forKey: id)
        }
        realtimeOpenOrderCount = realtimeOrders.count
        openOrdersTitle = "OPEN ORDERS (\(effectiveOrderCount()))"
        lastSyncText = "Last \(timeStamp())"
        updateFooterStatus()
        scheduleRebuild()
    }

    func orderDataPayload(_ order: [String: Any]) -> [String: Any] {
        return order["data"] as? [String: Any] ?? order
    }

    func realtimeOrderBelongsToSelectedAccount(_ order: [String: Any]) -> Bool {
        if let payloadId = payloadAccountId(order) {
            return payloadId == selectedAccountId
        }
        // GatewayUserOrder is subscribed per account, and some payloads may omit accountId.
        return realtimeAccountId != nil && realtimeAccountId == selectedAccountId
    }

    func handleProtectionOrderUpdate(orderId: Int, status: Int?) {
        guard let status,
              let groupId = protectionOrderGroups[orderId] else { return }
        let isSingle = groupId.hasPrefix("single")
        let groupOrders: Set<Int> = isSingle ? [orderId] : (protectionGroupOrders[groupId] ?? [])
        if status == 2 {
            if !isSingle {
                cancelSiblingProtectionOrders(groupId: groupId, filledOrderId: orderId, orderIds: groupOrders)
            }
            // Ensure sound for protection fill (TP.caf for TP, Order.caf for SL), even if the "Filled" toast in showRealtime was skipped or deduped.
            // Use lastProtectionFillSound to avoid double-playing if showRealtime also played just before.
            let now = Date()
            if lastProtectionFillSound?.id != orderId || now.timeIntervalSince(lastProtectionFillSound!.time) > 1 {
                if protectionOrderKind[orderId] == "TP" {
                    playFillSoundFile("TP")
                } else if let otype = protectionOrderType[orderId] {
                    if otype == 1 {
                        playFillSoundFile("TP")
                    } else {
                        playFillSoundFile("Order")
                    }
                } else {
                    playFillSoundFile("Order")
                }
                lastProtectionFillSound = (orderId, now)
            }
        } else if status == 3 || status == 4 || status == 5 {
            protectionOrderGroups.removeValue(forKey: orderId)
            if !isSingle {
                if groupOrders.allSatisfy({ protectionOrderGroups[$0] == nil }) {
                    protectionGroupOrders.removeValue(forKey: groupId)
                    protectionCancelIssuedGroups.remove(groupId)
                }
            }
        }
    }

    func cancelSiblingProtectionOrders(groupId: String, filledOrderId: Int, orderIds: Set<Int>) {
        guard !protectionCancelIssuedGroups.contains(groupId),
              let apiClient,
              let accountId = selectedAccountId else { return }
        protectionCancelIssuedGroups.insert(groupId)
        let siblings = orderIds.filter { $0 != filledOrderId }
        guard !siblings.isEmpty else { return }
        showTradeToast("OCO cancel sent", subtitle: "Canceling sibling protection", color: palette.orange)
        cancelOrderIds(apiClient: apiClient, accountId: accountId, orderIds: Array(siblings)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.setEvent("OCO CANCEL FAILED: \(self.shortTradeError(error.localizedDescription))", color: self.palette.red, detail: error.localizedDescription)
                case .success:
                    self.setEvent("OCO CANCEL SENT: sibling protection", color: self.palette.orange)
                    self.refreshAfterTradeMutation()
                }
            }
        }
    }

    func applyRealtimePosition(_ position: [String: Any]) {
        let payload = positionDataPayload(position)
        guard payloadAccountId(payload) == selectedAccountId,
              let id = payload["id"] as? Int ?? (payload["id"] as? NSNumber)?.intValue else { return }
        let size = payload["size"] as? Int ?? (payload["size"] as? NSNumber)?.intValue ?? 0
        let posCid = payload["contractId"] as? String
        if size == 0 {
            realtimePositions.removeValue(forKey: id)
        } else {
            realtimePositions[id] = payload
            // Only update global avgPrice if this position is for the currently viewed contract/symbol.
            if let cid = posCid, let target = activeContractId(), cid == target,
               let avg = payload["averagePrice"] as? Double ?? (payload["averagePrice"] as? NSNumber)?.doubleValue {
                avgPrice = avg
            }
            lastKnownPositionSide = positionSideText()
            if lastKnownPositionSide != "FLAT" {
                lastNonFlatPositionSide = lastKnownPositionSide
                lastNonFlatPositionAt = Date()
            }
        }
        realtimeOpenPositionCount = realtimePositions.isEmpty ? realtimeOpenPositionCount : realtimePositions.count
        if size == 0, realtimeOpenPositionCount ?? 0 > 0 {
            realtimeOpenPositionCount = max(0, (realtimeOpenPositionCount ?? 0) - 1)
        }
        positionPrefix = positionSideText()
        lastSyncText = "Last \(timeStamp())"
        scheduleRebuild()
    }

    func applySnapshotPositions(_ positions: [[String: Any]]) {
        realtimePositions.removeAll()
        let targetCid = activeContractId()
        for (index, position) in positions.enumerated() {
            let payload = positionDataPayload(position)
            let size = payload["size"] as? Int ?? (payload["size"] as? NSNumber)?.intValue ?? 0
            guard size != 0 else { continue }
            let id = payload["id"] as? Int ?? (payload["id"] as? NSNumber)?.intValue ?? -(index + 1)
            realtimePositions[id] = payload
            // Only set avgPrice from snapshot if it matches the current viewed symbol/contract.
            if let cid = payload["contractId"] as? String, let target = targetCid, cid == target,
               let avg = payload["averagePrice"] as? Double ?? (payload["averagePrice"] as? NSNumber)?.doubleValue {
                avgPrice = avg
            }
        }
        realtimeOpenPositionCount = realtimePositions.count
        positionPrefix = positionSideText()
        if !realtimePositions.isEmpty {
            lastKnownPositionSide = positionSideText()
            if lastKnownPositionSide != "FLAT" {
                lastNonFlatPositionSide = lastKnownPositionSide
                lastNonFlatPositionAt = Date()
            }
        }
    }

    func positionDataPayload(_ position: [String: Any]) -> [String: Any] {
        return position["data"] as? [String: Any] ?? position
    }

    func applyRealtimeTrade(_ trade: [String: Any]) {
        guard realtimeTradeBelongsToSelectedAccount(trade) else { return }
        if trade["voided"] as? Bool == true { return }

        playRealtimeTradeFillSoundIfNeeded(trade)

        realtimeTradeCount = (realtimeTradeCount ?? 0) + 1

        // Accumulate realized P&L immediately from realtime trade events
        // for fast update after position close (instead of waiting for next snapshot).
        // Matches the logic in realizedPnlFromTrades (sum profitAndLoss - fees - commissions).
        var delta: Double = 0
        if let pnl = numberValue(trade["profitAndLoss"]) {
            delta += pnl
        }
        delta -= numberValue(trade["fees"]) ?? 0
        delta -= numberValue(trade["commissions"]) ?? 0

        if delta != 0 {
            officialRealizedDayPnl = (officialRealizedDayPnl ?? 0) + delta
        }

        lastSyncText = "Last \(timeStamp())"
        scheduleRebuild()
    }

    func realtimeTradeBelongsToSelectedAccount(_ trade: [String: Any]) -> Bool {
        if let payloadId = payloadAccountId(trade) {
            return payloadId == selectedAccountId
        }
        // GatewayUserTrade is subscribed per account, and some payloads do not carry accountId.
        // In that case, trust the active user-hub subscription identity.
        return realtimeAccountId != nil && realtimeAccountId == selectedAccountId
    }

    func playRealtimeTradeFillSoundIfNeeded(_ trade: [String: Any]) {
        let key = realtimeTradeFillSoundKey(trade)
        guard shouldPlayFillSound(key: key) else { return }
        let orderId = intValue(trade["orderId"])
            ?? intValue(trade["orderID"])
            ?? intValue(trade["order_id"])
            ?? intValue(trade["order"])
        if let orderId, protectionOrderKind[orderId] == "TP" {
            playFillSoundFile("TP")
        } else {
            playFillSoundFile("Order")
        }
        markFillSoundPlayed(key: key)
    }

    func realtimeTradeFillSoundKey(_ trade: [String: Any]) -> String {
        if let orderId = intValue(trade["orderId"])
            ?? intValue(trade["orderID"])
            ?? intValue(trade["order_id"])
            ?? intValue(trade["order"]) {
            return "order-\(orderId)"
        }
        if let tradeId = intValue(trade["id"]) ?? intValue(trade["tradeId"]) ?? intValue(trade["tradeID"]) {
            return "trade-\(tradeId)"
        }
        let contract = trade["contractId"] as? String ?? activeContractId() ?? selectedSymbol
        let timestamp = (trade["creationTimestamp"] as? String)
            ?? (trade["timestamp"] as? String)
            ?? (trade["updateTimestamp"] as? String)
            ?? timeStamp()
        let price = numberValue(trade["price"]) ?? numberValue(trade["fillPrice"]) ?? numberValue(trade["executionPrice"]) ?? 0
        let size = intValue(trade["size"]) ?? intValue(trade["qty"]) ?? intValue(trade["quantity"]) ?? 0
        let side = intValue(trade["side"]) ?? intValue(trade["type"]) ?? -1
        return "trade-\(contract)-\(timestamp)-\(price)-\(size)-\(side)"
    }

    func syncSnapshotTradeFillSounds(_ trades: [[String: Any]], accountId: Int?) {
        guard let accountId else { return }
        let keys = Set(trades.compactMap { trade -> String? in
            if trade["voided"] as? Bool == true { return nil }
            return realtimeTradeFillSoundKey(trade)
        })

        guard snapshotTradeSoundAccountId == accountId,
              knownSnapshotTradeSoundKeys != nil else {
            snapshotTradeSoundAccountId = accountId
            knownSnapshotTradeSoundKeys = keys
            return
        }

        // REST /Trade/search is authoritative for RP&L reconciliation, but it can arrive
        // seconds after the actual fill. Do not play delayed fill sounds from this snapshot;
        // sounds should come from realtime trade/order events or direct user actions.
        suppressSnapshotFillSoundsUntil = nil
        knownSnapshotTradeSoundKeys = keys
    }

    func shouldPlayFillSound(key: String) -> Bool {
        let now = Date()
        recentFillSoundKeys = recentFillSoundKeys.filter { now.timeIntervalSince($0.value) < 5 }
        if let previous = recentFillSoundKeys[key], now.timeIntervalSince(previous) < 2 {
            return false
        }
        return true
    }

    func markFillSoundPlayed(key: String) {
        recentFillSoundKeys[key] = Date()
    }

    func payloadAccountId(_ payload: [String: Any]) -> Int? {
        return payload["accountId"] as? Int
            ?? (payload["accountId"] as? NSNumber)?.intValue
            ?? payload["tradingAccountId"] as? Int
            ?? (payload["tradingAccountId"] as? NSNumber)?.intValue
    }

    func resetRealtimeState() {
        realtimeOpenOrderCount = nil
        realtimeOpenPositionCount = nil
        realtimeTradeCount = nil
        realtimeOrders.removeAll()
        realtimeClosedOrderIds.removeAll()
        realtimePositions.removeAll()
        hasRealtimeOrderState = false
        officialRealizedDayPnl = nil
        officialUnrealizedPnl = nil
    }

}
