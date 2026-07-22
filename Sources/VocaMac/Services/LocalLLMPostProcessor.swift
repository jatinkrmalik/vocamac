// LocalLLMPostProcessor.swift
// VocaMac
//
// Optional local LLM pass for cleaning up dictated text before insertion.

import Foundation

struct LocalLLMModel: Identifiable, Equatable {
    static let recommendedID = "gemma-3-1b-q4"
    static let customID = "custom-gguf"

    let id: String
    let displayName: String
    let detail: String
    let reference: String?

    static let catalog: [LocalLLMModel] = [
        LocalLLMModel(
            id: "gemma-3-1b-q4",
            displayName: "Gemma 3 1B",
            detail: "Recommended default, 806 MB",
            reference: "ggml-org/gemma-3-1b-it-GGUF:Q4_K_M"
        ),
        LocalLLMModel(
            id: "qwen3-1.7b-q8",
            displayName: "Qwen3 1.7B",
            detail: "Larger option, 1.83 GB",
            reference: "Qwen/Qwen3-1.7B-GGUF:Q8_0"
        ),
        LocalLLMModel(
            id: customID,
            displayName: "Custom GGUF",
            detail: "Use a local model file",
            reference: nil
        ),
    ]

    static func model(for id: String) -> LocalLLMModel {
        catalog.first { $0.id == id } ?? catalog[0]
    }
}

enum TextPostProcessingError: LocalizedError {
    case missingRunnerPath
    case missingModelPath
    case runnerNotExecutable(String)
    case modelNotFound(String)
    case homebrewNotFound
    case processFailed(Int32, String)
    case timedOut
    case emptyOutput
    case unexpectedResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingRunnerPath:
            return "Choose a local LLM runner."
        case .missingModelPath:
            return "Choose a local GGUF model."
        case .runnerNotExecutable(let path):
            return "LLM runner is not executable: \(path)"
        case .modelNotFound(let path):
            return "LLM model was not found: \(path)"
        case .homebrewNotFound:
            return "Homebrew was not found. Install llama.cpp manually."
        case .processFailed(let code, let details):
            return details.isEmpty ? "Local LLM exited with code \(code)." : "Local LLM exited with code \(code): \(details)"
        case .timedOut:
            return "Local LLM timed out."
        case .emptyOutput:
            return "Local LLM returned no text."
        case .unexpectedResponse(let response):
            return response.isEmpty
                ? "Local LLM returned an unexpected response."
                : "Local LLM returned an unexpected response: \(response)"
        }
    }
}

final class LocalLLMPostProcessor: TextPostProcessing {
    static let defaultRunnerPath = detectedRunnerPath() ?? "/opt/homebrew/bin/llama-cli"
    static let defaultInstructions = "You are a transcription cleanup engine. Rewrite the user's dictated transcript as clean final text for immediate pasting. Keep the original meaning and intent. Remove filler words and false starts. Fix punctuation and capitalization. Make only conservative wording changes. Do not summarize, answer, invent subject lines, or add commentary. Return only the final rewritten text."
    static let installURL = URL(string: "https://github.com/ggml-org/llama.cpp")!

    private static let runnerCandidates = [
        "/opt/homebrew/bin/llama",
        "/opt/homebrew/bin/llama-cli",
        "/usr/local/bin/llama",
        "/usr/local/bin/llama-cli",
    ]

    private static let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    private let timeout: TimeInterval
    private let prepareTimeout: TimeInterval

    init(timeout: TimeInterval = 60, prepareTimeout: TimeInterval = 600) {
        self.timeout = timeout
        self.prepareTimeout = prepareTimeout
    }

    func prepare(configuration: TextPostProcessingConfiguration) async throws {
        let timeout = prepareTimeout
        let response = try await Task.detached(priority: .userInitiated) {
            try Self.run(
                systemPrompt: "Reply with OK and nothing else.",
                userPrompt: "ping",
                configuration: configuration,
                timeout: timeout,
                maxTokens: 8
            )
        }.value

        let normalized = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .lowercased()
        guard normalized == "ok" else {
            throw TextPostProcessingError.unexpectedResponse(response)
        }
    }

    func improve(_ text: String, configuration: TextPostProcessingConfiguration) async throws -> String {
        let timeout = timeout
        return try await Task.detached(priority: .userInitiated) {
            try Self.run(
                systemPrompt: Self.rewriteSystemPrompt(instructions: configuration.instructions),
                userPrompt: text.trimmingCharacters(in: .whitespacesAndNewlines),
                configuration: configuration,
                timeout: timeout,
                maxTokens: 64
            )
        }.value
    }

