import CoreGraphics

/// Map a click in the SwiftUI view's coordinate space to a device pixel,
/// accounting for aspect-fit letterboxing. Result is clamped to the device bounds.
public func viewPointToDevicePoint(_ point: CGPoint,
                                   viewSize: CGSize,
                                   deviceSize: CGSize) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0,
          deviceSize.width > 0, deviceSize.height > 0 else { return .zero }

    let scale = min(viewSize.width / deviceSize.width,
                    viewSize.height / deviceSize.height)
    let rendered = CGSize(width: deviceSize.width * scale,
                          height: deviceSize.height * scale)
    let offsetX = (viewSize.width - rendered.width) / 2
    let offsetY = (viewSize.height - rendered.height) / 2

    let deviceX = (point.x - offsetX) / scale
    let deviceY = (point.y - offsetY) / scale

    return CGPoint(x: min(max(deviceX, 0), deviceSize.width),
                   y: min(max(deviceY, 0), deviceSize.height))
}
