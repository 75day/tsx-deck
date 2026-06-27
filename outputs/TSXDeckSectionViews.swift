import AppKit
import Foundation

// MARK: - Panel Section Views

final class HeaderView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let panel = NSView()
        owner.symbolButton = PillButton(owner.symbolButtonTitle(owner.selectedSymbol), bg: owner.palette.surface2, fg: owner.palette.text, size: 12)
        owner.symbolButton.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        owner.symbolButton.alignment = .center
        owner.symbolButton.target = owner
        owner.symbolButton.action = #selector(PanelController.showSymbolMenu(_:))
        owner.symbolButtonWidthStyle()
        owner.symbolMenuWidthConstraint = owner.symbolButton.widthAnchor.constraint(equalToConstant: owner.symbolMenuWidth(owner.selectedSymbol))
        owner.symbolMenuWidthConstraint?.isActive = true
        owner.symbolButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let priceBox = owner.vstack(spacing: 0)
        priceBox.alignment = .centerX
        priceBox.addArrangedSubview(owner.text("TSX LAST", 8, .medium, owner.palette.muted))
        owner.priceLabel = owner.digit("--", 16, .semibold, owner.palette.green)
        owner.priceLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        priceBox.addArrangedSubview(owner.priceLabel)

        let quoteLive = owner.marketStatusText == "Market Live" && !owner.quoteSyncing
        let live = owner.text(quoteLive ? "● LIVE" : "● SYNC", 9, .semibold, quoteLive ? owner.palette.green : owner.palette.orange)
        owner.headerQuoteStatusLabel = live

        let theme = PillButton(owner.isDark ? "☾" : "☀", bg: owner.palette.surface2, fg: owner.isDark ? NSColor.white : NSColor.systemOrange, size: 13)
        theme.fixedWidth(26)
        theme.fixedHeight(24)
        theme.target = owner
        theme.action = #selector(PanelController.toggleTheme)

        [owner.symbolButton, priceBox, live, theme].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview($0)
        }

        NSLayoutConstraint.activate([
            owner.symbolButton.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            owner.symbolButton.centerYAnchor.constraint(equalTo: panel.centerYAnchor),

            theme.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            theme.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            live.trailingAnchor.constraint(equalTo: theme.leadingAnchor, constant: -8),
            live.centerYAnchor.constraint(equalTo: panel.centerYAnchor),

            priceBox.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            priceBox.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            priceBox.leadingAnchor.constraint(greaterThanOrEqualTo: owner.symbolButton.trailingAnchor, constant: 8),
            priceBox.trailingAnchor.constraint(lessThanOrEqualTo: live.leadingAnchor, constant: -8)
        ])

        let card = owner.card(panel, pad: 6)
        card.fixedHeight(46)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class AccountCardView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let card = owner.card(content(owner: owner))
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func content(owner: PanelController) -> NSView {
        let box = owner.vstack(spacing: 6)
        let top = owner.hstack(spacing: 5)
        let account = HoverPopUpButton()
        var selectedAccountTitle = owner.hideAccount ? owner.anonymizedAccountName(owner.accountName) : owner.accountName
        if owner.activeAccounts.isEmpty {
            account.addItems(withTitles: [selectedAccountTitle])
        } else {
            let titles = owner.activeAccounts.map { owner.hideAccount ? owner.anonymizedAccountName($0.name) : $0.menuTitle }
            account.addItems(withTitles: titles)
            if let selectedAccountId = owner.selectedAccountId,
               let index = owner.activeAccounts.firstIndex(where: { $0.id == selectedAccountId }) {
                account.selectItem(at: index)
                selectedAccountTitle = titles[index]
            } else {
                selectedAccountTitle = titles.first ?? selectedAccountTitle
            }
        }
        account.target = owner
        account.action = #selector(PanelController.accountChanged(_:))
        owner.stylePopup(account)
        account.font = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        account.fixedWidth(owner.accountPopupWidth(selectedAccountTitle, font: account.font ?? NSFont.systemFont(ofSize: 10, weight: .semibold)))
        account.fixedHeight(22)
        top.addArrangedSubview(account)
        top.addArrangedSubview(owner.spacer())

        let canTradeColor = owner.canTradeText == "CAN TRADE" ? owner.palette.green : owner.palette.orange
        let tradeStatus = owner.canTradeText == "CAN TRADE" ? "● TRADE" : "● LOCKED"
        let tradeBadge = PillButton(tradeStatus, bg: NSColor.clear, fg: canTradeColor, size: 8, hoverable: false)
        tradeBadge.toolTip = "TopstepX canTrade: \(owner.canTradeText)"
        top.addArrangedSubview(tradeBadge)

        let anonTitle = owner.hideAccount ? "🙈" : "👁"
        let anonBtn = PillButton(anonTitle, bg: owner.alpha(owner.palette.text, owner.isDark ? 0.08 : 0.05), fg: owner.palette.muted, size: 10)
        anonBtn.fixedWidth(22)
        anonBtn.fixedHeight(18)
        anonBtn.target = owner
        anonBtn.action = #selector(PanelController.toggleAccountPrivacy)
        anonBtn.toolTip = owner.hideAccount ? "Show full account names" : "Anonymize accounts (mask last digits)"
        top.addArrangedSubview(anonBtn)

        box.addArrangedSubview(top)

        let stats = owner.hstack(spacing: 10)
        let balance = owner.vstack(spacing: 2)
        balance.alignment = .left
        balance.fixedWidth(116)
        let balanceLabel = owner.text("BALANCE", 7, .medium, owner.palette.muted)
        balanceLabel.alignment = .left
        balance.addArrangedSubview(balanceLabel)
        let balanceButton = PillButton(owner.displayBalanceText(), bg: NSColor.clear, fg: owner.palette.text, size: 12)
        balanceButton.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        balanceButton.alignment = .left
        balanceButton.target = owner
        balanceButton.action = #selector(PanelController.toggleBalancePrivacy)
        balanceButton.visualFeedback = false
        balanceButton.fixedHeight(18)
        balanceButton.fixedWidth(owner.privacyPillWidth(owner.displayBalanceText(), font: balanceButton.font ?? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), min: 62, max: 112))
        balanceButton.layer?.cornerRadius = 6
        balanceButton.imagePosition = .noImage
        balanceButton.toolTip = owner.hideBalance ? "Show balance" : "Hide balance"
        balance.addArrangedSubview(balanceButton)
        stats.addArrangedSubview(balance)
        stats.addArrangedSubview(owner.spacer())
        let miniStats = owner.hstack(spacing: 12)
        miniStats.addArrangedSubview(owner.compactMetric("POS", "\(owner.effectivePositionCount())"))
        miniStats.addArrangedSubview(owner.compactMetric("ORD", "\(owner.effectiveOrderCount())"))
        stats.addArrangedSubview(miniStats)
        box.addArrangedSubview(stats)

        let status = owner.hstack(spacing: 6)
        status.addArrangedSubview(owner.text("REST", 8, .regular, owner.palette.muted))
        status.addArrangedSubview(owner.text(owner.apiStatusText.contains("Connected") ? "● OK" : "● OFF", 8, .medium, owner.apiStatusText.contains("Connected") ? owner.palette.green : owner.palette.orange))
        status.addArrangedSubview(owner.spacer())
        status.addArrangedSubview(owner.text(owner.lastSyncText, 8, .regular, owner.palette.muted))
        box.addArrangedSubview(status)
        return box
    }
}

