import Foundation
import ApplicationServices

final class HexFnListener {
    private let formatterFlow: FormatterFlow
    private let stateRepository: StateRepository
    private var fnIsDown = false

    var tap: CFMachPort?

    init(formatterFlow: FormatterFlow, stateRepository: StateRepository) {
        self.formatterFlow = formatterFlow
        self.stateRepository = stateRepository
    }

    func handleFlagsChanged(event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == fnKeyCode else {
            stateRepository.debug("ignoring non-fn flagsChanged keyCode=\(keyCode) flags=0x\(String(flags.rawValue, radix: 16))")
            return
        }

        let nowDown = flags.contains(.maskSecondaryFn)
        if nowDown == fnIsDown { return }

        fnIsDown = nowDown
        stateRepository.debug("fn state changed keyCode=\(keyCode) nowDown=\(nowDown) flags=0x\(String(flags.rawValue, radix: 16))")

        if nowDown {
            formatterFlow.handleFnDown()
        } else {
            formatterFlow.handleFnUp()
        }
    }
}
