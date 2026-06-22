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
//   2. The app is now split into a small core file, this panel/UI file, and main.swift.
//   3. "一切正常" (everything working) as of the end of the last session.
//   4. Key recent areas: realtime fidelity, cross-symbol isolation,
//      custom toasts + sounds (TP.caf / Order.caf), hover/press feedback
//      on all clickable elements (PillButton, QuoteButton, inputs).
//   5. Always preserve 100% real TopstepX API behavior (no mocks in live paths).
//
// File last meaningfully updated: June 2026 (hover feedback final polish)
// ============================================================================

// MARK: - Main Controller

final class PanelController: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    // MARK: - State

    var window: NSWindow!
    var root = NSStackView()
    var palette = darkPalette
    var isDark = true
    var isRebuilding = false

    // Ticket editing guard
    var activeTicketInput: String?
    weak var activeTicketField: NSTextField?
    var pendingTicketInputRebuild = false
    var mouseDownMonitor: Any?

    // View references
    var symbolButton: NSButton!
    var symbolMenuWidthConstraint: NSLayoutConstraint?
    var priceLabel: NSTextField!
    var headerQuoteStatusLabel: NSTextField?
    var contractLabel: NSTextField!
    var pnlLabel: NSTextField!
    var positionLabel: NSTextField!
    var eventLabel: NSTextField!
    var bidAskLabel: NSTextField!
    var footerStatusView: FooterStatusView?
    var workingOrdersScrollY: CGFloat = 0
    var workingOrdersRestoringScroll = false
    var workingOrdersScrollView: TrackingScrollView?
    var sellQuoteButton: QuoteButton?
    var buyQuoteButton: QuoteButton?
    var spreadButton: SpreadBadge?

    // Market data
    var price = contracts["MNQ"]!.price
    var bestBidPrice: Double?
    var bestAskPrice: Double?
    var lastQuoteAt: Date?
    var quoteSyncing = false
    var avgPrice = contracts["MNQ"]!.price - 10.5

    // API / realtime state
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
    var selectedSymbol = "MNQ"
    var balanceText = "--"

    // Privacy toggles
    var hideBalance = false
    var hideRealizedPnl = false
    var hideAccount = false

    // Ticket draft
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

    // Account / position snapshots
    var activeAccounts: [AccountInfo] = []
    var selectedAccountId: Int?
    var officialRealizedDayPnl: Double?
    var officialUnrealizedPnl: Double?
    var realtimeOpenOrderCount: Int?
    var realtimeOpenPositionCount: Int?
    var realtimeTradeCount: Int?
    var realtimeOrders: [Int: [String: Any]] = [:]
    var realtimeClosedOrderIds: Set<Int> = []
    var realtimePositions: [Int: [String: Any]] = [:]
    var protectionOrderGroups: [Int: String] = [:]
    var protectionGroupOrders: [String: Set<Int>] = [:]
    var protectionCancelIssuedGroups: Set<String> = []

    // Sounds / fill dedupe
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
    private var recentFillSoundKeys: [String: Date] = [:]
    private var lastAnyFillSoundAt: Date = .distantPast
    private var knownSnapshotTradeSoundKeys: Set<String>?
    private var snapshotTradeSoundAccountId: Int?
    private var suppressSnapshotFillSoundsUntil: Date?
    private var recentLocalOrderAckSoundIds: [Int: Date] = [:]
    private var customSoundsLoadErrorReported = false

    // Status / timers / UI overlays
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
}

extension PanelController {

    // MARK: - App Lifecycle

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

}

extension PanelController {

    // MARK: - Menu Bar / Input Monitoring

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

}

extension PanelController {

    // MARK: - Render / Rebuild

