import AppKit
import Foundation

// MARK: - Base UI Controls

final class TrackingScrollView: NSScrollView {
    var onScroll: ((CGFloat) -> Void)?

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?(clipView.bounds.origin.y)
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
    var visualFeedback = true
    var hoverFeedback = true

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

        if !visualFeedback {
            targetBg = bgColor
            targetTint = isEnabled ? fgColor : fgColor.withAlphaComponent(0.42)
        } else if !isEnabled {
            targetBg = bgColor.withAlphaComponent(0.32)
            targetTint = fgColor.withAlphaComponent(0.42)
        } else if pressed {
            targetBg = bgColor.blended(withFraction: 0.38, of: NSColor.black) ?? bgColor
            targetTint = fgColor.withAlphaComponent(0.82)
        } else if hovered && hoverFeedback {
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

        if visualFeedback && hoverFeedback && hovered && !lowAlpha {
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

final class HoverPopUpButton: NSPopUpButton {
    var normalBackgroundColor = NSColor.clear
    var hoverBackgroundColor = NSColor.clear
    var normalBorderColor = NSColor.clear
    var hoverBorderColor = NSColor.clear

    private var trackingArea: NSTrackingArea?
    private var hovered = false

    init() {
        super.init(frame: .zero, pullsDown: false)
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureHover(normalBg: NSColor, hoverBg: NSColor, normalBorder: NSColor, hoverBorder: NSColor) {
        normalBackgroundColor = normalBg
        hoverBackgroundColor = hoverBg
        normalBorderColor = normalBorder
        hoverBorderColor = hoverBorder
        applyHoverState(animated: false)
    }

    private func setupTracking() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
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
        hovered = true
        applyHoverState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hovered = false
        applyHoverState(animated: true)
    }

    private func applyHoverState(animated: Bool) {
        guard let layer else { return }
        layer.removeAllAnimations()
        let bg = hovered ? hoverBackgroundColor : normalBackgroundColor
        let border = hovered ? hoverBorderColor : normalBorderColor

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.09)
        layer.backgroundColor = bg.cgColor
        layer.borderColor = border.cgColor
        CATransaction.commit()
    }
}

final class HoverProxyButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupTracking()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTracking() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
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
            onHoverChanged?(true)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
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
