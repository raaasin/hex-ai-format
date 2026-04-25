import Foundation

private enum XAIClientError: LocalizedError {
    case missingAPIKey
    case invalidBaseURL(String)
    case requestEncodingFailed
    case requestFailed(String)
    case httpFailure(statusCode: Int, details: String)
    case badAPIResponse
    case emptyModelOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing API key. Set XAI_API_KEY or OPENAI_API_KEY in the environment or ~/.zshrc."
        case .invalidBaseURL(let baseURL):
            return "Invalid xAI base URL: \(baseURL)"
        case .requestEncodingFailed:
            return "The xAI request payload could not be encoded."
        case .requestFailed(let message):
            return "The xAI request failed: \(message)"
        case .httpFailure(let statusCode, let details):
            if details.isEmpty {
                return "xAI returned HTTP \(statusCode)."
            }
            return "xAI returned HTTP \(statusCode): \(details)"
        case .badAPIResponse:
            return "xAI returned an unreadable response payload."
        case .emptyModelOutput:
            return "xAI returned an empty response."
        }
    }
}

final class XAIClient {
    private let stateRepository: StateRepository
    private let appConfig: AppConfig
    private let apiKey: String?

    init(stateRepository: StateRepository, appConfig: AppConfig) {
        self.stateRepository = stateRepository
        self.appConfig = appConfig
        self.apiKey = Self.loadAPIKey()
    }

    func format(original: String, instruction: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let apiKey, !apiKey.isEmpty else {
            stateRepository.debug("missing API key")
            completion(.failure(XAIClientError.missingAPIKey))
            return
        }

        guard let url = URL(string: "\(appConfig.baseURL)/responses") else {
            stateRepository.debug("invalid base URL: \(appConfig.baseURL)")
            completion(.failure(XAIClientError.invalidBaseURL(appConfig.baseURL)))
            return
        }

        let systemPrompt = PromptBuilder.systemPrompt
        let userPrompt = PromptBuilder.userPrompt(original: original, instruction: instruction)
        let payload: [String: Any] = [
            "model": appConfig.model,
            "max_output_tokens": appConfig.maxOutputTokens,
            "stream": false,
            "tools": [
                ["type": "web_search"],
                ["type": "x_search"]
            ],
            "input": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        stateRepository.debug("api request endpoint=\(url.absoluteString) model=\(appConfig.model)")
        stateRepository.debugBlock("api_system_prompt", systemPrompt)
        stateRepository.debugBlock("api_user_prompt", userPrompt)
        stateRepository.debugBlock("api_request_payload", stateRepository.prettyJSONString(payload))

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(XAIClientError.requestEncodingFailed))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = appConfig.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [stateRepository] data, response, error in
            if let error {
                stateRepository.debug("api request error: \(error.localizedDescription)")
                completion(.failure(XAIClientError.requestFailed(error.localizedDescription)))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                stateRepository.debug("api http failure: \(http.statusCode)")
                stateRepository.debugBlock("api_response_raw", bodyText)
                completion(.failure(XAIClientError.httpFailure(statusCode: http.statusCode, details: Self.summarizeResponseBody(bodyText))))
                return
            }

            if let data, let raw = String(data: data, encoding: .utf8) {
                stateRepository.debugBlock("api_response_raw", raw)
            }

            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                stateRepository.debug("bad API response payload")
                completion(.failure(XAIClientError.badAPIResponse))
                return
            }

            if let outputText = object["output_text"] as? String,
               !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                stateRepository.debugBlock("api_response_text", outputText)
                completion(.success(outputText))
                return
            }

            if let output = object["output"] as? [[String: Any]] {
                var parts: [String] = []

                for item in output {
                    if let contentArray = item["content"] as? [[String: Any]] {
                        for contentItem in contentArray {
                            if let text = contentItem["text"] as? String, !text.isEmpty {
                                parts.append(text)
                            } else if let text = contentItem["content"] as? String, !text.isEmpty {
                                parts.append(text)
                            }
                        }
                    } else if let contentString = item["content"] as? String, !contentString.isEmpty {
                        parts.append(contentString)
                    }
                }

                let joined = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                if !joined.isEmpty {
                    stateRepository.debugBlock("api_response_text", joined)
                    completion(.success(joined))
                    return
                }
            }

            if let choices = object["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any] {
                if let content = message["content"] as? String,
                   !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    stateRepository.debugBlock("api_response_text", content)
                    completion(.success(content))
                    return
                }

                if let contentParts = message["content"] as? [[String: Any]] {
                    let joined = contentParts.compactMap { $0["text"] as? String }.joined()
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        stateRepository.debugBlock("api_response_text", joined)
                        completion(.success(joined))
                        return
                    }
                }
            }

            completion(.failure(XAIClientError.emptyModelOutput))
        }.resume()
    }

    private static func summarizeResponseBody(_ body: String) -> String {
        let collapsed = body
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 180 else {
            return collapsed
        }

        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: 180)
        return String(collapsed[..<endIndex]) + "..."
    }

    private static func loadAPIKey() -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["XAI_API_KEY"]
            ?? env["OPENAI_API_KEY"]
            ?? envValueFromZsh("XAI_API_KEY")
            ?? envValueFromZsh("OPENAI_API_KEY")
    }

    private static func envValueFromZsh(_ key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "source ~/.zshrc >/dev/null 2>&1; print -r -- ${(P)1}", "zsh", key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty == false) ? output : nil
        } catch {
            return nil
        }
    }
}