final class PositionCardView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let card = owner.card(content(owner: owner))
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func content(owner: PanelController) -> NSView {
        let box = owner.vstack(spacing: 7)
        let top = owner.hstack(spacing: 6)
        // Use per-symbol position for this view (not global account positions).
        // This fixes showing MNQ position/PnL when NQ is selected, etc.
        let hasCurrentPos = owner.activePosition() != nil
        let isFlat = !hasCurrentPos
        let side = owner.positionSideText()
        let sideColor = side == "SHORT" ? owner.palette.red : (isFlat ? owner.palette.muted : owner.palette.green)
        let sidePill = PillButton(side, bg: owner.alpha(sideColor, 0.14), fg: sideColor, size: 8, hoverable: false)
        sidePill.fixedHeight(18)
        top.addArrangedSubview(sidePill)

        let identity = owner.hstack(spacing: 4)
        identity.addArrangedSubview(owner.digit("\(owner.positionSizeText())", 13, .semibold, owner.palette.text))
        identity.addArrangedSubview(owner.text(owner.selectedSymbol, 13, .semibold, owner.palette.text))
        top.addArrangedSubview(identity)
        top.addArrangedSubview(owner.spacer())
        top.addArrangedSubview(owner.text("U-PNL", 8, .medium, owner.palette.muted))
        owner.pnlLabel = owner.adaptiveDigit(owner.positionPnlText(), base: 13, min: 10, weight: .semibold, color: owner.positionPnlColor(), width: 76, alignment: .right)
        top.addArrangedSubview(owner.pnlLabel)
        box.addArrangedSubview(top)

        let details = owner.hstack(spacing: 10)
        details.addArrangedSubview(owner.inlineMetric("Avg", owner.averagePriceText(), width: 60))
        details.addArrangedSubview(owner.divider())
        details.addArrangedSubview(owner.privacyMetric("RP&L", owner.displayRealizedPnlText(), width: 52, valueColor: owner.displayRealizedPnlColor(), action: #selector(PanelController.toggleRealizedPnlPrivacy), hidden: owner.hideRealizedPnl))
        details.addArrangedSubview(owner.divider())
        details.addArrangedSubview(owner.inlineMetric("Protect", owner.protectionStatusText(), width: 64))
        details.addArrangedSubview(owner.spacer())
        box.addArrangedSubview(details)
        return box
    }
}

final class OrderTicketView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let card = owner.card(content(owner: owner))
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func content(owner: PanelController) -> NSView {
        let panel = NSView()
        panel.fixedHeight(owner.orderType == "LIMIT" ? 341 : 177)

        let quoteRow = QuoteRowView(owner: owner)
        let orderTypeTabs = OrderTypeTabsView(owner: owner)

        let priceRow = owner.orderType == "LIMIT" ? owner.limitPriceRow() : owner.zeroHeightView()

        let minus = PillButton("−", bg: owner.palette.surface2, fg: owner.palette.text, size: 13)
        let plus = PillButton("+", bg: owner.palette.surface2, fg: owner.palette.text, size: 13)
        minus.target = owner
        minus.action = #selector(PanelController.decrementQty)
        plus.target = owner
        plus.action = #selector(PanelController.incrementQty)
        let qtyRow = owner.quantityAndQuickQtyRow(minus: minus, plus: plus)
        let qtyQuickRow = owner.zeroHeightView()

        let bracketRow = owner.orderType == "LIMIT" ? owner.protectionRow() : owner.zeroHeightView()

        let risk = owner.orderType == "LIMIT" ? owner.card(owner.ticketRiskSummary(), pad: 6, color: owner.palette.surface2) : owner.zeroHeightView()
        if owner.orderType == "LIMIT" {
            risk.fixedHeight(24)
        }

        let actionColor = owner.isOppositeOpenPositionOrder(side: owner.orderSide) ? owner.palette.orange : (owner.orderSide == "BUY" ? owner.palette.green : owner.palette.red)
        let submit = PillButton(owner.orderSubmitTitle(), bg: owner.readOnlyActionColor(actionColor), fg: owner.readOnlyActionTextColor(), size: 11)
        submit.target = owner
        submit.action = owner.orderSide == "BUY" ? #selector(PanelController.buyClicked) : #selector(PanelController.sellClicked)
        submit.isEnabled = !owner.quoteSyncing
        submit.fixedHeight(38)

        [quoteRow, orderTypeTabs, priceRow, qtyRow, qtyQuickRow, bracketRow, risk, submit].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview($0)
        }

        NSLayoutConstraint.activate([
            quoteRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            quoteRow.topAnchor.constraint(equalTo: panel.topAnchor),
            quoteRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            orderTypeTabs.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            orderTypeTabs.topAnchor.constraint(equalTo: quoteRow.bottomAnchor, constant: 6),
            orderTypeTabs.trailingAnchor.constraint(equalTo: panel.trailingAnchor),

            priceRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            priceRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            priceRow.topAnchor.constraint(equalTo: orderTypeTabs.bottomAnchor, constant: owner.orderType == "LIMIT" ? 7 : 0),

            qtyRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            qtyRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            qtyRow.topAnchor.constraint(equalTo: priceRow.bottomAnchor, constant: owner.orderType == "LIMIT" ? 12 : 8),

            qtyQuickRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            qtyQuickRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            qtyQuickRow.topAnchor.constraint(equalTo: qtyRow.bottomAnchor),

            bracketRow.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            bracketRow.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            bracketRow.topAnchor.constraint(equalTo: qtyQuickRow.bottomAnchor, constant: owner.orderType == "LIMIT" ? 7 : 0),

            risk.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            risk.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            risk.topAnchor.constraint(equalTo: bracketRow.bottomAnchor, constant: owner.orderType == "LIMIT" ? 7 : 0),

            submit.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            submit.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            submit.topAnchor.constraint(equalTo: risk.bottomAnchor, constant: owner.orderType == "LIMIT" ? 7 : 8)
        ])

        return panel
    }
}

