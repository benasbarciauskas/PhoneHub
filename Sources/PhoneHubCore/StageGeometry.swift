import CoreGraphics
import Foundation

public func centeredRect(forContentSize contentSize: CGSize, within container: CGRect, inset: CGFloat) -> CGRect {
    let width = max(0, contentSize.width)
    let height = max(0, contentSize.height)
    let clampedInset = max(0, inset)
    let insetContainer = container.insetBy(dx: min(clampedInset, max(0, container.width / 2)),
                                           dy: min(clampedInset, max(0, container.height / 2)))

    return CGRect(x: insetContainer.midX - width / 2,
                  y: insetContainer.midY - height / 2,
                  width: width,
                  height: height)
}

public func requiredStageSize(forMirrorSize mirrorSize: CGSize, inset: CGFloat) -> CGSize {
    let clampedInset = max(0, inset)
    return CGSize(width: max(0, mirrorSize.width) + 2 * clampedInset,
                  height: max(0, mirrorSize.height) + 2 * clampedInset)
}
