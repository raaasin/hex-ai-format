import Foundation

private enum HexHistoryRepositoryError: LocalizedError {
    case missingHistoryFile
    case invalidHistoryFile

    var errorDescription: String? {
        switch self {
        case .missingHistoryFile:
            return "Hex transcription history was not found. Open Hex once and confirm it is saving history."
        case .invalidHistoryFile:
            return "Hex transcription history could not be read. Check whether Hex wrote invalid history data."
        }
    }
}

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
        switch loadHistory() {
        case .success(let history):
            return history.first
        case .failure:
            return nil
        }
    }

    func firstNewEntry(sinceTimestamp: Double, excludingID: String?, bundleID: String?) -> Result<HexHistoryEntry?, Error> {
        let history: [HexHistoryEntry]
        switch loadHistory() {
        case .success(let entries):
            history = entries
        case .failure(let error):
            return .failure(error)
        }

        for entry in history {
            if isMatchingNewEntry(entry, sinceTimestamp: sinceTimestamp, excludingID: excludingID, bundleID: bundleID) {
                return .success(entry)
            }
        }

        return .success(nil)
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

    private func loadHistory() -> Result<[HexHistoryEntry], Error> {
        guard let data = try? Data(contentsOf: historyPath) else {
            stateRepository.debug("hex history read failed path missing path=\(historyPath.path)")
            return .failure(HexHistoryRepositoryError.missingHistoryFile)
        }

        guard let decoded = try? JSONDecoder().decode(HexHistoryFile.self, from: data) else {
            stateRepository.debug("hex history decode failed path=\(historyPath.path)")
            return .failure(HexHistoryRepositoryError.invalidHistoryFile)
        }

        return .success(
            decoded.history
                .enumerated()
                .sorted { lhs, rhs in
                    if lhs.element.timestamp == rhs.element.timestamp {
                        return lhs.offset < rhs.offset
                    }
                    return lhs.element.timestamp > rhs.element.timestamp
                }
                .map(\.element)
        )
    }
}
