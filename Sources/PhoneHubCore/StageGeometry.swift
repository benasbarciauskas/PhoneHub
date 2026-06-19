import CoreGraphics
import Foundation

public func aspectFitRect(aspectRatio: CGFloat, in container: CGRect, inset: CGFloat) -> CGRect {
    let clampedInset = max(0, inset)
    let insetContainer = container.insetBy(dx: clampedInset, dy: clampedInset)
    let maxWidth = max(0, min(container.width, insetContainer.width))
    let maxHeight = max(0, min(container.height, insetContainer.height))

    guard maxWidth > 0, maxHeight > 0, aspectRatio > 0, aspectRatio.isFinite else {
        return CGRect(x: container.midX, y: container.midY, width: 0, height: 0)
    }

    var width = maxWidth
    var height = width / aspectRatio

    if height > maxHeight {
        height = maxHeight
        width = height * aspectRatio
    }

    width = min(width, maxWidth, container.width)
    height = min(height, maxHeight, container.height)

    return CGRect(x: container.midX - width / 2,
                  y: container.midY - height / 2,
                  width: width,
                  height: height)
}
