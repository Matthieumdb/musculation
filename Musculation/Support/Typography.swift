import SwiftUI

extension Font {
    /// SF Pro Rounded for big figures, as in Fitness and Health, scaled with Dynamic Type.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title2) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style.uiTextStyle).scaledValue(for: size), weight: weight, design: .rounded)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}

/// Card header in the style of Health: a small tinted symbol and title above the figures.
struct CardTitle: View {
    let title: String
    var symbol: String?
    var tint: Color = .accentColor

    init(_ title: String, symbol: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension Animation {
    /// easeOutQuint (easings.net): fast start, long soft landing. For things that appear or move.
    static let appEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)
    /// Same curve, slower, for rings and bars that fill up.
    static let appEaseSlow = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.9)
    /// Light spring for taps and toggles.
    static let appSpring = Animation.spring(duration: 0.4, bounce: 0.15)
}
