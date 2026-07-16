import CoreGraphics
import Foundation

public enum FitStep: Equatable, Sendable {
    case smaller
    case larger
    // Retained for compatibility; fitStep now probes larger for every fitting size.
    case fits
}

public enum WallGridPreset: String, CaseIterable, Identifiable, Sendable {
    case auto
    case twoByTwo
    case threeByTwo
    case row

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .twoByTwo: return "2x2"
        case .threeByTwo: return "3x2"
        case .row: return "Row"
        }
    }

    public var capacity: Int {
        switch self {
        case .auto, .row: return 9
        case .twoByTwo: return 4
        case .threeByTwo: return 6
        }
    }
}

/// Chooses the best discrete View-menu size observed during one fit pass.
/// If the menu cannot produce a fitting size, the smallest observed size is
/// returned so the AppKit layer can attempt a final best-effort aspect fit.
public func selectFinalMirrorMenuSize(from observedSizes: [CGSize], target: CGSize) -> CGSize? {
    let validSizes = observedSizes.filter { $0.width > 0 && $0.height > 0 }
    guard !validSizes.isEmpty else { return nil }

    let fittingSizes = validSizes.filter { $0.width <= target.width && $0.height <= target.height }
    return (fittingSizes.max(by: { area(of: $0) < area(of: $1) })
        ?? validSizes.min(by: { area(of: $0) < area(of: $1) }))
}

public func aspectFitSize(_ contentSize: CGSize, within target: CGSize) -> CGSize {
    guard contentSize.width > 0,
          contentSize.height > 0,
          target.width > 0,
          target.height > 0 else {
        return .zero
    }

    let scale = min(1, target.width / contentSize.width, target.height / contentSize.height)
    return CGSize(width: contentSize.width * scale,
                  height: contentSize.height * scale)
}

public struct MirrorAXResizeDecision: Equatable, Sendable {
    public let finalSize: CGSize
    public let resizeWasIgnored: Bool

    public init(finalSize: CGSize, resizeWasIgnored: Bool) {
        self.finalSize = finalSize
        self.resizeWasIgnored = resizeWasIgnored
    }
}

/// Uses the actual AX read-back when available. If AX sizing is ignored or
/// cannot be verified, the menu-controlled size remains the safe fallback.
public func finalMirrorSizeAfterBestEffortAXResize(
    menuSize: CGSize,
    requestedSize: CGSize,
    readBackSize: CGSize?
) -> MirrorAXResizeDecision {
    guard let readBackSize,
          readBackSize.width > 0,
          readBackSize.height > 0 else {
        return MirrorAXResizeDecision(finalSize: menuSize, resizeWasIgnored: true)
    }

    let resizeWasIgnored = abs(readBackSize.width - requestedSize.width) > 1
        || abs(readBackSize.height - requestedSize.height) > 1
    return MirrorAXResizeDecision(finalSize: readBackSize, resizeWasIgnored: resizeWasIgnored)
}

private func area(of size: CGSize) -> CGFloat {
    size.width * size.height
}

public func fitStep(current: CGSize, target: CGSize) -> FitStep {
    if current.width > target.width || current.height > target.height {
        return .smaller
    }

    return .larger
}

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

public func rectsEffectivelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance &&
        abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance &&
        abs(lhs.height - rhs.height) <= tolerance
}

/// Whether an AX window needs a real reposition. A missing current position is
/// treated as movable; sub-point layout jitter is ignored.
public func shouldRepositionWindow(current: CGPoint?, target: CGPoint, tolerance: CGFloat) -> Bool {
    guard let current else { return true }
    return abs(current.x - target.x) > tolerance || abs(current.y - target.y) > tolerance
}

