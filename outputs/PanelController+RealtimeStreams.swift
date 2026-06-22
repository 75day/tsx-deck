import AppKit
import Foundation

extension PanelController {

    // MARK: - Realtime Streams

    func startRealtimeIfNeeded(accountId: Int?, force: Bool) {
        guard let apiClient, let accountId else {
            streamStatusText = "Stream Offline"
            return
        }
        if !force, realtimeAccountId == accountId,
           (streamStatusText == "Stream Live" || streamStatusText == "Stream Connecting") {
            return
        }
        realtimeAccountId = accountId
        streamStatusText = "Stream Connecting"
        updateFooterStatus()
        realtimeClient.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.streamStatusText = status
                if status == "Stream Live" {
                    self.lastSyncText = "Last \(self.timeStamp())"
                    self.reconnectBackoff = 1.0
                    self.lastReconnectAttempt = nil
                }
                self.updateFooterStatus()
                self.scheduleRebuild()
            }
        }
        realtimeClient.onEvent = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastSyncText = "Last \(self.timeStamp())"
                self.updateFooterStatus()
            }
        }
        realtimeClient.onAccount = { [weak self] account in
            DispatchQueue.main.async {
                self?.applyRealtimeAccount(account)
            }
        }
        realtimeClient.onOrder = { [weak self] order in
            DispatchQueue.main.async {
                self?.applyRealtimeOrder(order)
            }
        }
        realtimeClient.onPosition = { [weak self] position in
            DispatchQueue.main.async {
                self?.applyRealtimePosition(position)
            }
        }
        realtimeClient.onTrade = { [weak self] trade in
            DispatchQueue.main.async {
                self?.applyRealtimeTrade(trade)
            }
        }
        apiClient.ensureToken { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure:
                    self.streamStatusText = "Stream Offline"
                    self.updateFooterStatus()
                    self.rebuild()
                case .success(let token):
                    self.realtimeClient.connect(token: token, accountId: accountId)
                }
            }
        }
    }

    func startMarketIfNeeded(contractId: String, force: Bool) {
        guard let apiClient else {
            marketStatusText = "Market Offline"
            return
        }
        if !force, realtimeContractId == contractId,
           (marketStatusText == "Market Live" || marketStatusText == "Market Connecting") {
            return
        }
        realtimeContractId = contractId
        marketStatusText = "Market Connecting"
        updateFooterStatus()
        marketClient.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.marketStatusText = status
                self.dataStatusText = status == "Market Live" ? "Data Live" : (status.contains("Offline") ? "Data Offline" : "Data Syncing")
                if status == "Market Live" {
                    self.reconnectBackoff = 1.0
                    self.lastReconnectAttempt = nil
                }
                self.updateFooterStatus()
                self.scheduleRebuild()
            }
        }
        marketClient.onQuote = { [weak self] quoteContractId, quote in
            DispatchQueue.main.async {
                self?.applyMarketQuote(contractId: quoteContractId, quote)
            }
        }
        apiClient.ensureToken { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure:
                    self.marketStatusText = "Market Offline"
                    self.updateFooterStatus()
                    self.rebuild()
                case .success(let token):
                    self.marketClient.connect(token: token, contractId: contractId)
                }
            }
        }
    }

    func checkAndReconnectStreams() {
        // Health check + backoff to keep us always synced with official TopstepX realtime hubs.
        // In extreme fast markets, WS can flap or drop; this + snapshot fallback + token refresh
        // gives multiple layers to recover without manual intervention.
        guard apiClient != nil else { return }
        let now = Date()
        let canAttempt = lastReconnectAttempt == nil || now.timeIntervalSince(lastReconnectAttempt!) >= reconnectBackoff

        if (streamStatusText.contains("Offline") || streamStatusText.contains("Error") || streamStatusText.contains("Connecting")) {
            if let aid = realtimeAccountId, canAttempt {
                lastReconnectAttempt = now
                reconnectBackoff = min(reconnectBackoff * 1.8 + 0.2, 30.0) // gentle exp backoff, cap 30s
                startRealtimeIfNeeded(accountId: aid, force: true)
            }
        }
        if (marketStatusText.contains("Offline") || marketStatusText.contains("Error") || marketStatusText.contains("Connecting")) {
            if let cid = realtimeContractId, canAttempt {
                lastReconnectAttempt = now
                reconnectBackoff = min(reconnectBackoff * 1.8 + 0.2, 30.0)
                startMarketIfNeeded(contractId: cid, force: true)
            }
        }
    }

    func scheduleRebuild() {
        updateFooterStatus()
        needsRebuild = true
        if rebuildCoalesceTimer != nil { return }
        rebuildCoalesceTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.rebuildCoalesceTimer = nil
            if self.needsRebuild {
                self.needsRebuild = false
                self.rebuild()
            }
        }
    }

}