    func rebuild(disableAnimations: Bool = false, force: Bool = false) {
        if isRebuilding { return }

        // Capture current scroll position from the *existing* scroll view before we tear it down
        // in this rebuild. This ensures we have the user's latest position even if onScroll
        // didn't fire for some internal adjustment.
        if let scroll = workingOrdersScrollView, !workingOrdersRestoringScroll {
            workingOrdersScrollY = scroll.contentView.bounds.origin.y
        }

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
            // Nest another async so restore happens *after* the window resize + layout side-effects
            // from setContentSize / frame change have settled. This prevents the system from
            // re-adjusting the scroll position to bottom as a side effect of the height change.
            DispatchQueue.main.async { [weak self] in
                self?.restoreWorkingOrdersScrollPosition()
            }
        }
    }

    func fitWindowToContent() {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()
        let targetHeight = ceil(root.fittingSize.height + 2)
        let clampedHeight = max(360, min(targetHeight, 720))
        let targetWidth: CGFloat = 284
        let currentHeight = content.bounds.height
        let currentWidth = content.bounds.width
        guard abs(currentHeight - clampedHeight) > 2 || abs(currentWidth - targetWidth) > 2 else { return }

        let frame = window.frame
        let topY = frame.maxY
        window.setContentSize(NSSize(width: targetWidth, height: clampedHeight))
        let resized = window.frame
        window.setFrameOrigin(NSPoint(x: resized.minX, y: topY - resized.height))
    }

    private func restoreWorkingOrdersScrollPosition() {
        guard let scroll = workingOrdersScrollView,
              !workingOrdersRestoringScroll else { return }
        workingOrdersRestoringScroll = true
        scroll.layoutSubtreeIfNeeded()
        if let document = scroll.documentView {
            let maxY = max(0, document.frame.height - scroll.contentView.bounds.height)
            let y = min(max(0, workingOrdersScrollY), maxY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        DispatchQueue.main.async { [weak self] in
            self?.workingOrdersRestoringScroll = false
        }
    }

}

extension PanelController {

    // MARK: - View Factories

    func header() -> NSView {
        return HeaderView(owner: self)
    }

    func accountCard() -> NSView {
        return AccountCardView(owner: self)
    }

    func positionCard() -> NSView {
        return PositionCardView(owner: self)
    }

    func ticketCard() -> NSView {
        return OrderTicketView(owner: self)
    }

    func openOrdersCard() -> NSView {
        return WorkingOrdersSectionView(owner: self)
    }

    func footer() -> NSView {
        let view = FooterStatusView(
            palette: palette,
            isDark: isDark,
            lastSyncText: lastSyncText,
            snapshotStatusText: snapshotStatusText,
            apiLive: apiStatusText.contains("Connected"),
            streamLive: streamStatusText.contains("Live"),
            marketLive: marketStatusText.contains("Live") && !quoteSyncing
        )
        footerStatusView = view
        eventLabel = view.eventLabel
        return view
    }

}

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

    // MARK: - Status Updates

    func updateFooterStatus() {
        updateHeaderQuoteStatus()
        footerStatusView?.update(
            palette: palette,
            isDark: isDark,
            lastSyncText: lastSyncText,
            snapshotStatusText: snapshotStatusText,
            apiLive: apiStatusText.contains("Connected"),
            streamLive: streamStatusText.contains("Live"),
            marketLive: marketStatusText.contains("Live") && !quoteSyncing
        )
    }

    func updateHeaderQuoteStatus() {
        let live = marketStatusText == "Market Live" && !quoteSyncing
        headerQuoteStatusLabel?.stringValue = live ? "● LIVE" : "● SYNC"
        headerQuoteStatusLabel?.textColor = live ? palette.green : palette.orange
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

        let suppressRealtimeSound = status != 2 && shouldSuppressRealtimeOrderSound(orderId: id)
        showTradeToast(title, subtitle: subtitle, color: status == 3 ? palette.orange : color, playSound: !suppressRealtimeSound)
        if status == 2 {
            markFillSoundPlayed(key: "order-\(id)")
        }
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

    func markLocalOrderAckSound(orderIds: [Int]) {
        let now = Date()
        recentLocalOrderAckSoundIds = recentLocalOrderAckSoundIds.filter { now.timeIntervalSince($0.value) < 8 }
        for id in orderIds where id > 0 {
            recentLocalOrderAckSoundIds[id] = now
        }
    }

    func shouldSuppressRealtimeOrderSound(orderId: Int) -> Bool {
        let now = Date()
        recentLocalOrderAckSoundIds = recentLocalOrderAckSoundIds.filter { now.timeIntervalSince($0.value) < 8 }
        guard let previous = recentLocalOrderAckSoundIds[orderId] else { return false }
        return now.timeIntervalSince(previous) < 6
    }

    func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

}

extension PanelController {

    // MARK: - Snapshot / API Refresh

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
                self.syncSnapshotTradeFillSounds(snapshot.trades, accountId: snapshot.accountId)
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

}

extension PanelController {

    // MARK: - Timers / Rendering Updates

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

}

extension PanelController {

    // MARK: - Symbol / Account Selection

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
        let requestedSymbol = (sender.representedObject as? String) ?? sender.title
        guard supportedSymbols.contains(requestedSymbol) else {
            eventLabel?.stringValue = "\(requestedSymbol) is not supported"
            return
        }
        selectedSymbol = requestedSymbol
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

}

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

extension PanelController {

    // MARK: - Realtime Payload Handlers

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
        if wasSyncing && !quoteSyncing {
            scheduleRebuild()
        }
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
        let payload = orderDataPayload(order)
        guard realtimeOrderBelongsToSelectedAccount(payload),
              let id = intValue(payload["id"]) else { return }
        hasRealtimeOrderState = true
        let previous = realtimeOrders[id]
        let status = intValue(payload["status"])
        if status == 1 || status == 6 {
            realtimeOrders[id] = payload
            realtimeClosedOrderIds.remove(id)
        } else {
            realtimeOrders.removeValue(forKey: id)
            realtimeClosedOrderIds.insert(id)
            clearEditingOrder(orderId: id)
        }
        // Record type for protection orders so we can decide TP vs SL sound even if fill toast is for protection.
        if protectionOrderGroups[id] != nil {
            if let otype = intValue(payload["type"]) {
                protectionOrderType[id] = otype
            }
        }
        showRealtimeOrderToast(payload, previous: previous)
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

    func orderDataPayload(_ order: [String: Any]) -> [String: Any] {
        return order["data"] as? [String: Any] ?? order
    }

    func realtimeOrderBelongsToSelectedAccount(_ order: [String: Any]) -> Bool {
        if let payloadId = payloadAccountId(order) {
            return payloadId == selectedAccountId
        }
        // GatewayUserOrder is subscribed per account, and some payloads may omit accountId.
        return realtimeAccountId != nil && realtimeAccountId == selectedAccountId
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
                    playFillSoundFile("TP")
                } else if let otype = protectionOrderType[orderId] {
                    if otype == 1 {
                        playFillSoundFile("TP")
                    } else {
                        playFillSoundFile("Order")
                    }
                } else {
                    playFillSoundFile("Order")
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
        guard realtimeTradeBelongsToSelectedAccount(trade) else { return }
        if trade["voided"] as? Bool == true { return }

        playRealtimeTradeFillSoundIfNeeded(trade)

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

    func realtimeTradeBelongsToSelectedAccount(_ trade: [String: Any]) -> Bool {
        if let payloadId = payloadAccountId(trade) {
            return payloadId == selectedAccountId
        }
        // GatewayUserTrade is subscribed per account, and some payloads do not carry accountId.
        // In that case, trust the active user-hub subscription identity.
        return realtimeAccountId != nil && realtimeAccountId == selectedAccountId
    }

    func playRealtimeTradeFillSoundIfNeeded(_ trade: [String: Any]) {
        let key = realtimeTradeFillSoundKey(trade)
        guard shouldPlayFillSound(key: key) else { return }
        let orderId = intValue(trade["orderId"])
            ?? intValue(trade["orderID"])
            ?? intValue(trade["order_id"])
            ?? intValue(trade["order"])
        if let orderId, protectionOrderKind[orderId] == "TP" {
            playFillSoundFile("TP")
        } else {
            playFillSoundFile("Order")
        }
        markFillSoundPlayed(key: key)
    }

    func realtimeTradeFillSoundKey(_ trade: [String: Any]) -> String {
        if let orderId = intValue(trade["orderId"])
            ?? intValue(trade["orderID"])
            ?? intValue(trade["order_id"])
            ?? intValue(trade["order"]) {
            return "order-\(orderId)"
        }
        if let tradeId = intValue(trade["id"]) ?? intValue(trade["tradeId"]) ?? intValue(trade["tradeID"]) {
            return "trade-\(tradeId)"
        }
        let contract = trade["contractId"] as? String ?? activeContractId() ?? selectedSymbol
        let timestamp = (trade["creationTimestamp"] as? String)
            ?? (trade["timestamp"] as? String)
            ?? (trade["updateTimestamp"] as? String)
            ?? timeStamp()
        let price = numberValue(trade["price"]) ?? numberValue(trade["fillPrice"]) ?? numberValue(trade["executionPrice"]) ?? 0
        let size = intValue(trade["size"]) ?? intValue(trade["qty"]) ?? intValue(trade["quantity"]) ?? 0
        let side = intValue(trade["side"]) ?? intValue(trade["type"]) ?? -1
        return "trade-\(contract)-\(timestamp)-\(price)-\(size)-\(side)"
    }

    func syncSnapshotTradeFillSounds(_ trades: [[String: Any]], accountId: Int?) {
        guard let accountId else { return }
        let keys = Set(trades.compactMap { trade -> String? in
            if trade["voided"] as? Bool == true { return nil }
            return realtimeTradeFillSoundKey(trade)
        })

        guard snapshotTradeSoundAccountId == accountId,
              knownSnapshotTradeSoundKeys != nil else {
            snapshotTradeSoundAccountId = accountId
            knownSnapshotTradeSoundKeys = keys
            return
        }

        // REST /Trade/search is authoritative for RP&L reconciliation, but it can arrive
        // seconds after the actual fill. Do not play delayed fill sounds from this snapshot;
        // sounds should come from realtime trade/order events or direct user actions.
        suppressSnapshotFillSoundsUntil = nil
        knownSnapshotTradeSoundKeys = keys
    }

    func shouldPlayFillSound(key: String) -> Bool {
        let now = Date()
        recentFillSoundKeys = recentFillSoundKeys.filter { now.timeIntervalSince($0.value) < 5 }
        if let previous = recentFillSoundKeys[key], now.timeIntervalSince(previous) < 2 {
            return false
        }
        return true
    }

    func markFillSoundPlayed(key: String) {
        recentFillSoundKeys[key] = Date()
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
        realtimeClosedOrderIds.removeAll()
        realtimePositions.removeAll()
        hasRealtimeOrderState = false
        officialRealizedDayPnl = nil
        officialUnrealizedPnl = nil
    }

}

extension PanelController {

    // MARK: - Position / Account Calculations

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

    func officialSubmissionContractId() throws -> String {
        guard let contractId = lastSnapshot?.contractId else {
            throw ProjectXError.api("official contractId not confirmed")
        }
        guard realtimeContractId == contractId else {
            throw ProjectXError.api("market stream not synced to official contract")
        }
        return contractId
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

}

extension PanelController {

    // MARK: - Panel Actions

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

}

extension PanelController {

    // MARK: - Trading Actions

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
                    self.markLocalOrderAckSound(orderIds: ids)
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
                let placedIds = ids.filter { $0 > 0 }
                guard !placedIds.isEmpty,
                      let accountId = payloads.compactMap({ self.intValue($0["accountId"]) }).first else {
                    completion(.failure(firstError))
                    return
                }
                self.cancelOrderIds(apiClient: apiClient, accountId: accountId, orderIds: placedIds) { cancelResult in
                    switch cancelResult {
                    case .success:
                        completion(.failure(ProjectXError.api("partial protection send failed; rolled back \(placedIds.count) order(s): \(firstError.localizedDescription)")))
                    case .failure(let cancelError):
                        completion(.failure(ProjectXError.api("partial protection send failed; rollback failed for \(placedIds.map(String.init).joined(separator: ",")): \(cancelError.localizedDescription); original: \(firstError.localizedDescription)")))
                    }
                }
            } else {
                completion(.success(ids))
            }
        }
    }

}

