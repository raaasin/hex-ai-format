import Foundation

final class FormatterFlow {
    private let queue = DispatchQueue(label: "hex.trigger.listener.serial")
    private let systemAdapter: SystemAdapter
    private let stateRepository: StateRepository
    private let historyRepository: HexHistoryRepository
    private let xaiClient: XAIClient
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
        appConfig: AppConfig
    ) {
        self.systemAdapter = systemAdapter
        self.stateRepository = stateRepository
        self.historyRepository = historyRepository
        self.xaiClient = xaiClient
        self.appConfig = appConfig
    }

    func handleTriggerDown() {
        queue.async {
            if self.processing { return }

            let selected = self.systemAdapter.captureSelectionText()
            if selected.count > maxOriginalLength {
                self.systemAdapter.notify("Please select less text.")
                self.stateRepository.debug("selected too long: \(selected.count)")
                self.clearFlowState()
                return
            }

            guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.stateRepository.debug("trigger down with no selection")
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
            self.systemAdapter.notify("Original captured. Speak instruction, then release \(triggerKeyName).")
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

        guard let rawInstruction = waitForNewHexInstruction(context: context, timeoutSeconds: appConfig.instructionWaitTimeoutSeconds) else {
            systemAdapter.notify("No instruction detected.")
            stateRepository.debug("no instruction detected from hex history")
            clearFlowState()
            return
        }

        let instruction = rawInstruction.trimmingCharacters(in: .whitespacesAndNewlines)

        stateRepository.debug("instruction captured length=\(instruction.count) selected=true")
        stateRepository.debugBlock("instruction_text", rawInstruction)

        startFormattingAnimation(replacing: rawInstruction)

        xaiClient.format(original: context.originalText, instruction: instruction) { result in
            self.queue.async {
                switch result {
                case .success(let formatted):
                    self.stopFormattingAnimation()
                    self.replaceVisiblePlaceholder(with: formatted)
                    self.systemAdapter.notify("Formatting applied.")
                    self.stateRepository.debug("formatting success resultLength=\(formatted.count)")
                case .failure:
                    self.stopFormattingAnimation()
                    self.replaceVisiblePlaceholder(with: context.originalText)
                    self.systemAdapter.notify("Formatting failed.")
                    self.stateRepository.debug("formatting failed, original restored")
                }

                self.clearFlowState()
            }
        }
    }

    private func waitForNewHexInstruction(context: ArmedContext, timeoutSeconds: TimeInterval) -> String? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let entry = historyRepository.firstNewEntry(
                sinceTimestamp: context.historyBaselineTimestamp,
                excludingID: context.historyBaselineID,
                bundleID: context.bundleID
            ) {
                let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    stateRepository.debug("new hex history entry id=\(entry.id) timestamp=\(entry.timestamp)")
                    return entry.text
                }
            }

            usleep(250_000)
        }

        return nil
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

    private func clearFlowState() {
        stopFormattingAnimation()
        waitingForInstruction = false
        processing = false
        armedContext = nil
        currentVisiblePlaceholder = ""
        stateRepository.resetPersistedState()
    }
}
