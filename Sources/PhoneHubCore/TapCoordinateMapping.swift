import CoreGraphics
import Foundation

/// Maps a top-left-origin click in an aspect-fit image view into the coordinate
/// space consumed by the phone MCP tap tool. Android uses image/device pixels.
/// Mirroir screenshots use backing pixels while `status` reports the authoritative
/// mirroring-window point size used by `tap` and `describe_screen`.
public func mapClickToDevicePoint(
    clickInView: CGPoint,
    viewSize: CGSize,
    imagePixelSize: CGSize,
    deviceSpaceSize: CGSize
) -> CGPoint {
    let values = [
        clickInView.x, clickInView.y,
        viewSize.width, viewSize.height,
        imagePixelSize.width, imagePixelSize.height,
        deviceSpaceSize.width, deviceSpaceSize.height,
    ]
    guard values.allSatisfy(\.isFinite),
          viewSize.width > 0, viewSize.height > 0,
          imagePixelSize.width > 0, imagePixelSize.height > 0,
          deviceSpaceSize.width > 0, deviceSpaceSize.height > 0 else {
        return .zero
    }

    let fitScale = min(
        viewSize.width / imagePixelSize.width,
        viewSize.height / imagePixelSize.height
    )
    guard fitScale.isFinite, fitScale > 0 else { return .zero }

    let renderedSize = CGSize(
        width: imagePixelSize.width * fitScale,
        height: imagePixelSize.height * fitScale
    )
    let origin = CGPoint(
        x: (viewSize.width - renderedSize.width) / 2,
        y: (viewSize.height - renderedSize.height) / 2
    )
    let localX = min(max(clickInView.x - origin.x, 0), renderedSize.width)
    let localY = min(max(clickInView.y - origin.y, 0), renderedSize.height)
    let imageX = localX / fitScale
    let imageY = localY / fitScale

    return CGPoint(
        x: imageX / imagePixelSize.width * deviceSpaceSize.width,
        y: imageY / imagePixelSize.height * deviceSpaceSize.height
    )
}

/// Parses mirroir's current `status` text, for example
/// `Connected — mirroring active (window: 410x898, ...)`.
public func parseMirroirWindowSize(_ status: String) -> CGSize? {
    let pattern = #"\bwindow:\s*([0-9]+)x([0-9]+)\b"#
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(
              in: status,
              range: NSRange(status.startIndex..., in: status)
          ),
          let widthRange = Range(match.range(at: 1), in: status),
          let heightRange = Range(match.range(at: 2), in: status),
          let width = Double(status[widthRange]),
          let height = Double(status[heightRange]),
          width.isFinite, height.isFinite,
          width > 0, height > 0 else {
        return nil
    }
    return CGSize(width: width, height: height)
}
