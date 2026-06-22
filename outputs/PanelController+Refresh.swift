import AppKit
import Foundation

extension PanelController {

    // MARK: - Status Updates

    func updateFooterStatus() {
        updateHeaderQuoteStatus()
        footerStatusView?.update(
            palette: palette,
            isDark: isDark,
            lastSyncText: lastSyncText,
            snapshotStatusText: snapshotStatusText,
            apiLive: apiStatusText.contains("Connected"),
            streamLive: streamStatusText.contains("Live"),
            marketLive: marketStatusText.contains("Live") && !quoteSyncing
        )
    }

    func updateHeaderQuoteStatus() {
        let live = marketStatusText == "Market Live" && !quoteSyncing
        headerQuoteStatusLabel?.stringValue = live ? "● LIVE" : "● SYNC"
        headerQuoteStatusLabel?.textColor = live ? palette.green : palette.orange
    }

}

extension PanelController {

    // MARK: - Snapshot / API Refresh

    func updateSymbol(resetPrice: Bool = true) {
        let key = selectedSymbol
        let c = contracts[key]!
        symbolButton?.title = symbolButtonTitle(key)
        updateSymbolMenuWidth(for: key)
        if resetPrice {
            price = c.price
            avgPrice = price - c.tick * 42
        }
        contractLabel?.stringValue = c.id
        render(direction: 1)
    }

    func refreshReadOnly() {
        guard let apiClient else {
            apiStatusText = "API Config missing"
            dataStatusText = "No API Config"
            snapshotStatusText = "Snapshot off"
            eventLabel?.stringValue = "Last: \(apiStatusText)"
            updateFooterStatus()
            return
        }
        let symbol = selectedSymbol
        apiClient.refresh(symbol: symbol, accountId: selectedAccountId) { [weak self] result in
            guard let self else { return }
            let needsInitialAccountRender = self.selectedAccountId == nil || self.accountName == "TopstepX - not connected"
            switch result {
            case .failure(let error):
                self.apiStatusText = "API Error"
                self.dataStatusText = "Data Offline"
                self.snapshotStatusText = "Snapshot failed"
                self.eventLabel?.stringValue = "Last: API Error - \(error.localizedDescription.prefix(80))"
                self.eventLabel?.textColor = self.palette.red
                self.updateFooterStatus()
            case .success(let snapshot):
                self.lastSnapshot = snapshot
                self.activeAccounts = snapshot.accounts
                self.selectedAccountId = snapshot.accountId
                self.apiStatusText = "API Connected"
                if self.tokenStatusText == "Token Pending" {
                    self.tokenStatusText = "Token Valid"
                }
                self.dataStatusText = "Data Read-only"
                self.lastSyncText = "Last \(self.timeStamp())"
                self.snapshotStatusText = self.effectivePositionCount() > 0 || self.effectiveOrderCount() > 0 ? "Snapshot 2s" : "Snapshot 30s"
                self.accountName = snapshot.accountName
                self.applyManualRoleAndRisk(accountId: snapshot.accountId)
                self.canTradeText = self.tradeStatusText(accountId: snapshot.accountId, apiCanTrade: snapshot.canTrade)
                self.realtimeOpenOrderCount = snapshot.openOrderCount
                self.realtimeOpenPositionCount = snapshot.openPositionCount
                self.realtimeTradeCount = snapshot.tradeCount
                self.openOrdersTitle = "OPEN ORDERS (\(self.effectiveOrderCount()))"
                self.positionPrefix = self.effectivePositionCount() > 0 ? "OPEN" : "FLAT"
                self.balanceText = snapshot.balance.map { money($0) } ?? "--"
                // Prefer trade-sum over the (often missing) account["realizedDayPnl"] because we now
                // window the /Trade/search to the ET 18:00 reset boundary. This makes RP&L reset
                // cleanly when the official platform does (instead of mixing yesterday's trades via old -24h).
                self.officialRealizedDayPnl = self.realizedPnlFromTrades(snapshot.trades) ?? snapshot.realizedDayPnl
                self.officialUnrealizedPnl = snapshot.unrealizedPnl
                self.syncSnapshotTradeFillSounds(snapshot.trades, accountId: snapshot.accountId)
                self.applySnapshotPositions(snapshot.openPositions)
                self.reconcileProtectionGroups(openOrders: snapshot.openOrders, openPositionCount: snapshot.openPositionCount)
                if let contractId = snapshot.contractId {
                    self.contractLabel?.stringValue = contractId
                    self.startMarketIfNeeded(contractId: contractId, force: false)
                }
                self.startRealtimeIfNeeded(accountId: snapshot.accountId, force: false)
                self.updateFooterStatus()
                self.rebuild(force: needsInitialAccountRender)
            }
        }
    }

