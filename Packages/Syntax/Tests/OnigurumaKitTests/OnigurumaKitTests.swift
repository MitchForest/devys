// OnigurumaKitTests.swift
// Tests for OnigurumaKit wrapper

import Testing
@testable import OnigurumaKit

@Suite("OnigurumaKit Tests")
struct OnigurumaKitTests {
    
    @Test("Compiles simple pattern")
    func testCompileSimple() throws {
        let regex = try OnigRegex(pattern: "hello")
        #expect(regex.pattern == "hello")
    }
    
    @Test("Matches simple string")
    func testMatchSimple() throws {
        let regex = try OnigRegex(pattern: "world")
        let match = regex.search(in: "hello world")
        
        #expect(match != nil)
        #expect(match?.start == 6)  // "world" starts at byte 6
        #expect(match?.end == 11)   // "world" ends at byte 11
    }
    
    @Test("Captures groups")
    func testCaptureGroups() throws {
        let regex = try OnigRegex(pattern: "(\\w+)\\s+(\\w+)")
        let match = regex.search(in: "hello world")
        
        #expect(match != nil)
        #expect(match?.captures.count == 3)  // Full match + 2 groups
        
        // Full match
        #expect(match?.captures[0].start == 0)
        #expect(match?.captures[0].end == 11)
        
        // Group 1: "hello"
        #expect(match?.captures[1].start == 0)
        #expect(match?.captures[1].end == 5)
        
        // Group 2: "world"
        #expect(match?.captures[2].start == 6)
        #expect(match?.captures[2].end == 11)
    }
    
    @Test("Named capturing groups work")
    func testNamedCaptures() throws {
        // This is a key feature that NSRegularExpression doesn't support well
        let regex = try OnigRegex(pattern: "(?<name>\\w+)")
        let match = regex.search(in: "hello")
        
        #expect(match != nil)
        #expect((match?.captures.count ?? 0) >= 1)
    }
    
    @Test("Named backreferences work")
    func testNamedBackreferences() throws {
        // This pattern matches quoted strings with matching quotes
        // NSRegularExpression cannot handle \k<q>
        let regex = try OnigRegex(pattern: "(?<q>['\"]).*?\\k<q>")
        
        let match1 = regex.search(in: "'hello'")
        #expect(match1 != nil, "Should match single-quoted string")
        
        let match2 = regex.search(in: "\"hello\"")
        #expect(match2 != nil, "Should match double-quoted string")
        
        // This should NOT match (mismatched quotes)
        let match3 = regex.search(in: "'hello\"")
        #expect(match3 == nil, "Should not match mismatched quotes")
    }
    
    @Test("Swift let pattern works")
    func testSwiftLetPattern() throws {
        // This is the exact pattern from the Swift grammar that fails with NSRegularExpression
        let pattern = "\\b(?:(async)\\s+)?(let|var)\\b\\s+(?<q>`?)[_\\p{L}][_\\p{L}\\p{N}\\p{M}]*(\\k<q>)\\s*:"
        
        let regex = try OnigRegex(pattern: pattern)
        
        let match = regex.search(in: "let name: String")
        #expect(match != nil, "Should match 'let name: String'")
    }
    
    @Test("Scanner finds best match")
    func testScannerBestMatch() throws {
        let scanner = try OnigScanner(patterns: ["abc", "ab", "a"])
        
        let match = scanner.findNextMatch(in: "abc", from: 0)
        #expect(match != nil)
        #expect(match?.patternIndex == 0)  // "abc" should match first (earliest and longest)
    }
    
    @Test("Scanner handles multiple patterns")
    func testScannerMultiplePatterns() throws {
        let scanner = try OnigScanner(patterns: ["func", "let", "var"])
        
        let match1 = scanner.findNextMatch(in: "let x = 1", from: 0)
        #expect(match1?.patternIndex == 1)  // "let"
        
        let match2 = scanner.findNextMatch(in: "func hello()", from: 0)
        #expect(match2?.patternIndex == 0)  // "func"
    }
    
    @Test("Swift func pattern captures correctly")
    func testSwiftFuncPatternCaptures() throws {
        // Simplified version of Swift grammar's declarations-function begin pattern
        let pattern = #"\b(func)\s+(\w+)\s*(?=\()"#
        
        let regex = try OnigRegex(pattern: pattern)
        let match = regex.search(in: "func hello() {")
        #expect(match != nil, "Should match 'func hello() {'")
        
        if let match = match {
            #expect(match.captures.count == 3, "Should have 3 captures")
            #expect(match.captures[0].start == 0 && match.captures[0].end == 10, "Full match")
            #expect(match.captures[1].start == 0 && match.captures[1].end == 4, "Capture 1 = func")
            #expect(match.captures[2].start == 5 && match.captures[2].end == 10, "Capture 2 = hello")
        }
    }
    
    @Test("Pattern with named groups and backreferences captures numbered groups")
    func testNamedGroupsWithBackreferences() throws {
        // This tests the CRITICAL fix: patterns with named groups like (?<q>...)
        // must still capture numbered groups like (func)
        let pattern = #"\b(func)\s+((?<q>`?)\w+(\k<q>))\s*(?=\()"#
        
        let regex = try OnigRegex(pattern: pattern)
        
        // Test with backtick-quoted function name
        let match1 = regex.search(in: "func `hello`() {")
        #expect(match1 != nil, "Should match backtick-quoted function")
        if let m = match1 {
            // Capture 1 should be "func" (0-4), NOT the backtick capture
            let cap1 = m.captures.first { $0.index == 1 }
            #expect(cap1?.start == 0 && cap1?.end == 4, "Capture 1 should be 'func'")
        }
        
        // Test without backticks
        let match2 = regex.search(in: "func hello() {")
        #expect(match2 != nil, "Should match regular function")
        if let m = match2 {
            let cap1 = m.captures.first { $0.index == 1 }
            #expect(cap1?.start == 0 && cap1?.end == 4, "Capture 1 should be 'func'")
        }
    }
}
