import AppKit
import Foundation

// MARK: - Data Models

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

// MARK: - ProjectX API Client

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

// MARK: - Realtime Client

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

let supportedSymbols: [String] = ["MNQ", "NQ", "ES", "MES", "GC", "MGC"]  // curated order, not from API list-all

// MARK: - Theme / Base UI

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
    bg: NSColor(calibratedRed: 0.043, green: 0.059, blue: 0.078, alpha: 1),
    surface: NSColor(calibratedRed: 0.067, green: 0.094, blue: 0.125, alpha: 1),
    surface2: NSColor(calibratedRed: 0.090, green: 0.129, blue: 0.169, alpha: 1),
    border: NSColor(calibratedRed: 0.180, green: 0.216, blue: 0.267, alpha: 1),
    text: NSColor(calibratedRed: 0.929, green: 0.929, blue: 0.929, alpha: 1),
    muted: NSColor(calibratedRed: 0.627, green: 0.627, blue: 0.627, alpha: 1),
    green: NSColor(calibratedRed: 0.000, green: 0.792, blue: 0.314, alpha: 1),
    red: NSColor(calibratedRed: 1.000, green: 0.337, blue: 0.373, alpha: 1),
    orange: NSColor(calibratedRed: 1.000, green: 0.682, blue: 0.000, alpha: 1),
    blue: NSColor(calibratedRed: 0.278, green: 0.659, blue: 1.000, alpha: 1)
)

let lightPalette = Palette(
    bg: NSColor(calibratedRed: 0.969, green: 0.973, blue: 0.980, alpha: 1),
    surface: NSColor(calibratedRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),
    surface2: NSColor(calibratedRed: 0.949, green: 0.961, blue: 0.973, alpha: 1),
    border: NSColor(calibratedRed: 0.847, green: 0.871, blue: 0.910, alpha: 1),
    text: NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 1),
    muted: NSColor(calibratedRed: 0.490, green: 0.490, blue: 0.490, alpha: 1),
    green: NSColor(calibratedRed: 0.157, green: 0.663, blue: 0.282, alpha: 1),
    red: NSColor(calibratedRed: 0.918, green: 0.000, blue: 0.114, alpha: 1),
    orange: NSColor(calibratedRed: 1.000, green: 0.576, blue: 0.000, alpha: 1),
    blue: NSColor(calibratedRed: 0.000, green: 0.420, blue: 1.000, alpha: 1)
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