    func refreshAfterTradeMutation() {
        refreshReadOnly()
        for delay in [1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshReadOnly()
            }
        }
    }

    func refreshActiveTradeStateIfNeeded() {
        guard effectivePositionCount() > 0 || effectiveOrderCount() > 0 else { return }
        refreshReadOnly()
    }

    func reconcileProtectionGroups(openOrders: [[String: Any]], openPositionCount: Int) {
        guard openPositionCount == 0,
              !protectionGroupOrders.isEmpty,
              let apiClient,
              let accountId = selectedAccountId else { return }
        let openIds = Set(openOrders.compactMap { intValue($0["id"]) })
        for (groupId, orderIds) in protectionGroupOrders where !protectionCancelIssuedGroups.contains(groupId) {
            let openSiblingIds = Array(orderIds.intersection(openIds))
            guard !openSiblingIds.isEmpty else { continue }
            protectionCancelIssuedGroups.insert(groupId)
            cancelOrderIds(apiClient: apiClient, accountId: accountId, orderIds: openSiblingIds) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .failure(let error):
                        self.setEvent("OCO REST CANCEL FAILED: \(self.shortTradeError(error.localizedDescription))", color: self.palette.red, detail: error.localizedDescription)
                    case .success:
                        self.setEvent("OCO REST CANCEL SENT: stale protection", color: self.palette.orange)
                    }
                }
            }
        }
    }

    func validateAPIToken() {
        guard let apiClient else {
            tokenStatusText = "No Token"
            return
        }
        apiClient.validateToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.tokenStatusText = "Reauth Needed"
                self.apiStatusText = "API Error"
                self.eventLabel?.stringValue = "Last: Token validate failed - \(error.localizedDescription.prefix(80))"
                self.eventLabel?.textColor = self.palette.red
                self.updateFooterStatus()
                self.rebuild()
            case .success(let status):
                self.tokenStatusText = status
                self.apiStatusText = "API Connected"
                self.eventLabel?.stringValue = "Last: \(status)"
                self.eventLabel?.textColor = self.palette.green
                if status.contains("Refreshed") {
                    // restart realtime with fresh token so WS stays authorized long-term
                    self.resetRealtimeState()
                    if let aid = self.realtimeAccountId { self.startRealtimeIfNeeded(accountId: aid, force: true) }
                    if let cid = self.realtimeContractId { self.startMarketIfNeeded(contractId: cid, force: true) }
                }
                self.updateFooterStatus()
                self.rebuild()
            }
        }
    }

}

extension PanelController {

    // MARK: - Timers / Rendering Updates

    func timeStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    func tick() {
        if marketStatusText == "Market Live" || quoteSyncing {
            return
        }
        let key = selectedSymbol
        let c = contracts[key]!
        let direction = Double.random(in: 0...1) > 0.45 ? 1.0 : -1.0
        price += direction * c.tick
        render(direction: direction)
        updateFooterStatus()
    }

    func render(direction: Double) {
        if quoteSyncing {
            priceLabel?.stringValue = "SYNCING"
            priceLabel?.textColor = palette.orange
        } else {
            priceLabel?.stringValue = number2(price)
            priceLabel?.textColor = direction >= 0 ? palette.green : palette.red
        }
        sellQuoteButton?.update(side: "SELL", price: quotePriceText(side: "SELL"), color: quoteTextColor(side: "SELL"))
        buyQuoteButton?.update(side: "BUY", price: quotePriceText(side: "BUY"), color: quoteTextColor(side: "BUY"))
            spreadButton?.stringValue = spreadText()
        updateHeaderQuoteStatus()
        pnlLabel?.stringValue = positionPnlText()
        pnlLabel?.textColor = positionPnlColor()
        if let bid = displayBidPrice(), let ask = displayAskPrice() {
            bidAskLabel?.stringValue = "Bid \(number2(bid))  Ask \(number2(ask))"
        } else {
            bidAskLabel?.stringValue = "Bid --  Ask --"
        }
    }

}