extension PanelController {

    // MARK: - Order Mutation Helpers

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
                    self.markLocalOrderAckSound(orderIds: [orderId])
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
                            self.markLocalOrderAckSound(orderIds: orderIds)
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
                    self.suppressSnapshotFillSoundsUntil = Date().addingTimeInterval(5)
                    self.showTradeToast("Flatten sent", subtitle: self.selectedSymbol, color: self.palette.red)
                    self.refreshAfterTradeMutation()
                }
            }
        }
    }

}

extension PanelController {

    // MARK: - Order Payloads / Protection

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
        let contractId = try officialSubmissionContractId()
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
        let contractId = try officialSubmissionContractId()
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

        let isEntryLimit = orderType == "LIMIT" && !isOppositeOpenPositionOrder(side: side)
        if isEntryLimit && (tpEnabled || slEnabled) && apiClient?.config.sendBrackets != true {
            throw ProjectXError.api("official bracket sending is disabled; turn off TP/SL or enable sendBrackets")
        }
        let includeBrackets = apiClient?.config.sendBrackets == true && isEntryLimit
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

}

extension PanelController {

    // MARK: - Toasts / Sounds

    func setEvent(_ message: String, color: NSColor, detail: String? = nil) {
        eventLabel?.stringValue = message
        eventLabel?.textColor = color
        eventLabel?.toolTip = detail
    }

