import Foundation

private enum FormatterFlowError: LocalizedError {
    case instructionTimeout(timeoutSeconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .instructionTimeout(let timeoutSeconds):
            return "No new Hex transcript appeared within \(Int(timeoutSeconds))s. Make sure Hex is recording and bound directly to \(triggerKeyName)."
        }
    }
}

final class FormatterFlow {
    private let queue = DispatchQueue(label: "hex.trigger.listener.serial")
    private let systemAdapter: SystemAdapter
    private let stateRepository: StateRepository
    private let historyRepository: HexHistoryRepository
    private let xaiClient: XAIClient
    private let statusOverlay: StatusOverlayController
    private let appConfig: AppConfig

    private var waitingForInstruction = false
    private var processing = false
    private var armedContext: ArmedContext?
    private var formattingAnimationTimer: DispatchSourceTimer?
    private var formattingFrameIndex = 0
    private var currentVisiblePlaceholder = ""

    init(
        systemAdapter: SystemAdapter,
        stateRepository: StateRepository,
        historyRepository: HexHistoryRepository,
        xaiClient: XAIClient,
        statusOverlay: StatusOverlayController,
        appConfig: AppConfig
    ) {
        self.systemAdapter = systemAdapter
        self.stateRepository = stateRepository
        self.historyRepository = historyRepository
        self.xaiClient = xaiClient
        self.statusOverlay = statusOverlay
        self.appConfig = appConfig
    }

