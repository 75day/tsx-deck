import AppKit
import Foundation

// ============================================================================
// PROJECT SESSION SUMMARY
// This file + the accompanying SESSION_SUMMARY.md capture the full history
// of development, debugging, and UI polish for the TopstepX floating panel.
//
// IMPORTANT FOR FUTURE WORK (by me or any other AI):
//   1. Read SESSION_SUMMARY.md (same directory) first — it contains
//      architecture notes, what was fixed, current status, build/deploy
//      instructions, and tips.
//   2. The entire application is deliberately in this single .swift file.
//   3. "一切正常" (everything working) as of the end of the last session.
//   4. Key recent areas: realtime fidelity, cross-symbol isolation,
//      custom toasts + sounds (TP.caf / Order.caf), hover/press feedback
//      on all clickable elements (PillButton, QuoteButton, inputs).
//   5. Always preserve 100% real TopstepX API behavior (no mocks in live paths).
//
// File last meaningfully updated: June 2026 (hover feedback final polish)
// ============================================================================

struct Contract {
    let price: Double
    let tick: Double
    let tickValue: Double
    let id: String
}

struct APIConfig: Decodable {
    let baseURL: String
    let userName: String
    let apiKey: String
    let readOnly: Bool
    let leadAccountId: Int?
    let followerAccountIds: [Int]?
    let practiceAccountIds: [Int]?
    let manualRisk: ManualRisk?
    let accountSize: String?
    let localDailyMaxLoss: Double?
    let localDailyProfitTarget: Double?
    let sendBrackets: Bool?
}

struct ManualRisk: Decodable {
    let mll: Double?
    let dllUsed: Double?
    let dllLimit: Double?
    let pdptUsed: Double?
    let pdptLimit: Double?
    let source: String?
}

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

final class ProjectXClient {
    let config: APIConfig
    var token: String?
    var tokenIssuedAt: Date?

    init(config: APIConfig) {
        self.config = config
    }

    static func loadConfig() -> APIConfig? {
        let bundledConfig = Bundle.main.resourceURL?.appendingPathComponent("topstepx_config.json")
        let appSupportFromHome = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("TopstepXFloatPanel")
            .appendingPathComponent("topstepx_config.json")
        let appSupportFromFileManager = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("TopstepXFloatPanel")
            .appendingPathComponent("topstepx_config.json")
        for url in [bundledConfig, appSupportFromHome, appSupportFromFileManager].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url),
               let config = try? JSONDecoder().decode(APIConfig.self, from: data),
               !config.userName.contains("YOUR_"),
               !config.apiKey.contains("YOUR_") {
                return config
            }
        }
        return nil
    }

    func refresh(symbol: String, accountId: Int?, completion: @escaping (Result<ReadOnlySnapshot, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.fetchSnapshot(symbol: symbol, selectedAccountId: accountId, completion: completion)
            }
        }
    }

    func ensureToken(completion: @escaping (Result<String, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                if let token = self.token {
                    completion(.success(token))
                } else {
                    completion(.failure(ProjectXError.api("token missing")))
                }
            }
        }
    }

    private func login(completion: @escaping (Result<Void, Error>) -> Void) {
        if token != nil {
            completion(.success(()))
            return
        }
        post(path: "/api/Auth/loginKey", body: ["userName": config.userName, "apiKey": config.apiKey], authenticated: false) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let json):
                guard let success = json["success"] as? Bool, success,
                      let token = json["token"] as? String else {
                    completion(.failure(ProjectXError.api(json["errorMessage"] as? String ?? "loginKey failed")))
                    return
                }
                self.token = token
                self.tokenIssuedAt = Date()
                completion(.success(()))
            }
        }
    }

    func validateToken(completion: @escaping (Result<String, Error>) -> Void) {
        login { [weak self] loginResult in
            guard let self else { return }
            switch loginResult {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.post(path: "/api/Auth/validate", body: [:], authenticated: true) { result in
                    switch result {
                    case .failure(let error):
                        self.token = nil
                        completion(.failure(error))
                    case .success(let json):
                        guard let success = json["success"] as? Bool, success else {
                            self.token = nil
                            completion(.failure(ProjectXError.api(json["errorMessage"] as? String ?? "validate failed")))
                            return
                        }
                        if let newToken = json["newToken"] as? String, !newToken.isEmpty {
                            self.token = newToken
                            self.tokenIssuedAt = Date()
                            completion(.success("Token Refreshed"))
                        } else {
                            completion(.success("Token Valid"))
                        }
                    }
                }
            }
        }
    }

    func placeOrder(payload: [String: Any], completion: @escaping (Result<Int, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.post(path: "/api/Order/place", body: payload, authenticated: true) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let json):
                        guard self.apiSuccess(json) else {
                            completion(.failure(ProjectXError.api(self.apiErrorMessage(json, fallback: "order place failed"))))
                            return
                        }
                        let orderId = json["orderId"] as? Int ?? (json["orderId"] as? NSNumber)?.intValue ?? 0
                        completion(.success(orderId))
                    }
                }
            }
        }
    }

    func cancelOrder(accountId: Int, orderId: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.post(path: "/api/Order/cancel", body: ["accountId": accountId, "orderId": orderId], authenticated: true) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let json):
                        guard self.apiSuccess(json) else {
                            completion(.failure(ProjectXError.api(self.apiErrorMessage(json, fallback: "order cancel failed"))))
                            return
                        }
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func modifyOrder(payload: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.post(path: "/api/Order/modify", body: payload, authenticated: true) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let json):
                        guard self.apiSuccess(json) else {
                            completion(.failure(ProjectXError.api(self.apiErrorMessage(json, fallback: "order modify failed"))))
                            return
                        }
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func closeContract(accountId: Int, contractId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        login { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                self.post(path: "/api/Position/closeContract", body: ["accountId": accountId, "contractId": contractId], authenticated: true) { result in
                    switch result {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let json):
                        guard self.apiSuccess(json) else {
                            completion(.failure(ProjectXError.api(self.apiErrorMessage(json, fallback: "position close failed"))))
                            return
                        }
                        completion(.success(()))
                    }
                }
            }
        }
    }

    private func apiSuccess(_ json: [String: Any]) -> Bool {
        return json["success"] as? Bool ?? false
    }

    private func apiErrorMessage(_ json: [String: Any], fallback: String) -> String {
        return json["errorMessage"] as? String ?? fallback
    }

    private func fetchSnapshot(symbol: String, selectedAccountId: Int?, completion: @escaping (Result<ReadOnlySnapshot, Error>) -> Void) {
        post(path: "/api/Account/search", body: ["onlyActiveAccounts": true], authenticated: true) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let accountJson):
                let rawAccounts = accountJson["accounts"] as? [[String: Any]] ?? []
                let accounts = rawAccounts.compactMap(self.parseAccount).sorted {
                    self.sortRank($0.id) < self.sortRank($1.id)
                }
                let account = self.pickAccount(rawAccounts, selectedAccountId: selectedAccountId, sortedAccounts: accounts)
                let accountId = self.intValue(account?["id"])
                let name = account?["name"] as? String ?? "No account"
                let balance = account?["balance"] as? Double ?? (account?["balance"] as? NSNumber)?.doubleValue
                let canTrade = account?["canTrade"] as? Bool
                let realizedDayPnl = self.numberValue(account?["realizedDayPnl"])
                let unrealizedPnl = self.numberValue(account?["unrealizedPnl"])
                let keys = account.map { Array($0.keys).sorted() } ?? []
                guard let accountId else {
                    completion(.success(ReadOnlySnapshot(accountId: nil, accountName: name, balance: balance, canTrade: canTrade, realizedDayPnl: realizedDayPnl, unrealizedPnl: unrealizedPnl, openOrderCount: 0, openPositionCount: 0, tradeCount: 0, contractId: nil, rawAccountKeys: keys, accounts: accounts, openOrders: [], openPositions: [], trades: [])))
                    return
                }
                self.fetchDetails(accountId: accountId, symbol: symbol) { details in
                    completion(.success(ReadOnlySnapshot(
                        accountId: accountId,
                        accountName: name,
                        balance: balance,
                        canTrade: canTrade,
                        realizedDayPnl: realizedDayPnl,
                        unrealizedPnl: unrealizedPnl,
                        openOrderCount: details.orders,
                        openPositionCount: details.positions,
                        tradeCount: details.trades,
                        contractId: details.contractId,
                        rawAccountKeys: keys,
                        accounts: accounts,
                        openOrders: details.openOrders,
                        openPositions: details.openPositions,
                        trades: details.tradesList
                    )))
                }
            }
        }
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func parseAccount(_ account: [String: Any]) -> AccountInfo? {
        guard let id = intValue(account["id"]),
              let name = account["name"] as? String else { return nil }
        let balance = account["balance"] as? Double ?? (account["balance"] as? NSNumber)?.doubleValue
        return AccountInfo(
            id: id,
            name: name,
            balance: balance,
            canTrade: account["canTrade"] as? Bool,
            simulated: account["simulated"] as? Bool,
            isVisible: account["isVisible"] as? Bool
        )
    }

    private func sortRank(_ accountId: Int) -> Int {
        if config.leadAccountId == accountId { return 0 }
        if config.followerAccountIds?.contains(accountId) == true { return 1 }
        if config.practiceAccountIds?.contains(accountId) == true { return 3 }
        return 2
    }

    private func pickAccount(_ accounts: [[String: Any]], selectedAccountId: Int?, sortedAccounts: [AccountInfo]) -> [String: Any]? {
        if let selectedAccountId {
            return accounts.first { self.intValue($0["id"]) == selectedAccountId } ?? accounts.first
        }
        if let lead = config.leadAccountId {
            if let account = accounts.first(where: { self.intValue($0["id"]) == lead }) {
                return account
            }
        }
        if let firstSorted = sortedAccounts.first {
            return accounts.first { self.intValue($0["id"]) == firstSorted.id }
        }
        return accounts.first
    }

    /// Returns ISO8601 (Z) timestamp for the start of the current TopstepX trading day.
    /// The official platform resets realized day P&L at 18:00 America/New_York (ET / UTC-4 during daylight).
    /// Using a naive rolling 24h for /Trade/search caused RP&L to include pre-reset "yesterday" trades
    /// (and never cleanly reset at 18:00). We now align the window so the fallback sum (and tradeCount)
    /// reflects only the current session.
    private func dailyTradeStartISO() -> String {
        let etTZ = TimeZone(identifier: "America/New_York") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = etTZ
        let now = Date()
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        let currentHour = comps.hour ?? 0
        if currentHour >= 18 {
            comps.hour = 18
            comps.minute = 0
            comps.second = 0
        } else {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
                comps = calendar.dateComponents([.year, .month, .day], from: yesterday)
                comps.hour = 18
                comps.minute = 0
                comps.second = 0
            }
        }
        if let etDate = calendar.date(from: comps) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: etDate)
        }
        // Fallback (should not reach)
        return ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 60 * 60))
    }

    private func fetchDetails(accountId: Int, symbol: String, completion: @escaping ((orders: Int, positions: Int, trades: Int, contractId: String?, openOrders: [[String: Any]], openPositions: [[String: Any]], tradesList: [[String: Any]])) -> Void) {
        let group = DispatchGroup()
        var orders = 0
        var positions = 0
        var trades = 0
        var contractId: String?
        var openOrders: [[String: Any]] = []
        var openPositions: [[String: Any]] = []
        var tradesList: [[String: Any]] = []

        group.enter()
        post(path: "/api/Order/searchOpen", body: ["accountId": accountId], authenticated: true) { result in
            if case .success(let json) = result {
                openOrders = json["orders"] as? [[String: Any]] ?? []
                orders = openOrders.count
            }
            group.leave()
        }

        group.enter()
        post(path: "/api/Position/searchOpen", body: ["accountId": accountId], authenticated: true) { result in
            if case .success(let json) = result {
                openPositions = json["positions"] as? [[String: Any]] ?? []
                positions = openPositions.count
            }
            group.leave()
        }

        group.enter()
        // Use trading-day aligned window (18:00 ET reset) instead of naive -24h so RP&L
        // (and trade count) correctly exclude pre-reset trades from "yesterday".
        let start = dailyTradeStartISO()
        let end = ISO8601DateFormatter().string(from: Date())
        post(path: "/api/Trade/search", body: ["accountId": accountId, "startTimestamp": start, "endTimestamp": end], authenticated: true) { result in
            if case .success(let json) = result {
                tradesList = json["trades"] as? [[String: Any]] ?? []
                trades = tradesList.count
            }
            group.leave()
        }

        group.enter()
        post(path: "/api/Contract/search", body: ["searchText": symbol, "live": false], authenticated: true) { result in
            if case .success(let json) = result,
               let contracts = json["contracts"] as? [[String: Any]] {
                contractId = contracts.first?["id"] as? String
            }
            group.leave()
        }

        group.notify(queue: .main) {
            completion((orders, positions, trades, contractId, openOrders, openPositions, tradesList))
        }
    }

    private func post(path: String, body: [String: Any], authenticated: Bool, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let url = URL(string: config.baseURL + path) else {
            completion(.failure(ProjectXError.api("bad URL \(path)")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain", forHTTPHeaderField: "accept")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                DispatchQueue.main.async { completion(.failure(ProjectXError.api("empty response"))) }
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                DispatchQueue.main.async { completion(.failure(ProjectXError.api(message))) }
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                DispatchQueue.main.async { completion(.success(json)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}

enum ProjectXError: Error, LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        }
    }
}

final class SignalRRealtimeClient {
    private let separator = "\u{1e}"
    private var task: URLSessionWebSocketTask?
    private var accountId: Int?
    private var contractId: String?
    private let hub: String
    private var didHandshake = false

    init(hub: String = "user") {
        self.hub = hub
    }

    var onStatus: ((String) -> Void)?
    var onAccount: (([String: Any]) -> Void)?
    var onOrder: (([String: Any]) -> Void)?
    var onPosition: (([String: Any]) -> Void)?
    var onTrade: (([String: Any]) -> Void)?
    var onQuote: ((String, [String: Any]) -> Void)?
    var onEvent: ((String) -> Void)?

    func connect(token: String, accountId: Int) {
        connect(token: token, accountId: accountId, contractId: nil)
    }

    func connect(token: String, contractId: String) {
        connect(token: token, accountId: nil, contractId: contractId)
    }

    private func connect(token: String, accountId: Int?, contractId: String?) {
        disconnect()
        self.accountId = accountId
        self.contractId = contractId
        didHandshake = false

        var components = URLComponents(string: "wss://rtc.topstepx.com/hubs/\(hub)")
        components?.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = components?.url else {
            onStatus?("\(statusName()) URL Error")
            return
        }

        onStatus?("\(statusName()) Connecting")
        let task = URLSession.shared.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak task] in
            guard let self,
                  let task,
                  self.task === task else { return }
            self.send(["protocol": "json", "version": 1])
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self, weak task] in
            guard let self,
                  let task,
                  self.task === task,
                  !self.didHandshake else { return }
            self.onStatus?("\(self.statusName()) Offline")
            self.disconnect()
        }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        didHandshake = false
    }

    private func subscribe() {
        if hub == "user" {
            sendInvocation("SubscribeAccounts", [])
            if let accountId {
                sendInvocation("SubscribeOrders", [accountId])
                sendInvocation("SubscribePositions", [accountId])
                sendInvocation("SubscribeTrades", [accountId])
            }
            onStatus?("Stream Live")
        } else {
            if let contractId {
                sendInvocation("SubscribeContractQuotes", [contractId])
                sendInvocation("SubscribeContractTrades", [contractId])
            }
            onStatus?("Market Live")
        }
    }

    private func sendInvocation(_ target: String, _ arguments: [Any]) {
        send(["type": 1, "target": target, "arguments": arguments])
    }

    private func send(_ object: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text + separator)) { [weak self] error in
            if error != nil {
                self?.onStatus?("\(self?.statusName() ?? "Stream") Offline")
            }
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.onStatus?("\(self.statusName()) Offline")
                // health timer (every 8s in controller) will detect Offline and force reconnect via start*IfNeeded

            case .success(let message):
                switch message {
                case .string(let text):
                    self.handle(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handle(text)
                    }
                @unknown default:
                    break
                }
                self.receiveLoop()
            }
        }
    }

    private func statusName() -> String {
        return hub == "market" ? "Market" : "Stream"
    }

    private func handle(_ text: String) {
        for raw in text.components(separatedBy: separator) where !raw.isEmpty {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "{}" {
                didHandshake = true
                subscribe()
                continue
            }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if json.isEmpty {
                didHandshake = true
                subscribe()
                continue
            }
            if let error = json["error"] as? String, !error.isEmpty {
                onStatus?("\(statusName()) Offline")
                continue
            }
            if (json["type"] as? Int) == 6 {
                continue
            }
            if (json["type"] as? Int) == 7 {
                onStatus?("\(statusName()) Offline")
                continue
            }
            guard (json["type"] as? Int) == 1,
                  let target = json["target"] as? String else { continue }
            onEvent?(target)
            if target == "GatewayUserAccount" {
                firstPayloads(json).forEach { onAccount?($0) }
            } else if target == "GatewayUserOrder" {
                firstPayloads(json).forEach { onOrder?($0) }
            } else if target == "GatewayUserPosition" {
                firstPayloads(json).forEach { onPosition?($0) }
            } else if target == "GatewayUserTrade" {
                firstPayloads(json).forEach { onTrade?($0) }
            } else if target == "GatewayQuote" {
                guard let payload = firstPayloads(json).first else { continue }
                let contract = (json["arguments"] as? [Any])?.first as? String ?? contractId ?? ""
                onQuote?(contract, payload)
            }
        }
    }

    private func firstPayloads(_ json: [String: Any]) -> [[String: Any]] {
        guard let args = json["arguments"] as? [Any] else { return [] }
        var payloads: [[String: Any]] = []
        for arg in args {
            if let payload = arg as? [String: Any] {
                payloads.append(payload)
            }
            if let list = arg as? [[String: Any]] {
                payloads.append(contentsOf: list)
            }
        }
        return payloads
    }
}