final class TicketRiskSummaryView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let slActive = owner.protectionDisplayActive(kind: "SL")
        let tpActive = owner.protectionDisplayActive(kind: "TP")
        let slTicks = owner.protectionDisplayTicks(kind: "SL")
        let tpTicks = owner.protectionDisplayTicks(kind: "TP")
        let slAmount = owner.protectionDisplaySignedAmount(kind: "SL")
        let tpAmount = owner.protectionDisplaySignedAmount(kind: "TP")

        let sl = segment(
            owner: owner,
            label: "SL",
            value: slActive ? owner.summarySignedAmountText(value: slAmount, ticks: slTicks) : "--",
            valueColor: slActive ? (slAmount >= 0 ? owner.palette.green : owner.palette.red) : owner.palette.muted,
            valueWidth: 54,
            valueAlignment: .center
        )
        let tp = segment(
            owner: owner,
            label: "TP",
            value: tpActive ? owner.summarySignedAmountText(value: tpAmount, ticks: tpTicks) : "--",
            valueColor: tpActive ? (tpAmount >= 0 ? owner.palette.green : owner.palette.red) : owner.palette.muted,
            valueWidth: 54,
            valueAlignment: .center
        )
        let rr = segment(
            owner: owner,
            label: "R:R",
            value: owner.rrCompactText(),
            valueColor: tpActive && slActive && tpTicks > 0 ? owner.palette.text : owner.palette.muted,
            valueWidth: 36,
            valueAlignment: .center
        )
        let leftDivider = owner.text("|", 10, .regular, owner.palette.muted)
        leftDivider.alignment = .center
        let rightDivider = owner.text("|", 10, .regular, owner.palette.muted)
        rightDivider.alignment = .center

        [sl, tp, rr, leftDivider, rightDivider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            sl.leadingAnchor.constraint(equalTo: leadingAnchor),
            sl.trailingAnchor.constraint(equalTo: leftDivider.leadingAnchor),
            sl.centerYAnchor.constraint(equalTo: centerYAnchor),

            leftDivider.leadingAnchor.constraint(equalTo: sl.trailingAnchor),
            leftDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftDivider.widthAnchor.constraint(equalToConstant: 1),

            tp.leadingAnchor.constraint(equalTo: leftDivider.trailingAnchor),
            tp.trailingAnchor.constraint(equalTo: rightDivider.leadingAnchor),
            tp.centerYAnchor.constraint(equalTo: centerYAnchor),
            tp.widthAnchor.constraint(equalTo: sl.widthAnchor),

            rightDivider.leadingAnchor.constraint(equalTo: tp.trailingAnchor),
            rightDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightDivider.widthAnchor.constraint(equalToConstant: 1),

            rr.leadingAnchor.constraint(equalTo: rightDivider.trailingAnchor),
            rr.trailingAnchor.constraint(equalTo: trailingAnchor),
            rr.centerYAnchor.constraint(equalTo: centerYAnchor),
            rr.widthAnchor.constraint(equalTo: sl.widthAnchor)
        ])
    }

    private func segment(owner: PanelController, label: String, value: String, valueColor: NSColor, valueWidth: CGFloat, valueAlignment: NSTextAlignment) -> NSView {
        let view = NSView()
        let row = owner.hstack(spacing: 4)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alignment = .centerY
        view.addSubview(row)
        let labelView = owner.text(label, 10, .regular, owner.palette.muted)
        labelView.alignment = .left
        labelView.fixedWidth(label == "R:R" ? 18 : 13)
        row.addArrangedSubview(labelView)
        row.addArrangedSubview(owner.adaptiveDigit(value, base: 9, min: 6.5, weight: .semibold, color: valueColor, width: valueWidth, alignment: valueAlignment))
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -2)
        ])
        return view
    }
}

