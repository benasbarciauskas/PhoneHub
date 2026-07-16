import Foundation
import XCTest
@testable import PhoneHubCore

final class TextSourceParserTests: XCTestCase {
    func testTXTParsesNumberedLines() throws {
        let items = try parse("1. First caption\n2) Second caption", as: .plainText)
        XCTAssertEqual(items, ["First caption", "Second caption"])
    }

    func testTXTParsesMixedSupportedListMarkersWhenEveryLineIsAListItem() throws {
        let items = try parse("- First\n* Second\n• Third\n4. Fourth", as: .plainText)
        XCTAssertEqual(items, ["First", "Second", "Third", "Fourth"])
    }

    func testTXTParsesBlankLineSeparatedBlocks() throws {
        let items = try parse(
            "First line\ncontinues here\n\n  Second block  \n\n\nThird",
            as: .plainText
        )
        XCTAssertEqual(items, ["First line\ncontinues here", "Second block", "Third"])
    }

    func testTXTFallsBackToWholeDocumentWhenNoCompletePatternMatches() throws {
        XCTAssertEqual(
            try parse("A caption\nwith another line", as: .plainText),
            ["A caption\nwith another line"]
        )
        XCTAssertEqual(
            try parse("- one list-looking line\nplain prose", as: .plainText),
            ["- one list-looking line\nplain prose"]
        )
    }

    func testStripsControlsButPreservesTabsAndNewlines() throws {
        let items = try parse("Hello\u{0}\u{7}\tworld\nnext", as: .plainText)
        XCTAssertEqual(items, ["Hello\tworld\nnext"])
    }

    func testDropsItemsThatBecomeEmpty() throws {
        let items = try parse("1. \u{0}\n2. kept", as: .plainText)
        XCTAssertEqual(items, ["kept"])
    }

    func testRejectsMoreThanTenThousandItems() {
        let text = (1...10_001).map { "\($0). x" }.joined(separator: "\n")
        assertError(.tooManyItems, data: Data(text.utf8), format: .plainText)
    }

    func testRejectsOversizedInputBeforeParsing() {
        let data = Data(repeating: 0x61, count: TextSourceParser.maximumBytes + 1)
        assertError(.fileTooLarge, data: data, format: .plainText)
    }

    func testRejectsInvalidUTF8() {
        assertError(.invalidUTF8, data: Data([0xC3, 0x28]), format: .plainText)
    }

    func testRejectsInputWithNoNonEmptyItems() {
        assertError(.noItems, data: Data(" \n\t\u{0}".utf8), format: .plainText)
    }

    func testJSONAcceptsTopLevelStringArray() throws {
        let items = try parse(#"["one", "two", "\u0000three"]"#, as: .json)
        XCTAssertEqual(items, ["one", "two", "three"])
    }

    func testJSONAcceptsItemsObject() throws {
        let items = try parse(#"{"items":["one","two"]}"#, as: .json)
        XCTAssertEqual(items, ["one", "two"])
    }

    func testJSONRejectsWrongRootsMixedValuesAndExtraKeys() {
        for text in [
            #"{"other":["one"]}"#,
            #"{"items":["one"],"extra":true}"#,
            #"["one", 2]"#,
            #"{"items":["one", null]}"#,
            #""one""#,
        ] {
            assertError(.invalidStructure, data: Data(text.utf8), format: .json)
        }
    }

    func testJSONRejectsMalformedInput() {
        assertError(.malformedJSON, data: Data(#"["one""#.utf8), format: .json)
    }

    func testJSONRejectsExcessiveNestingBeforeFoundationParsing() {
        let depth = TextSourceParser.maximumJSONDepth + 1
        let text = String(repeating: "[", count: depth)
            + #""value""#
            + String(repeating: "]", count: depth)
        assertError(.excessiveNesting, data: Data(text.utf8), format: .json)
    }

    func testJSONDepthScannerIgnoresBracketsInsideStrings() throws {
        let bracketText = String(repeating: "[", count: 100)
        let data = try JSONSerialization.data(withJSONObject: [bracketText])
        XCTAssertEqual(try TextSourceParser.parse(data: data, format: .json), [bracketText])
    }

    func testXMLAcceptsOnlyItemsWithDirectItemChildren() throws {
        let items = try parse(
            "<items><item>one &amp; two</item><item> line\n two </item></items>",
            as: .xml
        )
        XCTAssertEqual(items, ["one & two", "line\n two"])
    }

    func testXMLRejectsMalformedUnexpectedAndNestedStructures() {
        for text in [
            "<items><item>one</items>",
            "<root><item>one</item></root>",
            "<items><other>one</other></items>",
            "<items><item><b>one</b></item></items>",
            "<items>outside<item>one</item></items>",
            "<items><item>one</item></items><items/>",
        ] {
            assertAnyXMLParseError(text)
        }
    }

    func testXMLRejectsDTDAndXXEAttempts() {
        let attempts = [
            "<!DOCTYPE items><items><item>one</item></items>",
            "<!DOCTYPE items [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><items><item>&xxe;</item></items>",
            "<!ENTITY xxe SYSTEM \"https://example.com/evil\"><items><item>&xxe;</item></items>",
        ]
        for text in attempts {
            assertError(.unsafeXML, data: Data(text.utf8), format: .xml)
        }
    }

    func testXMLRejectsNoItems() {
        assertError(.noItems, data: Data("<items></items>".utf8), format: .xml)
    }

    private func parse(_ text: String, as format: TextSourceFormat) throws -> [String] {
        try TextSourceParser.parse(data: Data(text.utf8), format: format)
    }

    private func assertError(
        _ expected: TextSourceParseError,
        data: Data,
        format: TextSourceFormat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try TextSourceParser.parse(data: data, format: format),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? TextSourceParseError, expected, file: file, line: line)
        }
    }

    private func assertAnyXMLParseError(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try TextSourceParser.parse(data: Data(text.utf8), format: .xml),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(error is TextSourceParseError, file: file, line: line)
        }
    }
}
