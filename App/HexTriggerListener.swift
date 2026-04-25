import Foundation
import ApplicationServices

final class HexTriggerListener {
    private let formatterFlow: FormatterFlow
    private let stateRepository: StateRepository
    private var triggerKeyIsDown = false

    var tap: CFMachPort?

    init(formatterFlow: FormatterFlow, stateRepository: StateRepository) {
        self.formatterFlow = formatterFlow
        self.stateRepository = stateRepository
    }

    func handleFlagsChanged(event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == triggerKeyCode else {
            stateRepository.debug("ignoring non-trigger flagsChanged keyCode=\(keyCode) flags=0x\(String(flags.rawValue, radix: 16))")
            return
        }

        let nowDown = flags.contains(.maskAlternate)
        if nowDown == triggerKeyIsDown { return }

        triggerKeyIsDown = nowDown
        stateRepository.debug("\(triggerKeyName) state changed keyCode=\(keyCode) nowDown=\(nowDown) flags=0x\(String(flags.rawValue, radix: 16))")

        if nowDown {
            formatterFlow.handleTriggerDown()
        } else {
            formatterFlow.handleTriggerUp()
        }
    }
}