final class ProtectionRowView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        fixedHeight(106)

        let priceMode = PillButton("Price", bg: owner.bracketMode == "PRICE" ? owner.alpha(owner.palette.blue, owner.isDark ? 0.42 : 0.18) : owner.palette.surface2, fg: owner.bracketMode == "PRICE" ? owner.palette.text : owner.palette.muted, size: 8)
        let ticks = PillButton("Ticks", bg: owner.bracketMode == "TICKS" ? owner.alpha(owner.palette.blue, owner.isDark ? 0.42 : 0.18) : owner.palette.surface2, fg: owner.bracketMode == "TICKS" ? owner.palette.text : owner.palette.muted, size: 8)
        ticks.target = owner
        ticks.action = #selector(PanelController.selectTicksMode)
        priceMode.target = owner
        priceMode.action = #selector(PanelController.selectPriceMode)
        ticks.fixedWidth(52)
        priceMode.fixedWidth(52)
        ticks.fixedHeight(20)
        priceMode.fixedHeight(20)

        let modeControl = NSView()
        modeControl.wantsLayer = true
        modeControl.layer?.cornerRadius = 7
        modeControl.layer?.backgroundColor = owner.alpha(owner.palette.surface2, owner.isDark ? 0.72 : 0.90).cgColor

        let priceProtectionReady = !(owner.quoteSyncing && owner.bracketMode == "PRICE")
        let tpDisplayActive = owner.tpEnabled || owner.officialProtectionPrice(kind: "TP") != nil
        let slDisplayActive = owner.slEnabled || owner.officialProtectionPrice(kind: "SL") != nil
        let tp = owner.compactField(owner.bracketMode == "PRICE" ? "TP price" : "TP ticks", owner.bracketValueText(kind: "TP"), id: "bracketTP", enabled: tpDisplayActive && priceProtectionReady)
        let sl = owner.compactField(owner.bracketMode == "PRICE" ? "SL price" : "SL ticks", owner.bracketValueText(kind: "SL"), id: "bracketSL", enabled: slDisplayActive && priceProtectionReady)
        let tpCheck = owner.protectionToggle(title: "TP", enabled: owner.tpEnabled, action: #selector(PanelController.toggleTPProtection))
        let slCheck = owner.protectionToggle(title: "SL", enabled: owner.slEnabled, action: #selector(PanelController.toggleSLProtection))
        let fieldWidth = owner.bracketInputWidth()
        let tpPanel = owner.protectionPanel(color: owner.palette.green, active: owner.tpEnabled)
        let slPanel = owner.protectionPanel(color: owner.palette.red, active: owner.slEnabled)
        let tpHit = owner.protectionPanelHitButton(panel: tpPanel, color: owner.palette.green, active: owner.tpEnabled, action: #selector(PanelController.toggleTPProtection))
        let slHit = owner.protectionPanelHitButton(panel: slPanel, color: owner.palette.red, active: owner.slEnabled, action: #selector(PanelController.toggleSLProtection))

        [modeControl, tpPanel, slPanel, tpCheck, slCheck, tp, sl, tpHit, slHit].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        [priceMode, ticks].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            modeControl.addSubview($0)
        }

        NSLayoutConstraint.activate([
            modeControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: topAnchor),
            modeControl.widthAnchor.constraint(equalToConstant: 110),
            modeControl.heightAnchor.constraint(equalToConstant: 22),

            priceMode.leadingAnchor.constraint(equalTo: modeControl.leadingAnchor, constant: 2),
            priceMode.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            ticks.leadingAnchor.constraint(equalTo: priceMode.trailingAnchor, constant: 2),
            ticks.trailingAnchor.constraint(equalTo: modeControl.trailingAnchor, constant: -2),
            ticks.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),

            tpPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            tpPanel.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -5),
            tpPanel.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 9),
            tpPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            slPanel.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 5),
            slPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            slPanel.topAnchor.constraint(equalTo: tpPanel.topAnchor),
            slPanel.bottomAnchor.constraint(equalTo: tpPanel.bottomAnchor),

            tpCheck.topAnchor.constraint(equalTo: tpPanel.topAnchor, constant: 10),
            tpCheck.centerXAnchor.constraint(equalTo: tpPanel.centerXAnchor),
            slCheck.centerXAnchor.constraint(equalTo: slPanel.centerXAnchor),
            slCheck.centerYAnchor.constraint(equalTo: tpCheck.centerYAnchor),

            tp.topAnchor.constraint(equalTo: tpCheck.bottomAnchor, constant: 6),
            tp.centerXAnchor.constraint(equalTo: tpPanel.centerXAnchor),
            tp.widthAnchor.constraint(equalToConstant: fieldWidth),
            sl.centerXAnchor.constraint(equalTo: slPanel.centerXAnchor),
            sl.topAnchor.constraint(equalTo: tp.topAnchor),
            sl.widthAnchor.constraint(equalToConstant: fieldWidth),

            tpHit.leadingAnchor.constraint(equalTo: tpPanel.leadingAnchor),
            tpHit.trailingAnchor.constraint(equalTo: tpPanel.trailingAnchor),
            tpHit.topAnchor.constraint(equalTo: tpPanel.topAnchor),
            tpHit.bottomAnchor.constraint(equalTo: tp.topAnchor, constant: 13),

            slHit.leadingAnchor.constraint(equalTo: slPanel.leadingAnchor),
            slHit.trailingAnchor.constraint(equalTo: slPanel.trailingAnchor),
            slHit.topAnchor.constraint(equalTo: slPanel.topAnchor),
            slHit.bottomAnchor.constraint(equalTo: sl.topAnchor, constant: 13)
        ])
    }
}

