import Foundation

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
