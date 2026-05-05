//
//  StaticAnalysisTests.swift
//  LHS LifeTests
//
//  Architecture enforcement via source-file scanning.
//  These tests do not run code — they read .swift files as text and assert
//  that forbidden patterns are absent.
//

import XCTest

final class StaticAnalysisTests: XCTestCase {

    // MARK: - Source file discovery

    /// Path to the app source directory, derived from this test file's location.
    private var appSourceDir: URL {
        // __FILE__ is at .../LHS LifeTests/StaticAnalysisTests.swift
        // Go up two levels: LHS LifeTests/ → project root → LHS Life/
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // LHS LifeTests/
            .deletingLastPathComponent()   // project root
            .appendingPathComponent("LHS Life")
    }

    /// All .swift files under appSourceDir (recursive), excluding the widget extension.
    private var appSwiftFiles: [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: appSourceDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func contents(of file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    private func occurrences(of pattern: String, in files: [URL]) -> [(file: String, line: Int, text: String)] {
        var results: [(file: String, line: Int, text: String)] = []
        for file in files {
            let lines = contents(of: file).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if line.contains(pattern) {
                    results.append((file.lastPathComponent, i + 1, line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return results
    }

    // MARK: 11.1 No @Published in app source

    func test_noPublished() {
        let hits = occurrences(of: "@Published", in: appSwiftFiles)
        XCTAssertTrue(hits.isEmpty,
            "@Published found \(hits.count) time(s). Use @Observable instead.\n" +
            hits.map { "  \($0.file):\($0.line)  \($0.text)" }.joined(separator: "\n"))
    }

    // MARK: 11.2 No @EnvironmentObject in app source

    func test_noEnvironmentObject() {
        let hits = occurrences(of: "@EnvironmentObject", in: appSwiftFiles)
        XCTAssertTrue(hits.isEmpty,
            "@EnvironmentObject found \(hits.count) time(s). Use @Environment(Type.self) instead.\n" +
            hits.map { "  \($0.file):\($0.line)  \($0.text)" }.joined(separator: "\n"))
    }

    // MARK: 11.3 No ObservableObject conformance (except RemindersService)

    func test_noObservableObject() {
        let excluded = ["RemindersService.swift"]
        let files    = appSwiftFiles.filter { !excluded.contains($0.lastPathComponent) }
        let hits     = occurrences(of: ": ObservableObject", in: files)
        XCTAssertTrue(hits.isEmpty,
            ": ObservableObject found \(hits.count) time(s). Use @Observable instead.\n" +
            hits.map { "  \($0.file):\($0.line)  \($0.text)" }.joined(separator: "\n"))
    }

    // MARK: 11.4 No didSet disk writes in UserSettings

    func test_noDidSetDiskWritesInUserSettings() {
        let settingsFiles = appSwiftFiles.filter { $0.lastPathComponent == "UserSettings.swift" }
        for file in settingsFiles {
            let text   = contents(of: file)
            let lines  = text.components(separatedBy: "\n")
            var inDidSet = false
            for line in lines {
                if line.contains("didSet") { inDidSet = true }
                if inDidSet && (line.contains("store.set") || line.contains("defaults.set")) {
                    XCTFail("UserSettings.swift: found disk write inside didSet: \(line.trimmingCharacters(in: .whitespaces))")
                }
                if inDidSet && line.contains("}") { inDidSet = false }
            }
        }
    }

    // MARK: 11.5 No magic numbers in view files (spacing / layout only)
    //
    // Checks that .padding() and .spacing() calls do not use bare numeric literals
    // where LS.* constants should be used instead.
    // Excludes DesignSystem.swift (where constants are defined).
    // Allowed bare values: 0, 1, 2, 0.0, 1.0, 0.5

    func test_noMagicSpacingNumbers() {
        let excluded     = ["DesignSystem.swift"]
        let uiDir        = appSourceDir.appendingPathComponent("UI")
        guard let enumerator = FileManager.default.enumerator(
            at: uiDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let uiFiles = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && !excluded.contains($0.lastPathComponent) }

        let allowedValues: Set<String> = ["0", "1", "2", "0.0", "1.0", "0.5"]
        // Regex matches .padding(<number>) or .spacing(<number>) with no LS. on the line
        let pattern = try! NSRegularExpression(
            pattern: #"\.(padding|spacing)\(\s*(\d+(?:\.\d+)?)\s*\)"#
        )

        var violations: [(file: String, line: Int, text: String)] = []
        for file in uiFiles {
            let lines = contents(of: file).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard !line.contains("LS.") else { continue }  // LS.* present — exempt
                let range = NSRange(line.startIndex..., in: line)
                let matches = pattern.matches(in: line, range: range)
                for match in matches {
                    if let numRange = Range(match.range(at: 2), in: line) {
                        let num = String(line[numRange])
                        if !allowedValues.contains(num) {
                            violations.append((file.lastPathComponent, i + 1, line.trimmingCharacters(in: .whitespaces)))
                        }
                    }
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
            "Magic spacing numbers found \(violations.count) time(s). Use LS.* constants.\n" +
            violations.map { "  \($0.file):\($0.line)  \($0.text)" }.joined(separator: "\n"))
    }

    // MARK: 11.6 Shared files do not import UIKit or SwiftUI

    func test_sharedFilesDoNotImportUIKitOrSwiftUI() {
        let sharedMarker = "// Add this file to:"
        let forbidden    = ["import UIKit", "import SwiftUI"]
        for file in appSwiftFiles {
            let text = contents(of: file)
            guard text.contains(sharedMarker) else { continue }
            for banned in forbidden {
                if text.contains(banned) {
                    XCTFail("Shared file \(file.lastPathComponent) must not contain '\(banned)'")
                }
            }
        }
    }

    // MARK: 11.7 No telemetry print statements

    func test_noTelemetryPrintStatements() {
        let hits = occurrences(of: "// TELEMETRY", in: appSwiftFiles)
        XCTAssertTrue(hits.isEmpty,
            "TELEMETRY comments found \(hits.count) time(s). Remove debug print statements before release.\n" +
            hits.map { "  \($0.file):\($0.line)  \($0.text)" }.joined(separator: "\n"))
    }
}