final class LimitPriceRowView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        fixedHeight(34)
        let priceText = owner.quoteSyncing ? "--" : number2(owner.orderEntryPrice())
        let priceFont = NSFont.monospacedDigitSystemFont(ofSize: owner.adaptiveSize(for: priceText, base: 14, min: 12), weight: .semibold)
        let inputWidth = owner.limitPriceInputWidth(priceText, font: priceFont)

        let title = owner.text(owner.editingOrderId == nil ? "LIMIT PRICE" : "ORDER PRICE", 10, .semibold, owner.palette.muted)
        title.alignment = .center
        let row = NSView()
        row.wantsLayer = true
        row.layer?.cornerRadius = 7
        row.layer?.backgroundColor = owner.inputBackgroundColor().cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = owner.palette.border.cgColor

        let labelCell = NSView()
        labelCell.wantsLayer = true
        labelCell.layer?.backgroundColor = owner.alpha(owner.palette.surface2, owner.isDark ? 0.72 : 0.90).cgColor

        let control = NSView()
        control.wantsLayer = true
        control.layer?.backgroundColor = NSColor.clear.cgColor

        let input = PriceInputTextField(string: priceText)
        input.identifier = NSUserInterfaceItemIdentifier("limitPrice")
        input.delegate = owner
        input.target = owner
        input.action = #selector(PanelController.ticketInputCommitted(_:))
        input.onBegin = { [weak owner] (field: NSTextField) in
            owner?.beginTicketInput(field)
        }
        input.onCommit = { [weak owner] (field: NSTextField) in
            guard let owner, let id = field.identifier?.rawValue else { return }
            owner.activeTicketInput = nil
            owner.activeTicketField = nil
            owner.commitTicketInput(field, id: id)
        }
        input.cell = CenteredTextFieldCell(textCell: input.stringValue)
        input.font = priceFont
        input.textColor = owner.quoteSyncing ? owner.alpha(owner.palette.muted, 0.70) : owner.palette.text
        input.alignment = NSTextAlignment.center
        input.isEditable = !owner.quoteSyncing
        input.isSelectable = !owner.quoteSyncing
        input.isEnabled = !owner.quoteSyncing
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

        let up = PillButton("▲", bg: owner.palette.surface2, fg: owner.palette.text, size: 8)
        let down = PillButton("▼", bg: owner.palette.surface2, fg: owner.palette.text, size: 8)
        up.hoverFeedback = false
        down.hoverFeedback = false
        up.target = owner
        up.action = #selector(PanelController.incrementLimitPrice)
        down.target = owner
        down.action = #selector(PanelController.decrementLimitPrice)
        up.fixedWidth(24)
        down.fixedWidth(24)
        up.isEnabled = !owner.quoteSyncing
        down.isEnabled = !owner.quoteSyncing

        let stepper = owner.vstack(spacing: 4)
        stepper.addArrangedSubview(up)
        stepper.addArrangedSubview(down)

        let dividerLine = NSView()
        dividerLine.wantsLayer = true
        dividerLine.layer?.backgroundColor = owner.palette.border.cgColor

        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        labelCell.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labelCell)
        [title, control].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        [input, dividerLine, stepper].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            control.addSubview($0)
        }

        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.widthAnchor.constraint(equalToConstant: 238),
            row.heightAnchor.constraint(equalToConstant: 32),

            labelCell.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            labelCell.topAnchor.constraint(equalTo: row.topAnchor),
            labelCell.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            labelCell.widthAnchor.constraint(equalToConstant: 82),

            title.leadingAnchor.constraint(equalTo: labelCell.leadingAnchor, constant: 5),
            title.trailingAnchor.constraint(equalTo: labelCell.trailingAnchor, constant: -5),
            title.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            control.leadingAnchor.constraint(equalTo: labelCell.trailingAnchor),
            control.topAnchor.constraint(equalTo: row.topAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.heightAnchor.constraint(equalToConstant: 32),
            control.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            input.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 7),
            input.topAnchor.constraint(equalTo: control.topAnchor),
            input.bottomAnchor.constraint(equalTo: control.bottomAnchor),
            input.widthAnchor.constraint(equalToConstant: inputWidth),

            dividerLine.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 4),
            dividerLine.widthAnchor.constraint(equalToConstant: 1),
            dividerLine.topAnchor.constraint(equalTo: control.topAnchor, constant: 5),
            dividerLine.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -5),

            stepper.leadingAnchor.constraint(equalTo: dividerLine.trailingAnchor, constant: 4),
            stepper.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -4),
            stepper.centerYAnchor.constraint(equalTo: control.centerYAnchor),

            up.heightAnchor.constraint(equalToConstant: 12),
            down.heightAnchor.constraint(equalToConstant: 12)
        ])
    }
}

final class QuantityAndQuickQtyRowView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController, minus: NSButton, plus: NSButton) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner, minus: minus, plus: plus)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController, minus: NSButton, plus: NSButton) {
        fixedHeight(30)

        let surface = NSView()
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 6
        surface.layer?.backgroundColor = owner.inputBackgroundColor().cgColor

        let qty = owner.quantityInputField()
        let symbol = owner.text(owner.selectedSymbol, 8, .medium, owner.palette.muted)

        [minus, plus].forEach {
            $0.fixedHeight(24)
            $0.fixedWidth(24)
        }

        let row = NSView()
        let quickRow = owner.hstack(spacing: 4)
        for value in [1, 3, 5, 10, 15] {
            let selected = owner.orderQty == value
            let button = PillButton("\(value)", bg: selected ? owner.alpha(owner.palette.text, owner.isDark ? 0.30 : 0.20) : owner.alpha(owner.palette.text, owner.isDark ? 0.08 : 0.07), fg: selected ? owner.palette.text : owner.palette.muted, size: 9)
            button.fixedWidth(24)
            button.fixedHeight(24)
            button.layer?.cornerRadius = 12
            button.target = owner
            button.action = #selector(PanelController.selectQuickQty(_:))
            quickRow.addArrangedSubview(button)
        }

        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        [surface, qty, symbol, minus, plus, quickRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }

        let controlWidth = min(max(CGFloat(66 + owner.selectedSymbol.count * 5 + String(owner.orderQty).count * 3), 70), 78)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.widthAnchor.constraint(equalToConstant: 282),
            row.heightAnchor.constraint(equalToConstant: 24),

            surface.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            surface.widthAnchor.constraint(equalToConstant: controlWidth),
            surface.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            surface.heightAnchor.constraint(equalToConstant: 24),

