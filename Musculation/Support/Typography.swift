import SwiftUI
import CoreText

/// Satoshi (Fontshare) for titles and figures, SF Pro for running text.
/// The font files are fetched by `scripts/fetch-fonts.sh`; without them the app falls back to SF Pro Rounded.
enum AppFont {
    static let medium = "Satoshi-Medium"
    static let bold = "Satoshi-Bold"
    static let black = "Satoshi-Black"

    /// Registers the bundled font files and styles the navigation bar titles.
    static func setUp() {
        for ext in ["otf", "ttf"] {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        guard let large = UIFont(name: black, size: 34), let inline = UIFont(name: bold, size: 17) else { return }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
    }
}

extension Font {
    /// Display face for titles and big numbers, scaled with Dynamic Type.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title2) -> Font {
        let name = switch weight {
        case .black, .heavy: AppFont.black
        case .medium, .regular, .light: AppFont.medium
        default: AppFont.bold
        }
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .rounded).weight(weight)
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
