import Foundation

enum OneRepMax {
    /// Epley formula: weight × (1 + reps / 30).
    static func epley(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }
}
