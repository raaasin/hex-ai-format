import Foundation

final class StateRepository {
    private let fileManager = FileManager.default
    let baseDir: URL
    let configPath: URL
    let originalPath: URL
    let statePath: URL
    let debugPath: URL
    private var debugLoggingEnabled = false

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.baseDir = home.appendingPathComponent(".hex-formatter", isDirectory: true)
        self.configPath = baseDir.appendingPathComponent("config.json")
        self.originalPath = baseDir.appendingPathComponent("original.txt")
        self.statePath = baseDir.appendingPathComponent("state.json")
        self.debugPath = baseDir.appendingPathComponent("debug.log")
        try? fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
    }

    func setDebugLoggingEnabled(_ enabled: Bool) {
        debugLoggingEnabled = enabled
    }

    func writeOriginal(_ text: String) {
        try? text.write(to: originalPath, atomically: true, encoding: .utf8)
    }

    func writeWaitingState() {
        writeState("waiting_for_instruction")
    }

    func writeIdleState() {
        writeState("idle")
    }

    func resetPersistedState() {
        try? fileManager.removeItem(at: originalPath)
        writeIdleState()
    }

    func debug(_ message: String) {
        guard debugLoggingEnabled else { return }

        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        append(data: Data(line.utf8), to: debugPath)
    }

    func debugBlock(_ title: String, _ text: String) {
        guard debugLoggingEnabled else { return }

        let block = """
        [\(ISO8601DateFormatter().string(from: Date()))] BEGIN \(title)
        \(text)
        [\(ISO8601DateFormatter().string(from: Date()))] END \(title)

        """
        append(data: Data(block.utf8), to: debugPath)
    }

    func prettyJSONString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "<unable to serialize JSON>"
        }
        return text
    }

    private func writeState(_ state: String) {
        let payload = ListenerState(
            state: state,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            hexRecordButton: triggerKeyName
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        try? encoded.write(to: statePath, options: .atomic)
    }

    private func append(data: Data, to url: URL) {
        if fileManager.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
            _ = try? handle.close()
            return
        }

        try? data.write(to: url, options: .atomic)
    }
}
