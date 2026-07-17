import XCTest
@testable import PhoneHub

final class IPhoneSwitcherTests: XCTestCase {
    func testExactMatchReturnsPopupAndItemIndex() {
        let menus = [
            ["Light", "Dark", "Auto"],
            ["iPhone 13 Pro", "iPhone 16 Pro"],
            ["Left", "Right"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro"],
            popupMenus: menus
        )
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 1, itemIndex: 1))
    }

    func testCaseInsensitiveMatch() {
        let menus = [
            ["Displays"],
            ["iphone 13 pro", "IPHONE 16 PRO"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro"],
            popupMenus: menus
        )
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 1, itemIndex: 1))
    }

    func testContainmentMatchOnPartialName() {
        let menus = [
            ["Some Control"],
            ["My iPhone 16 Pro", "Work iPhone"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro"],
            popupMenus: menus
        )
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 1, itemIndex: 0))
    }

    func testPrefersExactOverLaterContainment() {
        let menus = [
            ["iPhone", "Not a phone"],
            ["iPhone 16 Pro Max", "iPhone 16 Pro"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro"],
            popupMenus: menus
        )
        // Exact equality wins in pass 1 on popup 1 item 1 before containment on item 0.
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 1, itemIndex: 1))
    }

    func testMultipleTargetNamesUsesFirstAvailable() {
        let menus = [
            ["Pixel 9"],
            ["My iPhone", "Other"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro", "My iPhone"],
            popupMenus: menus
        )
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 1, itemIndex: 0))
    }

    func testNoMatchReturnsNil() {
        let menus = [
            ["Light", "Dark"],
            ["None", "Built-in Display"],
        ]
        XCTAssertNil(matchIPhonePopupMenuItem(
            targetNames: ["iPhone 16 Pro"],
            popupMenus: menus
        ))
    }

    func testEmptyTargetsOrMenusReturnNil() {
        XCTAssertNil(matchIPhonePopupMenuItem(targetNames: [], popupMenus: [["iPhone"]]))
        XCTAssertNil(matchIPhonePopupMenuItem(targetNames: ["iPhone"], popupMenus: []))
        XCTAssertNil(matchIPhonePopupMenuItem(targetNames: ["  "], popupMenus: [["iPhone"]]))
    }

    func testSkipsEmptyMenuItemTitles() {
        let menus = [
            ["", "  ", "iPhone 13 Pro"],
        ]
        let match = matchIPhonePopupMenuItem(
            targetNames: ["iPhone 13 Pro"],
            popupMenus: menus
        )
        XCTAssertEqual(match, IPhonePopupMatch(popupIndex: 0, itemIndex: 2))
    }

    func testPickerUnavailableMessageIsStable() {
        XCTAssertEqual(
            IPhoneSwitchResult.pickerUnavailable.userMessage,
            iPhonePickerUnavailableMessage
        )
        XCTAssertTrue(iPhonePickerUnavailableMessage.contains("2+ iPhones"))
    }
}
