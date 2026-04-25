import Foundation

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
            completion(.failure(NSError(domain: "HexTriggerListener", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"])))
            return
        }

        guard let url = URL(string: "\(appConfig.baseURL)/responses") else {
            stateRepository.debug("invalid base URL: \(appConfig.baseURL)")
            completion(.failure(NSError(domain: "HexTriggerListener", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])))
            return
        }

        let systemPrompt = PromptBuilder.systemPrompt
        let userPrompt = PromptBuilder.userPrompt(original: original, instruction: instruction)
        let payload: [String: Any] = [
            "model": appConfig.model,
            "max_output_tokens": appConfig.maxOutputTokens,
            "stream": false,
            "tools": [
                ["type": "web_search_preview"],
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
            completion(.failure(NSError(domain: "HexTriggerListener", code: 3, userInfo: [NSLocalizedDescriptionKey: "JSON encode failed"])))
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
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                stateRepository.debug("api http failure: \(http.statusCode)")
                stateRepository.debugBlock("api_response_raw", bodyText)
                completion(.failure(NSError(domain: "HexTriggerListener", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(bodyText)"])))
                return
            }

            if let data, let raw = String(data: data, encoding: .utf8) {
                stateRepository.debugBlock("api_response_raw", raw)
            }

            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                stateRepository.debug("bad API response payload")
                completion(.failure(NSError(domain: "HexTriggerListener", code: 4, userInfo: [NSLocalizedDescriptionKey: "Bad API response"])))
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

            completion(.failure(NSError(domain: "HexTriggerListener", code: 5, userInfo: [NSLocalizedDescriptionKey: "Empty model output"])))
        }.resume()
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
