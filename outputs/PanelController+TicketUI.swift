import AppKit
import Foundation

extension PanelController {

    // MARK: - Ticket Quote Helpers

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

}

extension PanelController {

    // MARK: - Submit Summary Helpers

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

}

extension PanelController {

    // MARK: - Ticket Field Builders

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

    func quantityAndQuickQtyRow(minus: NSButton, plus: NSButton) -> NSView {
        return QuantityAndQuickQtyRowView(owner: self, minus: minus, plus: plus)
    }

    func quantityInputField() -> PriceInputTextField {
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
        return qty
    }

}

extension PanelController {

    // MARK: - Protection UI Helpers

    func protectionRow() -> NSView {
        return ProtectionRowView(owner: self)
    }

    func protectionPanel(color: NSColor, active: Bool) -> NSView {
        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 7
        panel.layer?.backgroundColor = alpha(color, active ? (isDark ? 0.10 : 0.06) : (isDark ? 0.025 : 0.04)).cgColor
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = alpha(color, active ? 0.62 : 0.16).cgColor
        return panel
    }

    func protectionPanelHitButton(panel: NSView, color: NSColor, active: Bool, action: Selector) -> HoverProxyButton {
        let button = HoverProxyButton()
        button.target = self
        button.action = action
        button.toolTip = active ? "Disable protection" : "Enable protection"

        let normalBg = alpha(color, active ? (isDark ? 0.10 : 0.06) : (isDark ? 0.025 : 0.04))
        let hoverBg = alpha(color, active ? (isDark ? 0.16 : 0.10) : (isDark ? 0.075 : 0.08))
        let normalBorder = alpha(color, active ? 0.62 : 0.16)
        let hoverBorder = alpha(color, active ? 0.88 : 0.42)

        button.onHoverChanged = { [weak panel] hovering in
            guard let layer = panel?.layer else { return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.08)
            layer.backgroundColor = (hovering ? hoverBg : normalBg).cgColor
            layer.borderColor = (hovering ? hoverBorder : normalBorder).cgColor
            CATransaction.commit()
        }
        return button
    }

    func bracketInputWidth() -> CGFloat {
        let longest = max(bracketValueText(kind: "TP").count, bracketValueText(kind: "SL").count)
        let raw = CGFloat(longest * 8 + 22)
        return min(max(raw, bracketMode == "PRICE" ? 98 : 46), bracketMode == "PRICE" ? 108 : 56)
    }

    func protectionToggle(title: String, enabled: Bool, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = enabled ? .on : .off
        button.font = NSFont.systemFont(ofSize: 9, weight: .medium)
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
        if bracketMode == "PRICE", let official = officialProtectionPrice(kind: kind) {
            return number2(official)
        }
        if isOppositeOpenPositionOrder(side: orderSide) {
            return number2(positionProtectionPrice(kind: kind))
        }
        return number2(bracketPrice(kind: kind))
    }

    func officialProtectionOrder(kind: String) -> [String: Any]? {
        guard let position = activePosition(),
              let posContractId = position["contractId"] as? String else { return nil }
        let posSide = positionSideText()
        guard posSide == "LONG" || posSide == "SHORT" else { return nil }
        let exitSide = posSide == "SHORT" ? "BUY" : "SELL"
        let avg = numberValue(position["averagePrice"])
        let candidates = workingOrders().filter { order in
            guard (order["contractId"] as? String) == posContractId,
                  orderSideText(order) == exitSide,
                  let type = intValue(order["type"]),
                  let price = officialProtectionOrderPrice(order, kind: kind) else { return false }
            if kind == "TP" {
                guard type == 1 else { return false }
                if let avg {
                    return posSide == "SHORT" ? price < avg : price > avg
                }
                return true
            }
            guard type == 3 || type == 4 || type == 5 else { return false }
            if let avg {
                return posSide == "SHORT" ? price > avg : price < avg
            }
            return true
        }
        return candidates.sorted {
            let a = officialProtectionOrderPrice($0, kind: kind) ?? 0
            let b = officialProtectionOrderPrice($1, kind: kind) ?? 0
            if let avg {
                return abs(a - avg) < abs(b - avg)
            }
            return (intValue($0["id"]) ?? 0) > (intValue($1["id"]) ?? 0)
        }.first
    }

    func officialProtectionOrderPrice(_ order: [String: Any], kind: String) -> Double? {
        if kind == "TP" {
            return numberValue(order["limitPrice"]) ?? numberValue(order["stopPrice"]) ?? numberValue(order["trailPrice"])
        }
        return numberValue(order["stopPrice"]) ?? numberValue(order["limitPrice"]) ?? numberValue(order["trailPrice"])
    }

    func officialProtectionPrice(kind: String) -> Double? {
        if kind == "TP", activeTicketInput == "bracketTP" { return nil }
        if kind == "SL", activeTicketInput == "bracketSL" { return nil }
        guard bracketMode == "PRICE" else { return nil }
        if editingProtectionKind() == kind, let value = limitPriceOverride {
            return value
        }
        guard let order = officialProtectionOrder(kind: kind) else { return nil }
        return officialProtectionOrderPrice(order, kind: kind)
    }

    func editingProtectionKind() -> String? {
        guard editingOrderId != nil,
              let type = editingOrderType,
              let side = editingOrderSide,
              isOppositeOpenPositionOrder(side: side) else { return nil }
        if type == 1 { return "TP" }
        if type == 3 || type == 4 || type == 5 { return "SL" }
        return nil
    }

}

extension PanelController {

    // MARK: - Price / Bracket Calculations

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

}