    func orderToastTitle(side: String) -> String {
        let sign = side == "BUY" ? "+" : "-"
        return "\(sign)\(orderQty) \(selectedSymbol) \(side)"
    }

    func showTradeToast(_ title: String, subtitle: String, color: NSColor, playSound: Bool = true) {
        if playSound {
            playToastSound(title: title, subtitle: subtitle)
        }

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
            playFillSoundFile("TP")
            return
        }

        if combined.contains("filled") {
            playFillSoundFile("Order")
            return
        }

        // Trigger sound for market quick entries, limit entries, fills, SL, protection TP/SL sent, cancels, etc.
        // "accepted" and "sent" often live in the subtitle for placeOrder success path.
        let shouldPlay = combined.contains("rejected") || combined.contains("expired")
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
        s.volume = 0.45
        s.stop()
        s.currentTime = 0
        s.play()
    }

    @discardableResult
    private func playFillSoundFile(_ kind: String) -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastAnyFillSoundAt) < 0.9 {
            suppressSnapshotFillSoundsUntil = now.addingTimeInterval(5)
            return false
        }
        lastAnyFillSoundAt = now
        suppressSnapshotFillSoundsUntil = now.addingTimeInterval(5)
        playSoundFile(kind)
        return true
    }

    private func ensureSound(_ kind: String) -> NSSound? {
        if kind == "TP" {
            if tpSound == nil {
                if let url = soundURL(for: "TP"),
                   let s = NSSound(contentsOf: url, byReference: true) {
                    s.volume = 0.45
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
                    s.volume = 0.45
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

}
