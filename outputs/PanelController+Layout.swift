import AppKit
import Foundation

extension PanelController {

    // MARK: - Layout / Color Helpers

    func fixedScaleLabels(left: String, middle: String, right: String) -> NSView {
        let view = NSView()
        let leftLabel = text(left, 9, .regular, palette.muted)
        let middleLabel = text(middle, 9, .regular, palette.muted)
        let rightLabel = text(right, 9, .regular, palette.muted)
        [leftLabel, middleLabel, rightLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            leftLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftLabel.topAnchor.constraint(equalTo: view.topAnchor),
            leftLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            middleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            middleLabel.centerYAnchor.constraint(equalTo: leftLabel.centerYAnchor),
            rightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightLabel.centerYAnchor.constraint(equalTo: leftLabel.centerYAnchor)
        ])
        view.fixedHeight(12)
        return view
    }

    func hstack(spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }

    func vstack(spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .width
        stack.distribution = .fill
        return stack
    }

    func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func divider() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.border.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    func shortDivider() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = palette.border.cgColor
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return view
    }

    func card(_ content: NSView, pad: CGFloat = 6, color: NSColor? = nil) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = (color ?? palette.surface).cgColor
        view.layer?.cornerRadius = 8
        view.layer?.borderWidth = 1
        view.layer?.borderColor = palette.border.cgColor
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad)
        ])
        return view
    }

    func alpha(_ color: NSColor, _ value: CGFloat) -> NSColor {
        return color.withAlphaComponent(value)
    }

    func clearSurface() -> NSColor {
        return isDark ? NSColor(calibratedWhite: 0, alpha: 0.02) : NSColor(calibratedWhite: 1, alpha: 0.25)
    }

    func inputBackgroundColor() -> NSColor {
        return isDark
            ? NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.08, alpha: 1)
            : NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.985, alpha: 1)
    }

    func readOnlyActionColor(_ color: NSColor) -> NSColor {
        return isDark ? alpha(color, 0.45) : alpha(color, 0.28)
    }

    func readOnlyActionTextColor() -> NSColor {
        return isDark ? NSColor.white : palette.text
    }
}