            minus.leadingAnchor.constraint(equalTo: surface.trailingAnchor, constant: 4),
            minus.centerYAnchor.constraint(equalTo: surface.centerYAnchor),

            plus.leadingAnchor.constraint(equalTo: minus.trailingAnchor, constant: 4),
            plus.centerYAnchor.constraint(equalTo: surface.centerYAnchor),

            quickRow.leadingAnchor.constraint(equalTo: plus.trailingAnchor, constant: 8),
            quickRow.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            quickRow.centerYAnchor.constraint(equalTo: surface.centerYAnchor),

            qty.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            qty.trailingAnchor.constraint(equalTo: symbol.leadingAnchor, constant: -5),
            qty.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            symbol.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -7),
            symbol.centerYAnchor.constraint(equalTo: surface.centerYAnchor)
        ])
    }
}

final class QuoteRowView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        fixedHeight(44)

        let sellQuote = owner.sideQuoteButton(side: "SELL")
        let buyQuote = owner.sideQuoteButton(side: "BUY")
        let spread = owner.spreadBadge()
        owner.sellQuoteButton = sellQuote
        owner.buyQuoteButton = buyQuote
        owner.spreadButton = spread

        [sellQuote, buyQuote, spread].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            sellQuote.leadingAnchor.constraint(equalTo: leadingAnchor),
            sellQuote.topAnchor.constraint(equalTo: topAnchor),
            sellQuote.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -1),

            buyQuote.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 1),
            buyQuote.trailingAnchor.constraint(equalTo: trailingAnchor),
            buyQuote.centerYAnchor.constraint(equalTo: sellQuote.centerYAnchor),

            spread.centerXAnchor.constraint(equalTo: centerXAnchor),
            spread.centerYAnchor.constraint(equalTo: sellQuote.centerYAnchor)
        ])
    }
}

final class OrderTypeTabsView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        fixedHeight(24)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = owner.alpha(owner.palette.surface2, owner.isDark ? 0.62 : 0.86).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = owner.alpha(owner.palette.border, 0.55).cgColor

        let selectedTabBg = owner.alpha(owner.palette.blue, owner.isDark ? 0.36 : 0.20)
        let inactiveTabBg = NSColor.clear
        let market = PillButton("Market", bg: owner.orderType == "MARKET" ? selectedTabBg : inactiveTabBg, fg: owner.orderType == "MARKET" ? owner.palette.text : owner.palette.muted, size: 9)
        let limit = PillButton("Limit", bg: owner.orderType == "LIMIT" ? selectedTabBg : inactiveTabBg, fg: owner.orderType == "LIMIT" ? owner.palette.text : owner.palette.muted, size: 9)
        market.target = owner
        market.action = #selector(PanelController.selectMarketOrder)
        limit.target = owner
        limit.action = #selector(PanelController.selectLimitOrder)
        market.fixedHeight(22)
        limit.fixedHeight(22)

        [market, limit].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            market.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            market.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            market.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            market.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -1),

            limit.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 1),
            limit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            limit.centerYAnchor.constraint(equalTo: market.centerYAnchor)
        ])
    }
}

