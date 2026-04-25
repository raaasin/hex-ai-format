import Foundation

let maxOriginalLength = 20_000
let fnKeyCode = 63
let hexRecordButtonName = "Fn"

struct ListenerState: Codable {
    let state: String
    let createdAt: String
    let hexRecordButton: String
}

struct HexHistoryFile: Codable {
    let history: [HexHistoryEntry]
}

struct HexHistoryEntry: Codable {
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let text: String
    let id: String
    let timestamp: Double
}

struct ArmedContext {
    let originalText: String
    let bundleID: String?
    let historyBaselineTimestamp: Double
    let historyBaselineID: String?
}

struct AppConfig: Codable {
    let model: String
    let baseURL: String
    let maxOutputTokens: Int
    let requestTimeoutSeconds: TimeInterval
    let instructionWaitTimeoutSeconds: TimeInterval
    let placeholderText: String
    let formattingPlaceholderFrames: [String]
    let formattingPlaceholderFrameIntervalSeconds: TimeInterval

    static let defaults = AppConfig(
        model: "grok-4-1-fast-non-reasoning",
        baseURL: "https://api.x.ai/v1",
        maxOutputTokens: 2_000_000,
        requestTimeoutSeconds: 60,
        instructionWaitTimeoutSeconds: 20,
        placeholderText: "*** formatting... ***",
        formattingPlaceholderFrames: [
            "* formatting *",
            "** formatting **",
            "*** formatting ***",
            "** formatting **"
        ],
        formattingPlaceholderFrameIntervalSeconds: 0.35
    )

    enum CodingKeys: String, CodingKey {
        case model
        case baseURL = "base_url"
        case maxOutputTokens = "max_output_tokens"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case instructionWaitTimeoutSeconds = "instruction_wait_timeout_seconds"
        case placeholderText = "placeholder_text"
        case formattingPlaceholderFrames = "formatting_placeholder_frames"
        case formattingPlaceholderFrameIntervalSeconds = "formatting_placeholder_frame_interval_seconds"
    }
}

struct PartialAppConfig: Codable {
    let model: String?
    let baseURL: String?
    let maxOutputTokens: Int?
    let requestTimeoutSeconds: TimeInterval?
    let instructionWaitTimeoutSeconds: TimeInterval?
    let placeholderText: String?
    let formattingPlaceholderFrames: [String]?
    let formattingPlaceholderFrameIntervalSeconds: TimeInterval?

    func merged(with defaults: AppConfig) -> AppConfig {
        AppConfig(
            model: model ?? defaults.model,
            baseURL: baseURL ?? defaults.baseURL,
            maxOutputTokens: maxOutputTokens ?? defaults.maxOutputTokens,
            requestTimeoutSeconds: requestTimeoutSeconds ?? defaults.requestTimeoutSeconds,
            instructionWaitTimeoutSeconds: instructionWaitTimeoutSeconds ?? defaults.instructionWaitTimeoutSeconds,
            placeholderText: placeholderText ?? defaults.placeholderText,
            formattingPlaceholderFrames: formattingPlaceholderFrames ?? defaults.formattingPlaceholderFrames,
            formattingPlaceholderFrameIntervalSeconds: formattingPlaceholderFrameIntervalSeconds ?? defaults.formattingPlaceholderFrameIntervalSeconds
        )
    }

    enum CodingKeys: String, CodingKey {
        case model
        case baseURL = "base_url"
        case maxOutputTokens = "max_output_tokens"
        case requestTimeoutSeconds = "request_timeout_seconds"
        case instructionWaitTimeoutSeconds = "instruction_wait_timeout_seconds"
        case placeholderText = "placeholder_text"
        case formattingPlaceholderFrames = "formatting_placeholder_frames"
        case formattingPlaceholderFrameIntervalSeconds = "formatting_placeholder_frame_interval_seconds"
    }
}