public func gridTileRects(count: Int, within container: CGRect, inset: CGFloat, spacing: CGFloat) -> [CGRect] {
    guard count > 0, container.width > 0, container.height > 0 else { return [] }

    let clampedInset = max(0, inset)
    let clampedSpacing = max(0, spacing)
    let tileCount = max(1, count)
    let columns = Int(ceil(sqrt(Double(tileCount))))
    let rows = Int(ceil(Double(tileCount) / Double(columns)))
    let insetX = min(clampedInset, max(0, container.width / 2))
    let insetY = min(clampedInset, max(0, container.height / 2))
    let available = container.insetBy(dx: insetX, dy: insetY)

    let totalSpacingX = clampedSpacing * CGFloat(max(0, columns - 1))
    let totalSpacingY = clampedSpacing * CGFloat(max(0, rows - 1))
    let tileWidth = max(0, (available.width - totalSpacingX) / CGFloat(columns))
    let tileHeight = max(0, (available.height - totalSpacingY) / CGFloat(rows))
    let gridWidth = CGFloat(columns) * tileWidth + totalSpacingX
    let gridHeight = CGFloat(rows) * tileHeight + totalSpacingY
    let originX = available.midX - gridWidth / 2
    let originY = available.midY - gridHeight / 2

    return (0..<tileCount).map { index in
        let row = index / columns
        let column = index % columns
        return CGRect(x: originX + CGFloat(column) * (tileWidth + clampedSpacing),
                      y: originY + CGFloat(row) * (tileHeight + clampedSpacing),
                      width: tileWidth,
                      height: tileHeight)
    }
}

public func gridTileRects(count: Int,
                          preset: WallGridPreset,
                          within container: CGRect,
                          inset: CGFloat,
                          spacing: CGFloat) -> [CGRect] {
    guard preset != .auto else {
        return gridTileRects(count: count, within: container, inset: inset, spacing: spacing)
    }
    guard count > 0, container.width > 0, container.height > 0 else { return [] }

    let dimensions: (columns: Int, rows: Int)
    switch preset {
    case .auto:
        return []
    case .twoByTwo:
        dimensions = (2, 2)
    case .threeByTwo:
        dimensions = (3, 2)
    case .row:
        dimensions = (9, 1)
    }

    let tileCount = min(count, preset.capacity)
    let clampedInset = max(0, inset)
    let clampedSpacing = max(0, spacing)
    let insetX = min(clampedInset, max(0, container.width / 2))
    let insetY = min(clampedInset, max(0, container.height / 2))
    let available = container.insetBy(dx: insetX, dy: insetY)
    let totalSpacingX = clampedSpacing * CGFloat(dimensions.columns - 1)
    let totalSpacingY = clampedSpacing * CGFloat(dimensions.rows - 1)
    let tileWidth = max(0, (available.width - totalSpacingX) / CGFloat(dimensions.columns))
    let tileHeight = max(0, (available.height - totalSpacingY) / CGFloat(dimensions.rows))

    return (0..<tileCount).map { index in
        let row = index / dimensions.columns
        let column = index % dimensions.columns
        return CGRect(x: available.minX + CGFloat(column) * (tileWidth + clampedSpacing),
                      y: available.minY + CGFloat(row) * (tileHeight + clampedSpacing),
                      width: tileWidth,
                      height: tileHeight)
    }
}

public func swapSlots(order: [String: Int], from: String, to: String) -> [String: Int] {
    guard let fromSlot = order[from], let toSlot = order[to] else { return order }
    var swapped = order
    swapped[from] = toSlot
    swapped[to] = fromSlot
    return swapped
}

public func zoomedTileRect(in tile: CGRect, scale: CGFloat, minimumScale: CGFloat = 0.35) -> CGRect {
    let lowerBound = min(1, max(0, minimumScale))
    let clampedScale = min(1, max(lowerBound, scale))
    let size = CGSize(width: max(0, tile.width) * clampedScale,
                      height: max(0, tile.height) * clampedScale)
    return CGRect(x: tile.midX - size.width / 2,
                  y: tile.midY - size.height / 2,
                  width: size.width,
                  height: size.height)
}
