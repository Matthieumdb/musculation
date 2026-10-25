import SwiftUI

extension Double {
    /// "82,5 kg"
    var kgText: String {
        "\(formatted(.number.precision(.fractionLength(0...1)))) kg"
    }

    /// "1,25 kg", for small jumps that must not be rounded.
    var preciseKgText: String {
        "\(formatted(.number.precision(.fractionLength(0...2)))) kg"
    }
}

/// "45 min" or "1 h 05"
func durationText(_ interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    guard minutes >= 60 else { return "\(minutes) min" }
    return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
