import Foundation

public struct ScreenElement: Equatable, Sendable {
    public let label: String
    public let x: Double
    public let y: Double

    public init(label: String, x: Double, y: Double) {
        self.label = label
        self.x = x
        self.y = y
    }
}

public enum ProbeOutcome: Equatable, Sendable {
    case keep(Automation.Binding)
    case rebind(Automation.Binding)
    case missing
}

public func parseScreenElements(_ describeOutput: String) -> [ScreenElement] {
    describeOutput.split(whereSeparator: \Character.isNewline).compactMap { rawLine in
        let line = String(rawLine)
        guard let label = capture(#"[\"']?label[\"']?\s*:\s*\"([^\"]+)\""#, in: line)
                ?? capture(#"\"([^\"]+)\""#, in: line) else { return nil }

        if let groups = captures(#"\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)"#,
                                 in: line), groups.count == 2,
           let x = Double(groups[0]), let y = Double(groups[1]) {
            return ScreenElement(label: label, x: x, y: y)
        }

        guard let xText = capture(#"\bx[\"']?\s*:\s*(-?\d+(?:\.\d+)?)"#, in: line),
              let yText = capture(#"\by[\"']?\s*:\s*(-?\d+(?:\.\d+)?)"#, in: line),
              let x = Double(xText), let y = Double(yText) else { return nil }
        return ScreenElement(label: label, x: x, y: y)
    }
}

public func probe(step label: String, stored: Automation.Binding?,
                  elements: [ScreenElement]) -> ProbeOutcome {
    let sought = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let matches = elements.filter {
        let candidate = $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !candidate.isEmpty && (candidate.contains(sought) || sought.contains(candidate))
    }
    guard !matches.isEmpty else { return .missing }

    let match: ScreenElement
    if let stored {
        match = matches.min {
            squaredDistance($0, stored) < squaredDistance($1, stored)
        }!
        if squaredDistance(match, stored) <= 60 * 60 { return .keep(stored) }
    } else {
        match = matches[0]
    }
    return .rebind(.init(x: match.x, y: match.y))
}

private func squaredDistance(_ element: ScreenElement, _ binding: Automation.Binding) -> Double {
    let dx = element.x - binding.x
    let dy = element.y - binding.y
    return dx * dx + dy * dy
}

private func capture(_ pattern: String, in text: String) -> String? {
    captures(pattern, in: text)?.first
}

private func captures(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
        return nil
    }
    return (1..<match.numberOfRanges).compactMap { index in
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}
