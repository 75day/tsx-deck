import AppKit
import Foundation

extension PanelController {

    // MARK: - UI Text / Components

    func text(_ value: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func digit(_ value: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func adaptiveDigit(_ value: String, base: CGFloat, min: CGFloat, weight: NSFont.Weight, color: NSColor, width: CGFloat, alignment: NSTextAlignment) -> NSTextField {
        let field = digit(value, adaptiveSize(for: value, base: base, min: min), weight, color)
        field.alignment = alignment
        field.fixedWidth(width)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }

    func adaptiveSize(for value: String, base: CGFloat, min: CGFloat) -> CGFloat {
        let count = value.count
        if count <= 8 { return base }
        if count <= 10 { return max(min, base - 1) }
        if count <= 12 { return max(min, base - 2) }
        return min
    }

    func compactMetric(_ name: String, _ value: String) -> NSView {
        let box = vstack(spacing: 2)
        box.alignment = .right
        box.addArrangedSubview(text(name, 7, .medium, palette.muted))
        box.addArrangedSubview(digit(value, 11, .semibold, palette.muted))
        box.fixedWidth(32)
        return box
    }

    func inlineMetric(_ name: String, _ value: String, width: CGFloat, valueColor: NSColor? = nil) -> NSView {
        let row = hstack(spacing: 4)
        row.addArrangedSubview(text(name, 8, .regular, palette.muted))
        let color = valueColor ?? (value == "None" || value == "--" ? palette.muted : palette.text)
        row.addArrangedSubview(adaptiveDigit(value, base: 10, min: 8, weight: .semibold, color: color, width: width, alignment: .left))
        return row
    }

    func privacyMetric(_ name: String, _ value: String, width: CGFloat, valueColor: NSColor, action: Selector, hidden: Bool) -> NSView {
        let row = hstack(spacing: 4)
        row.addArrangedSubview(text(name, 8, .regular, palette.muted))
        let slot = NSView()
        slot.fixedWidth(width)
        slot.fixedHeight(14)

        let label = digit(value, adaptiveSize(for: value, base: 10, min: 8), .semibold, valueColor)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let hit = HoverProxyButton()
        hit.target = self
        hit.action = action
        hit.toolTip = hidden ? "Show \(name)" : "Hide \(name)"
        hit.translatesAutoresizingMaskIntoConstraints = false

        slot.addSubview(label)
        slot.addSubview(hit)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            hit.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            hit.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            hit.topAnchor.constraint(equalTo: slot.topAnchor),
            hit.bottomAnchor.constraint(equalTo: slot.bottomAnchor)
        ])

        row.addArrangedSubview(slot)
        return row
    }

    func privacyPillWidth(_ value: String, font: NSFont, min: CGFloat, max: CGFloat) -> CGFloat {
        let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
        return Swift.min(Swift.max(ceil(textWidth + 12), min), max)
    }

    func displayBalanceText() -> String {
        return hideBalance ? "*****" : balanceText
    }

    func displayRealizedPnlText() -> String {
        return hideRealizedPnl ? "*****" : officialDayNetText()
    }

    func displayRealizedPnlColor() -> NSColor {
        return hideRealizedPnl ? palette.muted : officialDayNetColor()
    }

    func anonymizedAccountName(_ name: String) -> String {
        var compact = name.replacingOccurrences(of: "-219616-", with: "-")
        // Anonymize last 4 (or more) trailing digits with •••• for privacy/screenshots
        if let range = compact.range(of: #"\d{3,}$"#, options: .regularExpression) {
            let digits = String(compact[range])
            let visible = max(0, digits.count - 4)
            let masked = String(digits.prefix(visible)) + String(repeating: "•", count: 4)
            compact.replaceSubrange(range, with: masked)
        } else if compact.count > 6 {
            // Fallback: mask last 4 characters
            compact = String(compact.dropLast(4)) + "••••"
        }
        if compact.count > 22 {
            compact = String(compact.prefix(19)) + "..."
        }
        return compact
    }

}
