import CoreGraphics
import Foundation

public struct HumanRecordingPoint: Equatable, Sendable {
    public let windowPoint: CGPoint
    public let devicePoint: CGPoint

    public init(windowPoint: CGPoint, devicePoint: CGPoint) {
        self.windowPoint = windowPoint
        self.devicePoint = devicePoint
    }
}

public enum HumanRecordedEvent: Equatable, Sendable {
    case leftMouseDown(time: TimeInterval, point: HumanRecordingPoint)
    case leftMouseUp(time: TimeInterval, point: HumanRecordingPoint)
    case rightMouseDown(time: TimeInterval)
    case scroll(time: TimeInterval, deltaX: Double, deltaY: Double)
    case printableKey(time: TimeInterval, text: String)
    case returnKey(time: TimeInterval)
    case deleteKey(time: TimeInterval)
    case nonPrintableKey(time: TimeInterval)
    case idle(time: TimeInterval)
}

public func humanRecordedKeyEvent(
    time: TimeInterval,
    keyCode: Int64,
    text: String,
    hasCommandOrControl: Bool
) -> HumanRecordedEvent {
    if keyCode == 36 || keyCode == 76 { return .returnKey(time: time) }
    if keyCode == 51 || keyCode == 117 { return .deleteKey(time: time) }
    guard !hasCommandOrControl, !text.isEmpty,
          text.unicodeScalars.allSatisfy({
              !CharacterSet.controlCharacters.contains($0)
          }) else { return .nonPrintableKey(time: time) }
    return .printableKey(time: time, text: text)
}

public struct HumanRecordingTranslator: Sendable {
    private struct MouseDown: Sendable {
        let time: TimeInterval
        let point: HumanRecordingPoint
    }

