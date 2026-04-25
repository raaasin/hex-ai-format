import Foundation

final class ConfigRepository {
    private let stateRepository: StateRepository
    private let fileManager = FileManager.default

    init(stateRepository: StateRepository) {
        self.stateRepository = stateRepository
    }

    func load() -> AppConfig {
        if !fileManager.fileExists(atPath: stateRepository.configPath.path) {
            writeDefaults()
            return .defaults
        }

        guard let data = try? Data(contentsOf: stateRepository.configPath) else {
            stateRepository.debug("config read failed; using defaults")
            return .defaults
        }

        if let partial = try? JSONDecoder().decode(PartialAppConfig.self, from: data) {
            return partial.merged(with: .defaults)
        }

        stateRepository.debug("config decode failed; using defaults")
        return .defaults
    }

    private func writeDefaults() {
        guard let data = try? JSONEncoder.pretty.encode(AppConfig.defaults) else { return }
        try? data.write(to: stateRepository.configPath, options: .atomic)
        stateRepository.debug("created default config at \(stateRepository.configPath.path)")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
