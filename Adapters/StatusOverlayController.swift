import AppKit

final class StatusOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ message: String, autoHideAfter delay: TimeInterval? = 2.0) {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.hideWorkItem = nil

            let panel = self.overlayPanel()
            let label = self.label ?? NSTextField(labelWithString: "")
            label.stringValue = message

            self.resize(panel: panel, for: message)
            panel.orderFrontRegardless()

            if let delay {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.hide()
                }
                self.hideWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.hideWorkItem?.cancel()
            self.hideWorkItem = nil
            self.panel?.orderOut(nil)
        }
    }

    private func overlayPanel() -> NSPanel {
        if let panel {
            return panel
        }

        let contentRect = NSRect(x: 0, y: 0, width: 280, height: 48)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white

        effectView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -12)
        ])

        panel.contentView = effectView
        self.panel = panel
        self.label = label
        return panel
    }

    private func resize(panel: NSPanel, for message: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ]
        let maxWidth: CGFloat = 640
        let horizontalPadding: CGFloat = 48
        let verticalPadding: CGFloat = 24
        let textBounds = (message as NSString).boundingRect(
            with: NSSize(width: maxWidth - horizontalPadding, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let width = min(max(ceil(textBounds.width) + horizontalPadding, 220), maxWidth)
        let height = min(max(ceil(textBounds.height) + verticalPadding, 48), 140)
        let screen = screenForOverlay()
        let frame = NSRect(
            x: screen.visibleFrame.midX - (width / 2),
            y: screen.visibleFrame.maxY - height - 72,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    private func screenForOverlay() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