final class SubmitActionButtonView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let submit = SubmitActionButtonView(owner: owner)
        submit.translatesAutoresizingMaskIntoConstraints = false
        addSubview(submit)
        NSLayoutConstraint.activate([
            submit.leadingAnchor.constraint(equalTo: leadingAnchor),
            submit.trailingAnchor.constraint(equalTo: trailingAnchor),
            submit.topAnchor.constraint(equalTo: topAnchor),
            submit.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

final class WorkingOrdersSectionView: NSView {
    private weak var owner: PanelController?

    init(owner: PanelController) {
        self.owner = owner
        super.init(frame: .zero)
        build(owner: owner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(owner: PanelController) {
        let card = owner.card(content(owner: owner))
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func content(owner: PanelController) -> NSView {
        let box = owner.vstack(spacing: 8)
        let orders = owner.workingOrders()
        let orderCount = orders.count
        let positionCount = owner.effectivePositionCount()
        let hasOrders = orderCount > 0
        let hasPosition = positionCount > 0

        let head = owner.hstack(spacing: 7)
        head.addArrangedSubview(owner.text("WORKING ORDERS", 9, .medium, owner.alpha(owner.palette.text, 0.88)))
        head.addArrangedSubview(orderCountText(count: orderCount, owner: owner))
        head.addArrangedSubview(owner.spacer())
        head.addArrangedSubview(orderDataSourcePill(owner: owner))
        box.addArrangedSubview(head)

        if owner.lastSnapshot != nil {
            if orderCount == 0 {
                box.addArrangedSubview(openOrdersEmptyState(owner: owner))
            } else {
                box.addArrangedSubview(openOrdersList(orders, owner: owner))
            }
        } else {
            box.addArrangedSubview(openOrdersStatusState("Loading orders from API...", owner: owner))
        }

        box.addArrangedSubview(orderActionRow(hasOrders: hasOrders, hasPosition: hasPosition, owner: owner))
        return box
    }

    private func orderCountText(count: Int, owner: PanelController) -> NSTextField {
        let label = owner.text("\(count)", 9, .medium, count > 0 ? owner.palette.orange : owner.alpha(owner.palette.muted, 0.86))
        label.alignment = .left
        return label
    }

    private func orderDataSourcePill(owner: PanelController) -> NSView {
        let live = owner.hasRealtimeOrderState
        let restFailed = owner.snapshotStatusText.lowercased().contains("failed") || owner.snapshotStatusText.lowercased().contains("off")
        let restLoading = !live && owner.lastSnapshot == nil
        let statusColor: NSColor = live ? owner.palette.green : (restFailed ? owner.palette.red : (restLoading ? owner.palette.orange : owner.palette.green))
        let dot = owner.text("●", 7, .semibold, statusColor)
        let label = owner.text(live ? "STREAM" : "REST", 7.5, .semibold, live ? owner.palette.text : (restFailed ? owner.palette.red : owner.palette.text))
        let detail = owner.text(live ? "live" : (restFailed ? "failed" : (restLoading ? "loading" : "snapshot")), 7.5, .medium, owner.alpha(restFailed ? owner.palette.red : owner.palette.muted, restFailed ? 0.92 : 0.82))
        let row = owner.hstack(spacing: 4)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(label)
        row.addArrangedSubview(detail)
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = owner.alpha(statusColor, live ? 0.10 : (restFailed ? 0.10 : 0.04)).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = owner.alpha(statusColor, live ? 0.22 : (restFailed || restLoading ? 0.26 : 0.14)).cgColor
        row.fixedHeight(17)
        return row
    }

    private func openOrdersEmptyState(owner: PanelController) -> NSView {
        return openOrdersStatusState("No working orders", owner: owner)
    }

    private func openOrdersStatusState(_ message: String, owner: PanelController) -> NSView {
        let box = NSView()
        box.fixedHeight(34)
        let label = owner.text(message, 10, .medium, owner.alpha(owner.palette.muted, 0.92))
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }

    private func orderActionRow(hasOrders: Bool, hasPosition: Bool, owner: PanelController) -> NSView {
        let cancel = owner.riskActionButton("Cancel All Orders", color: owner.palette.orange, active: hasOrders && owner.liveTradingEnabled())
        let flatten = owner.riskActionButton("Flatten Position", color: owner.palette.red, active: hasPosition && owner.liveTradingEnabled())
        cancel.fixedWidth(105)
        flatten.fixedWidth(105)
        cancel.target = owner
        cancel.action = #selector(PanelController.cancelAllOrdersClicked)
        flatten.target = owner
        flatten.action = #selector(PanelController.flattenPositionClicked)

        let buttons = owner.hstack(spacing: 8)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(flatten)

        let container = NSView()
        container.addSubview(buttons)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttons.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: container.topAnchor),
            buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
        ])
        return container
    }

    private func openOrdersList(_ orders: [[String: Any]], owner: PanelController) -> NSView {
        let list = owner.vstack(spacing: 0)
        list.addArrangedSubview(workingOrdersTableHeader(owner: owner))
        for order in orders {
            list.addArrangedSubview(workingOrderRow(order, owner: owner))
        }
        if orders.count <= 3 {
            owner.workingOrdersScrollY = 0
            owner.workingOrdersScrollView = nil
            return workingOrdersListContainer(list, height: CGFloat(20 + orders.count * 27))
        }

        list.layoutSubtreeIfNeeded()

        let scroll = TrackingScrollView()
        owner.workingOrdersRestoringScroll = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = false
        scroll.onScroll = { [weak owner] y in
            guard let owner, !owner.workingOrdersRestoringScroll else { return }
            owner.workingOrdersScrollY = y
        }

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(equalToConstant: list.fittingSize.height),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -10),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        scroll.fixedHeight(104)
        owner.workingOrdersScrollView = scroll
        return scroll
    }

    private func workingOrderRow(_ order: [String: Any], owner: PanelController) -> NSView {
        let side = owner.orderSideText(order)
        let sideColor = side == "BUY" ? owner.palette.green : owner.palette.red
        let status = owner.orderStatusText(order)
        let statusColor = ["Open", "Working", "Pending"].contains(status) ? owner.palette.green : owner.palette.muted
        let edit = owner.orderRowButton("✎", color: owner.palette.blue, action: #selector(PanelController.editWorkingOrder(_:)), order: order)
        let cancel = owner.orderRowButton("×", color: owner.palette.orange, action: #selector(PanelController.cancelWorkingOrder(_:)), order: order)

        let row = workingOrdersTableRowBase(owner: owner)
        row.wantsLayer = true
        row.layer?.backgroundColor = owner.alpha(owner.palette.text, owner.isDark ? 0.025 : 0.045).cgColor
        row.addArrangedSubview(owner.orderColumn(owner.shortOrderIdText(order), width: 48, color: owner.palette.text, weight: .medium))
        row.addArrangedSubview(owner.orderColumn(side, width: 30, color: sideColor, weight: .semibold))
        row.addArrangedSubview(owner.orderColumn(owner.orderCompactTypeText(order), width: 32, color: owner.palette.text, weight: .semibold))
        row.addArrangedSubview(owner.orderColumn("\(owner.intValue(order["size"]) ?? 0)", width: 22, color: owner.palette.text, weight: .medium, align: .center, digitFont: true))
        row.addArrangedSubview(owner.orderColumn(owner.orderDisplayPriceText(order), width: 62, color: owner.palette.text, weight: .medium, align: .center, digitFont: true))
        row.addArrangedSubview(owner.orderColumn(status.uppercased(), width: 36, color: statusColor, weight: .semibold, size: 7, align: .center))
        row.addArrangedSubview(owner.spacer())
        row.addArrangedSubview(orderActionCluster(edit, cancel, owner: owner))

        let outer = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            row.topAnchor.constraint(equalTo: outer.topAnchor),
            row.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            outer.heightAnchor.constraint(equalToConstant: 27)
        ])
        return outer
    }

    private func workingOrdersTableHeader(owner: PanelController) -> NSView {
        let row = workingOrdersTableRowBase(owner: owner)
        row.addArrangedSubview(orderHeaderColumn("ID", width: 48, owner: owner))
        row.addArrangedSubview(orderHeaderColumn("SIDE", width: 30, owner: owner))
        row.addArrangedSubview(orderHeaderColumn("TYPE", width: 32, owner: owner))
        row.addArrangedSubview(orderHeaderColumn("QTY", width: 22, align: .center, owner: owner))
        row.addArrangedSubview(orderHeaderColumn("PRICE", width: 62, align: .center, owner: owner))
        row.addArrangedSubview(orderHeaderColumn("STATUS", width: 36, align: .center, owner: owner))
        row.addArrangedSubview(owner.spacer())
        let actions = owner.hstack(spacing: 8)
        actions.fixedWidth(44)
        actions.addArrangedSubview(orderHeaderColumn("E", width: 16, align: .center, owner: owner))
        actions.addArrangedSubview(orderHeaderColumn("X", width: 16, align: .center, owner: owner))
        row.addArrangedSubview(actions)

        let outer = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        outer.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            row.topAnchor.constraint(equalTo: outer.topAnchor),
            row.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            outer.heightAnchor.constraint(equalToConstant: 20)
        ])
        return outer
    }

    private func workingOrdersTableRowBase(owner: PanelController) -> NSStackView {
        let row = owner.hstack(spacing: 4)
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        return row
    }

    private func orderActionCluster(_ edit: NSButton, _ cancel: NSButton, owner: PanelController) -> NSStackView {
        let actions = owner.hstack(spacing: 8)
        actions.fixedWidth(44)
        actions.addArrangedSubview(edit)
        actions.addArrangedSubview(cancel)
        return actions
    }

    private func workingOrdersListContainer(_ list: NSView, height: CGFloat) -> NSView {
        let container = NSView()
        list.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            list.topAnchor.constraint(equalTo: container.topAnchor),
            list.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: height)
        ])
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return container
    }

    private func orderHeaderColumn(_ value: String, width: CGFloat, align: NSTextAlignment = .left, owner: PanelController) -> NSTextField {
        return owner.orderColumn(value, width: width, color: owner.palette.muted, weight: .semibold, size: 7, align: align)
    }
}


