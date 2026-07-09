// LocalLLMPostProcessor.swift
// VocaMac
//
// Optional local LLM pass for cleaning up dictated text before insertion.

import Foundation

enum TextPostProcessingError: LocalizedError {
    case missingRunnerPath
    case missingModelPath
    case runnerNotExecutable(String)
    case modelNotFound(String)
    case processFailed(Int32)
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
        case .processFailed(let code):
            return "Local LLM exited with code \(code)."
        case .timedOut:
            return "Local LLM timed out."
        case .emptyOutput:
            return "Local LLM returned no text."
        }
    }
}

final class LocalLLMPostProcessor: TextPostProcessing {
    static let defaultRunnerPath = "/opt/homebrew/bin/llama-cli"
    static let defaultInstructions = "Clean up dictation into polished text while preserving my meaning. Remove filler words, false starts, duplicate phrases, and obvious speech disfluencies. Fix punctuation and capitalization. Keep my tone concise and natural. Return only the final text."

    private let timeout: TimeInterval

    init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    func improve(_ text: String, configuration: TextPostProcessingConfiguration) async throws -> String {
        let timeout = timeout
        return try await Task.detached(priority: .userInitiated) {
            try Self.run(text, configuration: configuration, timeout: timeout)
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
        timeout: TimeInterval
    ) throws -> String {
        let runnerPath = expandedPath(configuration.runnerPath)
        let modelPath = expandedPath(configuration.modelPath)

        guard !runnerPath.isEmpty else { throw TextPostProcessingError.missingRunnerPath }
        guard !modelPath.isEmpty else { throw TextPostProcessingError.missingModelPath }
        guard FileManager.default.isExecutableFile(atPath: runnerPath) else {
            throw TextPostProcessingError.runnerNotExecutable(runnerPath)
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TextPostProcessingError.modelNotFound(modelPath)
        }

        let prompt = prompt(for: text, instructions: configuration.instructions)
        let task = Process()
        let stdout = Pipe()
        let finished = DispatchSemaphore(value: 0)

        task.executableURL = URL(fileURLWithPath: runnerPath)
        task.arguments = [
            "-m", modelPath,
            "-p", prompt,
            "-n", "256",
            "--temp", "0.2",
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
            throw TextPostProcessingError.processFailed(task.terminationStatus)
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        let cleaned = cleanedOutput(output, prompt: prompt)
        guard !cleaned.isEmpty else { throw TextPostProcessingError.emptyOutput }
        return cleaned
    }

    private static func expandedPath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^~(?=/|$)"#, with: NSHomeDirectory(), options: .regularExpression)
    }
}
