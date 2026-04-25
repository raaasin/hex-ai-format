import Foundation

final class HexHistoryRepository {
    private let stateRepository: StateRepository
    private let historyPath: URL

    init(stateRepository: StateRepository, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.stateRepository = stateRepository
        self.historyPath = home.appendingPathComponent(
            "Library/Containers/com.kitlangton.Hex/Data/Library/Application Support/com.kitlangton.Hex/transcription_history.json"
        )
    }

    func latestEntry() -> HexHistoryEntry? {
        loadHistory()?.first
    }

    func firstNewEntry(sinceTimestamp: Double, excludingID: String?, bundleID: String?) -> HexHistoryEntry? {
        for entry in loadHistory() ?? [] {
            if isMatchingNewEntry(entry, sinceTimestamp: sinceTimestamp, excludingID: excludingID, bundleID: bundleID) {
                return entry
            }
        }

        return nil
    }

    private func isMatchingNewEntry(
        _ entry: HexHistoryEntry,
        sinceTimestamp: Double,
        excludingID: String?,
        bundleID: String?
    ) -> Bool {
        guard entry.timestamp >= sinceTimestamp else { return false }
        guard entry.id != excludingID else { return false }
        if let bundleID, let sourceBundleID = entry.sourceAppBundleID {
            return bundleID == sourceBundleID
        }
        return bundleID == nil || entry.sourceAppBundleID == nil
    }

    private func loadHistory() -> [HexHistoryEntry]? {
        guard let data = try? Data(contentsOf: historyPath) else {
            stateRepository.debug("hex history read failed path missing")
            return nil
        }

        guard let decoded = try? JSONDecoder().decode(HexHistoryFile.self, from: data) else {
            stateRepository.debug("hex history decode failed")
            return nil
        }

        return decoded.history
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp > rhs.element.timestamp
            }
            .map(\.element)
    }
}
