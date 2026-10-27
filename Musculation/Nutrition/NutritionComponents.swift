import SwiftUI

extension Grade {
    var color: Color {
        switch self {
        case .A: Color(red: 0.2, green: 0.62, blue: 0.3)
        case .B: Color(red: 0.52, green: 0.73, blue: 0.2)
        case .C: Color(red: 0.95, green: 0.72, blue: 0.1)
        case .D: Color(red: 0.93, green: 0.48, blue: 0.16)
        case .E: Color(red: 0.84, green: 0.22, blue: 0.18)
        }
    }
}

extension MacroKey {
    var label: String {
        switch self {
        case .kcal: "Calories"
        case .p: "Protéines"
        case .c: "Glucides"
        case .f: "Lipides"
        }
    }

    var short: String {
        switch self {
        case .kcal: "kcal"
        case .p: "Prot."
        case .c: "Gluc."
        case .f: "Lip."
        }
    }

    var color: Color {
        switch self {
        case .kcal: Theme.calories
        case .p: Theme.protein
        case .c: Theme.carbs
        case .f: Theme.fat
        }
    }

    var unit: String { self == .kcal ? "kcal" : "g" }
}

extension Aisle {
    var color: Color {
        switch self {
        case .viandes: .red
        case .oeufs: .yellow
        case .laitiers: .cyan
        case .fromages: .orange
        case .feculents: .brown
        case .legumes: .green
        case .fruits: .pink
        case .graisses: .mint
        case .sauces: .indigo
        case .poudre: .purple
        case .extras: .gray
        }
    }
}

/// Nutri-Score-like letter.
struct GradeBadge: View {
    let grade: Grade
    var size: CGFloat = 22

    var body: some View {
        Text(grade.rawValue)
            .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(grade.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel("Note \(grade.rawValue), \(grade.verdict)")
    }
}

/// Product picture from Open Food Facts, or a tinted aisle symbol.
struct ProductThumb: View {
    let product: Product
    var grade: Grade?
    var size: CGFloat = 46

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let url = URL(string: product.imageURL), !product.imageURL.isEmpty {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: size, height: size)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))

            if let grade {
                GradeBadge(grade: grade, size: size * 0.42)
                    .offset(x: 4, y: 4)
            }
        }
        .padding(.trailing, grade == nil ? 0 : 4)
        .padding(.bottom, grade == nil ? 0 : 4)
    }

    private var placeholder: some View {
        Image(systemName: product.fam.symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(product.fam.color)
            .frame(width: size, height: size)
            .background(product.fam.color.opacity(0.15))
    }
}

/// Proportion of calories coming from protein, carbs and fat.
struct MacroMixBar: View {
    let n: Nutrients

    var body: some View {
        let kp = n.p * 4, kc = n.c * 4, kf = n.f * 9
        let sum = max(kp + kc + kf, 1)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                Capsule().fill(Theme.protein).frame(width: proxy.size.width * kp / sum)
                Capsule().fill(Theme.carbs).frame(width: proxy.size.width * kc / sum)
                Capsule().fill(Theme.fat).frame(width: proxy.size.width * kf / sum)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Value, bar and label for one macro against its target.
struct MacroGauge: View {
    let key: MacroKey
    let value: Double
    let total: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(key.short)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))")
                .font(.title3.bold())
                .fontDesign(.rounded)
            + Text(key == .kcal ? "" : " g")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressBar(progress: total > 0 ? value / total : 0, tint: key.color, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Capsule toggle used for filters and choices.
struct ChoiceChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Theme.field), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Lays chips out in rows, wrapping to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Short message that fades away, shown above the floating buttons.
struct Toast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassSurface(in: Capsule(), fallback: .regularMaterial)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Inline error, in red.
struct InlineError: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Empty-state block inside a card.
struct EmptyCardContent: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(Theme.gradient)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// − value + control for small counts.
struct CountStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...14

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .font(.body.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }
}
