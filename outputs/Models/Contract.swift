import Foundation

struct Contract {
    let price: Double
    let tick: Double
    let tickValue: Double
    let id: String
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

let supportedSymbols: [String] = ["NQ", "ES", "MNQ", "MES", "GC", "MGC"]  // curated order, not from API list-all
