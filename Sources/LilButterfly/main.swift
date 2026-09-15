import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory) // no Dock icon, no Cmd-Tab entry
app.run()
