import AppKit
import Foundation

extension PanelController {

    // MARK: - Working Orders Display Helpers

    func orderColumn(_ value: String, width: CGFloat, color: NSColor, weight: NSFont.Weight, size: CGFloat = 8, align: NSTextAlignment = .left, digitFont: Bool = false) -> NSTextField {
        let label = text(value, size, weight, color)
        label.alignment = align
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = digitFont ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        label.fixedWidth(width)
        return label
    }

    func orderRowButton(_ title: String, color: NSColor, action: Selector, order: [String: Any]) -> NSButton {
        let button = PillButton(title, bg: alpha(color, isDark ? 0.13 : 0.10), fg: color, size: 8)
        button.fixedWidth(16)
        button.fixedHeight(16)
        button.layer?.cornerRadius = 8
        button.target = self
        button.action = action
        button.tag = intValue(order["id"]) ?? 0
        return button
    }

    func riskActionButton(_ title: String, color: NSColor, active: Bool) -> NSButton {
        let fg = active ? color : palette.muted
        let button = PillButton(title, bg: active ? alpha(color, 0.10) : alpha(palette.text, isDark ? 0.04 : 0.08), fg: fg, size: 9, hoverable: active)
        button.fixedHeight(24)
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        button.layer?.borderColor = alpha(fg, active ? 0.85 : 0.35).cgColor
        button.isEnabled = active
        button.captureBaseBorder()
        return button
    }

}

extension PanelController {

    // MARK: - Working Orders State

    func workingOrders() -> [[String: Any]] {
        var byId: [Int: [String: Any]] = [:]
        for order in lastSnapshot?.openOrders ?? [] {
            guard let id = intValue(order["id"]),
                  !realtimeClosedOrderIds.contains(id) else { continue }
            byId[id] = order
        }
        for (id, order) in realtimeOrders {
            byId[id] = order
        }
        let source = Array(byId.values)
        return source.sorted {
            (intValue($0["id"]) ?? 0) < (intValue($1["id"]) ?? 0)
        }
    }

    func orderDataSourceText() -> String {
        return hasRealtimeOrderState ? "Stream" : "REST snapshot"
    }

    func shortOrderIdText(_ order: [String: Any]) -> String {
        guard let id = intValue(order["id"]) else { return "--" }
        let raw = "\(id)"
        return "#\(raw.count > 7 ? String(raw.suffix(7)) : raw)"
    }

    func orderSideText(_ order: [String: Any]) -> String {
        guard let side = intValue(order["side"]) else { return "--" }
        return side == 0 ? "BUY" : "SELL"
    }

    func orderCompactTypeText(_ order: [String: Any]) -> String {
        switch intValue(order["type"]) {
        case 1: return "LMT"
        case 2: return "MKT"
        case 3: return "STP-L"
        case 4: return "STP"
        case 5: return "TRL"
        case 6: return "BID"
        case 7: return "ASK"
        default: return "ORD"
        }
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

    func orderDisplayPriceText(_ order: [String: Any]) -> String {
        if let p = numberValue(order["limitPrice"]) ?? numberValue(order["stopPrice"]) ?? numberValue(order["trailPrice"]) {
            return number2(p)
        }
        return "MKT"
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

}