    static func detectedRunnerPath() -> String? {
        detectedRunnerPath(in: runnerCandidates)
    }

    static func detectedRunnerPath(in candidates: [String]) -> String? {
        candidates.first { runnerExists(at: $0) }
    }

    static func detectedBrewPath() -> String? {
        brewCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func runnerExists(at path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: expandedPath(path))
    }

    static func installLlamaCpp() async throws -> String {
        guard let brewPath = detectedBrewPath() else {
            throw TextPostProcessingError.homebrewNotFound
        }

        return try await Task.detached(priority: .userInitiated) {
            try installLlamaCpp(using: brewPath)
        }.value
    }

    static func rewriteSystemPrompt(instructions: String) -> String {
        let style = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return style.isEmpty ? defaultInstructions : style
    }

    static func cleanedOutput(_ output: String, userPrompt: String) -> String {
        var text = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        let promptMarker = "> \(userPrompt)"
        if let range = text.range(of: promptMarker) {
            text = String(text[range.upperBound...])
        }

        text = text.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?m)^\[ Prompt:.*$"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?m)^Exiting\.\.\.$"#,
            with: "",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(
        systemPrompt: String,
        userPrompt: String,
        configuration: TextPostProcessingConfiguration,
        timeout: TimeInterval,
        maxTokens: Int
    ) throws -> String {
        let runnerPath = expandedPath(configuration.runnerPath)

        guard !runnerPath.isEmpty else { throw TextPostProcessingError.missingRunnerPath }
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw TextPostProcessingError.runnerNotExecutable(runnerPath)
        }

        let task = Process()
        let outputPipe = Pipe()
        let finished = DispatchSemaphore(value: 0)
        let outputRead = DispatchSemaphore(value: 0)
        var outputData = Data()

        task.executableURL = URL(fileURLWithPath: runnerPath)
        task.arguments = runnerCommandPrefix(for: runnerPath) + (try modelArguments(for: configuration)) + [
            "-sys", systemPrompt,
            "-p", userPrompt,
            "-n", "\(maxTokens)",
            "-c", "2048",
            "--temp", "0.1",
            "--top-k", "20",
            "--top-p", "0.8",
            "--simple-io",
            "--no-display-prompt",
            "-st",
            "--reasoning", "off",
        ]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = outputPipe
        task.standardError = outputPipe
        task.terminationHandler = { _ in finished.signal() }

        try task.run()

        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputRead.signal()
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            task.terminate()
            throw TextPostProcessingError.timedOut
        }

        outputRead.wait()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            throw TextPostProcessingError.processFailed(
                task.terminationStatus,
                output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let cleaned = cleanedOutput(output, userPrompt: userPrompt)
        guard !cleaned.isEmpty else { throw TextPostProcessingError.emptyOutput }
        return cleaned
    }

    static func modelArguments(for configuration: TextPostProcessingConfiguration) throws -> [String] {
        let model = LocalLLMModel.model(for: configuration.modelID)
        if let reference = model.reference {
            return ["-hf", reference]
        }

        let modelPath = expandedPath(configuration.customModelPath)
        guard !modelPath.isEmpty else { throw TextPostProcessingError.missingModelPath }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TextPostProcessingError.modelNotFound(modelPath)
        }
        return ["-m", modelPath]
    }

    static func expandedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^~(?=/|$)"#, with: NSHomeDirectory(), options: .regularExpression)
    }

    private static func installLlamaCpp(using brewPath: String) throws -> String {
        let task = Process()
        let finished = DispatchSemaphore(value: 0)

        task.executableURL = URL(fileURLWithPath: brewPath)
        task.arguments = ["install", "llama.cpp"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in finished.signal() }

        try task.run()
        guard finished.wait(timeout: .now() + 600) == .success else {
            task.terminate()
            throw TextPostProcessingError.timedOut
        }

        guard task.terminationStatus == 0 else {
            throw TextPostProcessingError.processFailed(task.terminationStatus, "")
        }
        guard let runner = detectedRunnerPath() else {
            throw TextPostProcessingError.runnerNotExecutable("llama.cpp installed, but no llama runner was found.")
        }
        return runner
    }

    private static func runnerCommandPrefix(for runnerPath: String) -> [String] {
        URL(fileURLWithPath: runnerPath).lastPathComponent == "llama" ? ["cli"] : []
    }

}
