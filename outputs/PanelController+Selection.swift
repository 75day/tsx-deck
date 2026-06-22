import AppKit
import Foundation

extension PanelController {

    // MARK: - Symbol / Account Selection

    @objc func showSymbolMenu(_ sender: NSButton) {
        let menu = NSMenu()
        for symbol in supportedSymbols {
            let item = NSMenuItem(title: symbol, action: #selector(symbolChanged(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = symbol
            item.state = symbol == selectedSymbol ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 3), in: sender)
    }

    @objc func symbolChanged(_ sender: NSMenuItem) {
        let requestedSymbol = (sender.representedObject as? String) ?? sender.title
        guard supportedSymbols.contains(requestedSymbol) else {
            eventLabel?.stringValue = "\(requestedSymbol) is not supported"
            return
        }
        selectedSymbol = requestedSymbol
        marketStatusText = "Market Syncing"
        quoteSyncing = true
        realtimeContractId = nil
        bestBidPrice = nil
        bestAskPrice = nil
        lastQuoteAt = nil
        limitPriceOverride = nil
        tpPriceOverride = nil
        slPriceOverride = nil
        updateSymbolMenuWidth(for: selectedSymbol, animated: true)
        updateSymbol(resetPrice: false)

        // Immediately start the market quotes WS subscription using the static/last-known
        // contract ID for this symbol. This makes price/quote refresh much faster on switch
        // (no longer blocked waiting for the full REST snapshot roundtrip + contract search).
        // The later refreshReadOnly() will get the official current contractId from API
        // (important for contract rolls) and restart the market sub if it differs.
        if let staticC = contracts[selectedSymbol] {
            startMarketIfNeeded(contractId: staticC.id, force: true)
        }

        // Full refresh still needed for fresh account snapshot, positions/orders (account-level),
        // official contractId, last sync time, etc. Other parts may still take ~1s due to network.
        refreshReadOnly()
    }

    func symbolButtonTitle(_ symbol: String) -> String {
        // Always a down chevron because the menu is a standard downward popup (macOS convention).
        // No up-arrow state is needed or implemented — the popup always appears below the button.
        return "\(symbol) ▾"
    }

    func symbolButtonWidthStyle() {
        symbolButton.fixedHeight(24)
        symbolButton.layer?.cornerRadius = 6
        symbolButton.layer?.masksToBounds = true
    }

    func symbolMenuWidth(_ symbol: String) -> CGFloat {
        let arrowAndPadding: CGFloat = 28
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let textWidth = (symbol as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth + arrowAndPadding)
    }

    func updateSymbolMenuWidth(for symbol: String, animated: Bool = false) {
        let width = symbolMenuWidth(symbol)
        guard symbolMenuWidthConstraint?.constant != width else { return }
        symbolMenuWidthConstraint?.constant = width
        symbolButton?.title = symbolButtonTitle(symbol)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                symbolButton.superview?.layoutSubtreeIfNeeded()
            }
        }
    }

    @objc func accountChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard activeAccounts.indices.contains(index) else { return }
        let account = activeAccounts[index]
        selectedAccountId = account.id
        accountName = account.name
        balanceText = account.balance.map { money($0) } ?? "--"
        resetRealtimeState()
        applyManualRoleAndRisk(accountId: selectedAccountId)
        canTradeText = tradeStatusText(accountId: account.id, apiCanTrade: account.canTrade)
        openOrdersTitle = "OPEN ORDERS"
        positionPrefix = "SYNC"
        lastSnapshot = ReadOnlySnapshot(
            accountId: account.id,
            accountName: account.name,
            balance: account.balance,
            canTrade: account.canTrade,
            realizedDayPnl: nil,
            unrealizedPnl: nil,
            openOrderCount: 0,
            openPositionCount: 0,
            tradeCount: 0,
            contractId: nil,
            rawAccountKeys: [],
            accounts: activeAccounts,
            openOrders: [],
            openPositions: [],
            trades: []
        )
        rebuild(force: true)
        startRealtimeIfNeeded(accountId: account.id, force: true)
        refreshReadOnly()
    }

}