    private struct Click: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        let point: HumanRecordingPoint
    }

    private struct ScrollBurst: Sendable {
        let start: TimeInterval
        var last: TimeInterval
        var deltaX: Double
        var deltaY: Double
    }

    private struct TextBuffer: Sendable {
        let start: TimeInterval
        var last: TimeInterval
        var text: String
    }

    private var mouseDown: MouseDown?
    private var click: Click?
    private var scroll: ScrollBurst?
    private var text: TextBuffer?
    private var lastStepEnd: TimeInterval?

    public init() {}

    public mutating func consume(_ event: HumanRecordedEvent) -> [AutomationStep] {
        var output: [AutomationStep] = []
        flushExpired(at: event.time, into: &output)

        switch event {
        case let .leftMouseDown(time, point):
            flushText(into: &output)
            flushScroll(into: &output)
            mouseDown = MouseDown(time: time, point: point)

        case let .leftMouseUp(time, point):
            flushText(into: &output)
            flushScroll(into: &output)
            guard let down = mouseDown else { break }
            mouseDown = nil
            classifyMouseGesture(from: down, to: point, at: time, into: &output)

        case .rightMouseDown:
            flushClick(into: &output)
            flushText(into: &output)
            flushScroll(into: &output)
            mouseDown = nil

        case let .scroll(time, deltaX, deltaY):
            flushClick(into: &output)
            flushText(into: &output)
            mouseDown = nil
            if var burst = scroll {
                burst.last = time
                burst.deltaX += deltaX
                burst.deltaY += deltaY
                scroll = burst
            } else {
                scroll = ScrollBurst(start: time, last: time,
                                     deltaX: deltaX, deltaY: deltaY)
            }

        case let .printableKey(time, value):
            flushClick(into: &output)
            flushScroll(into: &output)
            guard !value.isEmpty else { break }
            if var buffer = text {
                buffer.last = time
                buffer.text += value
                text = buffer
            } else {
                text = TextBuffer(start: time, last: time, text: value)
            }

        case let .returnKey(time):
            flushClick(into: &output)
            flushScroll(into: &output)
            flushText(into: &output)
            append(.pressKey(id: UUID(), key: "return"), start: time, end: time, into: &output)

        case let .deleteKey(time):
            flushClick(into: &output)
            flushScroll(into: &output)
            if var buffer = text, !buffer.text.isEmpty {
                buffer.text.removeLast()
                buffer.last = time
                text = buffer
            } else {
                append(.pressKey(id: UUID(), key: "delete"), start: time, end: time, into: &output)
            }

        case .nonPrintableKey:
            flushClick(into: &output)
            flushScroll(into: &output)
            flushText(into: &output)

        case .idle:
            break
        }
        return output
    }

    public mutating func finish(at time: TimeInterval) -> [AutomationStep] {
        var output: [AutomationStep] = []
        flushClick(into: &output)
        flushScroll(into: &output)
        flushText(into: &output)
        mouseDown = nil
        return output
    }

    private mutating func flushExpired(at time: TimeInterval, into output: inout [AutomationStep]) {
        if let click, time - click.end >= 0.35 { flushClick(into: &output) }
        if let scroll, time - scroll.last >= 0.4 { flushScroll(into: &output) }
        if let text, time - text.last >= 2 { flushText(into: &output) }
    }

    private mutating func classifyMouseGesture(
        from down: MouseDown,
        to point: HumanRecordingPoint,
        at time: TimeInterval,
        into output: inout [AutomationStep]
    ) {
        let duration = max(0, time - down.time)
        let dx = point.windowPoint.x - down.point.windowPoint.x
        let dy = point.windowPoint.y - down.point.windowPoint.y
        let distance = hypot(dx, dy)

        if distance >= 40 {
            flushClick(into: &output)
            let direction: String
            if abs(dx) >= abs(dy) {
                direction = dx >= 0 ? "right" : "left"
            } else {
                direction = dy >= 0 ? "down" : "up"
            }
            append(.swipe(id: UUID(), direction: direction),
                   start: down.time, end: time, into: &output)
            return
        }

        if duration >= 0.6, distance < 6 {
            flushClick(into: &output)
            append(.longPress(id: UUID(), label: nil,
                              x: point.devicePoint.x, y: point.devicePoint.y,
                              durationMs: Int((duration * 1_000).rounded())),
                   start: down.time, end: time, into: &output)
            return
        }

        guard duration < 0.3, distance < 6 else {
            flushClick(into: &output)
            return
        }

        let current = Click(start: down.time, end: time, point: point)
        if let previous = click {
            let separation = hypot(
                point.windowPoint.x - previous.point.windowPoint.x,
                point.windowPoint.y - previous.point.windowPoint.y
            )
            if down.time - previous.end <= 0.35, separation <= 10 {
                click = nil
                append(.doubleTap(id: UUID(), label: nil,
                                  x: point.devicePoint.x, y: point.devicePoint.y),
                       start: previous.start, end: time, into: &output)
            } else {
                flushClick(into: &output)
                click = current
            }
        } else {
            click = current
        }
    }

    private mutating func flushClick(into output: inout [AutomationStep]) {
        guard let click else { return }
        self.click = nil
        append(.tap(id: UUID(), label: nil,
                    x: click.point.devicePoint.x, y: click.point.devicePoint.y),
               start: click.start, end: click.end, into: &output)
    }

    private mutating func flushScroll(into output: inout [AutomationStep]) {
        guard let scroll else { return }
        self.scroll = nil
        guard scroll.deltaX != 0 || scroll.deltaY != 0 else { return }
        let direction: String
        if abs(scroll.deltaX) >= abs(scroll.deltaY) {
            direction = scroll.deltaX >= 0 ? "right" : "left"
        } else {
            direction = scroll.deltaY >= 0 ? "down" : "up"
        }
        append(.swipe(id: UUID(), direction: direction),
               start: scroll.start, end: scroll.last, into: &output)
    }

    private mutating func flushText(into output: inout [AutomationStep]) {
        guard let text else { return }
        self.text = nil
        guard !text.text.isEmpty else { return }
        append(.typeText(id: UUID(), text: text.text),
               start: text.start, end: text.last, into: &output)
    }

    private mutating func append(
        _ step: AutomationStep,
        start: TimeInterval,
        end: TimeInterval,
        into output: inout [AutomationStep]
    ) {
        if let previous = lastStepEnd {
            let gapMilliseconds = (start - previous) * 1_000
            if gapMilliseconds >= 800 {
                let rounded = Int((gapMilliseconds / 100).rounded()) * 100
                output.append(.wait(id: UUID(), ms: min(5_000, rounded)))
            }
        }
        output.append(step)
        lastStepEnd = max(start, end)
    }
}

