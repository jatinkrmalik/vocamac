// LocalLLMPostProcessorTests.swift
// VocaMac Tests

import XCTest
@testable import VocaMac

final class LocalLLMPostProcessorTests: XCTestCase {
    func testRewriteSystemPromptUsesCustomInstructions() {
        XCTAssertEqual(
            LocalLLMPostProcessor.rewriteSystemPrompt(instructions: "Keep it concise."),
            "Keep it concise."
        )
    }

    func testCleanedOutputExtractsAssistantReplyFromChatTranscript() {
        let userPrompt = "um let's email Namrata about the launch"
        let output = """
        Loading model...

        available commands:
          /exit or Ctrl+C     stop or exit

        > um let's email Namrata about the launch

        <think>
        hidden reasoning
        </think>
        Email Namrata about the launch.

        [ Prompt: 99.6 t/s | Generation: 214.6 t/s ]

        Exiting...
        """

        XCTAssertEqual(
            LocalLLMPostProcessor.cleanedOutput(output, userPrompt: userPrompt),
            "Email Namrata about the launch."
        )
    }

    func testModelArgumentsUseHuggingFaceReferenceForCatalogModel() throws {
        let config = TextPostProcessingConfiguration(
            runnerPath: "/usr/bin/false",
            modelID: "gemma-3-1b-q4",
            customModelPath: "",
            instructions: ""
        )

        XCTAssertEqual(
            try LocalLLMPostProcessor.modelArguments(for: config),
            ["-hf", "ggml-org/gemma-3-1b-it-GGUF:Q4_K_M"]
        )
    }

    func testModelArgumentsValidateCustomModelPath() {
        let config = TextPostProcessingConfiguration(
            runnerPath: "/usr/bin/false",
            modelID: LocalLLMModel.customID,
            customModelPath: "/definitely/not/a/model.gguf",
            instructions: ""
        )

        XCTAssertThrowsError(try LocalLLMPostProcessor.modelArguments(for: config))
    }

    func testDetectedRunnerPathUsesFirstExecutableCandidate() {
        XCTAssertEqual(
            LocalLLMPostProcessor.detectedRunnerPath(in: ["/definitely/missing", "/bin/echo"]),
            "/bin/echo"
        )
    }

    func testPrepareDrainsChattyRunnerOutput() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocamac-chatty-runner-\(UUID().uuidString).sh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        let script = """
        #!/bin/sh
        i=0
        while [ "$i" -lt 5000 ]; do
          printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\n'
          i=$((i + 1))
        done
        printf '> ping\\n\\n'
        printf 'OK\\n\\n'
        printf '[ Prompt: 1.0 t/s | Generation: 1.0 t/s ]\\n\\n'
        printf 'Exiting...\\n'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let processor = LocalLLMPostProcessor(prepareTimeout: 2)
        try await processor.prepare(
            configuration: TextPostProcessingConfiguration(
                runnerPath: scriptURL.path,
                modelID: "gemma-3-1b-q4",
                customModelPath: "",
                instructions: ""
            )
        )
    }
}
