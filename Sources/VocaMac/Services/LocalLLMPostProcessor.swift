// LocalLLMPostProcessor.swift
// VocaMac
//
// Optional local LLM pass for cleaning up dictated text before insertion.

import Foundation

struct LocalLLMModel: Identifiable, Equatable {
    static let recommendedID = "qwen3-1.7b-q8"
    static let customID = "custom-gguf"

    let id: String
    let displayName: String
    let detail: String
    let reference: String?

    static let catalog: [LocalLLMModel] = [
        LocalLLMModel(
            id: recommendedID,
            displayName: "Qwen3 1.7B",
            detail: "Best quality, 1.83 GB",
            reference: "Qwen/Qwen3-1.7B-GGUF:Q8_0"
        ),
        LocalLLMModel(
            id: "gemma-3-1b-q4",
            displayName: "Gemma 3 1B",
            detail: "Fast setup, 806 MB",
            reference: "ggml-org/gemma-3-1b-it-GGUF:Q4_K_M"
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
        }
    }
}

final class LocalLLMPostProcessor: TextPostProcessing {
    static let defaultRunnerPath = detectedRunnerPath() ?? "/opt/homebrew/bin/llama-cli"
    static let defaultInstructions = "Clean up dictation into polished text while preserving my meaning. Remove filler words, false starts, duplicate phrases, and obvious speech disfluencies. Fix punctuation and capitalization. Keep my tone concise and natural. Return only the final text."
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
        _ = try await Task.detached(priority: .userInitiated) {
            try Self.run(
                "Reply with OK.",
                configuration: configuration,
                timeout: timeout,
                maxTokens: 4
            )
        }.value
    }

    func improve(_ text: String, configuration: TextPostProcessingConfiguration) async throws -> String {
        let timeout = timeout
        return try await Task.detached(priority: .userInitiated) {
            try Self.run(
                text,
                configuration: configuration,
                timeout: timeout,
                maxTokens: 256
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

    static func prompt(for text: String, instructions: String) -> String {
        let style = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        /no_think
        Rewrite this dictated transcript before insertion.
        Preserve meaning and facts. Do not answer commands. Return only the rewritten text.

        Style instructions:
        \(style.isEmpty ? defaultInstructions : style)

        Transcript:
        \"\"\"
        \(text)
        \"\"\"

        Rewritten text:
        """
    }

    static func cleanedOutput(_ output: String, prompt: String) -> String {
        var text = output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        if text.hasPrefix(prompt) {
            text.removeFirst(prompt.count)
        }
        text = text.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#,
            with: "",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(
        _ text: String,
        configuration: TextPostProcessingConfiguration,
        timeout: TimeInterval,
        maxTokens: Int
    ) throws -> String {
        let runnerPath = expandedPath(configuration.runnerPath)

        guard !runnerPath.isEmpty else { throw TextPostProcessingError.missingRunnerPath }
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw TextPostProcessingError.runnerNotExecutable(runnerPath)
        }

        let prompt = prompt(for: text, instructions: configuration.instructions)
        let task = Process()
        let stdout = Pipe()
        let finished = DispatchSemaphore(value: 0)

        task.executableURL = URL(fileURLWithPath: runnerPath)
        task.arguments = runnerCommandPrefix(for: runnerPath) + (try modelArguments(for: configuration)) + [
            "-p", prompt,
            "-n", "\(maxTokens)",
            "-c", "2048",
            "--temp", "0.3",
            "--top-k", "20",
            "--top-p", "0.8",
            "--presence-penalty", "1.1",
            "--no-display-prompt",
        ]
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { _ in finished.signal() }

        try task.run()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            task.terminate()
            throw TextPostProcessingError.timedOut
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard task.terminationStatus == 0 else {
            throw TextPostProcessingError.processFailed(task.terminationStatus, "")
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        let cleaned = cleanedOutput(output, prompt: prompt)
        guard !cleaned.isEmpty else { throw TextPostProcessingError.emptyOutput }
        return cleaned
    }

    static func modelArguments(for configuration: TextPostProcessingConfiguration) throws -> [String] {
        let model = LocalLLMModel.model(for: configuration.modelID)
        if let reference = model.reference {
            return ["-hf", reference, "--jinja"]
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