final class FooterStatusView: NSView {
    let eventLabel = NSTextField(labelWithString: "Ready")

    private let lastLabel = NSTextField(labelWithString: "")
    private let snapshotLabel = NSTextField(labelWithString: "")
    private let apiDotLabel = NSTextField(labelWithString: "●")
    private let apiNameLabel = NSTextField(labelWithString: "API")
    private let streamDotLabel = NSTextField(labelWithString: "●")
    private let streamNameLabel = NSTextField(labelWithString: "Stream")
    private let marketDotLabel = NSTextField(labelWithString: "●")
    private let marketNameLabel = NSTextField(labelWithString: "Market")

    private var palette: Palette
    private var isDark: Bool

    init(palette: Palette, isDark: Bool, lastSyncText: String, snapshotStatusText: String, apiLive: Bool, streamLive: Bool, marketLive: Bool) {
        self.palette = palette
        self.isDark = isDark
        super.init(frame: .zero)
        build()
        update(palette: palette, isDark: isDark, lastSyncText: lastSyncText, snapshotStatusText: snapshotStatusText, apiLive: apiLive, streamLive: streamLive, marketLive: marketLive)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(palette: Palette, isDark: Bool, lastSyncText: String, snapshotStatusText: String, apiLive: Bool, streamLive: Bool, marketLive: Bool) {
        self.palette = palette
        self.isDark = isDark
        layer?.backgroundColor = palette.surface.cgColor
        layer?.borderColor = palette.border.cgColor
        lastLabel.stringValue = lastSyncText
        lastLabel.textColor = palette.text
        snapshotLabel.stringValue = snapshotStatusText
        snapshotLabel.textColor = palette.muted
        updateConnection(dot: apiDotLabel, label: apiNameLabel, live: apiLive)
        updateConnection(dot: streamDotLabel, label: streamNameLabel, live: streamLive)
        updateConnection(dot: marketDotLabel, label: marketNameLabel, live: marketLive)
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        let box = hstack(spacing: 10)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addArrangedSubview(connectionStrip())
        box.addArrangedSubview(spacer())

        let meta = vstack(spacing: 3)
        meta.alignment = .trailing
        let top = hstack(spacing: 6)
        style(lastLabel, size: 8, weight: .semibold, color: palette.text)
        top.addArrangedSubview(lastLabel)
        top.addArrangedSubview(shortDivider())
        style(eventLabel, size: 8, weight: .regular, color: palette.muted)
        eventLabel.maximumNumberOfLines = 1
        eventLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(eventLabel)
        meta.addArrangedSubview(top)

        style(snapshotLabel, size: 8, weight: .regular, color: palette.muted)
        meta.addArrangedSubview(snapshotLabel)
        box.addArrangedSubview(meta)

        addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            box.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }

    private func connectionStrip() -> NSView {
        let row = hstack(spacing: 8)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.layer?.backgroundColor = alpha(palette.text, isDark ? 0.035 : 0.055).cgColor
        row.layer?.borderWidth = 1
        row.layer?.borderColor = alpha(palette.border, 0.28).cgColor
        row.addArrangedSubview(connectionState(dot: apiDotLabel, label: apiNameLabel))
        row.addArrangedSubview(connectionState(dot: streamDotLabel, label: streamNameLabel))
        row.addArrangedSubview(connectionState(dot: marketDotLabel, label: marketNameLabel))
        row.fixedHeight(21)
        return row
    }

    private func connectionState(dot: NSTextField, label: NSTextField) -> NSView {
        let row = hstack(spacing: 4)
        style(dot, size: 7, weight: .semibold, color: palette.muted)
        style(label, size: 8, weight: .regular, color: palette.muted)
        row.addArrangedSubview(dot)
        row.addArrangedSubview(label)
        return row
    }

    private func updateConnection(dot: NSTextField, label: NSTextField, live: Bool) {
        let color = live ? palette.green : palette.muted
        dot.textColor = color
        label.textColor = live ? palette.text : palette.muted
    }

    private func style(_ field: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
    }

    private func hstack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }

    private func vstack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .width
        stack.distribution = .fill
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func shortDivider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.border.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return view
    }

    private func alpha(_ color: NSColor, _ value: CGFloat) -> NSColor {
        color.withAlphaComponent(value)
    }
}
