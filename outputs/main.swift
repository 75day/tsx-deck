import AppKit

let app = NSApplication.shared
let delegate = PanelController()
app.delegate = delegate

// Default to regular app so it appears in Dock as running with standard right-click Quit menu.
// Status item (top menu bar) still provides quick Quit for convenience with the floating panel.
app.setActivationPolicy(.regular)
app.run()