// Supported symbols for the selector. This list is curated (not dynamically fetched from a "list all" endpoint)
// because we need local knowledge of tick size / tick value for correct price stepping, bracket calcs,
// mark-to-market PnL, etc. Once selected, the *specific* contract ID (e.g. front month) *is* resolved
// live from /api/Contract/search, and all quotes/positions come 100% from official TopstepX REST + rtc WS.
let contracts: [String: Contract] = [
    "NQ": Contract(price: 18452.25, tick: 0.25, tickValue: 5.00, id: "CON.F.US.ENQ.U25"),
    "MNQ": Contract(price: 18452.25, tick: 0.25, tickValue: 0.50, id: "CON.F.US.MNQ.U25"),
    "ES": Contract(price: 5928.25, tick: 0.25, tickValue: 12.50, id: "CON.F.US.EP.U25"),
    "MES": Contract(price: 5928.25, tick: 0.25, tickValue: 1.25, id: "CON.F.US.MES.U25"),
    "GC": Contract(price: 3372.8, tick: 0.1, tickValue: 10.00, id: "CON.F.US.GC.Q25"),
    "MGC": Contract(price: 3372.8, tick: 0.1, tickValue: 1.00, id: "CON.F.US.MGC.Q25")
]

private let supportedSymbols: [String] = ["NQ", "ES", "MNQ", "MES", "GC", "MGC"]  // curated order, not from API list-all

struct Palette {
    let bg: NSColor
    let surface: NSColor
    let surface2: NSColor
    let border: NSColor
    let text: NSColor
    let muted: NSColor
    let green: NSColor
    let red: NSColor
    let orange: NSColor
    let blue: NSColor
}

let darkPalette = Palette(
    bg: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.09, alpha: 1),
    surface: NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.13, alpha: 1),
    surface2: NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.17, alpha: 1),
    border: NSColor(calibratedRed: 0.19, green: 0.23, blue: 0.29, alpha: 1),
    text: NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.97, alpha: 1),
    muted: NSColor(calibratedRed: 0.54, green: 0.58, blue: 0.64, alpha: 1),
    green: NSColor(calibratedRed: 0.13, green: 0.77, blue: 0.37, alpha: 1),
    red: NSColor(calibratedRed: 0.94, green: 0.27, blue: 0.27, alpha: 1),
    orange: NSColor(calibratedRed: 0.96, green: 0.58, blue: 0.04, alpha: 1),
    blue: NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
)

let lightPalette = Palette(
    bg: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.97, alpha: 1),
    surface: NSColor(calibratedRed: 0.97, green: 0.985, blue: 1.00, alpha: 1),
    surface2: NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.96, alpha: 1),
    border: NSColor(calibratedRed: 0.70, green: 0.77, blue: 0.84, alpha: 1),
    text: NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.13, alpha: 1),
    muted: NSColor(calibratedRed: 0.39, green: 0.47, blue: 0.58, alpha: 1),
    green: NSColor(calibratedRed: 0.02, green: 0.58, blue: 0.28, alpha: 1),
    red: NSColor(calibratedRed: 0.86, green: 0.12, blue: 0.12, alpha: 1),
    orange: NSColor(calibratedRed: 0.86, green: 0.43, blue: 0.02, alpha: 1),
    blue: NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.68, alpha: 1)
)

func money(_ value: Double) -> String {
    let sign = value >= 0 ? "" : "-"
    return "\(sign)$\(String(format: "%.2f", abs(value)))"
}

func number2(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}

extension NSView {
    func fixedHeight(_ value: CGFloat) {
        heightAnchor.constraint(equalToConstant: value).isActive = true
    }

    func fixedWidth(_ value: CGFloat) {
        widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

final class FillBar: NSView {
    var palette = darkPalette {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let track = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        palette.surface2.setFill()
        track.fill()

        let fill = NSRect(x: 0, y: 0, width: bounds.width * 0.7438, height: bounds.height)
        let gradient = NSGradient(colors: [palette.green, NSColor.systemYellow, palette.red])
        gradient?.draw(in: NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3), angle: 0)

        let markerX = bounds.width * 0.75
        let marker = NSBezierPath()
        marker.move(to: NSPoint(x: markerX - 5, y: bounds.height + 6))
        marker.line(to: NSPoint(x: markerX + 5, y: bounds.height + 6))
        marker.line(to: NSPoint(x: markerX, y: bounds.height))
        marker.close()
        palette.text.setFill()
        marker.fill()
    }
}

final class PillButton: NSButton {
    var bgColor = NSColor.clear
    var fgColor = NSColor.white

    private var trackingArea: NSTrackingArea?
    private var hovered = false
    private var pressed = false
    private var baseBorderWidth: CGFloat = 0
    private var baseBorderColor: CGColor?
    private var hoverable = true

    convenience init(_ title: String, bg: NSColor, fg: NSColor, size: CGFloat = 12, hoverable: Bool = true) {
        self.init(frame: .zero)
        self.title = title
        self.bgColor = bg
        self.fgColor = fg
        self.font = NSFont.systemFont(ofSize: size, weight: .bold)
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.layer?.backgroundColor = bg.cgColor
        self.contentTintColor = fg
        self.setButtonType(.momentaryPushIn)
        self.hoverable = hoverable
        if hoverable {
            setupTracking()
        }
        updateAppearance(animated: false)
        captureBaseBorder()
    }

