import AppKit
import ApplicationServices
import Foundation

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let listener = Unmanaged<HexTriggerListener>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = listener.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if type == .flagsChanged {
        listener.handleFlagsChanged(event: event)
    }

    return Unmanaged.passUnretained(event)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stateRepository = StateRepository()
    private let statusOverlay = StatusOverlayController()

    private var configRepository: ConfigRepository?
    private var appConfig: AppConfig?
    private var systemAdapter: SystemAdapter?
    private var historyRepository: HexHistoryRepository?
    private var xaiClient: XAIClient?
    private var formatterFlow: FormatterFlow?
    private var listener: HexTriggerListener?
    private var menuBarController: MenuBarController?
    private var eventTapSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityTrust()
        wireDependencies()
        installMenuBar()
        setupEventTap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let tap = listener?.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
    }

    private func requestAccessibilityTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func wireDependencies() {
        let configRepository = ConfigRepository(stateRepository: stateRepository)
        let appConfig = configRepository.load()
        stateRepository.setDebugLoggingEnabled(appConfig.debugLoggingEnabled)

        let systemAdapter = SystemAdapter(stateRepository: stateRepository)
        let historyRepository = HexHistoryRepository(stateRepository: stateRepository)
        let xaiClient = XAIClient(stateRepository: stateRepository, appConfig: appConfig)
        let formatterFlow = FormatterFlow(
            systemAdapter: systemAdapter,
            stateRepository: stateRepository,
            historyRepository: historyRepository,
            xaiClient: xaiClient,
            statusOverlay: statusOverlay,
            appConfig: appConfig
        )
        let listener = HexTriggerListener(formatterFlow: formatterFlow, stateRepository: stateRepository)

        self.configRepository = configRepository
        self.appConfig = appConfig
        self.systemAdapter = systemAdapter
        self.historyRepository = historyRepository
        self.xaiClient = xaiClient
        self.formatterFlow = formatterFlow
        self.listener = listener

        stateRepository.debug("listener init")
        stateRepository.debug("config path=\(stateRepository.configPath.path) model=\(appConfig.model)")
    }

    private func installMenuBar() {
        menuBarController = MenuBarController(
            stateRepository: stateRepository,
            statusOverlay: statusOverlay,
            retryListener: { [weak self] in
                self?.setupEventTap()
            }
        )
        menuBarController?.updateStatus("Starting")
    }

    private func setupEventTap() {
        guard let listener else {
            menuBarController?.updateStatus("Not ready")
            statusOverlay.show("Hex Fix is not ready.", autoHideAfter: 2.5)
            return
        }

        if let tap = listener.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            showListeningStatus()
            return
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(listener).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: ref
        ) else {
            menuBarController?.updateStatus("Permissions needed")
            statusOverlay.show("Grant Accessibility and Input Monitoring, then retry.", autoHideAfter: 4.0)
            stateRepository.debug("failed to create event tap")
            return
        }

        listener.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        eventTapSource = source
        CGEvent.tapEnable(tap: tap, enable: true)

        showListeningStatus()
    }

    private func showListeningStatus() {
        menuBarController?.updateStatus("Listening")
        statusOverlay.show("Listening.", autoHideAfter: 1.5)
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
