import XCTest
@testable import PhoneHubCore

final class AutomationProbeTests: XCTestCase {
    func testParsesRealMirroirDescribeScreenLines() {
        let fixture = """
        Screen (418x920, portrait):
        - "Settings" button at (209, 100)
        - "General" cell at (209, 340)
        - "Wi-Fi" cell at (209, 260)
        """
        XCTAssertEqual(parseScreenElements(fixture), [
            ScreenElement(label: "Settings", x: 209, y: 100),
            ScreenElement(label: "General", x: 209, y: 340),
            ScreenElement(label: "Wi-Fi", x: 209, y: 260)
        ])
    }

    func testParsesCoordinatesAnywhereAndJSONishElements() {
        let fixture = """
        element "Continue" role=button center = (12.5, 44)
        {"label":"Privacy & Security","x":201,"y":512.5}
        { label: "Bluetooth", position: { x: 180, y: 220 } }
        """
        XCTAssertEqual(parseScreenElements(fixture), [
            ScreenElement(label: "Continue", x: 12.5, y: 44),
            ScreenElement(label: "Privacy & Security", x: 201, y: 512.5),
            ScreenElement(label: "Bluetooth", x: 180, y: 220)
        ])
    }

    func testProbeKeepsStoredPointWhenMatchWithinSixtyPoints() {
        let stored = Automation.Binding(x: 100, y: 100)
        XCTAssertEqual(probe(step: "general", stored: stored,
                             elements: [.init(label: "General", x: 136, y: 148)]), .keep(stored))
    }

    func testProbeRebindsMovedOrPreviouslyUnboundElement() {
        let moved = Automation.Binding(x: 220, y: 300)
        XCTAssertEqual(probe(step: "General settings", stored: .init(x: 10, y: 10),
                             elements: [.init(label: "General", x: 220, y: 300)]), .rebind(moved))
        XCTAssertEqual(probe(step: "GENERAL", stored: nil,
                             elements: [.init(label: "General settings", x: 220, y: 300)]), .rebind(moved))
    }

    func testProbeUsesNearestFuzzyMatchAndReportsMissing() {
        let stored = Automation.Binding(x: 100, y: 100)
        let elements = [
            ScreenElement(label: "Account", x: 300, y: 300),
            ScreenElement(label: "Account details", x: 120, y: 110)
        ]
        XCTAssertEqual(probe(step: "Account", stored: stored, elements: elements), .keep(stored))
        XCTAssertEqual(probe(step: "Missing", stored: stored, elements: elements), .missing)
    }
}
