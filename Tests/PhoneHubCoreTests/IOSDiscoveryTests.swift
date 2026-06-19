import XCTest
@testable import PhoneHubCore

final class IOSDiscoveryTests: XCTestCase {
    func testParseDevicectlDevicesWithTwoIOSDevices() throws {
        let data = Data("""
        {
          "result": {
            "devices": [
              {
                "identifier": "C59850DA-1234-4567-89AB-ABCDEF123456",
                "deviceProperties": {
                  "name": "Benas iPhone",
                  "osVersionNumber": "26.6",
                  "osBuildUpdate": "23G93",
                  "developerModeStatus": "enabled"
                },
                "hardwareProperties": {
                  "marketingName": "iPhone 15 Pro",
                  "productType": "iPhone16,1",
                  "platform": "iOS",
                  "udid": "00008110-0016592C1E12801E",
                  "ecid": "123456789",
                  "serialNumber": "ABC123DEF456"
                },
                "connectionProperties": {
                  "tunnelState": "connected",
                  "transportType": "usb"
                }
              },
              {
                "identifier": "90F22BE8-1234-4567-89AB-ABCDEF123456",
                "deviceProperties": {
                  "name": "Spare iPhone",
                  "osVersionNumber": "17.6"
                },
                "hardwareProperties": {
                  "marketingName": "iPhone 14",
                  "productType": "iPhone14,7",
                  "platform": "iOS",
                  "udid": "00008120-00ABCDEF12345678"
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
        XCTAssertEqual(devices[0].id, "00008110-0016592C1E12801E")
        XCTAssertEqual(devices[0].platform, .ios)
        XCTAssertEqual(devices[0].model, "iPhone 15 Pro")
        XCTAssertEqual(devices[0].osVersion, "26.6")
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

    func testParseDevicectlDevicesFallsBackToIdentifierWhenUdidMissing() {
        let data = Data("""
        {
          "result": {
            "devices": [
              {
                "identifier": "C59850DA-1234-4567-89AB-ABCDEF123456",
                "deviceProperties": {
                  "name": "Fallback iPhone",
                  "osVersionNumber": "26.6"
                },
                "hardwareProperties": {
                  "marketingName": "iPhone 15 Pro",
                  "platform": "iOS"
                },
                "connectionProperties": {
                  "tunnelState": "connected"
                }
              }
            ]
          }
        }
        """.utf8)

        let devices = parseDevicectlDevices(data)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].id, "C59850DA-1234-4567-89AB-ABCDEF123456")
        XCTAssertEqual(devices[0].osVersion, "26.6")
    }
}
