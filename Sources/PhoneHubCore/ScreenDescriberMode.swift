import Foundation

/// mirroir-mcp `screenDescriberMode`: how the iOS screen-describer works.
/// `"auto"` resolves to vision only if embacle-ffi is linked into mirroir; else OCR.
public enum ScreenDescriberMode: String, Codable, CaseIterable, Sendable {
    case auto
    case ocr
    case vision

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .ocr: return "OCR"
        case .vision: return "Vision"
        }
    }
}
