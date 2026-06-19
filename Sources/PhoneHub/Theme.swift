import SwiftUI

/// OLED-black design system. Single source of truth for color, spacing, radius, motion.
enum Theme {
    // Color tokens
    static let bg        = Color(hex: 0x000000)
    static let surface   = Color(hex: 0x0B0B0D)
    static let elevated  = Color(hex: 0x1C1C1F)
    static let border    = Color(hex: 0x2A2A2E)
    static let text      = Color(hex: 0xF5F5F7)
    static let subtext   = Color(hex: 0x8A8A8E)
    static let accent    = Color(hex: 0x0A84FF)
    static let ok        = Color(hex: 0x30D158)
    static let warn      = Color(hex: 0xFFD60A)
    static let err       = Color(hex: 0xFF453A)

    // Spacing grid (4pt)
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24

    // Radii
    static let rSm: CGFloat = 6
    static let rMd: CGFloat = 10
    static let rLg: CGFloat = 16

    // Motion — fast, purposeful (Emil Kowalski)
    static let focusSpring = Animation.spring(response: 0.32, dampingFraction: 0.85)
    static let selection   = Animation.easeOut(duration: 0.16)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Card surface modifier used across the UI.
struct CardSurface: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Theme.elevated : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func cardSurface(elevated: Bool = false) -> some View { modifier(CardSurface(elevated: elevated)) }
}
