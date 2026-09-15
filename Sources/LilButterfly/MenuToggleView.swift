import AppKit

/// A compact, visual on/off row for settings hosted inside the status menu.
final class MenuToggleView: NSView {
    init(
        title: String,
        detail: String,
        symbol: String,
        isOn: Bool,
        target: AnyObject,
        action: Selector
    ) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 42))

        let icon = NSImageView(frame: NSRect(x: 14, y: 13, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 40, y: 20, width: 175, height: 17)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.frame = NSRect(x: 40, y: 5, width: 175, height: 15)
        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .secondaryLabelColor
        addSubview(detailLabel)

        let toggle = NSSwitch(frame: NSRect(x: 224, y: 9, width: 42, height: 24))
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError("unavailable") }
}