    func handleTriggerDown() {
        queue.async {
            if self.processing { return }

            let selected = self.systemAdapter.captureSelectionText()
            if selected.count > maxOriginalLength {
                self.statusOverlay.show("Selection too large: \(selected.count) characters. Limit is \(maxOriginalLength).", autoHideAfter: 4.0)
                self.stateRepository.debug("selected too long: \(selected.count)")
                self.clearFlowState()
                return
            }

            guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.stateRepository.debug("trigger down with no selection")
                self.statusOverlay.show("Nothing selected. Select text before holding \(triggerKeyName).", autoHideAfter: 3.0)
                return
            }

            let baseline = self.historyRepository.latestEntry()
            self.armedContext = ArmedContext(
                originalText: selected,
                bundleID: self.systemAdapter.frontmostBundleID(),
                historyBaselineTimestamp: baseline?.timestamp ?? 0,
                historyBaselineID: baseline?.id
            )

            self.waitingForInstruction = true
            self.stateRepository.writeOriginal(selected)
            self.stateRepository.writeWaitingState()
            self.statusOverlay.show("Speak, then release \(triggerKeyName).", autoHideAfter: nil)
            self.stateRepository.debug("armed with selection length=\(selected.count) bundle=\(self.armedContext?.bundleID ?? "unknown") historyBaselineTimestamp=\(self.armedContext?.historyBaselineTimestamp ?? 0)")
            self.stateRepository.debug("expecting Hex to be bound to \(triggerKeyName) directly")
            self.stateRepository.debugBlock("selected_text", selected)
        }
    }

    func handleTriggerUp() {
        queue.async {
            guard self.waitingForInstruction, !self.processing else { return }

            self.waitingForInstruction = false
            self.processing = true
            self.statusOverlay.show("Reading instruction...", autoHideAfter: nil)
            self.stateRepository.debug("trigger up while waiting; processing instruction")

            self.queue.asyncAfter(deadline: .now() + 0.8) {
                self.processInstruction()
            }
        }
    }

    private func processInstruction() {
        guard let context = armedContext else {
            clearFlowState()
            return
        }

        switch waitForNewHexInstruction(context: context, timeoutSeconds: appConfig.instructionWaitTimeoutSeconds) {
        case .failure(let error):
            showFailure("Instruction capture failed", error: error, autoHideAfter: 5.0)
            stateRepository.debug("instruction capture failed reason=\(error.localizedDescription)")
            clearFlowState()
            return
        case .success(let rawInstruction):
            let instruction = rawInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

            stateRepository.debug("instruction captured length=\(instruction.count) selected=true")
            stateRepository.debugBlock("instruction_text", rawInstruction)

            statusOverlay.show("Formatting...", autoHideAfter: nil)
            startFormattingAnimation(replacing: rawInstruction)

            xaiClient.format(original: context.originalText, instruction: instruction) { result in
                self.queue.async {
                    switch result {
                    case .success(let formatted):
                        self.stopFormattingAnimation()
                        self.replaceVisiblePlaceholder(with: formatted)
                        self.statusOverlay.show("Done.", autoHideAfter: 1.5)
                        self.stateRepository.debug("formatting success resultLength=\(formatted.count)")
                    case .failure(let error):
                        self.stopFormattingAnimation()
                        self.replaceVisiblePlaceholder(with: context.originalText)
                        self.showFailure("Formatting failed", error: error, autoHideAfter: 5.0)
                        self.stateRepository.debug("formatting failed reason=\(error.localizedDescription), original restored")
                    }

                    self.clearFlowState()
                }
            }
        }
    }

    private func waitForNewHexInstruction(context: ArmedContext, timeoutSeconds: TimeInterval) -> Result<String, Error> {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastHistoryError: Error?

        while Date() < deadline {
            switch historyRepository.firstNewEntry(
                sinceTimestamp: context.historyBaselineTimestamp,
                excludingID: context.historyBaselineID,
                bundleID: context.bundleID
            ) {
            case .failure(let error):
                lastHistoryError = error
            case .success(let entry):
                lastHistoryError = nil
                guard let entry else { break }
                let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    stateRepository.debug("new hex history entry id=\(entry.id) timestamp=\(entry.timestamp)")
                    return .success(entry.text)
                }
            }

            usleep(250_000)
        }

        if let lastHistoryError {
            return .failure(lastHistoryError)
        }

        return .failure(FormatterFlowError.instructionTimeout(timeoutSeconds: timeoutSeconds))
    }

    private func startFormattingAnimation(replacing instruction: String) {
        stopFormattingAnimation()

        let frames = animationFrames()
        formattingFrameIndex = 0
        currentVisiblePlaceholder = frames[0]

        systemAdapter.selectLeftCharacters(instruction.count)
        systemAdapter.pasteTextSafely(currentVisiblePlaceholder)

        guard frames.count > 1 else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + appConfig.formattingPlaceholderFrameIntervalSeconds, repeating: appConfig.formattingPlaceholderFrameIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.advanceFormattingAnimationFrame()
        }
        formattingAnimationTimer = timer
        timer.resume()
    }

    private func advanceFormattingAnimationFrame() {
        guard processing else { return }

        let frames = animationFrames()
        guard frames.count > 1 else { return }

        formattingFrameIndex = (formattingFrameIndex + 1) % frames.count
        let nextFrame = frames[formattingFrameIndex]

        systemAdapter.selectLeftCharacters(currentVisiblePlaceholder.count)
        systemAdapter.pasteTextSafely(nextFrame)
        currentVisiblePlaceholder = nextFrame
    }

    private func stopFormattingAnimation() {
        formattingAnimationTimer?.setEventHandler {}
        formattingAnimationTimer?.cancel()
        formattingAnimationTimer = nil
        formattingFrameIndex = 0
    }

    private func replaceVisiblePlaceholder(with text: String) {
        let placeholderLength = currentVisiblePlaceholder.isEmpty ? appConfig.placeholderText.count : currentVisiblePlaceholder.count
        systemAdapter.selectLeftCharacters(placeholderLength)
        systemAdapter.pasteTextSafely(text)
        currentVisiblePlaceholder = ""
    }

    private func animationFrames() -> [String] {
        let cleaned = appConfig.formattingPlaceholderFrames.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return cleaned.isEmpty ? [appConfig.placeholderText] : cleaned
    }

    private func showFailure(_ prefix: String, error: Error, autoHideAfter delay: TimeInterval) {
        let detail = condensedMessage(error.localizedDescription)
        statusOverlay.show("\(prefix): \(detail)", autoHideAfter: delay)
    }

    private func condensedMessage(_ message: String) -> String {
        let collapsed = message
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 220 else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 220)
        return String(collapsed[..<endIndex]) + "..."
    }

    private func clearFlowState() {
        stopFormattingAnimation()
        waitingForInstruction = false
        processing = false
        armedContext = nil
        currentVisiblePlaceholder = ""
        stateRepository.resetPersistedState()
    }
}
