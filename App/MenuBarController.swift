import AppKit

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stateRepository: StateRepository
    private let statusOverlay: StatusOverlayController
    private let retryListener: () -> Void
    private let statusMenuItem = NSMenuItem(title: "Status: Starting", action: nil, keyEquivalent: "")

    init(
        stateRepository: StateRepository,
        statusOverlay: StatusOverlayController,
        retryListener: @escaping () -> Void
    ) {
        self.stateRepository = stateRepository
        self.statusOverlay = statusOverlay
        self.retryListener = retryListener
        super.init()
        configureMenu()
    }

    func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.statusMenuItem.title = "Status: \(status)"
        }
    }

    private func configureMenu() {
        statusItem.button?.title = "Hex Fix"
        statusItem.button?.toolTip = "Hex Fix"

        statusMenuItem.isEnabled = false

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Retry Listener", action: #selector(retryListenerTapped), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Debug Log", action: #selector(openDebugLog), keyEquivalent: "d"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hex Fix", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func retryListenerTapped() {
        retryListener()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(stateRepository.configPath)
    }

    @objc private func openDebugLog() {
        if !FileManager.default.fileExists(atPath: stateRepository.debugPath.path) {
            FileManager.default.createFile(atPath: stateRepository.debugPath.path, contents: nil)
        }
        NSWorkspace.shared.open(stateRepository.debugPath)
    }

    @objc private func quit() {
        statusOverlay.hide()
        NSApp.terminate(nil)
    }
}
