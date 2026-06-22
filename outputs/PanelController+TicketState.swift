import AppKit
import Foundation

extension PanelController {

    // MARK: - Ticket Validation

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

}

extension PanelController {

    // MARK: - Ticket Misc UI

    func limitPriceRow() -> NSView {
        return LimitPriceRowView(owner: self)
    }

    func limitPriceInputWidth(_ value: String, font: NSFont) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + 18), 92), 110)
    }

    func accountPopupWidth(_ value: String, font: NSFont) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth + 32), 104), 138)
    }

    func stylePopup(_ popup: NSPopUpButton) {
        popup.isBordered = false
        popup.contentTintColor = palette.text
        popup.wantsLayer = true
        popup.layer?.cornerRadius = 8
        popup.layer?.borderWidth = 1
        let normalBg = alpha(palette.surface2, isDark ? 0.70 : 0.92)
        let hoverBg = alpha(palette.surface2, isDark ? 0.98 : 1.0)
        let normalBorder = alpha(palette.border, isDark ? 0.20 : 0.28)
        let hoverBorder = alpha(palette.blue, isDark ? 0.42 : 0.34)
        popup.layer?.backgroundColor = normalBg.cgColor
        popup.layer?.borderColor = normalBorder.cgColor
        if let hoverPopup = popup as? HoverPopUpButton {
            hoverPopup.configureHover(
                normalBg: normalBg,
                hoverBg: hoverBg,
                normalBorder: normalBorder,
                hoverBorder: hoverBorder
            )
        }
    }

}

extension PanelController {

    // MARK: - Ticket Risk Summary

    func ticketRiskSummary() -> NSView {
        return TicketRiskSummaryView(owner: self)
    }

    func summaryAmountText(value: Double, ticks: Int, sign: String) -> String {
        let absValue = abs(value)
        let amount = "\(sign)$\(String(format: "%.0f", absValue))"
        if absValue >= 10_000 {
            return amount
        }
        return "\(amount)/\(ticks)t"
    }

    func summarySignedAmountText(value: Double, ticks: Int) -> String {
        let sign = value >= 0 ? "+" : "-"
        return summaryAmountText(value: value, ticks: ticks, sign: sign)
    }

    func estimatedRiskValue() -> Double {
        let c = contracts[selectedSymbol]!
        return Double(orderQty * effectiveSLTicks()) * c.tickValue
    }

    func estimatedTargetValue() -> Double {
        let c = contracts[selectedSymbol]!
        return Double(orderQty * effectiveTPTicks()) * c.tickValue
    }

    func protectionDisplayActive(kind: String) -> Bool {
        if kind == "TP" {
            return tpEnabled || officialProtectionPrice(kind: "TP") != nil
        }
        return slEnabled || officialProtectionPrice(kind: "SL") != nil
    }

    func protectionDisplayTicks(kind: String) -> Int {
        if kind == "TP", tpEnabled {
            return effectiveTPTicks()
        }
        if kind == "SL", slEnabled {
            return effectiveSLTicks()
        }
        guard let price = officialProtectionPrice(kind: kind) else {
            return kind == "TP" ? effectiveTPTicks() : effectiveSLTicks()
        }
        return ticksFromPrice(kind: kind, value: price)
    }

    func protectionDisplayAmount(kind: String) -> Double {
        let spec = contractSpec(for: activePosition()?["contractId"] as? String) ?? (contracts[selectedSymbol]!.tick, contracts[selectedSymbol]!.tickValue)
        return Double(protectionDisplayQty(kind: kind) * protectionDisplayTicks(kind: kind)) * spec.1
    }

    func protectionDisplaySignedAmount(kind: String) -> Double {
        guard let position = activePosition(),
              let avg = numberValue(position["averagePrice"]),
              let price = protectionDisplayPrice(kind: kind) else {
            return kind == "TP" ? protectionDisplayAmount(kind: kind) : -protectionDisplayAmount(kind: kind)
        }
        let spec = contractSpec(for: position["contractId"] as? String) ?? (contracts[selectedSymbol]!.tick, contracts[selectedSymbol]!.tickValue)
        let qty = protectionDisplayQty(kind: kind)
        let ticks: Int
        if positionSideText() == "SHORT" {
            ticks = Int(((avg - price) / spec.0).rounded())
        } else {
            ticks = Int(((price - avg) / spec.0).rounded())
        }
        return Double(qty * ticks) * spec.1
    }

    func protectionDisplayPrice(kind: String) -> Double? {
        if let official = officialProtectionPrice(kind: kind) {
            return official
        }
        if kind == "TP", tpEnabled {
            return bracketMode == "PRICE" ? tpPriceOverride ?? positionProtectionPrice(kind: "TP") : bracketPrice(kind: "TP")
        }
        if kind == "SL", slEnabled {
            return bracketMode == "PRICE" ? slPriceOverride ?? positionProtectionPrice(kind: "SL") : bracketPrice(kind: "SL")
        }
        return nil
    }

    func protectionDisplayQty(kind: String) -> Int {
        if let order = officialProtectionOrder(kind: kind),
           let size = intValue(order["size"]) {
            return max(1, abs(size))
        }
        return max(1, orderQty)
    }

    func estimatedRiskText() -> String {
        guard effectiveSLTicks() > 0 else { return "Invalid" }
        return money(estimatedRiskValue())
    }

    func estimatedTargetText() -> String {
        guard effectiveTPTicks() > 0 else { return "Invalid" }
        return money(estimatedTargetValue())
    }

    func riskSummaryText() -> String {
        if tpEnabled && !slEnabled {
            return "\(estimatedTargetText()) / \(effectiveTPTicks())t"
        }
        guard slEnabled else { return "No SL" }
        return "\(estimatedRiskText()) / \(effectiveSLTicks())t"
    }

    func rrText() -> String {
        guard protectionDisplayActive(kind: "TP"), protectionDisplayActive(kind: "SL") else { return "--" }
        let sl = protectionDisplayTicks(kind: "SL")
        let tp = protectionDisplayTicks(kind: "TP")
        guard sl > 0, tp > 0 else { return "--" }
        let rr = Double(tp) / Double(sl)
        return "\(String(format: "%.2f", rr)) : 1"
    }

    func rrCompactText() -> String {
        guard protectionDisplayActive(kind: "TP"), protectionDisplayActive(kind: "SL") else { return "--" }
        let sl = protectionDisplayTicks(kind: "SL")
        let tp = protectionDisplayTicks(kind: "TP")
        guard sl > 0, tp > 0 else { return "--" }
        return String(format: "%.2f", Double(tp) / Double(sl))
    }

}

extension PanelController {

    // MARK: - Ticket Input Handling

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

}
