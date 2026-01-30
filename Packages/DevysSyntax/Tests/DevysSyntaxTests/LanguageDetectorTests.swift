// LanguageDetectorTests.swift
// DevysSyntax Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import Foundation
@testable import DevysSyntax

@Suite("LanguageDetector Tests")
struct LanguageDetectorTests {
    @Test("Detects Swift files")
    func detectSwift() {
        #expect(LanguageDetector.detect(from: "main.swift") == "swift")
        #expect(LanguageDetector.detect(from: "/path/to/File.swift") == "swift")
    }
    
    @Test("Detects JavaScript and TypeScript variants")
    func detectJavaScript() {
        #expect(LanguageDetector.detect(from: "app.js") == "javascript")
        #expect(LanguageDetector.detect(from: "app.mjs") == "javascript")
        #expect(LanguageDetector.detect(from: "app.ts") == "typescript")
        #expect(LanguageDetector.detect(from: "App.tsx") == "tsx")
        #expect(LanguageDetector.detect(from: "App.jsx") == "jsx")
    }
    
    @Test("Detects special filenames")
    func detectSpecialFilenames() {
        #expect(LanguageDetector.detect(from: "Dockerfile") == "dockerfile")
        #expect(LanguageDetector.detect(from: "Makefile") == "makefile")
        #expect(LanguageDetector.detect(from: "Gemfile") == "ruby")
        #expect(LanguageDetector.detect(from: ".gitignore") == "gitignore")
    }
    
    @Test("Returns plaintext for unknown extensions")
    func detectUnknown() {
        #expect(LanguageDetector.detect(from: "file.xyz") == "plaintext")
        #expect(LanguageDetector.detect(from: nil) == "plaintext")
    }
    
    @Test("Display names are correct")
    func displayNames() {
        #expect(LanguageDetector.displayName(for: "swift") == "Swift")
        #expect(LanguageDetector.displayName(for: "javascript") == "JavaScript")
        #expect(LanguageDetector.displayName(for: "cpp") == "C++")
        #expect(LanguageDetector.displayName(for: "plaintext") == "Plain Text")
    }
}
