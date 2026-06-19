import XCTest
@testable import PhoneHubCore

final class IOSDiscoveryTests: XCTestCase {
    func testParseDevicectlDevicesWithTwoIOSDevices() throws {
        let data = Data("""
        {
          "result": {
            "devices": [
              {
                "identifier": "00008110-001234563C91801E",
                "deviceProperties": { "name": "Benas iPhone" },
                "hardwareProperties": {
                  "marketingName": "iPhone 15 Pro",
                  "productType": "iPhone16,1",
                  "osVersionNumber": "18.5",
                  "platform": "iOS"
                },
                "connectionProperties": {
                  "tunnelState": "connected",
                  "transportType": "usb"
                }
              },
              {
                "identifier": "00008120-00ABCDEF12345678",
                "deviceProperties": { "name": "Spare iPhone" },
                "hardwareProperties": {
                  "marketingName": "iPhone 14",
                  "productType": "iPhone14,7",
                  "osVersionNumber": "17.6",
                  "platform": "iOS"
                },
                "connectionProperties": {
                  "tunnelState": "disconnected",
                  "transportType": "network"
                }
              }
            ]
          }
        }
        """.utf8)

        let devices = parseDevicectlDevices(data)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].id, "00008110-001234563C91801E")
        XCTAssertEqual(devices[0].platform, .ios)
        XCTAssertEqual(devices[0].model, "iPhone 15 Pro")
        XCTAssertEqual(devices[0].osVersion, "18.5")
        XCTAssertEqual(devices[0].status, "connected")
        XCTAssertEqual(devices[1].id, "00008120-00ABCDEF12345678")
        XCTAssertEqual(devices[1].platform, .ios)
        XCTAssertEqual(devices[1].model, "iPhone 14")
        XCTAssertEqual(devices[1].osVersion, "17.6")
        XCTAssertEqual(devices[1].status, "disconnected")
    }

    func testParseDevicectlDevicesEmptyArray() {
        let data = Data("""
        { "result": { "devices": [] } }
        """.utf8)

        XCTAssertTrue(parseDevicectlDevices(data).isEmpty)
    }

    func testParseDevicectlDevicesMissingOptionalFieldsDefaultsSensibly() {
        let data = Data("""
        {
          "result": {
            "devices": [
              {
                "identifier": "00008110-001234563C91801E",
                "deviceProperties": { "name": "Benas iPhone" },
                "hardwareProperties": {
                  "platform": "iOS"
                },
                "connectionProperties": {}
              }
            ]
          }
        }
        """.utf8)

        let devices = parseDevicectlDevices(data)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].id, "00008110-001234563C91801E")
        XCTAssertEqual(devices[0].model, "Benas iPhone")
        XCTAssertEqual(devices[0].osVersion, "")
        XCTAssertEqual(devices[0].status, "unknown")
    }

    func testParseDevicectlDevicesExcludesNonIOSDevices() {
        let data = Data("""
        {
          "result": {
            "devices": [
              {
                "identifier": "MAC-123",
                "deviceProperties": { "name": "Mac" },
                "hardwareProperties": {
                  "marketingName": "MacBook Pro",
                  "osVersionNumber": "15.5",
                  "platform": "macOS"
                },
                "connectionProperties": {
                  "tunnelState": "connected"
                }
              }
            ]
          }
        }
        """.utf8)

        XCTAssertTrue(parseDevicectlDevices(data).isEmpty)
    }
}
