import Foundation
import AppKit
import ApplicationServices

final class SystemAdapter {
    private struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private let stateRepository: StateRepository

    init(stateRepository: StateRepository) {
        self.stateRepository = stateRepository
    }

    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func notify(_ message: String) {
        let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = #"display notification "\#(escaped)" with title "Hex Right Option Listener""#
        _ = runOSA(script)
    }

    func captureSelectionText() -> String {
        if let axSelected = captureSelectedTextViaAX(), !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stateRepository.debug("captureSelection source=ax app=\(frontmostBundleID() ?? "unknown") selectedLen=\(axSelected.count)")
            return axSelected
        }

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotClipboard()

        let token = "__HEXFMT_TOKEN_\(UUID().uuidString)__"
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        let before = pasteboard.changeCount

        let copiedTriggered = sendCopyShortcut()

        let deadline = Date().addingTimeInterval(0.35)
        while Date() < deadline {
            if pasteboard.changeCount != before { break }
            if (pasteboard.string(forType: .string) ?? "") != token { break }
            usleep(20_000)
        }

        var current = pasteboard.string(forType: .string) ?? ""
        if current == token {
            let menuCopyTriggered = sendCopyMenuAction()
            if menuCopyTriggered {
                let secondDeadline = Date().addingTimeInterval(0.35)
                while Date() < secondDeadline {
                    current = pasteboard.string(forType: .string) ?? ""
                    if current != token { break }
                    usleep(20_000)
                }
                stateRepository.debug("captureSelection menuCopyFallbackTriggered=true")
            }
        }

        let copied = (current == token) ? "" : current
        let ours = pasteboard.changeCount
        restoreClipboardIfUnchanged(snapshot, expectedChangeCount: ours)
        stateRepository.debug("captureSelection source=clipboard app=\(frontmostBundleID() ?? "unknown") copyShortcutSent=\(copiedTriggered) before=\(before) after=\(ours) copiedLen=\(copied.count)")
        return copied
    }

    func pasteTextSafely(_ text: String) {
        let snapshot = snapshotClipboard()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ours = pasteboard.changeCount
        _ = sendPasteShortcut()
        usleep(120_000)
        restoreClipboardIfUnchanged(snapshot, expectedChangeCount: ours)
    }

    func selectLeftCharacters(_ count: Int) {
        guard count > 0 else { return }
        let script = """
        tell application "System Events"
            repeat \(count) times
                key code 123 using shift down
            end repeat
        end tell
        """
        _ = runOSA(script)
    }

    private func snapshotClipboard() -> ClipboardSnapshot {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
            var map: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type] = data
                }
            }
            return map
        }
        return ClipboardSnapshot(items: saved)
    }

    private func restoreClipboard(_ snapshot: ClipboardSnapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.items.map { itemData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private func restoreClipboardIfUnchanged(_ snapshot: ClipboardSnapshot, expectedChangeCount: Int) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else { return }
        restoreClipboard(snapshot)
    }

    private func captureSelectedTextViaAX() -> String? {
        enableAXManualAccessibilityIfPossible()

        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusedStatus == .success, let focusedElement = focused else { return nil }

        var currentElement: AXUIElement? = unsafeBitCast(focusedElement, to: AXUIElement.self)
        var visited = 0

        while let element = currentElement, visited < 7 {
            if let direct = axSelectedText(on: element), !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return direct
            }

            if let byRange = axSelectedTextByRange(on: element), !byRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return byRange
            }

            var parent: CFTypeRef?
            let parentStatus = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
            if parentStatus == .success, let parent {
                currentElement = unsafeBitCast(parent, to: AXUIElement.self)
            } else {
                currentElement = nil
            }

            visited += 1
        }

        return nil
    }

    private func axSelectedText(on element: AXUIElement) -> String? {
        var selected: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
        guard status == .success, let text = selected as? String else { return nil }
        return text
    }

    private func axSelectedTextByRange(on element: AXUIElement) -> String? {
        var selectedRangeRef: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef)
        guard rangeStatus == .success, let selectedRangeRef else { return nil }
        guard CFGetTypeID(selectedRangeRef) == AXValueGetTypeID() else { return nil }

        let rangeValue = selectedRangeRef as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length > 0 else { return nil }

        var selectedStringRef: CFTypeRef?
        let stringStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &selectedStringRef
        )
        guard stringStatus == .success, let text = selectedStringRef as? String else { return nil }
        return text
    }

    private func enableAXManualAccessibilityIfPossible() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        let status = AXUIElementSetAttributeValue(appAX, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if status != .success && status != .attributeUnsupported {
            stateRepository.debug("AXManualAccessibility set status=\(status.rawValue) app=\(app.bundleIdentifier ?? "unknown")")
        }
    }

    private func isTerminalLikeApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return id == "com.mitchellh.ghostty" || id == "com.apple.Terminal" || id == "com.googlecode.iterm2"
    }

    private func sendCopyShortcut() -> Bool {
        let bundleID = frontmostBundleID()
        if isTerminalLikeApp(bundleID) {
            return runOSA(#"tell application "System Events" to keystroke "c" using {command down, shift down}"#)
        }
        return runOSA(#"tell application "System Events" to keystroke "c" using command down"#)
    }

    private func sendCopyMenuAction() -> Bool {
        runOSA("""
        tell application "System Events"
            tell first process whose frontmost is true
                set frontmost to true
                if exists menu item "Copy" of menu 1 of menu bar item "Edit" of menu bar 1 then
                    click menu item "Copy" of menu 1 of menu bar item "Edit" of menu bar 1
                    return true
                end if
            end tell
        end tell
        """)
    }

    private func sendPasteShortcut() -> Bool {
        let bundleID = frontmostBundleID()
        if isTerminalLikeApp(bundleID) {
            return runOSA(#"tell application "System Events" to keystroke "v" using {command down, shift down}"#)
        }
        return runOSA(#"tell application "System Events" to keystroke "v" using command down"#)
    }

    @discardableResult
    private func runOSA(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return true }

            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            stateRepository.debug("osascript failed status=\(process.terminationStatus) err=\(message)")
            return false
        } catch {
            stateRepository.debug("osascript launch error: \(error.localizedDescription)")
            return false
        }
    }
}
