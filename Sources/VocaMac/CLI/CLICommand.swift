// CLICommand.swift
// VocaMac
//
// Parses the one-shot, headless command-line interface before SwiftUI starts.

import Foundation

/// Determines whether process arguments belong to the GUI or headless CLI.
enum CLIInvocationMode: Equatable {
    case gui
    case cli
}

/// A validated VocaMac command-line operation.
enum CLICommand: Equatable {
    case help
    case transcribeFile(path: String, model: String?, language: String?)
    case listModels

    /// Any explicit arguments are handled before SwiftUI constructs the app.
    /// This makes unknown arguments fail safely instead of opening the GUI.
    static func invocationMode(arguments: [String]) -> CLIInvocationMode {
        arguments.isEmpty ? .gui : .cli
    }

    /// Parse arguments excluding the executable path.
    static func parse(arguments: [String]) throws -> CLICommand {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .help
        }

        var audioPath: String?
        var model: String?
        var language: String?
        var wantsList = false
        var wantsJSON = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--transcribe-file":
                guard audioPath == nil else {
                    throw CLIError(.invalidArguments, "--transcribe-file may only be provided once.")
                }
                audioPath = try value(after: argument, in: arguments, index: &index)
            case "--list-models":
                guard !wantsList else {
                    throw CLIError(.invalidArguments, "--list-models may only be provided once.")
                }
                wantsList = true
            case "--model":
                guard model == nil else {
                    throw CLIError(.invalidArguments, "--model may only be provided once.")
                }
                model = try value(after: argument, in: arguments, index: &index)
            case "--language":
                guard language == nil else {
                    throw CLIError(.invalidArguments, "--language may only be provided once.")
                }
                language = try value(after: argument, in: arguments, index: &index)
            case "--json":
                guard !wantsJSON else {
                    throw CLIError(.invalidArguments, "--json may only be provided once.")
                }
                wantsJSON = true
            default:
                throw CLIError(.invalidArguments, "Unknown argument: \(argument)")
            }
            index += 1
        }

        guard wantsJSON else {
            throw CLIError(.invalidArguments, "Headless commands require --json.")
        }
        guard wantsList != (audioPath != nil) else {
            throw CLIError(
                .invalidArguments,
                "Specify exactly one of --transcribe-file or --list-models."
            )
        }

        if wantsList {
            guard model == nil, language == nil else {
                throw CLIError(.invalidArguments, "--model and --language only apply to --transcribe-file.")
            }
            return .listModels
        }

        guard let audioPath else {
            throw CLIError(.invalidArguments, "Missing value for --transcribe-file.")
        }
        return .transcribeFile(path: audioPath, model: model, language: language)
    }

    private static func value(
        after argument: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count,
              !arguments[valueIndex].hasPrefix("--"),
              !arguments[valueIndex].isEmpty else {
            throw CLIError(.invalidArguments, "Missing value for \(argument).")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}
