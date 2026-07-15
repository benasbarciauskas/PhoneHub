import Foundation

public enum MirrorDeviceMatch: Equatable, Sendable {
    case match
    case mismatch(actual: String)
}

public func compareMirroredDevice(clickedModel: String, mirroredTitle: String) -> MirrorDeviceMatch {
    let clicked = clickedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let actual = mirroredTitle.trimmingCharacters(in: .whitespacesAndNewlines)

    if clicked.localizedCaseInsensitiveCompare(actual) == .orderedSame {
        return .match
    }
    return .mismatch(actual: actual)
}
