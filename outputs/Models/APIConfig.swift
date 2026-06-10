import Foundation

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