private extension HumanRecordedEvent {
    var time: TimeInterval {
        switch self {
        case let .leftMouseDown(time, _), let .leftMouseUp(time, _),
             let .rightMouseDown(time), let .scroll(time, _, _),
             let .printableKey(time, _), let .returnKey(time),
             let .deleteKey(time), let .nonPrintableKey(time), let .idle(time):
            return time
        }
    }
}

public func mapIPhoneMirrorPoint(
    globalPoint: CGPoint,
    windowFrame: CGRect,
    contentSize: CGSize
) -> HumanRecordingPoint? {
    guard recordingGeometryIsValid(globalPoint: globalPoint, windowFrame: windowFrame,
                                   deviceSize: contentSize),
          windowFrame.contains(globalPoint) else { return nil }
    let titleBarHeight = max(0, windowFrame.height - contentSize.height)
    let local = CGPoint(x: globalPoint.x - windowFrame.minX,
                        y: globalPoint.y - windowFrame.minY - titleBarHeight)
    guard local.x >= 0, local.y >= 0,
          local.x <= contentSize.width, local.y <= contentSize.height else { return nil }
    return HumanRecordingPoint(windowPoint: local, devicePoint: local)
}

public func mapAndroidMirrorPoint(
    globalPoint: CGPoint,
    windowFrame: CGRect,
    devicePixelSize: CGSize
) -> HumanRecordingPoint? {
    guard recordingGeometryIsValid(globalPoint: globalPoint, windowFrame: windowFrame,
                                   deviceSize: devicePixelSize),
          windowFrame.contains(globalPoint) else { return nil }
    let local = CGPoint(x: globalPoint.x - windowFrame.minX,
                        y: globalPoint.y - windowFrame.minY)
    let device = CGPoint(x: local.x / windowFrame.width * devicePixelSize.width,
                         y: local.y / windowFrame.height * devicePixelSize.height)
    return HumanRecordingPoint(windowPoint: local, devicePoint: device)
}

private func recordingGeometryIsValid(
    globalPoint: CGPoint,
    windowFrame: CGRect,
    deviceSize: CGSize
) -> Bool {
    let values = [globalPoint.x, globalPoint.y, windowFrame.minX, windowFrame.minY,
                  windowFrame.width, windowFrame.height,
                  deviceSize.width, deviceSize.height]
    return values.allSatisfy(\.isFinite)
        && windowFrame.width > 0 && windowFrame.height > 0
        && deviceSize.width > 0 && deviceSize.height > 0
}

public func parseAndroidWindowManagerSize(_ output: String) -> CGSize? {
    let pattern = #"\b(Physical|Override) size:\s*([0-9]+)x([0-9]+)\b"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(output.startIndex..., in: output)
    let matches = expression.matches(in: output, range: range)
    var physical: CGSize?
    var override: CGSize?
    for match in matches {
        guard let kindRange = Range(match.range(at: 1), in: output),
              let widthRange = Range(match.range(at: 2), in: output),
              let heightRange = Range(match.range(at: 3), in: output),
              let width = Double(output[widthRange]),
              let height = Double(output[heightRange]),
              width > 0, height > 0 else { continue }
        let size = CGSize(width: width, height: height)
        if output[kindRange] == "Override" { override = size } else { physical = size }
    }
    return override ?? physical
}