    private func setupTracking() {
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverable {
            setupTracking()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled && hoverable {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if hoverable && isEnabled {
            hovered = true
            updateAppearance(animated: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovered = false
        pressed = false
        updateAppearance(animated: false)  // snap restore immediately to avoid lingering highlight
    }

    override func mouseDown(with event: NSEvent) {
        if hoverable && isEnabled {
            pressed = true
            updateAppearance(animated: false)
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if hoverable && isEnabled {
            pressed = false
            updateAppearance(animated: true)
        }
        super.mouseUp(with: event)
    }

    private func updateAppearance(animated: Bool) {
        guard let layer = self.layer else { return }

        // Always clear any pending hover animations first to prevent lingering effects (especially slow fade on exit)
        layer.removeAllAnimations()

        var targetBg = bgColor
        var targetTint = fgColor

        let lowAlpha = bgColor.alphaComponent < 0.15

        if !isEnabled {
            targetBg = bgColor.withAlphaComponent(0.32)
            targetTint = fgColor.withAlphaComponent(0.42)
        } else if pressed {
            targetBg = bgColor.blended(withFraction: 0.38, of: NSColor.black) ?? bgColor
            targetTint = fgColor.withAlphaComponent(0.82)
        } else if hovered {
            if lowAlpha {
                targetBg = bgColor
                targetTint = fgColor.withAlphaComponent(0.85)
            } else {
                targetBg = bgColor.blended(withFraction: 0.22, of: NSColor.white) ?? bgColor
                targetTint = fgColor
            }
        }

        let duration: TimeInterval = pressed ? 0.035 : 0.085

        if animated {
            let bgAnim = CABasicAnimation(keyPath: "backgroundColor")
            bgAnim.fromValue = layer.backgroundColor
            bgAnim.toValue = targetBg.cgColor
            bgAnim.duration = duration
            bgAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(bgAnim, forKey: "bgHover")

            let s: CGFloat = pressed ? 0.965 : 1.0
            let t = CATransform3DMakeScale(s, s, 1.0)
            let scaleAnim = CABasicAnimation(keyPath: "transform")
            scaleAnim.fromValue = layer.transform
            scaleAnim.toValue = t
            scaleAnim.duration = duration
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(scaleAnim, forKey: "scaleHover")

            layer.backgroundColor = targetBg.cgColor
            layer.transform = t
        } else {
            // Force immediate, no animation at all on exit (especially important for low-alpha buttons)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = targetBg.cgColor
            layer.transform = CATransform3DMakeScale(1.0, 1.0, 1.0)
            CATransaction.commit()
        }

        // Tint change also forced immediate when not animating
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.contentTintColor = targetTint
            CATransaction.commit()
        } else {
            self.contentTintColor = targetTint
        }

        if hovered && !lowAlpha {
            layer.borderWidth = 1
            layer.borderColor = fgColor.withAlphaComponent(0.3).cgColor
        } else if !hovered {
            layer.borderWidth = baseBorderWidth
            layer.borderColor = baseBorderColor
        }
    }

    func captureBaseBorder() {
        if let l = layer {
            baseBorderWidth = l.borderWidth
            baseBorderColor = l.borderColor
        }
    }
}

final class SpreadBadge: NSTextField {
    private final class CenteredTextCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var drawingRect = super.drawingRect(forBounds: rect)
            let textSize = cellSize(forBounds: rect)
            drawingRect.origin.y += max(0, (rect.height - textSize.height) / 2) - 1
            drawingRect.size.height = textSize.height
            return drawingRect
        }
    }

    init(_ value: String, bg: NSColor, fg: NSColor, border: NSColor) {
        super.init(frame: .zero)
        cell = CenteredTextCell(textCell: value)
        stringValue = value
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)
        textColor = fg
        lineBreakMode = .byClipping
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = bg.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = border.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class QuoteButton: NSButton {
    private let sideLabel = NSTextField(labelWithString: "")
    private let priceLabel = NSTextField(labelWithString: "")
    private var quoteSide = "BUY"
    private var quoteColor = NSColor.white
    private let horizontalInset: CGFloat = 12

    private var baseBgColor = NSColor.clear
    private var trackingArea: NSTrackingArea?
    private var hovered = false
    private var pressed = false

    convenience init(side: String, price: String, bg: NSColor, fg: NSColor) {
        self.init(frame: .zero)
        title = ""
        quoteSide = side
        quoteColor = fg
        isBordered = false
        imagePosition = .noImage
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = bg.cgColor
        baseBgColor = bg
        setButtonType(.momentaryPushIn)
        setupLabels()
        setupTracking()
        updateAppearance(animated: false)
        update(side: side, price: price, color: fg)
    }

    private func setupLabels() {
        [sideLabel, priceLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.isSelectable = false
            $0.lineBreakMode = .byTruncatingTail
            addSubview($0)
        }
        sideLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        priceLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        NSLayoutConstraint.activate([
            sideLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            priceLabel.topAnchor.constraint(equalTo: sideLabel.bottomAnchor, constant: 2),
            priceLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
    }

    func update(side: String, price: String, color: NSColor) {
        quoteSide = side
        quoteColor = color
        sideLabel.stringValue = side
        priceLabel.stringValue = price
        sideLabel.textColor = color
        priceLabel.textColor = color
        sideLabel.alignment = side == "BUY" ? .right : .left
        priceLabel.alignment = side == "BUY" ? .right : .left
        removeQuoteAlignmentConstraints()
        if side == "BUY" {
            sideLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset).isActive = true
            sideLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset).isActive = true
            priceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset).isActive = true
            priceLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: horizontalInset).isActive = true
        } else {
            sideLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset).isActive = true
            sideLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset).isActive = true
            priceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset).isActive = true
            priceLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -horizontalInset).isActive = true
        }
    }

    private func removeQuoteAlignmentConstraints() {
        for constraint in constraints {
            let first = constraint.firstItem as AnyObject?
            let second = constraint.secondItem as AnyObject?
            let isHorizontal = constraint.firstAttribute == .leading || constraint.firstAttribute == .trailing
                || constraint.secondAttribute == .leading || constraint.secondAttribute == .trailing
            if isHorizontal && (first === sideLabel || second === sideLabel || first === priceLabel || second === priceLabel) {
                constraint.isActive = false
            }
        }
    }

    private func setupTracking() {
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        setupTracking()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if isEnabled {
            hovered = true
            updateAppearance(animated: true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovered = false
        pressed = false
        updateAppearance(animated: false)
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled {
            pressed = true
            updateAppearance(animated: false)
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isEnabled {
            pressed = false
            updateAppearance(animated: true)
        }
        super.mouseUp(with: event)
    }

    private func updateAppearance(animated: Bool) {
        guard let layer = self.layer else { return }

        var target = baseBgColor

        if !isEnabled {
            target = baseBgColor.withAlphaComponent(0.38)
        } else if pressed {
            target = baseBgColor.blended(withFraction: 0.35, of: NSColor.black) ?? baseBgColor
        } else if hovered {
            // strong hover lift so the big quote buttons feel very alive
            target = baseBgColor.blended(withFraction: 0.22, of: NSColor.white) ?? baseBgColor
        }

        let duration: TimeInterval = pressed ? 0.03 : 0.09

        if animated {
            let bgAnim = CABasicAnimation(keyPath: "backgroundColor")
            bgAnim.fromValue = layer.backgroundColor
            bgAnim.toValue = target.cgColor
            bgAnim.duration = duration
            bgAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(bgAnim, forKey: "bgHover")

            let s: CGFloat = pressed ? 0.97 : 1.0
            let t = CATransform3DMakeScale(s, s, 1.0)
            let scaleAnim = CABasicAnimation(keyPath: "transform")
            scaleAnim.fromValue = layer.transform
            scaleAnim.toValue = t
            scaleAnim.duration = duration
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(scaleAnim, forKey: "scaleHover")

            layer.backgroundColor = target.cgColor
            layer.transform = t
        } else {
            layer.backgroundColor = target.cgColor
            let s: CGFloat = pressed ? 0.97 : 1.0
            layer.transform = CATransform3DMakeScale(s, s, 1.0)
        }
    }
}

final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        drawingRect.origin.y = rect.origin.y + max(0, (rect.height - textSize.height) / 2) - 1
        return drawingRect
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

func extractNumber(_ text: String) -> Double? {
    let normalized = text
        .replacingOccurrences(of: "−", with: "-")
        .replacingOccurrences(of: "–", with: "-")
    let pattern = "-?(?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d+)?"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
    let matches = regex.matches(in: normalized, range: range)
    guard let match = matches.last,
          let swiftRange = Range(match.range, in: normalized) else { return nil }
    let cleaned = normalized[swiftRange].replacingOccurrences(of: ",", with: "")
    return Double(cleaned)
}

final class PriceInputTextField: NSTextField {
    var onBegin: ((NSTextField) -> Void)?
    var onCommit: ((NSTextField) -> Void)?
    private var pendingPasteCommit = false

    @objc func paste(_ sender: Any?) {
        guard let raw = NSPasteboard.general.string(forType: .string),
              let value = extractNumber(raw) else {
            currentEditor()?.paste(sender)
            return
        }
        let pasted = String(format: "%.2f", value)
        if let editor = currentEditor() {
            editor.replaceCharacters(in: editor.selectedRange, with: pasted)
            stringValue = editor.string
        } else {
            stringValue = pasted
        }
        pendingPasteCommit = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(nil)
            if self.pendingPasteCommit {
                self.pendingPasteCommit = false
                self.onCommit?(self)
            }
        }
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        onBegin?(self)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        pendingPasteCommit = false
        onCommit?(self)
    }
}

final class PanelController: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var window: NSWindow!
    var root = NSStackView()
    var palette = darkPalette
    var isDark = true
    var isRebuilding = false
    var activeTicketInput: String?
    weak var activeTicketField: NSTextField?
    var pendingTicketInputRebuild = false
    var mouseDownMonitor: Any?

    var symbolButton: NSButton!
    var symbolMenuWidthConstraint: NSLayoutConstraint?
    var priceLabel: NSTextField!
    var headerQuoteStatusLabel: NSTextField?
    var contractLabel: NSTextField!
    var pnlLabel: NSTextField!
    var positionLabel: NSTextField!
    var eventLabel: NSTextField!
    var bidAskLabel: NSTextField!
    var footerLastLabel: NSTextField?
    var footerSnapshotLabel: NSTextField?
    var footerApiDotLabel: NSTextField?
    var footerApiNameLabel: NSTextField?
    var footerStreamDotLabel: NSTextField?
    var footerStreamNameLabel: NSTextField?
    var footerMarketDotLabel: NSTextField?
    var footerMarketNameLabel: NSTextField?
    var sellQuoteButton: QuoteButton?
    var buyQuoteButton: QuoteButton?
    var spreadButton: SpreadBadge?
    var price = contracts["NQ"]!.price
    var bestBidPrice: Double?
    var bestAskPrice: Double?
    var lastQuoteAt: Date?
    var quoteSyncing = false
    var avgPrice = contracts["NQ"]!.price - 10.5
    var apiClient: ProjectXClient?
    var realtimeClient = SignalRRealtimeClient(hub: "user")
    var marketClient = SignalRRealtimeClient(hub: "market")
    var realtimeAccountId: Int?
    var realtimeContractId: String?
    var lastSnapshot: ReadOnlySnapshot?
    var apiStatusText = "API Config missing"
    var dataStatusText = "Initializing"
    var lastSyncText = "Last --:--:--"
    var snapshotStatusText = "Snapshot 30s"
    var streamStatusText = "Stream Offline"
    var marketStatusText = "Market Offline"
    var accountName = "TopstepX - not connected"
    var canTradeText = "READ ONLY"
    var openOrdersTitle = "OPEN ORDERS"
    var positionPrefix = "SYNC"
    var selectedSymbol = "NQ"
    var balanceText = "--"
    var hideBalance = false
    var hideRealizedPnl = false
    var hideAccount = false
    var orderSide = "BUY"
    var orderType = "MARKET"
    var orderQty = 1
    let maxOrderQty = 999
    var limitPriceOverride: Double?
    var editingOrderId: Int?
    var editingOrderType: Int?
    var editingOrderSide: String?
    var tpEnabled = false
    var slEnabled = false
    var tpTicks = 40
    var slTicks = 20
    var tpPriceOverride: Double?
    var slPriceOverride: Double?
    var bracketMode = "PRICE"
    var activeAccounts: [AccountInfo] = []
    var selectedAccountId: Int?
    var officialRealizedDayPnl: Double?
    var officialUnrealizedPnl: Double?
    var realtimeOpenOrderCount: Int?
    var realtimeOpenPositionCount: Int?
    var realtimeTradeCount: Int?
    var realtimeOrders: [Int: [String: Any]] = [:]
    var realtimePositions: [Int: [String: Any]] = [:]
    var protectionOrderGroups: [Int: String] = [:]
    var protectionGroupOrders: [String: Set<Int>] = [:]
    var protectionCancelIssuedGroups: Set<String> = []
    private var tpSound: NSSound?
    private var orderSound: NSSound?
    private var lastProtectionFillWasTP = false
    private var lastKnownPositionSide: String = "FLAT"
    private var lastNonFlatPositionSide: String = "FLAT"
    private var lastNonFlatPositionAt: Date = .distantPast
    private var submittedEntryOrderIds: Set<Int> = []
    private var protectionOrderType: [Int: Int] = [:]  // id -> 1 TP, 4 SL etc for sound decision on fills
    private var protectionOrderKind: [Int: String] = [:]  // id -> TP or SL from local submit intent
    private var lastProtectionFillSound: (id: Int, time: Date)?
    private var customSoundsLoadErrorReported = false
    var hasRealtimeOrderState = false
    var accountRoleText = "LEAD UNSET"
    var dllText = "Pending"
    var mllText = "Manual"
    var pdptText = "Pending"
    var riskLineText = "MLL / DLL / PDPT manual config"
    var tokenStatusText = "Token Pending"
    var tradeRequestInFlight = false
    var wsHealthTimer: Timer?
    var rebuildCoalesceTimer: Timer?
    var needsRebuild = false
    var reconnectBackoff: TimeInterval = 1.0
    var lastReconnectAttempt: Date?
    var toastStack: [NSView] = []
    var recentOrderToastKeys: [String: Date] = [:]
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        window = NSWindow(
            contentRect: NSRect(x: 1080, y: 210, width: 284, height: 418),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "TSX Deck"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 270, height: 398)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if let icon = NSImage(named: "topstepx_icon") {
            NSApp.applicationIconImage = icon
        }

        let content = NSView()
        content.wantsLayer = true
        window.contentView = content

        root.orientation = .vertical
        root.spacing = 3
        root.alignment = .width
        root.distribution = .fill
        root.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        ])

        apiClient = ProjectXClient.loadConfig().map(ProjectXClient.init(config:))
        if apiClient == nil {
            apiStatusText = "API Config missing"
            dataStatusText = "No API Config"
        }
        installTicketCommitMonitor()
        rebuild()
        refreshReadOnly()
        validateAPIToken()
        Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.tick()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshReadOnly()
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshActiveTradeStateIfNeeded()
        }
        Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
            self?.validateAPIToken()
        }
        wsHealthTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.checkAndReconnectStreams()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Preload custom sounds (TP.caf / Order.caf) so missing-file message appears early if needed.
        _ = ensureSound("TP")
        _ = ensureSound("Order")

        setupStatusItem()
    }

    func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit TSX Deck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func setupStatusItem() {
        // Status item in the top menu bar (right side) for quick access to Quit.
        // This provides a reliable way to exit even with the floating panel style.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            if let icon = NSImage(named: "topstepx_icon") {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
        }

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit TSX Deck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    func installTicketCommitMonitor() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.commitActiveTicketInputIfNeeded(for: event)
            return event
        }
    }

    func commitActiveTicketInputIfNeeded(for event: NSEvent) {
        guard let field = activeTicketField,
              let id = activeTicketInput else { return }
        if event.window === field.window {
            let point = field.convert(event.locationInWindow, from: nil)
            if field.bounds.contains(point) {
                return
            }
        }
        activeTicketInput = nil
        activeTicketField = nil
        commitTicketInput(field, id: id)
    }

    func rebuild(disableAnimations: Bool = false, force: Bool = false) {
        if isRebuilding { return }
        if !force && isTicketInputActivelyEditing() {
            pendingTicketInputRebuild = true
            updateFooterStatus()
            return
        }
        pendingTicketInputRebuild = false
        isRebuilding = true
        defer { isRebuilding = false }
        palette = isDark ? darkPalette : lightPalette
        window.backgroundColor = palette.bg
        window.contentView?.layer?.backgroundColor = palette.bg.cgColor

        let rebuildViews = {
            while let view = self.root.arrangedSubviews.first {
                self.root.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            [self.header(), self.accountCard(), self.positionCard(), self.ticketCard(), self.openOrdersCard(), self.footer()].forEach { view in
                self.root.addArrangedSubview(view)
                view.setContentHuggingPriority(.defaultLow, for: .horizontal)
                view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                view.widthAnchor.constraint(equalTo: self.root.widthAnchor, constant: -10).isActive = true
            }
        }

        if disableAnimations {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0
                ctx.allowsImplicitAnimation = false
                rebuildViews()
                root.layoutSubtreeIfNeeded()
            }
            CATransaction.commit()
        } else {
            rebuildViews()
        }
        updateSymbol(resetPrice: false)
        updateFooterStatus()
        DispatchQueue.main.async { [weak self] in
            self?.fitWindowToContent()
        }
    }

    func fitWindowToContent() {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        let targetHeight = ceil(root.fittingSize.height + 2)
        let clampedHeight = max(360, min(targetHeight, 720))
        let currentHeight = content.bounds.height
        guard abs(currentHeight - clampedHeight) > 2 else { return }

        let frame = window.frame
        let topY = frame.maxY
        window.setContentSize(NSSize(width: 284, height: clampedHeight))
        let resized = window.frame
        window.setFrameOrigin(NSPoint(x: resized.minX, y: topY - resized.height))
    }

    func header() -> NSView {
        let panel = NSView()
        symbolButton = PillButton(symbolButtonTitle(selectedSymbol), bg: palette.surface2, fg: palette.text, size: 12)
        symbolButton.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        symbolButton.alignment = .center
        symbolButton.target = self
        symbolButton.action = #selector(showSymbolMenu(_:))
        symbolButtonWidthStyle()
        symbolMenuWidthConstraint = symbolButton.widthAnchor.constraint(equalToConstant: symbolMenuWidth(selectedSymbol))
        symbolMenuWidthConstraint?.isActive = true
        symbolButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let priceBox = vstack(spacing: 0)
        priceBox.alignment = .centerX
        priceBox.addArrangedSubview(text("TSX LAST", 8, .medium, palette.muted))
        priceLabel = digit("--", 16, .semibold, palette.green)
        priceLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        priceBox.addArrangedSubview(priceLabel)

        let quoteLive = marketStatusText == "Market Live" && !quoteSyncing
        let live = text(quoteLive ? "● LIVE" : "● SYNC", 9, .semibold, quoteLive ? palette.green : palette.orange)
        headerQuoteStatusLabel = live

        let theme = PillButton(isDark ? "☾" : "☀", bg: palette.surface2, fg: isDark ? NSColor.white : NSColor.systemOrange, size: 13)
        theme.fixedWidth(26)
        theme.fixedHeight(24)
        theme.target = self
        theme.action = #selector(toggleTheme)

        [symbolButton, priceBox, live, theme].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview($0)
        }

        NSLayoutConstraint.activate([

            symbolButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            symbolButton.centerYAnchor.constraint(equalTo: panel.centerYAnchor),

            theme.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            theme.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            live.trailingAnchor.constraint(equalTo: theme.leadingAnchor, constant: -8),
            live.centerYAnchor.constraint(equalTo: panel.centerYAnchor),

            priceBox.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            priceBox.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            priceBox.leadingAnchor.constraint(greaterThanOrEqualTo: symbolButton.trailingAnchor, constant: 8),
            priceBox.trailingAnchor.constraint(lessThanOrEqualTo: live.leadingAnchor, constant: -8)
        ])

        let view = card(panel, pad: 6)
        view.fixedHeight(46)
        return view
    }

    func accountCard() -> NSView {
        let box = vstack(spacing: 6)
        let top = hstack(spacing: 5)
        let account = NSPopUpButton()
        var selectedAccountTitle = hideAccount ? anonymizedAccountName(accountName) : accountName
        if activeAccounts.isEmpty {
            account.addItems(withTitles: [selectedAccountTitle])
        } else {
            let titles = activeAccounts.map { hideAccount ? anonymizedAccountName($0.name) : $0.menuTitle }
            account.addItems(withTitles: titles)
            if let selectedAccountId,
               let index = activeAccounts.firstIndex(where: { $0.id == selectedAccountId }) {
                account.selectItem(at: index)
                selectedAccountTitle = titles[index]
            } else {
                selectedAccountTitle = titles.first ?? selectedAccountTitle
            }
        }
        account.target = self
        account.action = #selector(accountChanged(_:))
        stylePopup(account)
        account.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        account.fixedWidth(accountPopupWidth(selectedAccountTitle, font: account.font ?? NSFont.systemFont(ofSize: 10, weight: .semibold)))
        styleAccountPopupMenu(account, titles: titlesForAccountPopup(account), selectedIndex: account.indexOfSelectedItem)
        account.title = selectedAccountTitle
        top.addArrangedSubview(account)
        top.addArrangedSubview(spacer())

        let canTradeColor = canTradeText == "CAN TRADE" ? palette.green : palette.orange
        let tradeStatus = canTradeText == "CAN TRADE" ? "● TRADE" : "● LOCKED"
        let tradeBadge = PillButton(tradeStatus, bg: NSColor.clear, fg: canTradeColor, size: 8, hoverable: false)
        tradeBadge.toolTip = "TopstepX canTrade: \(canTradeText)"
        top.addArrangedSubview(tradeBadge)

        // Account privacy / anonymize toggle (masks last digits of account names for screenshots etc.)
        let anonTitle = hideAccount ? "🙈" : "👁"
        let anonBtn = PillButton(anonTitle, bg: alpha(palette.text, isDark ? 0.08 : 0.05), fg: palette.muted, size: 10, hoverable: false)
        anonBtn.fixedWidth(22)
        anonBtn.fixedHeight(18)
        anonBtn.target = self
        anonBtn.action = #selector(toggleAccountPrivacy)
        anonBtn.toolTip = hideAccount ? "Show full account names" : "Anonymize accounts (mask last digits)"
        top.addArrangedSubview(anonBtn)

        box.addArrangedSubview(top)

        let stats = hstack(spacing: 10)
        let balance = vstack(spacing: 2)
        balance.alignment = .left
        balance.fixedWidth(116)
        let balanceLabel = text("BALANCE", 7, .medium, palette.muted)
        balanceLabel.alignment = .left
        balance.addArrangedSubview(balanceLabel)
        let balanceButton = PillButton(displayBalanceText(), bg: NSColor.clear, fg: palette.text, size: 12, hoverable: false)
        balanceButton.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        balanceButton.alignment = .left
        balanceButton.target = self
        balanceButton.action = #selector(toggleBalancePrivacy)
        balanceButton.fixedHeight(18)
        balanceButton.fixedWidth(112)
        balanceButton.imagePosition = .noImage
        balanceButton.toolTip = hideBalance ? "Show balance" : "Hide balance"
        balance.addArrangedSubview(balanceButton)
        stats.addArrangedSubview(balance)
        stats.addArrangedSubview(spacer())
        let miniStats = hstack(spacing: 12)
        miniStats.addArrangedSubview(compactMetric("POS", "\(effectivePositionCount())"))
        miniStats.addArrangedSubview(compactMetric("ORD", "\(effectiveOrderCount())"))
        stats.addArrangedSubview(miniStats)
        box.addArrangedSubview(stats)

        let status = hstack(spacing: 6)
        status.addArrangedSubview(text("REST", 8, .regular, palette.muted))
        status.addArrangedSubview(text(apiStatusText.contains("Connected") ? "● OK" : "● OFF", 8, .medium, apiStatusText.contains("Connected") ? palette.green : palette.orange))
        status.addArrangedSubview(spacer())
        status.addArrangedSubview(text(lastSyncText, 8, .regular, palette.muted))
        box.addArrangedSubview(status)
        return card(box)
    }

    func positionCard() -> NSView {
        let box = vstack(spacing: 7)
        let top = hstack(spacing: 6)
        // Use per-symbol position for this view (not global account positions).
        // This fixes showing MNQ position/PnL when NQ is selected, etc.
        let hasCurrentPos = activePosition() != nil
        let isFlat = !hasCurrentPos
        let side = positionSideText()
        let sideColor = side == "SHORT" ? palette.red : (isFlat ? palette.muted : palette.green)
        let sidePill = PillButton(side, bg: alpha(sideColor, 0.14), fg: sideColor, size: 8)
        sidePill.fixedHeight(18)
        top.addArrangedSubview(sidePill)

        let identity = hstack(spacing: 4)
        identity.addArrangedSubview(digit("\(positionSizeText())", 13, .semibold, palette.text))
        identity.addArrangedSubview(text(selectedSymbol, 13, .semibold, palette.text))
        top.addArrangedSubview(identity)
        top.addArrangedSubview(spacer())
        top.addArrangedSubview(text("U-PNL", 8, .medium, palette.muted))
        pnlLabel = adaptiveDigit(positionPnlText(), base: 13, min: 10, weight: .semibold, color: positionPnlColor(), width: 76, alignment: .right)
        top.addArrangedSubview(pnlLabel)
        box.addArrangedSubview(top)

        let details = hstack(spacing: 10)
        details.addArrangedSubview(inlineMetric("Avg", averagePriceText(), width: 60))
        details.addArrangedSubview(divider())
        details.addArrangedSubview(privacyMetric("RP&L", displayRealizedPnlText(), width: 58, valueColor: displayRealizedPnlColor(), action: #selector(toggleRealizedPnlPrivacy), hidden: hideRealizedPnl))
        details.addArrangedSubview(divider())
        details.addArrangedSubview(inlineMetric("Protect", protectionStatusText(), width: 64))
        details.addArrangedSubview(spacer())
        box.addArrangedSubview(details)
        return card(box)
    }

    func ticketCard() -> NSView {
        let panel = NSView()
        panel.fixedHeight(orderType == "LIMIT" ? 369 : 206)

        let sellQuote = sideQuoteButton(side: "SELL")
        let buyQuote = sideQuoteButton(side: "BUY")
        let spread = spreadBadge()
        sellQuoteButton = sellQuote
        buyQuoteButton = buyQuote
        spreadButton = spread

        let selectedTabBg = alpha(palette.blue, isDark ? 0.16 : 0.10)
        let market = PillButton("Market", bg: orderType == "MARKET" ? selectedTabBg : clearSurface(), fg: orderType == "MARKET" ? palette.text : palette.muted, size: 9)
        let limit = PillButton("Limit", bg: orderType == "LIMIT" ? selectedTabBg : clearSurface(), fg: orderType == "LIMIT" ? palette.text : palette.muted, size: 9)
        market.target = self
        market.action = #selector(selectMarketOrder)
        limit.target = self
        limit.action = #selector(selectLimitOrder)
        market.fixedHeight(20)
        limit.fixedHeight(20)

        let priceRow = orderType == "LIMIT" ? limitPriceRow() : zeroHeightView()

        let minus = PillButton("−", bg: palette.surface2, fg: palette.text, size: 13)
        let plus = PillButton("+", bg: palette.surface2, fg: palette.text, size: 13)
        minus.target = self
        minus.action = #selector(decrementQty)
        plus.target = self
        plus.action = #selector(incrementQty)
        let qtyRow = quantityControlRow(minus: minus, plus: plus)
        let qtyQuickRow = quickQtyRow()

        let bracketRow = orderType == "LIMIT" ? protectionRow() : zeroHeightView()

        let risk = orderType == "LIMIT" ? card(ticketRiskSummary(), pad: 6, color: palette.surface2) : zeroHeightView()
        if orderType == "LIMIT" {
            risk.fixedHeight(24)
        }

        let actionColor = isOppositeOpenPositionOrder(side: orderSide) ? palette.orange : (orderSide == "BUY" ? palette.green : palette.red)
        let submit = PillButton(orderSubmitTitle(), bg: readOnlyActionColor(actionColor), fg: readOnlyActionTextColor(), size: 11)
        submit.target = self
        submit.action = orderSide == "BUY" ? #selector(buyClicked) : #selector(sellClicked)
        submit.isEnabled = !quoteSyncing
        submit.fixedHeight(38)

        [sellQuote, buyQuote, spread, market, limit, priceRow, qtyRow, qtyQuickRow, bracketRow, risk, submit].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview($0)
        }

        NSLayoutConstraint.activate([
            sellQuote.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            sellQuote.topAnchor.constraint(equalTo: panel.topAnchor),
            sellQuote.trailingAnchor.constraint(equalTo: panel.centerXAnchor, constant: -1),
            buyQuote.leadingAnchor.constraint(equalTo: panel.centerXAnchor, constant: 1),
            buyQuote.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            buyQuote.centerYAnchor.constraint(equalTo: sellQuote.centerYAnchor),
            spread.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            spread.centerYAnchor.constraint(equalTo: sellQuote.centerYAnchor),

            market.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            market.topAnchor.constraint(equalTo: sellQuote.bottomAnchor, constant: 6),
            market.trailingAnchor.constraint(equalTo: panel.centerXAnchor, constant: -1),
            limit.leadingAnchor.constraint(equalTo: panel.centerXAnchor, constant: 1),
            limit.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            limit.centerYAnchor.constraint(equalTo: market.centerYAnchor),

            priceRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            priceRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            priceRow.topAnchor.constraint(equalTo: market.bottomAnchor, constant: orderType == "LIMIT" ? 7 : 0),

            qtyRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            qtyRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            qtyRow.topAnchor.constraint(equalTo: priceRow.bottomAnchor, constant: orderType == "LIMIT" ? 12 : 8),

            qtyQuickRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            qtyQuickRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            qtyQuickRow.topAnchor.constraint(equalTo: qtyRow.bottomAnchor, constant: 5),

            bracketRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            bracketRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            bracketRow.topAnchor.constraint(equalTo: qtyQuickRow.bottomAnchor, constant: orderType == "LIMIT" ? 7 : 0),

            risk.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            risk.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            risk.topAnchor.constraint(equalTo: bracketRow.bottomAnchor, constant: orderType == "LIMIT" ? 7 : 0),

            submit.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            submit.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            submit.topAnchor.constraint(equalTo: risk.bottomAnchor, constant: orderType == "LIMIT" ? 7 : 8)
        ])

        return card(panel)
    }

    func openOrdersCard() -> NSView {
        let box = vstack(spacing: 8)
        let orders = workingOrders()
        let orderCount = orders.count
        let positionCount = effectivePositionCount()
        let hasOrders = orderCount > 0
        let hasPosition = positionCount > 0

        let head = hstack(spacing: 8)
        head.addArrangedSubview(text("WORKING ORDERS", 10, .semibold, palette.text))
        head.addArrangedSubview(orderCountText(count: orderCount))
        head.addArrangedSubview(spacer())
        head.addArrangedSubview(text(orderDataSourceText(), 8, .regular, palette.muted))
        head.addArrangedSubview(orderDisclosureButton())
        box.addArrangedSubview(head)

        if lastSnapshot != nil {
            if orderCount == 0 {
                box.addArrangedSubview(openOrdersEmptyState())
            } else {
                box.addArrangedSubview(openOrdersList(orders))
            }
        } else {
            let loading = text("Loading orders from API...", 10, .regular, palette.muted)
            box.addArrangedSubview(loading)
        }

        box.addArrangedSubview(orderActionRow(hasOrders: hasOrders, hasPosition: hasPosition))
        return card(box)
    }

    func footer() -> NSView {
        let box = vstack(spacing: 4)
        let top = hstack(spacing: 6)
        let last = text(lastSyncText, 8, .semibold, palette.text)
        footerLastLabel = last
        top.addArrangedSubview(last)
        top.addArrangedSubview(shortDivider())
        eventLabel = text("Ready", 8, .regular, palette.muted)
        eventLabel.lineBreakMode = .byTruncatingTail
        eventLabel.maximumNumberOfLines = 1
        eventLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(eventLabel)
        box.addArrangedSubview(top)

        let bottom = hstack(spacing: 9)
        bottom.addArrangedSubview(footerConnectionState("API", live: apiStatusText.contains("Connected")))
        bottom.addArrangedSubview(footerConnectionState("Stream", live: streamStatusText.contains("Live")))
        bottom.addArrangedSubview(footerConnectionState("Market", live: marketStatusText.contains("Live")))
        bottom.addArrangedSubview(spacer())
        let snapshot = text(snapshotStatusText, 8, .regular, palette.muted)
        footerSnapshotLabel = snapshot
        bottom.addArrangedSubview(snapshot)
        box.addArrangedSubview(bottom)
        let view = card(box, pad: 7)
        updateFooterStatus()
        return view
    }

    func orderCountText(count: Int) -> NSTextField {
        let label = text("\(count)", 10, .semibold, count > 0 ? palette.orange : palette.muted)
        label.alignment = .left
        return label
    }

    func orderDisclosureButton() -> NSButton {
        let button = PillButton("⌄", bg: alpha(palette.text, isDark ? 0.05 : 0.08), fg: palette.muted, size: 10, hoverable: false)
        button.fixedWidth(22)
        button.fixedHeight(18)
        button.layer?.cornerRadius = 9
        button.isEnabled = false
        return button
    }

    func orderStatePill(count: Int) -> NSButton {
        let active = count > 0
        let color = active ? palette.orange : palette.muted
        let button = PillButton(active ? "\(count) WORKING" : "CLEAR", bg: alpha(color, active ? 0.16 : 0.10), fg: color, size: 8)
        button.fixedHeight(18)
        button.fixedWidth(active ? 74 : 48)
        button.layer?.cornerRadius = 9
        button.isEnabled = false
        return button
    }

    func openOrdersEmptyState() -> NSView {
        let box = NSView()
        box.fixedHeight(24)
        let label = text("No working orders", 10, .regular, palette.muted)
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    func orderActionRow(hasOrders: Bool, hasPosition: Bool) -> NSView {
        let row = hstack(spacing: 8)
        row.addArrangedSubview(spacer())
        let cancel = riskActionButton("Cancel All Orders", color: palette.orange, active: hasOrders && liveTradingEnabled())
        let flatten = riskActionButton("Flatten Position", color: palette.red, active: hasPosition && liveTradingEnabled())
        cancel.fixedWidth(112)
        flatten.fixedWidth(108)
        cancel.target = self
        cancel.action = #selector(cancelAllOrdersClicked)
        flatten.target = self
        flatten.action = #selector(flattenPositionClicked)
        row.addArrangedSubview(cancel)
        row.addArrangedSubview(flatten)
        return row
    }

    func openOrdersList(_ orders: [[String: Any]]) -> NSView {
        let list = vstack(spacing: 5)
        for order in orders {
            list.addArrangedSubview(workingOrderRow(order))
        }
        if orders.count <= 3 {
            return list
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = list
        scroll.fixedHeight(104)
        return scroll
    }

    func workingOrderRow(_ order: [String: Any]) -> NSView {
        let box = vstack(spacing: 2)
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.backgroundColor = alpha(palette.text, isDark ? 0.035 : 0.06).cgColor

        let side = orderSideText(order)
        let sideColor = side == "BUY" ? palette.green : palette.red
        let top = hstack(spacing: 5)
        top.addArrangedSubview(text(side, 9, .semibold, sideColor))
        top.addArrangedSubview(text(orderTypeText(order), 9, .semibold, palette.text))
        top.addArrangedSubview(digit("\(intValue(order["size"]) ?? 0)", 9, .medium, palette.text))
        top.addArrangedSubview(spacer())
        top.addArrangedSubview(text(orderStatusText(order), 8, .regular, palette.muted))
        let edit = orderRowButton("✎", color: palette.blue, action: #selector(editWorkingOrder(_:)), order: order)
        let cancel = orderRowButton("×", color: palette.orange, action: #selector(cancelWorkingOrder(_:)), order: order)
        top.addArrangedSubview(edit)
        top.addArrangedSubview(cancel)
        box.addArrangedSubview(top)

        let bottom = hstack(spacing: 5)
        bottom.addArrangedSubview(text(orderPriceText(order), 9, .regular, palette.muted))
        bottom.addArrangedSubview(spacer())
        bottom.addArrangedSubview(text("#\(intValue(order["id"]) ?? 0)", 8, .regular, palette.muted))
        bottom.addArrangedSubview(text(orderDataSourceText(), 8, .regular, palette.muted))
        box.addArrangedSubview(bottom)

        let outer = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            box.topAnchor.constraint(equalTo: outer.topAnchor),
            box.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            outer.heightAnchor.constraint(equalToConstant: 36)
        ])
        return outer
    }

    func orderRowButton(_ title: String, color: NSColor, action: Selector, order: [String: Any]) -> NSButton {
        let button = PillButton(title, bg: alpha(color, isDark ? 0.13 : 0.10), fg: color, size: 9)
        button.fixedWidth(20)
        button.fixedHeight(16)
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = action
        button.tag = intValue(order["id"]) ?? 0
        return button
    }

    func riskActionButton(_ title: String, color: NSColor, active: Bool) -> NSButton {
        let fg = active ? color : palette.muted
        let button = PillButton(title, bg: active ? alpha(color, 0.10) : alpha(palette.text, isDark ? 0.04 : 0.08), fg: fg, size: 9, hoverable: false)
        button.fixedHeight(24)
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.layer?.borderColor = alpha(fg, active ? 0.85 : 0.35).cgColor
        button.isEnabled = active
        (button as? PillButton)?.captureBaseBorder()
        return button
    }

    func statusPill(_ name: String, value: String, live: Bool) -> NSButton {
        let color = live ? palette.green : palette.muted
        let title = "\(name) \(value)"
        let button = PillButton(title, bg: alpha(color, live ? 0.13 : 0.08), fg: color, size: 8)
        button.fixedHeight(18)
        button.layer?.cornerRadius = 9
        button.isEnabled = false
        return button
    }

    func connectionState(_ name: String, live: Bool) -> NSView {
        let row = hstack(spacing: 4)
        let color = live ? palette.green : palette.muted
        row.addArrangedSubview(text("●", 7, .semibold, color))
        row.addArrangedSubview(text(name, 8, .regular, live ? palette.text : palette.muted))
        return row
    }

    func footerConnectionState(_ name: String, live: Bool) -> NSView {
        let row = hstack(spacing: 4)
        let color = live ? palette.green : palette.muted
        let dot = text("●", 7, .semibold, color)
        let label = text(name, 8, .regular, live ? palette.text : palette.muted)
        switch name {
        case "API":
            footerApiDotLabel = dot
            footerApiNameLabel = label
        case "Stream":
            footerStreamDotLabel = dot
            footerStreamNameLabel = label
        case "Market":
            footerMarketDotLabel = dot
            footerMarketNameLabel = label
        default:
            break
        }
        row.addArrangedSubview(dot)
        row.addArrangedSubview(label)
        return row
    }

    func updateFooterStatus() {
        footerLastLabel?.stringValue = lastSyncText
        footerLastLabel?.textColor = palette.text
        footerSnapshotLabel?.stringValue = snapshotStatusText
        footerSnapshotLabel?.textColor = palette.muted
        updateHeaderQuoteStatus()
        updateFooterConnection(dot: footerApiDotLabel, label: footerApiNameLabel, live: apiStatusText.contains("Connected"))
        updateFooterConnection(dot: footerStreamDotLabel, label: footerStreamNameLabel, live: streamStatusText.contains("Live"))
        updateFooterConnection(dot: footerMarketDotLabel, label: footerMarketNameLabel, live: marketStatusText.contains("Live") && !quoteSyncing)
    }

    func updateHeaderQuoteStatus() {
        let live = marketStatusText == "Market Live" && !quoteSyncing
        headerQuoteStatusLabel?.stringValue = live ? "● LIVE" : "● SYNC"
        headerQuoteStatusLabel?.textColor = live ? palette.green : palette.orange
    }

    func updateFooterConnection(dot: NSTextField?, label: NSTextField?, live: Bool) {
        let color = live ? palette.green : palette.muted
        dot?.textColor = color
        label?.textColor = live ? palette.text : palette.muted
    }

    func workingOrders() -> [[String: Any]] {
        let source = hasRealtimeOrderState ? Array(realtimeOrders.values) : (lastSnapshot?.openOrders ?? [])
        return source.sorted {
            (intValue($0["id"]) ?? 0) < (intValue($1["id"]) ?? 0)
        }
    }

    func orderDataSourceText() -> String {
        return hasRealtimeOrderState ? "Stream" : "REST snapshot"
    }

    func orderSideText(_ order: [String: Any]) -> String {
        guard let side = intValue(order["side"]) else { return "--" }
        return side == 0 ? "BUY" : "SELL"
    }

    func orderTypeText(_ order: [String: Any]) -> String {
        switch intValue(order["type"]) {
        case 1: return "LMT"
        case 2: return "MKT"
        case 3: return "STP LMT"
        case 4: return "STP"
        case 5: return "TRAIL"
        case 6: return "JOIN BID"
        case 7: return "JOIN ASK"
        default: return "ORDER"
        }
    }

    func orderStatusText(_ order: [String: Any]) -> String {
        switch intValue(order["status"]) {
        case 1: return "Open"
        case 6: return "Pending"
        case 2: return "Filled"
        case 3: return "Canceled"
        case 4: return "Expired"
        case 5: return "Rejected"
        default: return "Working"
        }
    }

    func orderPriceText(_ order: [String: Any]) -> String {
        let otype = intValue(order["type"]) ?? 0
        switch otype {
        case 1: // LMT (includes TP protection orders when closing position)
            if let p = numberValue(order["limitPrice"]) ?? numberValue(order["stopPrice"]) ?? numberValue(order["trailPrice"]) {
                return "@ \(number2(p))"
            }
        case 4: // STP (includes SL protection orders)
            if let p = numberValue(order["stopPrice"]) ?? numberValue(order["limitPrice"]) ?? numberValue(order["trailPrice"]) {
                return "Stop \(number2(p))"
            }
        case 5: // TRAIL
            if let p = numberValue(order["trailPrice"]) ?? numberValue(order["stopPrice"]) ?? numberValue(order["limitPrice"]) {
                return "Trail \(number2(p))"
            }
        case 3: // STP LMT
            if let p = numberValue(order["stopPrice"]) ?? numberValue(order["limitPrice"]) {
                return "Stop LMT \(number2(p))"
            }
        default:
            break
        }
        // fallback (original logic)
        if let limit = numberValue(order["limitPrice"]) {
            return "@ \(number2(limit))"
        }
        if let stop = numberValue(order["stopPrice"]) {
            return "Stop \(number2(stop))"
        }
        if let trail = numberValue(order["trailPrice"]) {
            return "Trail \(number2(trail))"
        }
        return "@ MKT"
    }

    func showRealtimeOrderToast(_ order: [String: Any], previous: [String: Any]?) {
        guard let id = intValue(order["id"]) else { return }
        let status = intValue(order["status"]) ?? -1
        let previousStatus = previous.flatMap { intValue($0["status"]) }
        guard previousStatus != status || previous == nil else { return }

        let key = "\(id)-\(status)"
        guard shouldShowOrderToast(key) else { return }

        let side = orderSideText(order)
        let qty = intValue(order["size"]) ?? 0
        let color = side == "BUY" ? palette.green : palette.red
        let title: String
        let subtitle = "\(orderTypeText(order)) \(orderPriceText(order))"

        switch status {
        case 1, 6:
            title = "\(side == "BUY" ? "+" : "-")\(qty) \(selectedSymbol) \(orderStatusText(order))"
        case 2:
            title = "\(side == "BUY" ? "+" : "-")\(qty) \(selectedSymbol) Filled"
        case 3:
            title = "Order canceled"
        case 4:
            title = "Order expired"
        case 5:
            title = "Order rejected"
        default:
            title = "Order update"
        }

        if isTakeProfitFill(order) {
            print("TopstepX TP sound matched order #\(id) side=\(side) type=\(intValue(order["type"]) ?? -1)")
            lastProtectionFillWasTP = true
        }

        if status == 2 && protectionOrderGroups[id] != nil {
            lastProtectionFillSound = (id, Date())
        }

        showTradeToast(title, subtitle: subtitle, color: status == 3 ? palette.orange : color)
    }

    func isTakeProfitFill(_ order: [String: Any]) -> Bool {
        guard intValue(order["status"]) == 2,
              let id = intValue(order["id"]) else { return false }

        // Local TP/SL intent is more reliable than optional realtime type fields.
        if let kind = protectionOrderKind[id] {
            return kind == "TP"
        }
        if let trackedType = protectionOrderType[id] {
            return trackedType == 1
        }

        // A normal LMT entry sent by this app is never a TP, even though ProjectX type 1 is also LMT.
        if submittedEntryOrderIds.contains(id) { return false }

        guard intValue(order["type"]) == 1 else { return false }

        // Server-side Auto OCO/bracket TP orders may not have been created by this app.
        // Treat a filled opposite-side LMT as TP when it is closing the current/recent position.
        let ordSide = orderSideText(order)
        let currentSide = positionSideText()
        let referenceSide: String
        if currentSide != "FLAT" {
            referenceSide = currentSide
        } else if Date().timeIntervalSince(lastNonFlatPositionAt) <= 30 {
            referenceSide = lastNonFlatPositionSide
        } else {
            referenceSide = lastKnownPositionSide
        }
        return (referenceSide == "LONG" && ordSide == "SELL") ||
               (referenceSide == "SHORT" && ordSide == "BUY")
    }

    func shouldShowOrderToast(_ key: String) -> Bool {
        let now = Date()
        recentOrderToastKeys = recentOrderToastKeys.filter { now.timeIntervalSince($0.value) < 10 }
        if recentOrderToastKeys[key] != nil {
            return false
        }
        recentOrderToastKeys[key] = now
        return true
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

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
        selectedSymbol = (sender.representedObject as? String) ?? sender.title
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
        guard payloadAccountId(order) == selectedAccountId,
              let id = order["id"] as? Int ?? (order["id"] as? NSNumber)?.intValue else { return }
        hasRealtimeOrderState = true
        let previous = realtimeOrders[id]
        let status = order["status"] as? Int ?? (order["status"] as? NSNumber)?.intValue
        if status == 1 || status == 6 {
            realtimeOrders[id] = order
        } else {
            realtimeOrders.removeValue(forKey: id)
            clearEditingOrder(orderId: id)
        }
        // Record type for protection orders so we can decide TP vs SL sound even if fill toast is for protection.
        if protectionOrderGroups[id] != nil {
            if let otype = intValue(order["type"]) ?? (order["type"] as? NSNumber)?.intValue {
                protectionOrderType[id] = otype
            }
        }
        showRealtimeOrderToast(order, previous: previous)
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
                    playSoundFile("TP")
                } else if let otype = protectionOrderType[orderId] {
                    if otype == 1 {
                        playSoundFile("TP")
                    } else {
                        playSoundFile("Order")
                    }
                } else {
                    playSoundFile("Order")
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
        guard payloadAccountId(trade) == selectedAccountId else { return }
        if trade["voided"] as? Bool == true { return }

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
        realtimePositions.removeAll()
        hasRealtimeOrderState = false
        officialRealizedDayPnl = nil
        officialUnrealizedPnl = nil
    }

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

    @objc func toggleTheme() {
        isDark.toggle()
        rebuild(force: true)
    }

    @objc func toggleBalancePrivacy() {
        hideBalance.toggle()
        rebuild(force: true)
    }

    @objc func toggleRealizedPnlPrivacy() {
        hideRealizedPnl.toggle()
        rebuild(force: true)
    }

    @objc func toggleAccountPrivacy() {
        hideAccount.toggle()
        rebuild(force: true)
    }

    @objc func closePanel() {
        window.close()
    }

    @objc func selectMarketOrder() {
        clearEditingOrder()
        orderType = "MARKET"
        limitPriceOverride = nil
        if bracketMode == "PRICE" {
            resetBracketPriceOverrides()
        }
        rebuild(force: true)
    }

    @objc func selectLimitOrder() {
        clearEditingOrder()
        orderType = "LIMIT"
        limitPriceOverride = quoteSyncing ? nil : normalizedPrice(marketEntryPrice())
        if bracketMode == "PRICE" {
            resetBracketPriceOverrides()
        }
        rebuild(force: true)
    }

    @objc func incrementQty() {
        orderQty = min(orderQty + 1, maxOrderQty)
        rebuild(force: true)
    }

    @objc func decrementQty() {
        orderQty = max(orderQty - 1, 1)
        rebuild(force: true)
    }

    @objc func incrementLimitPrice() {
        stepLimitPrice(1)
    }

    @objc func decrementLimitPrice() {
        stepLimitPrice(-1)
    }

    func stepLimitPrice(_ ticks: Int) {
        guard orderType == "LIMIT", !quoteSyncing else { return }
        let tick = contracts[selectedSymbol]!.tick
        let current = limitPriceOverride ?? marketEntryPrice()
        limitPriceOverride = normalizedPrice(current + Double(ticks) * tick)
        if bracketMode == "PRICE" {
            resetBracketPriceOverrides()
        }
        rebuild(disableAnimations: true, force: true)
    }

    @objc func selectQuickQty(_ sender: NSButton) {
        if let value = Int(sender.title) {
            orderQty = clampedOrderQty(value)
            rebuild(force: true)
        }
    }

    func clampedOrderQty(_ value: Int) -> Int {
        return min(max(value, 1), maxOrderQty)
    }

    @objc func selectTicksMode() {
        bracketMode = "TICKS"
        rebuild(force: true)
    }

    @objc func selectPriceMode() {
        bracketMode = "PRICE"
        resetBracketPriceOverrides()
        rebuild(force: true)
    }

    @objc func selectBuySide() {
        clearEditingOrder()
        orderSide = "BUY"
        limitPriceOverride = nil
        if bracketMode == "PRICE" {
            resetBracketPriceOverrides()
        }
        rebuild(force: true)
    }

    @objc func selectSellSide() {
        clearEditingOrder()
        orderSide = "SELL"
        limitPriceOverride = nil
        if bracketMode == "PRICE" {
            resetBracketPriceOverrides()
        }
        rebuild(force: true)
    }

    @objc func buyClicked() {
        submitOrder(side: "BUY")
    }

    @objc func sellClicked() {
        submitOrder(side: "SELL")
    }

    func submitOrder(side: String) {
        guard !tradeRequestInFlight else { return }
        do {
            if editingOrderId != nil {
                try submitOrderModification()
                return
            }
            if shouldSubmitPositionProtection(side: side) {
                try submitPositionProtection(side: side)
                return
            }
            let payload = try buildOrderPayload(side: side)
            let summary = orderType == "LIMIT"
                ? "\(side) LIMIT \(orderQty) \(selectedSymbol) @ \(number2(orderEntryPrice()))"
                : "\(side) MARKET \(orderQty) \(selectedSymbol)"
            let isManualTakeProfitLimit = orderType == "LIMIT" && isOppositeOpenPositionOrder(side: side)
            guard liveTradingEnabled() else {
                eventLabel?.stringValue = "CHECK OK, READ ONLY: \(summary)"
                eventLabel?.textColor = palette.green
                print("TopstepX order preflight payload (read only, not sent): \(jsonText(payload))")
                return
            }
            guard let apiClient else { throw ProjectXError.api("API config missing") }
            tradeRequestInFlight = true
            eventLabel?.stringValue = "SENDING: \(summary)"
            eventLabel?.textColor = palette.orange
            apiClient.placeOrder(payload: payload) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.tradeRequestInFlight = false
                    switch result {
                    case .failure(let error):
                        self.setEvent("SEND FAILED: \(self.shortTradeError(error.localizedDescription))", color: self.palette.red, detail: error.localizedDescription)
                    case .success(let orderId):
                        if orderId > 0 {
                            if isManualTakeProfitLimit {
                                self.protectionOrderKind[orderId] = "TP"
                                self.protectionOrderType[orderId] = 1
                            } else {
                                self.submittedEntryOrderIds.insert(orderId)
                            }
                        }
                        self.setEvent(orderId > 0 ? "SENT: \(summary) #\(orderId)" : "SENT: \(summary)", color: self.palette.green)
                        self.showTradeToast(self.orderToastTitle(side: side), subtitle: orderId > 0 ? "TopstepX accepted #\(orderId)" : "TopstepX accepted", color: side == "BUY" ? self.palette.green : self.palette.red)
                        self.refreshAfterTradeMutation()
                    }
                }
            }
        } catch {
            setEvent("CHECK FAILED: \(shortTradeError(error.localizedDescription))", color: palette.orange, detail: error.localizedDescription)
        }
    }

    func submitOrderModification() throws {
        guard liveTradingEnabled() else { throw ProjectXError.api("readOnly is enabled") }
        guard let apiClient else { throw ProjectXError.api("API config missing") }
        guard let accountId = selectedAccountId else { throw ProjectXError.api("accountId missing") }
        guard let orderId = editingOrderId,
              let type = editingOrderType else { throw ProjectXError.api("no order selected") }
        let price = orderEntryPrice()
        guard price > 0 else { throw ProjectXError.api("order price must be positive") }
        guard isTickAligned(price) else { throw ProjectXError.api("order price is not tick aligned") }
        let payload = modifyOrderPayload(accountId: accountId, orderId: orderId, type: type, price: price)
        tradeRequestInFlight = true
        eventLabel?.stringValue = "MODIFYING ORDER #\(orderId)"
        eventLabel?.textColor = palette.orange
        apiClient.modifyOrder(payload: payload) { [weak self] result in
            DispatchQueue.main.async {
                guard let controller = self else { return }
                controller.tradeRequestInFlight = false
                switch result {
                case .failure(let error):
                    controller.setEvent("MODIFY FAILED: \(controller.shortTradeError(error.localizedDescription))", color: controller.palette.red, detail: error.localizedDescription)
                case .success:
                    controller.setEvent("MODIFY SENT: #\(orderId) @ \(number2(price))", color: controller.palette.green)
                    controller.showTradeToast("Order modify sent", subtitle: "#\(orderId) @ \(number2(price))", color: controller.palette.blue)
                    controller.clearEditingOrder(orderId: orderId)
                    controller.refreshAfterTradeMutation()
                }
            }
        }
    }

    func modifyOrderPayload(accountId: Int, orderId: Int, type: Int, price: Double) -> [String: Any] {
        var payload: [String: Any] = [
            "accountId": accountId,
            "orderId": orderId,
            "size": orderQty
        ]
        if type == 1 {
            payload["limitPrice"] = price
            payload["stopPrice"] = NSNull()
            payload["trailPrice"] = NSNull()
        } else if type == 4 {
            payload["limitPrice"] = NSNull()
            payload["stopPrice"] = price
            payload["trailPrice"] = NSNull()
        } else if type == 5 {
            payload["limitPrice"] = NSNull()
            payload["stopPrice"] = NSNull()
            payload["trailPrice"] = price
        } else {
            payload["limitPrice"] = price
            payload["stopPrice"] = NSNull()
            payload["trailPrice"] = NSNull()
        }
        return payload
    }

    func shouldSubmitPositionProtection(side: String) -> Bool {
        return orderType == "LIMIT" && isOppositeOpenPositionOrder(side: side) && (tpEnabled || slEnabled)
    }

    func submitPositionProtection(side: String) throws {
        guard liveTradingEnabled() else { throw ProjectXError.api("readOnly is enabled") }
        guard let apiClient else { throw ProjectXError.api("API config missing") }
        let payloads = try positionProtectionPayloads(side: side)
        guard !payloads.isEmpty else { throw ProjectXError.api("select TP and/or SL first") }
        tradeRequestInFlight = true
        let summary = positionProtectionSummary(side: side)
        let wasTP = tpEnabled
        let wasSL = slEnabled
        eventLabel?.stringValue = "SENDING: \(summary)"
        eventLabel?.textColor = palette.orange
        placeOrderPayloads(apiClient: apiClient, payloads: payloads) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tradeRequestInFlight = false
                switch result {
                case .failure(let error):
                    self.setEvent("PROTECT FAILED: \(self.shortTradeError(error.localizedDescription))", color: self.palette.red, detail: error.localizedDescription)
                case .success(let ids):
                    self.registerProtectionGroup(orderIds: ids, payloads: payloads)
                    self.setEvent("PROTECT SENT: \(summary)", color: self.palette.green)
                    let toastTitle: String
                    if wasTP && wasSL {
                        toastTitle = "TP/SL sent"
                    } else if wasSL {
                        toastTitle = "SL sent"
                    } else if wasTP {
                        toastTitle = "TP sent"
                    } else {
                        toastTitle = "Protection sent"
                    }
                    self.showTradeToast(toastTitle, subtitle: ids.isEmpty ? self.selectedSymbol : "#\(ids.map(String.init).joined(separator: ","))", color: self.palette.orange)
                    self.refreshAfterTradeMutation()
                }
            }
        }
    }

    func registerProtectionGroup(orderIds: [Int], payloads: [[String: Any]] = []) {
        let validIds = orderIds.filter { $0 > 0 }
        if validIds.count > 1 {
            let groupId = "prot-\(Date().timeIntervalSince1970)"
            protectionGroupOrders[groupId] = Set(validIds)
            for id in validIds {
                protectionOrderGroups[id] = groupId
            }
        } else if validIds.count == 1 {
            // Single protection (e.g. only TP or only SL, no sibling). Still record in protectionOrderGroups
            // so that TP fill detection (otype==1) can identify it for special TP.caf sound.
            // Use a dummy groupId with no entry in protectionGroupOrders so OCO/cancel logic safely no-ops.
            let id = validIds[0]
            protectionOrderGroups[id] = "single-\(id)"
        }
        for (id, payload) in zip(validIds, payloads) {
            if let type = intValue(payload["type"]) {
                protectionOrderType[id] = type
                protectionOrderKind[id] = type == 1 ? "TP" : "SL"
            }
        }
    }

    func placeOrderPayloads(apiClient: ProjectXClient, payloads: [[String: Any]], completion: @escaping (Result<[Int], Error>) -> Void) {
        let group = DispatchGroup()
        var ids = Array(repeating: 0, count: payloads.count)
        var firstError: Error?
        for (index, payload) in payloads.enumerated() {
            group.enter()
            apiClient.placeOrder(payload: payload) { result in
                switch result {
                case .failure(let error):
                    if firstError == nil { firstError = error }
                case .success(let id):
                    ids[index] = id
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(ids))
            }
        }
    }

    @objc func cancelAllOrdersClicked() {
        cancelAllWorkingOrders(closeAfterCancel: false)
    }

    @objc func flattenPositionClicked() {
        cancelAllWorkingOrders(closeAfterCancel: true)
    }

    @objc func cancelWorkingOrder(_ sender: NSButton) {
        guard !tradeRequestInFlight else { return }
        let orderId = sender.tag
        guard orderId > 0,
              let apiClient,
              let accountId = selectedAccountId else { return }
        tradeRequestInFlight = true
        eventLabel?.stringValue = "CANCELLING ORDER #\(orderId)"
        eventLabel?.textColor = palette.orange
        apiClient.cancelOrder(accountId: accountId, orderId: orderId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tradeRequestInFlight = false
                switch result {
                case .failure(let error):
                    self.setEvent("CANCEL FAILED: \(self.shortTradeError(error.localizedDescription))", color: self.palette.red, detail: error.localizedDescription)
                case .success:
                    self.clearEditingOrder(orderId: orderId)
                    self.setEvent("CANCEL SENT: #\(orderId)", color: self.palette.green)
                    self.showTradeToast("Order cancel sent", subtitle: "#\(orderId)", color: self.palette.orange)
                    self.refreshAfterTradeMutation()
                }
            }
        }
    }

    @objc func editWorkingOrder(_ sender: NSButton) {
        let orderId = sender.tag
        guard let order = workingOrders().first(where: { intValue($0["id"]) == orderId }),
              let type = intValue(order["type"]),
              let price = editableOrderPrice(order) else { return }
        editingOrderId = orderId
        editingOrderType = type
        editingOrderSide = orderSideText(order)
        orderSide = editingOrderSide ?? orderSide
        orderType = "LIMIT"
        limitPriceOverride = normalizedPrice(price)
        orderQty = clampedOrderQty(intValue(order["size"]) ?? orderQty)
        tpEnabled = false
        slEnabled = false
        tpPriceOverride = nil
        slPriceOverride = nil
        setEvent("EDIT ORDER #\(orderId): adjust price, then Modify", color: palette.orange)
        rebuild(force: true)
    }

    func editableOrderPrice(_ order: [String: Any]) -> Double? {
        return numberValue(order["limitPrice"]) ?? numberValue(order["stopPrice"]) ?? numberValue(order["trailPrice"])
    }

    func clearEditingOrder(orderId: Int? = nil) {
        if let orderId, editingOrderId != orderId { return }
        editingOrderId = nil
        editingOrderType = nil
        editingOrderSide = nil
    }

    func cancelAllWorkingOrders(closeAfterCancel: Bool) {
        guard !tradeRequestInFlight else { return }
        do {
            guard liveTradingEnabled() else { throw ProjectXError.api("readOnly is enabled") }
            guard let apiClient else { throw ProjectXError.api("API config missing") }
            guard let accountId = selectedAccountId else { throw ProjectXError.api("accountId missing") }
            let orders = workingOrders()
            if !closeAfterCancel {
                guard !orders.isEmpty else { throw ProjectXError.api("no working orders") }
            }

            tradeRequestInFlight = true
            let orderIds = orders.compactMap { intValue($0["id"]) }
            eventLabel?.stringValue = closeAfterCancel ? "FLATTEN: cancelling orders first" : "CANCELLING \(orderIds.count) order(s)"
            eventLabel?.textColor = palette.orange

            cancelOrderIds(apiClient: apiClient, accountId: accountId, orderIds: orderIds) { [weak self] cancelResult in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch cancelResult {
                    case .failure(let error):
                        self.tradeRequestInFlight = false
                        self.eventLabel?.stringValue = "CANCEL FAILED: \(error.localizedDescription)"
                        self.eventLabel?.textColor = self.palette.red
                    case .success:
                        if closeAfterCancel {
                            self.closeCurrentContractPosition(apiClient: apiClient, accountId: accountId)
                        } else {
                            self.tradeRequestInFlight = false
                            self.eventLabel?.stringValue = "CANCEL SENT: \(orderIds.count) order(s)"
                            self.eventLabel?.textColor = self.palette.green
                            self.showTradeToast("Canceled \(orderIds.count)", subtitle: "TopstepX accepted", color: self.palette.orange)
                            self.refreshAfterTradeMutation()
                        }
                    }
                }
            }
        } catch {
            eventLabel?.stringValue = "ACTION FAILED: \(error.localizedDescription)"
            eventLabel?.textColor = palette.orange
        }
    }

    func cancelOrderIds(apiClient: ProjectXClient, accountId: Int, orderIds: [Int], completion: @escaping (Result<Void, Error>) -> Void) {
        guard !orderIds.isEmpty else {
            completion(.success(()))
            return
        }
        let group = DispatchGroup()
        var firstError: Error?
        for orderId in orderIds {
            group.enter()
            apiClient.cancelOrder(accountId: accountId, orderId: orderId) { result in
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(()))
            }
        }
    }

    func closeCurrentContractPosition(apiClient: ProjectXClient, accountId: Int) {
        guard effectivePositionCount() > 0 else {
            tradeRequestInFlight = false
            eventLabel?.stringValue = "FLATTEN FAILED: no open position"
            eventLabel?.textColor = palette.orange
            refreshAfterTradeMutation()
            return
        }
        guard let contractId = realtimeContractId ?? lastSnapshot?.contractId else {
            tradeRequestInFlight = false
            eventLabel?.stringValue = "FLATTEN FAILED: contractId missing"
            eventLabel?.textColor = palette.red
            return
        }
        eventLabel?.stringValue = "FLATTEN: closing \(selectedSymbol)"
        eventLabel?.textColor = palette.orange
        apiClient.closeContract(accountId: accountId, contractId: contractId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.tradeRequestInFlight = false
                switch result {
                case .failure(let error):
                    self.eventLabel?.stringValue = "FLATTEN FAILED: \(error.localizedDescription)"
                    self.eventLabel?.textColor = self.palette.red
                case .success:
                    self.eventLabel?.stringValue = "FLATTEN SENT: \(self.selectedSymbol)"
                    self.eventLabel?.textColor = self.palette.green
                    self.showTradeToast("Flatten sent", subtitle: self.selectedSymbol, color: self.palette.red)
                    self.refreshAfterTradeMutation()
                }
            }
        }
    }

    func positionProtectionPayloads(side: String) throws -> [[String: Any]] {
        var payloads: [[String: Any]] = []
        if tpEnabled {
            payloads.append(try buildPositionProtectionPayload(kind: "TP", side: side))
        }
        if slEnabled {
            payloads.append(try buildPositionProtectionPayload(kind: "SL", side: side))
        }
        return payloads
    }

    func buildPositionProtectionPayload(kind: String, side: String) throws -> [String: Any] {
        guard apiClient != nil else { throw ProjectXError.api("API config missing") }
        guard canTradeText == "CAN TRADE" else { throw ProjectXError.api("account is not tradable: \(canTradeText)") }
        guard let accountId = selectedAccountId else { throw ProjectXError.api("accountId missing") }
        guard let contractId = activeContractId() else { throw ProjectXError.api("contractId missing") }
        guard isQuoteFresh() else { throw ProjectXError.api("market quote stale or missing") }
        guard isOppositeOpenPositionOrder(side: side) else { throw ProjectXError.api("protection must be opposite side of open position") }
        let size = min(orderQty, positionSizeText())
        guard size > 0 else { throw ProjectXError.api("size must be positive") }
        let price = positionProtectionPrice(kind: kind)
        guard price > 0 else { throw ProjectXError.api("\(kind) price must be positive") }
        guard isTickAligned(price) else { throw ProjectXError.api("\(kind) price is not tick aligned") }
        try validatePositionProtectionPrice(kind: kind, side: side, price: price)
        let type = kind == "TP" ? 1 : 4
        return [
            "accountId": accountId,
            "contractId": contractId,
            "type": type,
            "side": side == "BUY" ? 0 : 1,
            "size": size,
            "limitPrice": kind == "TP" ? price : NSNull(),
            "stopPrice": kind == "SL" ? price : NSNull(),
            "trailPrice": NSNull(),
            "customTag": NSNull(),
            "stopLossBracket": NSNull(),
            "takeProfitBracket": NSNull()
        ]
    }

    func validatePositionProtectionPrice(kind: String, side: String, price: Double) throws {
        if kind == "TP" {
            if side == "BUY", let ask = displayAskPrice(), price >= ask {
                throw ProjectXError.api("TP buy limit \(number2(price)) would fill now; set it below current ask \(number2(ask))")
            }
            if side == "SELL", let bid = displayBidPrice(), price <= bid {
                throw ProjectXError.api("TP sell limit \(number2(price)) would fill now; set it above current bid \(number2(bid))")
            }
        } else {
            if side == "BUY", let ask = displayAskPrice(), price <= ask {
                throw ProjectXError.api("SL buy stop \(number2(price)) must be above current ask \(number2(ask))")
            }
            if side == "SELL", let bid = displayBidPrice(), price >= bid {
                throw ProjectXError.api("SL sell stop \(number2(price)) must be below current bid \(number2(bid))")
            }
        }
    }

    func positionProtectionPrice(kind: String) -> Double {
        if bracketMode == "PRICE" {
            if kind == "TP", let value = tpPriceOverride { return value }
            if kind == "SL", let value = slPriceOverride { return value }
        }
        return defaultPositionProtectionPrice(kind: kind)
    }

    func defaultPositionProtectionPrice(kind: String) -> Double {
        guard let avg = numberValue(activePosition()?["averagePrice"]) else {
            return orderEntryPrice()
        }
        // Use spec for the actual position's contract (now safe because activePosition is scoped).
        let spec = contractSpec(for: activePosition()?["contractId"] as? String) ?? (contracts[selectedSymbol]!.tick, contracts[selectedSymbol]!.tickValue)
        let offset = Double(kind == "TP" ? tpTicks : slTicks) * spec.0
        if positionSideText() == "SHORT" {
            return normalizedPrice(kind == "TP" ? avg - offset : avg + offset)
        }
        return normalizedPrice(kind == "TP" ? avg + offset : avg - offset)
    }

    func positionProtectionSummary(side: String) -> String {
        var parts: [String] = []
        if tpEnabled { parts.append("TP \(number2(positionProtectionPrice(kind: "TP")))") }
        if slEnabled { parts.append("SL \(number2(positionProtectionPrice(kind: "SL")))") }
        return "\(side) \(min(orderQty, positionSizeText())) \(selectedSymbol) \(parts.joined(separator: " / "))"
    }

    func buildOrderPayload(side: String) throws -> [String: Any] {
        guard apiClient != nil else { throw ProjectXError.api("API config missing") }
        guard canTradeText == "CAN TRADE" else { throw ProjectXError.api("account is not tradable: \(canTradeText)") }
        guard let accountId = selectedAccountId else { throw ProjectXError.api("accountId missing") }
        guard let contractId = realtimeContractId ?? lastSnapshot?.contractId else { throw ProjectXError.api("contractId missing") }
        guard isQuoteFresh() else { throw ProjectXError.api("market quote stale or missing") }
        guard orderQty > 0 else { throw ProjectXError.api("size must be positive") }
        if slEnabled {
            guard effectiveSLTicks() > 0 else { throw ProjectXError.api("SL ticks must be positive") }
        }
        if tpEnabled {
            guard effectiveTPTicks() > 0 else { throw ProjectXError.api("TP ticks must be positive") }
        }

        let type = orderType == "LIMIT" ? 1 : 2
        let sideValue = side == "BUY" ? 0 : 1
        var limitPrice: Any = NSNull()
        if orderType == "MARKET" {
            let quote = side == "BUY" ? displayAskPrice() : displayBidPrice()
            guard quote != nil else { throw ProjectXError.api("\(side) quote missing") }
        } else {
            let entry = orderEntryPrice()
            guard entry > 0 else { throw ProjectXError.api("limit price must be positive") }
            guard isTickAligned(entry) else { throw ProjectXError.api("limit price is not tick aligned") }
            if isMarketableExitLimit(side: side, price: entry) {
                throw ProjectXError.api("blocked: \(side) limit \(number2(entry)) is marketable and would close \(positionSideText()) immediately")
            }
            limitPrice = entry
        }

        let includeBrackets = apiClient?.config.sendBrackets == true && orderType == "LIMIT" && !isOppositeOpenPositionOrder(side: side)
        let bracketSign = side == "BUY" ? 1 : -1
        let stopLossBracket: Any = includeBrackets && slEnabled ? ["ticks": -bracketSign * effectiveSLTicks(), "type": 4] : NSNull()
        let takeProfitBracket: Any = includeBrackets && tpEnabled ? ["ticks": bracketSign * effectiveTPTicks(), "type": 1] : NSNull()

        return [
            "accountId": accountId,
            "contractId": contractId,
            "type": type,
            "side": sideValue,
            "size": orderQty,
            "limitPrice": limitPrice,
            "stopPrice": NSNull(),
            "trailPrice": NSNull(),
            "customTag": NSNull(),
            "stopLossBracket": stopLossBracket,
            "takeProfitBracket": takeProfitBracket
        ]
    }

    func text(_ value: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func digit(_ value: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func adaptiveDigit(_ value: String, base: CGFloat, min: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat, alignment: NSTextAlignment) -> NSTextField {
        let field = digit(value, adaptiveSize(for: value, base: base, min: min), weight, color)
        field.alignment = alignment
        field.fixedWidth(width)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }

    func adaptiveSize(for value: String, base: CGFloat, min: CGFloat) -> CGFloat {
        let count = value.count
        if count <= 8 { return base }
        if count <= 10 { return max(min, base - 1) }
        if count <= 12 { return max(min, base - 2) }
        return min
    }

    func metric(_ name: String, _ value: String, _ color: NSColor) -> NSView {
        let box = vstack(spacing: 5)
        box.addArrangedSubview(text(name, 8, .regular, palette.muted))
        box.addArrangedSubview(digit(value, 12, .semibold, color))
        return box
    }

    func compactMetric(_ name: String, _ value: String) -> NSView {
        let box = vstack(spacing: 2)
        box.alignment = .right
        box.addArrangedSubview(text(name, 7, .medium, palette.muted))
        box.addArrangedSubview(digit(value, 11, .semibold, palette.muted))
        box.fixedWidth(32)
        return box
    }

    func positionMetric(_ name: String, _ value: String, _ color: NSColor) -> NSView {
        let box = vstack(spacing: 2)
        box.alignment = .centerX
        let label = text(name, 7, .medium, palette.muted)
        label.alignment = .center
        let val = digit(value, 11, .semibold, color)
        val.alignment = .center
        box.addArrangedSubview(label)
        box.addArrangedSubview(val)
        return box
    }

    func inlineMetric(_ name: String, _ value: String, width: CGFloat, valueColor: NSColor? = nil) -> NSView {
        let row = hstack(spacing: 4)
        row.addArrangedSubview(text(name, 8, .regular, palette.muted))
        let color = valueColor ?? (value == "None" || value == "--" ? palette.muted : palette.text)
        row.addArrangedSubview(adaptiveDigit(value, base: 10, min: 8, weight: .semibold, color: color, width: width, alignment: .left))
        return row
    }

    func privacyMetric(_ name: String, _ value: String, width: CGFloat, valueColor: NSColor, action: Selector, hidden: Bool) -> NSView {
        let row = hstack(spacing: 4)
        row.addArrangedSubview(text(name, 8, .regular, palette.muted))
        let button = PillButton(value, bg: NSColor.clear, fg: valueColor, size: 10, hoverable: false)
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        button.alignment = .left
        button.fixedWidth(width)
        button.fixedHeight(14)
        button.target = self
        button.action = action
        button.imagePosition = .noImage
        button.toolTip = hidden ? "Show \(name)" : "Hide \(name)"
        row.addArrangedSubview(button)
        return row
    }

    func displayBalanceText() -> String {
        return hideBalance ? "*****" : balanceText
    }

    func displayRealizedPnlText() -> String {
        return hideRealizedPnl ? "*****" : officialDayNetText()
    }

    func displayRealizedPnlColor() -> NSColor {
        return hideRealizedPnl ? palette.muted : officialDayNetColor()
    }

    func anonymizedAccountName(_ name: String) -> String {
        var compact = name.replacingOccurrences(of: "-219616-", with: "-")
        // Anonymize last 4 (or more) trailing digits with •••• for privacy/screenshots
        if let range = compact.range(of: #"\d{3,}$"#, options: .regularExpression) {
            let digits = String(compact[range])
            let visible = max(0, digits.count - 4)
            let masked = String(digits.prefix(visible)) + String(repeating: "•", count: 4)
            compact.replaceSubrange(range, with: masked)
        } else if compact.count > 6 {
            // Fallback: mask last 4 characters
            compact = String(compact.dropLast(4)) + "••••"
        }
        if compact.count > 22 {
            compact = String(compact.prefix(19)) + "..."
        }
        return compact
    }

    func sideQuoteButton(side: String) -> QuoteButton {
        let selected = orderSide == side
        let color = side == "BUY" ? palette.green : palette.red
        let bg = selected ? alpha(color, isDark ? 0.42 : 0.18) : alpha(color, isDark ? 0.16 : 0.07)
        let fg = quoteTextColor(side: side)
        let button = QuoteButton(side: side, price: quotePriceText(side: side), bg: bg, fg: fg)
        button.fixedHeight(44)
        button.layer?.borderWidth = selected ? 1 : 0.5
        button.layer?.borderColor = alpha(color, selected ? 0.75 : 0.35).cgColor
        button.target = self
        button.action = side == "BUY" ? #selector(selectBuySide) : #selector(selectSellSide)
        return button
    }

    func quotePriceText(side: String) -> String {
        if quoteSyncing { return "--" }
        let value = side == "BUY" ? displayAskPrice() : displayBidPrice()
        return value.map(number2) ?? "--"
    }

    func quoteTextColor(side: String) -> NSColor {
        let selected = orderSide == side
        if selected {
            if isDark { return NSColor.white }
            return side == "BUY" ? palette.green : palette.red
        }
        return side == "BUY" ? palette.green : palette.red
    }

    func spreadBadge() -> SpreadBadge {
        let bg = isDark
            ? NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.18, alpha: 0.98)
            : NSColor(calibratedRed: 0.88, green: 0.93, blue: 0.98, alpha: 0.98)
        let badge = SpreadBadge(spreadText(), bg: bg, fg: palette.text, border: palette.border)
        badge.fixedWidth(38)
        badge.fixedHeight(18)
        return badge
    }

    func spreadText() -> String {
        guard let bid = displayBidPrice(), let ask = displayAskPrice(), ask >= bid else { return "--" }
        return number2(ask - bid)
    }

    func orderSubmitTitle() -> String {
        let action = orderSide == "BUY" ? "BUY" : "SELL"
        if quoteSyncing {
            return "WAITING FOR QUOTE\n\(selectedSymbol) OFFICIAL DATA"
        }
        if let orderId = editingOrderId {
            return "MODIFY ORDER #\(orderId)\n\(orderQty) \(selectedSymbol) @ \(number2(orderEntryPrice()))"
        }
        if isOppositeOpenPositionOrder(side: orderSide) {
            if orderType == "MARKET" {
                return "CLOSE \(positionSideText())\n\(orderQty) \(selectedSymbol) MARKET · LIVE"
            }
            if tpEnabled || slEnabled {
                return "PROTECT \(positionSideText())\n\(protectionSummaryText()) · \(min(orderQty, positionSizeText())) \(selectedSymbol)"
            }
            let entry = orderEntryPrice()
            if isMarketableExitLimit(side: orderSide, price: entry) {
                return "BLOCKED \(action)\nLIMIT WOULD FILL NOW"
            }
            return "TAKE PROFIT \(action)\n\(orderQty) \(selectedSymbol) @ \(number2(entry)) LIMIT · LIVE"
        }
        let type = orderType == "MARKET" ? "MARKET" : "LIMIT"
        let prefix = liveTradingEnabled() ? "SEND" : "CHECK"
        let suffix = liveTradingEnabled()
            ? (apiClient?.config.sendBrackets == true ? "LIVE" : "LIVE · NO BRACKET")
            : "READ ONLY"
        let protection = protectionSummaryText()
        if orderType == "LIMIT" {
            return "\(prefix) \(action)\n\(orderQty) \(selectedSymbol) @ \(number2(orderEntryPrice())) \(type) · \(suffix) · \(protection)"
        }
        return "\(prefix) \(action)\n\(orderQty) \(selectedSymbol) \(type) · \(suffix)"
    }

    func liveTradingEnabled() -> Bool {
        return apiClient?.config.readOnly == false
    }

    func protectionSummaryText() -> String {
        if tpEnabled && slEnabled { return "TP/SL" }
        if tpEnabled { return "TP ONLY" }
        if slEnabled { return "SL ONLY" }
        return "NO TP/SL"
    }

    func pair(_ name: String, _ value: String) -> NSView {
        let row = hstack(spacing: 8)
        row.addArrangedSubview(text(name, 9, .regular, palette.muted))
        row.addArrangedSubview(digit(value, 11, .semibold, palette.text))
        return row
    }

    func field(_ name: String, _ value: String) -> NSView {
        let box = vstack(spacing: 3)
        box.setContentHuggingPriority(.defaultLow, for: .horizontal)
        box.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        box.addArrangedSubview(text(name, 9, .regular, palette.muted))
        let input = NSTextField(string: value)
        input.cell = CenteredTextFieldCell(textCell: value)
        input.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        input.textColor = palette.text
        input.backgroundColor = inputBackgroundColor()
        input.drawsBackground = true
        input.isBezeled = false
        input.wantsLayer = true
        input.layer?.cornerRadius = 6
        input.layer?.backgroundColor = inputBackgroundColor().cgColor
        input.layer?.borderWidth = isDark ? 0 : 1
        input.layer?.borderColor = alpha(palette.border, 0.75).cgColor
        input.fixedHeight(26)
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        box.addArrangedSubview(input)
        return box
    }

    func compactField(_ name: String, _ value: String, id: String? = nil, enabled: Bool = true) -> NSView {
        let box = NSView()
        let title = text(name, 8, .regular, enabled ? palette.muted : alpha(palette.muted, 0.55))
        title.alignment = .center
        let input = PriceInputTextField(string: value)
        input.cell = CenteredTextFieldCell(textCell: value)
        if let id {
            input.identifier = NSUserInterfaceItemIdentifier(id)
            input.delegate = self
            input.target = self
            input.action = #selector(ticketInputCommitted(_:))
            input.onBegin = { [weak self] field in
                self?.beginTicketInput(field)
            }
            input.onCommit = { [weak self] field in
                guard let self, let id = field.identifier?.rawValue else { return }
                self.activeTicketInput = nil
                self.activeTicketField = nil
                self.commitTicketInput(field, id: id)
            }
        }
        input.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        input.textColor = enabled ? palette.text : alpha(palette.muted, 0.70)
        input.alignment = .center
        input.isEditable = enabled
        input.isSelectable = enabled
        input.isEnabled = enabled
        input.backgroundColor = inputBackgroundColor()
        input.drawsBackground = true
        input.isBezeled = false
        input.wantsLayer = true
        input.layer?.cornerRadius = 6
        input.layer?.backgroundColor = (enabled ? inputBackgroundColor() : alpha(inputBackgroundColor(), isDark ? 0.55 : 0.70)).cgColor
        input.cell?.wraps = false
        input.cell?.usesSingleLineMode = true
        input.cell?.controlSize = .small
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
        input.menu = menu
        [title, input].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            title.topAnchor.constraint(equalTo: box.topAnchor),
            input.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            input.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            input.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            input.heightAnchor.constraint(equalToConstant: 24),
            input.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    func zeroHeightView() -> NSView {
        let view = NSView()
        view.fixedHeight(0)
        return view
    }

    func quantityControlRow(minus: NSButton, plus: NSButton) -> NSView {
        let box = NSView()
        box.fixedHeight(28)

        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 6
        surface.layer?.backgroundColor = inputBackgroundColor().cgColor

        let qty = PriceInputTextField(string: "\(orderQty)")
        qty.identifier = NSUserInterfaceItemIdentifier("orderQty")
        qty.delegate = self
        qty.target = self
        qty.action = #selector(ticketInputCommitted(_:))
        qty.onBegin = { [weak self] field in
            self?.beginTicketInput(field)
        }
        qty.onCommit = { [weak self] field in
            guard let self, let id = field.identifier?.rawValue else { return }
            self.activeTicketInput = nil
            self.activeTicketField = nil
            self.commitTicketInput(field, id: id)
        }
        qty.cell = CenteredTextFieldCell(textCell: "\(orderQty)")
        qty.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        qty.textColor = palette.text
        qty.alignment = .center
        qty.isEditable = true
        qty.isSelectable = true
        qty.isBezeled = false
        qty.drawsBackground = false
        qty.wantsLayer = true
        qty.layer?.cornerRadius = 6
        qty.cell?.wraps = false
        qty.cell?.usesSingleLineMode = true
        let symbol = text(selectedSymbol, 8, .medium, palette.muted)

        [minus, plus].forEach {
            $0.fixedHeight(24)
            $0.fixedWidth(28)
        }

        [surface, qty, symbol, minus, plus].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }

        let controlWidth = max(CGFloat(70 + selectedSymbol.count * 8 + String(orderQty).count * 4), 82)
        NSLayoutConstraint.activate([
            surface.centerXAnchor.constraint(equalTo: box.centerXAnchor, constant: -34),
            surface.widthAnchor.constraint(equalToConstant: controlWidth),
            surface.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            surface.heightAnchor.constraint(equalToConstant: 24),

            qty.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            qty.trailingAnchor.constraint(equalTo: symbol.leadingAnchor, constant: -6),
            qty.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            symbol.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            symbol.centerYAnchor.constraint(equalTo: surface.centerYAnchor),

            minus.leadingAnchor.constraint(equalTo: surface.trailingAnchor, constant: 8),
            minus.trailingAnchor.constraint(equalTo: plus.leadingAnchor, constant: -6),
            minus.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            plus.centerYAnchor.constraint(equalTo: surface.centerYAnchor)
        ])

        return box
    }

    func quickQtyRow() -> NSView {
        let box = NSView()
        box.fixedHeight(24)
        let row = hstack(spacing: 7)
        row.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(row)
        for value in [1, 3, 5, 10, 15] {
            let selected = orderQty == value
            let button = PillButton("\(value)", bg: selected ? alpha(palette.text, isDark ? 0.30 : 0.20) : alpha(palette.text, isDark ? 0.08 : 0.07), fg: selected ? palette.text : palette.muted, size: 9)
            button.fixedWidth(28)
            button.fixedHeight(22)
            button.layer?.cornerRadius = 11
            button.target = self
            button.action = #selector(selectQuickQty(_:))
            row.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            row.topAnchor.constraint(equalTo: box.topAnchor),
            row.bottomAnchor.constraint(equalTo: box.bottomAnchor)
        ])
        return box
    }

    func protectionRow() -> NSView {
        let box = NSView()
        box.fixedHeight(88)

        let priceMode = PillButton("Price", bg: bracketMode == "PRICE" ? alpha(palette.blue, isDark ? 0.42 : 0.18) : palette.surface2, fg: bracketMode == "PRICE" ? palette.text : palette.muted, size: 8)
        let ticks = PillButton("Ticks", bg: bracketMode == "TICKS" ? alpha(palette.blue, isDark ? 0.42 : 0.18) : palette.surface2, fg: bracketMode == "TICKS" ? palette.text : palette.muted, size: 8)
        ticks.target = self
        ticks.action = #selector(selectTicksMode)
        priceMode.target = self
        priceMode.action = #selector(selectPriceMode)
        ticks.fixedWidth(48)
        priceMode.fixedWidth(48)
        ticks.fixedHeight(20)
        priceMode.fixedHeight(20)

        let priceProtectionReady = !(quoteSyncing && bracketMode == "PRICE")
        let tp = compactField(bracketMode == "PRICE" ? "TP price" : "TP ticks", bracketValueText(kind: "TP"), id: "bracketTP", enabled: tpEnabled && priceProtectionReady)
        let sl = compactField(bracketMode == "PRICE" ? "SL price" : "SL ticks", bracketValueText(kind: "SL"), id: "bracketSL", enabled: slEnabled && priceProtectionReady)
        let tpCheck = protectionToggle(title: "TP", enabled: tpEnabled, action: #selector(toggleTPProtection))
        let slCheck = protectionToggle(title: "SL", enabled: slEnabled, action: #selector(toggleSLProtection))
        let fieldWidth = bracketInputWidth()

        [priceMode, ticks, tpCheck, slCheck, tp, sl].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }

        NSLayoutConstraint.activate([
            priceMode.centerXAnchor.constraint(equalTo: tp.centerXAnchor),
            priceMode.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            ticks.centerXAnchor.constraint(equalTo: sl.centerXAnchor),
            ticks.centerYAnchor.constraint(equalTo: priceMode.centerYAnchor),

            tpCheck.topAnchor.constraint(equalTo: priceMode.bottomAnchor, constant: 12),
            tpCheck.centerXAnchor.constraint(equalTo: tp.centerXAnchor),
            slCheck.centerXAnchor.constraint(equalTo: sl.centerXAnchor),
            slCheck.centerYAnchor.constraint(equalTo: tpCheck.centerYAnchor),

            tp.topAnchor.constraint(equalTo: tpCheck.bottomAnchor, constant: 6),
            tp.trailingAnchor.constraint(equalTo: box.centerXAnchor, constant: -12),
            tp.widthAnchor.constraint(equalToConstant: fieldWidth),
            sl.leadingAnchor.constraint(equalTo: box.centerXAnchor, constant: 12),
            sl.topAnchor.constraint(equalTo: tp.topAnchor),
            sl.widthAnchor.constraint(equalToConstant: fieldWidth)
        ])

        return box
    }

    func bracketInputWidth() -> CGFloat {
        let longest = max(bracketValueText(kind: "TP").count, bracketValueText(kind: "SL").count)
        let raw = CGFloat(longest * 8 + 22)
        return min(max(raw, bracketMode == "PRICE" ? 86 : 42), bracketMode == "PRICE" ? 96 : 52)
    }

    func protectionToggle(title: String, enabled: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = enabled ? .on : .off
        button.font = NSFont.systemFont(ofSize: 8, weight: .medium)
        button.contentTintColor = enabled ? palette.text : palette.muted
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    @objc func toggleTPProtection() {
        tpEnabled.toggle()
        if bracketMode == "PRICE", tpEnabled {
            tpPriceOverride = isOppositeOpenPositionOrder(side: orderSide) ? defaultPositionProtectionPrice(kind: "TP") : bracketPrice(kind: "TP")
        }
        rebuild(force: true)
    }

    @objc func toggleSLProtection() {
        slEnabled.toggle()
        if bracketMode == "PRICE", slEnabled {
            slPriceOverride = isOppositeOpenPositionOrder(side: orderSide) ? defaultPositionProtectionPrice(kind: "SL") : bracketPrice(kind: "SL")
        }
        rebuild(force: true)
    }

    func bracketValueText(kind: String) -> String {
        if quoteSyncing && bracketMode == "PRICE" {
            return "--"
        }
        if bracketMode == "TICKS" {
            return kind == "TP" ? "\(tpTicks)" : "\(slTicks)"
        }
        if kind == "TP", let value = tpPriceOverride {
            return number2(value)
        }
        if kind == "SL", let value = slPriceOverride {
            return number2(value)
        }
        if isOppositeOpenPositionOrder(side: orderSide) {
            return number2(positionProtectionPrice(kind: kind))
        }
        return number2(bracketPrice(kind: kind))
    }

    func bidPrice() -> Double {
        return displayBidPrice() ?? max(0, price - contracts[selectedSymbol]!.tick)
    }

    func askPrice() -> Double {
        return displayAskPrice() ?? price + contracts[selectedSymbol]!.tick
    }

    func displayBidPrice() -> Double? {
        if quoteSyncing { return nil }
        if let bestBidPrice {
            return bestBidPrice
        }
        return marketStatusText == "Market Live" ? nil : max(0, price - contracts[selectedSymbol]!.tick)
    }

    func displayAskPrice() -> Double? {
        if quoteSyncing { return nil }
        if let bestAskPrice {
            return bestAskPrice
        }
        return marketStatusText == "Market Live" ? nil : price + contracts[selectedSymbol]!.tick
    }

    func midPrice() -> Double? {
        guard let bid = displayBidPrice(), let ask = displayAskPrice() else { return nil }
        return (bid + ask) / 2
    }

    func marketEntryPrice() -> Double {
        return orderSide == "BUY" ? askPrice() : bidPrice()
    }

    func orderEntryPrice() -> Double {
        if orderType == "LIMIT", let value = limitPriceOverride {
            return value
        }
        return marketEntryPrice()
    }

    func resetBracketPriceOverrides() {
        guard !quoteSyncing else {
            tpPriceOverride = nil
            slPriceOverride = nil
            return
        }
        if isOppositeOpenPositionOrder(side: orderSide) {
            tpPriceOverride = defaultPositionProtectionPrice(kind: "TP")
            slPriceOverride = defaultPositionProtectionPrice(kind: "SL")
        } else {
            tpPriceOverride = bracketPrice(kind: "TP")
            slPriceOverride = bracketPrice(kind: "SL")
        }
    }

    func bracketPrice(kind: String) -> Double {
        let c = contracts[selectedSymbol]!
        let tpOffset = Double(tpTicks) * c.tick
        let slOffset = Double(slTicks) * c.tick
        let entry = orderEntryPrice()
        if kind == "TP" {
            return orderSide == "BUY" ? entry + tpOffset : entry - tpOffset
        }
        return orderSide == "BUY" ? entry - slOffset : entry + slOffset
    }

    func parsedNumber(_ text: String) -> Double? {
        return extractNumber(text)
    }

    func normalizedPrice(_ value: Double) -> Double {
        let tick = contracts[selectedSymbol]!.tick
        return (value / tick).rounded() * tick
    }

    func isTickAligned(_ value: Double) -> Bool {
        abs(value - normalizedPrice(value)) < 0.000001
    }

    func isQuoteFresh(maxAge: TimeInterval = 5) -> Bool {
        guard marketStatusText == "Market Live",
              let lastQuoteAt,
              displayBidPrice() != nil,
              displayAskPrice() != nil else { return false }
        return Date().timeIntervalSince(lastQuoteAt) <= maxAge
    }

    func jsonText(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "\(object)"
        }
        return text
    }

    func setEvent(_ message: String, color: NSColor, detail: String? = nil) {
        eventLabel?.stringValue = message
        eventLabel?.textColor = color
        eventLabel?.toolTip = detail
    }

    func orderToastTitle(side: String) -> String {
        let sign = side == "BUY" ? "+" : "-"
        return "\(sign)\(orderQty) \(selectedSymbol) \(side)"
    }

    func showTradeToast(_ title: String, subtitle: String, color: NSColor) {
        playToastSound(title: title, subtitle: subtitle)

        guard let parent = window.contentView else { return }

        // Create toast view (same premium style as before)
        let width: CGFloat = 205
        let height: CGFloat = 52
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.backgroundColor = alpha(palette.surface2, 0.98).cgColor
        content.layer?.borderWidth = 1.5
        content.layer?.borderColor = alpha(color, 0.85).cgColor
        content.shadow = NSShadow()
        content.shadow?.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.5 : 0.25)
        content.shadow?.shadowBlurRadius = 20
        content.shadow?.shadowOffset = NSSize(width: 0, height: -4)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleNone
        if let symbol = toastSymbolName(for: title) {
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                iconView.image = img
                iconView.contentTintColor = color
            }
        }

        let titleLabel = text(title, 12, .semibold, palette.text)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Make the +/- qty part bolder for better readability (e.g. "+1 NQ Filled")
        if let range = title.range(of: "^[+-]\\d+\\s+[^\\s]+", options: .regularExpression) {
            let attr = NSMutableAttributedString(string: title)
            let nsRange = NSRange(range, in: title)
            attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: nsRange)
            titleLabel.attributedStringValue = attr
        }

        let subLabel = text(subtitle, 9, .regular, palette.muted)
        subLabel.alignment = .left
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        [iconView, titleLabel, subLabel].forEach { content.addSubview($0) }
        parent.addSubview(content, positioned: .above, relativeTo: nil)

        // Internal layout constraints for icon + text inside the toast content
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 9),

            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2)
        ])

        // Initial off-screen-ish for animation (slightly above final position)
        content.alphaValue = 0
        let initialX = parent.bounds.width - width - 10
        let initialY = parent.bounds.height - 55 - 15  // from top
        content.frame = NSRect(x: initialX, y: initialY, width: width, height: height)

        // Add to stack (newest at front)
        toastStack.insert(content, at: 0)

        // Limit to 3, remove oldest with fade
        if toastStack.count > 3 {
            let oldest = toastStack.removeLast()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                oldest.animator().alphaValue = 0
            } completionHandler: {
                oldest.removeFromSuperview()
            }
        }

        layoutToasts(animated: true)

        // Per-toast dismiss
        let duration: TimeInterval = title.lowercased().contains("filled") ? 2.6 : 2.0
        let item = DispatchWorkItem { [weak self, weak content] in
            guard let self = self, let c = content else { return }
            if let idx = self.toastStack.firstIndex(where: { $0 === c }) {
                self.toastStack.remove(at: idx)
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                c.animator().alphaValue = 0
            } completionHandler: {
                c.removeFromSuperview()
                self.layoutToasts(animated: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)

        // Flash PnL on fills
        if title.lowercased().contains("filled") {
            let isPositive = title.contains("+")
            flashPnLOnFill(isPositive: isPositive)
        }
    }

    func layoutToasts(animated: Bool = true) {
        guard let parent = window.contentView else { return }
        let toastWidth: CGFloat = 205
        let toastHeight: CGFloat = 52
        let rightMargin: CGFloat = 10
        let startFromTop: CGFloat = 55  // distance from top of window (to sit below header)
        let spacing: CGFloat = 4

        // AppKit y=0 is bottom, so compute from top
        var currentTop = startFromTop
        for toast in toastStack {
            let x = parent.bounds.width - toastWidth - rightMargin
            let y = parent.bounds.height - currentTop - toastHeight
            let targetFrame = NSRect(x: x, y: y, width: toastWidth, height: toastHeight)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    toast.animator().frame = targetFrame
                    toast.animator().alphaValue = 1.0
                }
            } else {
                toast.frame = targetFrame
                toast.alphaValue = 1.0
            }
            // Ensure subviews (labels with constraints) layout correctly after frame change
            toast.layoutSubtreeIfNeeded()
            currentTop += toastHeight + spacing
        }
    }

    func flashPnLOnFill(isPositive: Bool) {
        guard let label = pnlLabel else { return }
        let flashColor = isPositive ? NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.4, alpha: 1) : NSColor(calibratedRed: 1.0, green: 0.3, blue: 0.3, alpha: 1)
        let originalColor = label.textColor

        // Brief color flash + scale
        label.wantsLayer = true
        let originalTransform = label.layer?.transform ?? CATransform3DIdentity

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            label.animator().textColor = flashColor
            label.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            label.layer?.transform = CATransform3DMakeScale(1.12, 1.12, 1)
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                label.animator().textColor = originalColor
                label.layer?.transform = originalTransform
            }
        }
    }

    private func toastSymbolName(for title: String) -> String? {
        let lower = title.lowercased()
        if lower.contains("filled") { return "checkmark.circle.fill" }
        if lower.contains("canceled") || lower.contains("cancel") { return "xmark.circle.fill" }
        if lower.contains("sent") || lower.contains("accepted") { return "arrow.up.circle.fill" }
        if lower.contains("modify") { return "pencil.circle.fill" }
        if lower.contains("protection") { return "shield.lefthalf.filled" }
        if lower.contains("flatten") { return "arrow.down.circle.fill" }
        if lower.contains("expired") || lower.contains("rejected") { return "exclamationmark.triangle.fill" }
        return "info.circle.fill"
    }

    private func playToastSound(title: String, subtitle: String? = nil) {
        // Sounds now prefer bundled Resources/ (shipped with .app via build_app.sh).
        // User overrides can live in Application Support without requiring protected folder permission.
        // - TP.caf : only for TP (take-profit protection) fills (type 1 protection orders)
        // - Order.caf : everything else (market fills, regular limit fills, SL fills, sent/cancel/reject etc.)
        // We check both title and subtitle because entry "accepted" toasts use orderToastTitle("+1 NQ BUY") in title + "TopstepX accepted #id" in subtitle.
        let combined = (title + " " + (subtitle ?? "")).lowercased()

        // TP fill detection (only set for protection TP fills in the realtime order path, or closing LMT opposite side for bracket TPs).
        // These toasts have "Filled" in title.
        if combined.contains("filled") && lastProtectionFillWasTP {
            lastProtectionFillWasTP = false
            playSoundFile("TP")
            return
        }

        // Trigger sound for market quick entries, limit entries, fills, SL, protection TP/SL sent, cancels, etc.
        // "accepted" and "sent" often live in the subtitle for placeOrder success path.
        let shouldPlay = combined.contains("filled")
            || combined.contains("rejected") || combined.contains("expired")
            || combined.contains("canceled")
            || combined.contains("sent") || combined.contains("accepted")
            || combined.contains("modify") || combined.contains("protection") || combined.contains("flatten")
            || combined.contains("open") || combined.contains("pending")   // realtime status 1/6 for some orders

        if shouldPlay {
            playSoundFile("Order")
        }
    }

    // Helper: prefer bundle Resources/*.caf (clean for distribution), then Application Support.
    private func soundURL(for kind: String) -> URL? {
        let name = (kind == "TP") ? "TP" : "Order"
        if let bundled = Bundle.main.url(forResource: name, withExtension: "caf") {
            return bundled
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = appSupport
                .appendingPathComponent("TopstepXFloatPanel", isDirectory: true)
                .appendingPathComponent(name + ".caf")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func playSoundFile(_ kind: String) {
        guard let s = ensureSound(kind) else { return }
        s.volume = 1.0
        s.stop()
        s.currentTime = 0
        s.play()
    }

    private func ensureSound(_ kind: String) -> NSSound? {
        if kind == "TP" {
            if tpSound == nil {
                if let url = soundURL(for: "TP"),
                   let s = NSSound(contentsOf: url, byReference: true) {
                    s.volume = 1.0
                    tpSound = s
                }
            }
            if tpSound == nil && !customSoundsLoadErrorReported {
                customSoundsLoadErrorReported = true
                DispatchQueue.main.async { [weak self] in
                    self?.setEvent("Sound files missing: put TP.caf and Order.caf in Resources/ or Application Support", color: NSColor.systemOrange)
                }
            }
            return tpSound
        } else {
            if orderSound == nil {
                if let url = soundURL(for: "Order"),
                   let s = NSSound(contentsOf: url, byReference: true) {
                    s.volume = 1.0
                    orderSound = s
                }
            }
            if orderSound == nil && !customSoundsLoadErrorReported {
                customSoundsLoadErrorReported = true
                DispatchQueue.main.async { [weak self] in
                    self?.setEvent("Sound files missing: put TP.caf and Order.caf in Resources/ or Application Support", color: NSColor.systemOrange)
                }
            }
            return orderSound
        }
    }

    func shortTradeError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("instrument is not in an active trading status") {
            return "Instrument inactive"
        }
        if lower.contains("invalid stop loss ticks") {
            return "Invalid SL ticks"
        }
        if lower.contains("brackets cannot be used") {
            return "Bracket mode mismatch"
        }
        if message.count > 48 {
            return String(message.prefix(45)) + "..."
        }
        return message
    }

    func validBracketPrice(kind: String, value: Double) -> Bool {
        if isOppositeOpenPositionOrder(side: orderSide) {
            return (try? validatePositionProtectionPrice(kind: kind, side: orderSide, price: value)) != nil
        }
        if kind == "TP" {
            return orderSide == "BUY" ? value > orderEntryPrice() : value < orderEntryPrice()
        }
        return orderSide == "BUY" ? value < orderEntryPrice() : value > orderEntryPrice()
    }

    func ticksFromPrice(kind: String, value: Double) -> Int {
        let c = contracts[selectedSymbol]!
        if isOppositeOpenPositionOrder(side: orderSide),
           let avg = numberValue(activePosition()?["averagePrice"]) {
            let distance: Double
            if positionSideText() == "SHORT" {
                distance = kind == "TP" ? avg - value : value - avg
            } else {
                distance = kind == "TP" ? value - avg : avg - value
            }
            return max(0, Int((distance / c.tick).rounded()))
        }
        let entry = orderEntryPrice()
        let distance: Double
        if kind == "TP" {
            distance = orderSide == "BUY" ? value - entry : entry - value
        } else {
            distance = orderSide == "BUY" ? entry - value : value - entry
        }
        return max(0, Int((distance / c.tick).rounded()))
    }

    func equalSplitRow(_ left: NSView, _ right: NSView, height: CGFloat, spacing: CGFloat = 2) -> NSView {
        let row = NSView()
        [left, right].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            left.topAnchor.constraint(equalTo: row.topAnchor),
            left.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            left.trailingAnchor.constraint(equalTo: row.centerXAnchor, constant: -spacing / 2),
            right.leadingAnchor.constraint(equalTo: row.centerXAnchor, constant: spacing / 2),
            right.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            right.topAnchor.constraint(equalTo: row.topAnchor),
            right.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: height)
        ])
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }

    func limitPriceRow() -> NSView {
        let box = NSView()
        box.fixedHeight(50)
        let priceText = quoteSyncing ? "--" : number2(orderEntryPrice())
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: adaptiveSize(for: priceText, base: 16, min: 13), weight: .semibold)
        let inputWidth = limitPriceInputWidth(priceText, font: priceFont)

        let title = text(editingOrderId == nil ? "Limit Price" : "Order Price", 9, .medium, palette.muted)
        title.alignment = .center

        let control = NSView()
        control.wantsLayer = true
        control.layer?.cornerRadius = 6
        control.layer?.backgroundColor = inputBackgroundColor().cgColor
        control.layer?.borderWidth = 1
        control.layer?.borderColor = palette.border.cgColor

        let input = PriceInputTextField(string: priceText)
        input.identifier = NSUserInterfaceItemIdentifier("limitPrice")
        input.delegate = self
        input.target = self
        input.action = #selector(ticketInputCommitted(_:))
        input.onBegin = { [weak self] field in
            self?.beginTicketInput(field)
        }
        input.onCommit = { [weak self] field in
            guard let self, let id = field.identifier?.rawValue else { return }
            self.activeTicketInput = nil
            self.activeTicketField = nil
            self.commitTicketInput(field, id: id)
        }
        input.cell = CenteredTextFieldCell(textCell: input.stringValue)
        input.font = priceFont
        input.textColor = quoteSyncing ? alpha(palette.muted, 0.70) : palette.text
        input.alignment = .center
        input.isEditable = !quoteSyncing
        input.isSelectable = !quoteSyncing
        input.isEnabled = !quoteSyncing
        input.backgroundColor = NSColor.clear
        input.drawsBackground = false
        input.isBezeled = false
        input.wantsLayer = true
        input.layer?.cornerRadius = 6
        input.cell?.wraps = false
        input.cell?.usesSingleLineMode = true
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: ""))
        input.menu = menu

        let up = PillButton("▲", bg: palette.surface2, fg: palette.text, size: 8)
        let down = PillButton("▼", bg: palette.surface2, fg: palette.text, size: 8)
        up.target = self
        up.action = #selector(incrementLimitPrice)
        down.target = self
        down.action = #selector(decrementLimitPrice)
        up.fixedWidth(24)
        down.fixedWidth(24)
        up.isEnabled = !quoteSyncing
        down.isEnabled = !quoteSyncing

        let stepper = vstack(spacing: 2)
        stepper.addArrangedSubview(up)
        stepper.addArrangedSubview(down)

        let dividerLine = NSView()
        dividerLine.wantsLayer = true
        dividerLine.layer?.backgroundColor = palette.border.cgColor

        [title, control].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }
        [input, dividerLine, stepper].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            control.addSubview($0)
        }

        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            title.topAnchor.constraint(equalTo: box.topAnchor),

            control.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            control.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            control.widthAnchor.constraint(equalToConstant: inputWidth + 48),
            control.heightAnchor.constraint(equalToConstant: 34),
            control.bottomAnchor.constraint(equalTo: box.bottomAnchor),

            input.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 8),
            input.topAnchor.constraint(equalTo: control.topAnchor),
            input.bottomAnchor.constraint(equalTo: control.bottomAnchor),
            input.widthAnchor.constraint(equalToConstant: inputWidth),

            dividerLine.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 5),
            dividerLine.widthAnchor.constraint(equalToConstant: 1),
            dividerLine.topAnchor.constraint(equalTo: control.topAnchor, constant: 5),
            dividerLine.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -5),

            stepper.leadingAnchor.constraint(equalTo: dividerLine.trailingAnchor, constant: 5),
            stepper.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -5),
            stepper.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            up.heightAnchor.constraint(equalToConstant: 14),
            down.heightAnchor.constraint(equalToConstant: 14)
        ])

        return box
    }

    func limitPriceInputWidth(_ value: String, font: NSFont) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + 22), 106), 136)
    }

    func accountPopupWidth(_ value: String, font: NSFont) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + 32), 96), 138)
    }

    func titlesForAccountPopup(_ popup: NSPopUpButton) -> [String] {
        return popup.itemArray.map { $0.title }
    }

    func accountMenuDisplayTitle(_ value: String) -> String {
        let compact = value.replacingOccurrences(of: "-219616-", with: "-")
        guard compact.count > 25 else { return compact }
        return String(compact.prefix(21)) + "..."
    }

    func styleAccountPopupMenu(_ popup: NSPopUpButton, titles: [String], selectedIndex: Int) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraph
        ]
        for (index, item) in popup.itemArray.enumerated() {
            let baseTitle = titles.indices.contains(index) ? titles[index] : item.title
            let check = index == selectedIndex ? "✓ " : "  "
            item.state = .off
            item.attributedTitle = NSAttributedString(string: check + accountMenuDisplayTitle(baseTitle), attributes: attrs)
        }
    }

    func stylePopup(_ popup: NSPopUpButton) {
        popup.isBordered = false
        popup.contentTintColor = palette.text
        popup.wantsLayer = true
        popup.layer?.cornerRadius = 6
        popup.layer?.backgroundColor = palette.surface2.cgColor
    }

    func hstackText(_ items: [(String, NSColor)]) -> NSStackView {
        let stack = hstack(spacing: 6)
        stack.addArrangedSubview(spacer())
        for (value, color) in items {
            let isNumeric = value.contains("$") || value.contains(":") || value == "|"
            stack.addArrangedSubview(isNumeric ? digit(value, 9, .semibold, color) : text(value, 9, .regular, color))
        }
        stack.addArrangedSubview(spacer())
        return stack
    }

    func ticketRiskSummary() -> NSView {
        let box = NSView()

        let left = hstack(spacing: 5)
        let riskValid = slEnabled && effectiveSLTicks() > 0
        left.addArrangedSubview(text("Risk", 10, .regular, palette.muted))
        left.addArrangedSubview(adaptiveDigit(riskSummaryText(), base: 10, min: 8, weight: .semibold, color: riskValid ? palette.text : palette.orange, width: 86, alignment: .left))

        let mid = text("|", 10, .regular, palette.muted)
        mid.alignment = .center

        let right = hstack(spacing: 5)
        right.addArrangedSubview(text("R:R", 10, .regular, palette.muted))
        right.addArrangedSubview(adaptiveDigit("\(rrText())", base: 10, min: 8, weight: .semibold, color: tpEnabled && slEnabled && effectiveTPTicks() > 0 ? palette.text : palette.muted, width: 58, alignment: .right))

        [left, mid, right].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview($0)
        }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            mid.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            mid.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            right.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    func estimatedRiskValue() -> Double {
        let c = contracts[selectedSymbol]!
        return Double(orderQty * effectiveSLTicks()) * c.tickValue
    }

    func estimatedRiskText() -> String {
        guard effectiveSLTicks() > 0 else { return "Invalid" }
        return money(estimatedRiskValue())
    }

    func riskSummaryText() -> String {
        guard slEnabled else { return "No SL" }
        return "\(estimatedRiskText()) / \(effectiveSLTicks())t"
    }

    func rrText() -> String {
        guard tpEnabled, slEnabled else { return "--" }
        let sl = effectiveSLTicks()
        let tp = effectiveTPTicks()
        guard sl > 0, tp > 0 else { return "--" }
        let rr = Double(tp) / Double(sl)
        return "\(String(format: "%.2f", rr)) : 1"
    }

    func beginTicketInput(_ field: NSTextField) {
        guard let id = field.identifier?.rawValue,
              isTicketInputId(id) else { return }
        activeTicketInput = id
        activeTicketField = field
    }

    func isTicketInputId(_ id: String) -> Bool {
        return id == "limitPrice" || id == "bracketTP" || id == "bracketSL" || id == "orderQty"
    }

    func isTicketInputActivelyEditing() -> Bool {
        guard let editor = window?.firstResponder as? NSTextView,
              let field = editor.delegate as? NSTextField,
              let id = field.identifier?.rawValue else { return false }
        return isTicketInputId(id)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let id = field.identifier?.rawValue,
              isTicketInputId(id) else { return }
        activeTicketInput = id
        activeTicketField = field
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let id = field.identifier?.rawValue,
              isTicketInputId(id) else { return }
        let allowed = CharacterSet(charactersIn: "0123456789,.-")
        guard field.stringValue.rangeOfCharacter(from: allowed.inverted) != nil,
              let value = parsedNumber(field.stringValue) else { return }
        field.stringValue = id == "orderQty"
            ? "\(clampedOrderQty(Int(value.rounded())))"
            : (id == "limitPrice" || bracketMode == "PRICE" ? number2(normalizedPrice(value)) : "\(max(1, Int(value.rounded())))")
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field else { return }
            self.activeTicketInput = nil
            self.activeTicketField = nil
            self.commitTicketInput(field, id: id)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField,
              let id = field.identifier?.rawValue,
              isTicketInputId(id) else { return }
        activeTicketInput = nil
        activeTicketField = nil
        commitTicketInput(field, id: id)
    }

    @objc func ticketInputCommitted(_ sender: NSTextField) {
        guard let id = sender.identifier?.rawValue,
              isTicketInputId(id) else { return }
        activeTicketInput = nil
        activeTicketField = nil
        commitTicketInput(sender, id: id)
    }

    func currentTicketText(_ field: NSTextField) -> String {
        return field.currentEditor()?.string ?? field.stringValue
    }

    func commitTicketInput(_ field: NSTextField, id: String) {
        guard isTicketInputId(id) else { return }
        if id == "orderQty" {
            guard let value = parsedNumber(currentTicketText(field)) else {
                rebuild(force: true)
                return
            }
            orderQty = clampedOrderQty(Int(value.rounded()))
            rebuild(force: true)
            return
        }
        if id == "bracketTP", !tpEnabled {
            rebuild(force: true)
            return
        }
        if id == "bracketSL", !slEnabled {
            rebuild(force: true)
            return
        }
        if id == "limitPrice" {
            guard let value = parsedNumber(currentTicketText(field)) else {
                rebuild(force: true)
                return
            }
            limitPriceOverride = normalizedPrice(value)
            if bracketMode == "PRICE" {
                resetBracketPriceOverrides()
            }
            rebuild(force: true)
            return
        }
        if bracketMode == "PRICE" {
            guard let value = parsedNumber(currentTicketText(field)) else {
                rebuild(force: true)
                return
            }
            let normalized = normalizedPrice(value)
            let kind = id == "bracketTP" ? "TP" : "SL"
            guard validBracketPrice(kind: kind, value: normalized) else {
                eventLabel?.stringValue = "Last: \(kind) price is on the wrong side"
                eventLabel?.textColor = palette.orange
                rebuild(force: true)
                return
            }
            if id == "bracketTP" {
                tpPriceOverride = normalized
                tpTicks = max(1, ticksFromPrice(kind: "TP", value: normalized))
            } else if id == "bracketSL" {
                slPriceOverride = normalized
                slTicks = max(1, ticksFromPrice(kind: "SL", value: normalized))
            }
        } else {
            guard let parsed = parsedNumber(currentTicketText(field)) else {
                rebuild(force: true)
                return
            }
            let value = Int(parsed.rounded())
            if id == "bracketTP" {
                tpTicks = max(1, value)
                tpPriceOverride = nil
            } else if id == "bracketSL" {
                slTicks = max(1, value)
                slPriceOverride = nil
            }
        }
        rebuild(force: true)
    }

    func effectiveTPTicks() -> Int {
        if bracketMode == "PRICE", let value = tpPriceOverride {
            return ticksFromPrice(kind: "TP", value: value)
        }
        return tpTicks
    }

    func effectiveSLTicks() -> Int {
        if bracketMode == "PRICE", let value = slPriceOverride {
            return ticksFromPrice(kind: "SL", value: value)
        }
        return slTicks
    }

    func fixedScaleLabels(left: String, middle: String, right: String) -> NSView {
        let view = NSView()
        let leftLabel = text(left, 9, .regular, palette.muted)
        let middleLabel = text(middle, 9, .regular, palette.muted)
        let rightLabel = text(right, 9, .regular, palette.muted)
        [leftLabel, middleLabel, rightLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftLabel.topAnchor.constraint(equalTo: view.topAnchor),
            leftLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            middleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            middleLabel.centerYAnchor.constraint(equalTo: leftLabel.centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightLabel.centerYAnchor.constraint(equalTo: leftLabel.centerYAnchor)
        ])
        view.fixedHeight(12)
        return view
    }

    func hstack(spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }

    func vstack(spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .width
        stack.distribution = .fill
        return stack
    }

    func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func divider() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.border.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    func shortDivider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.border.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return view
    }

    func card(_ content: NSView, pad: CGFloat = 6, color: NSColor? = nil) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = (color ?? palette.surface).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = palette.border.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad)
        ])
        return view
    }

    func alpha(_ color: NSColor, _ value: CGFloat) -> NSColor {
        return color.withAlphaComponent(value)
    }

    func clearSurface() -> NSColor {
        return isDark ? NSColor(calibratedWhite: 0, alpha: 0.02) : NSColor(calibratedWhite: 1, alpha: 0.25)
    }

    func inputBackgroundColor() -> NSColor {
        return isDark
            ? NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.985, alpha: 1)
    }

    func readOnlyActionColor(_ color: NSColor) -> NSColor {
        return isDark ? alpha(color, 0.45) : alpha(color, 0.22)
    }

    func readOnlyActionTextColor() -> NSColor {
        return isDark ? NSColor.white : palette.text
    }
}

let app = NSApplication.shared
let delegate = PanelController()
app.delegate = delegate

// Default to regular app so it appears in Dock as running with standard right-click Quit menu.
// Status item (top menu bar) still provides quick Quit for convenience with the floating panel.
app.setActivationPolicy(.regular)
app.run()
