import Foundation
import ApplicationServices

private var globalListener: HexFnListener?

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let listener = Unmanaged<HexFnListener>.fromOpaque(refcon).takeUnretainedValue()

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

let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(options)

let stateRepository = StateRepository()
let configRepository = ConfigRepository(stateRepository: stateRepository)
let appConfig = configRepository.load()
let systemAdapter = SystemAdapter(stateRepository: stateRepository)
let historyRepository = HexHistoryRepository(stateRepository: stateRepository)
let xaiClient = XAIClient(stateRepository: stateRepository, appConfig: appConfig)
let formatterFlow = FormatterFlow(
    systemAdapter: systemAdapter,
    stateRepository: stateRepository,
    historyRepository: historyRepository,
    xaiClient: xaiClient,
    appConfig: appConfig
)
let listener = HexFnListener(formatterFlow: formatterFlow, stateRepository: stateRepository)
globalListener = listener
stateRepository.debug("listener init")
stateRepository.debug("config path=\(stateRepository.configPath.path) model=\(appConfig.model)")

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
    fputs("Failed to create event tap. Grant Accessibility + Input Monitoring and retry.\n", stderr)
    exit(1)
}

listener.tap = tap
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("Hex Fn listener running (no second press flow).")
RunLoop.main.run()
