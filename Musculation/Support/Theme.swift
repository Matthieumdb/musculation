import SwiftUI

enum Theme {
    static let gradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.55, blue: 0.2), Color(red: 0.84, green: 0.13, blue: 0.24)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let background = Color(.systemGroupedBackground)
    static let card = Color(.secondarySystemGroupedBackground)
    static let field = Color(.tertiarySystemFill)
    static let accentRed = Color(red: 0.84, green: 0.13, blue: 0.24)
    static let cardRadius: CGFloat = 20

    // Macro colors, shared by every nutrition screen
    static let calories = Color.orange
    static let protein = Color.blue
    static let carbs = Color.yellow
    static let fat = Color.pink
}

/// Grouped background with a slow, soft color glow behind the title.
/// Content sits on solid cards; Liquid Glass is kept for the controls that float above it.
struct AppBackground: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background
            if #available(iOS 18, *) {
                GlowMesh(paused: scenePhase != .active || reduceMotion)
                    .opacity(colorScheme == .dark ? 0.32 : 0.45)
                    .frame(height: 360)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Animated mesh gradient in the app's warm colors. It stops redrawing when paused.
@available(iOS 18, *)
private struct GlowMesh: View {
    var paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 6
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [Float(0.05 * sin(t)), 0.5], [Float(0.5 + 0.18 * sin(t * 1.3)), Float(0.5 + 0.12 * cos(t))], [Float(1 + 0.05 * cos(t)), 0.5],
                    [0, 1], [Float(0.5 + 0.15 * cos(t * 0.8)), 1], [1, 1],
                ],
                colors: [
                    .orange, Color(red: 1, green: 0.42, blue: 0.3), .pink,
                    Color(red: 1, green: 0.7, blue: 0.4), Theme.accentRed, .purple.opacity(0.7),
                    .clear, .clear, .clear,
                ]
            )
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26, `fallback` fill on earlier versions.
    @ViewBuilder
    func glassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallback: some ShapeStyle = Theme.card
    ) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            background(fallback, in: shape)
        }
        #else
        background(fallback, in: shape)
        #endif
    }

    #if compiler(>=6.2)
    @available(iOS 26, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif

    /// Lets the tab bar shrink while scrolling on iOS 26.
    @ViewBuilder
    func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

extension MuscleGroup {
    var color: Color {
        switch self {
        case .chest: .red
        case .back: .blue
        case .shoulders: .orange
        case .biceps: .purple
        case .triceps: .indigo
        case .legs: .green
        case .glutes: .pink
        case .abs: .teal
        case .fullBody: .brown
        case .cardio: .mint
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .biceps: "dumbbell.fill"
        case .triceps: "figure.strengthtraining.functional"
        case .legs: "figure.run"
        case .glutes: "figure.cross.training"
        case .abs: "figure.core.training"
        case .fullBody: "figure.mixed.cardio"
        case .cardio: "heart.fill"
        }
    }
}

extension Workout {
    /// The muscle group with the most sets in this workout.
    var mainMuscleGroup: MuscleGroup? {
        var counts: [MuscleGroup: Int] = [:]
        for entry in exercises {
            guard let group = entry.exercise?.muscleGroup else { continue }
            counts[group, default: 0] += entry.sets.count
        }
        return counts.max { $0.value < $1.value }?.key
    }
}

extension WorkoutTemplate {
    /// Muscle groups worked, in exercise order, without duplicates.
    var muscleGroups: [MuscleGroup] {
        var groups: [MuscleGroup] = []
        for item in orderedItems {
            if let group = item.exercise?.muscleGroup, !groups.contains(group) {
                groups.append(group)
            }
        }
        return groups
    }
}

/// Rounded, colored icon for a muscle group.
struct MuscleIcon: View {
    let group: MuscleGroup
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: group.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(group.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct MuscleChip: View {
    let group: MuscleGroup

    var body: some View {
        Label(group.label, systemImage: group.symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(group.color)
            .background(group.color.opacity(0.15), in: Capsule())
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.display(22))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardModifier())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .glassSurface(in: Capsule(), tint: Theme.accentRed, interactive: true, fallback: Theme.gradient)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Shrinks slightly when pressed, for custom tappable cards and icons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Section title in the style of Health and Fitness: bold, with an optional action on the right.
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.display(20, relativeTo: .title3))
            Spacer()
            trailing
                .font(.subheadline.weight(.semibold))
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

extension SectionHeader {
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }
}

/// Activity-style ring: a track and a rounded progress stroke that can go past 100 %.
struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .animation(.appEaseSlow, value: progress)
    }
}

/// Thin horizontal bar used for macro progress.
struct ProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.appEaseSlow, value: progress)
    }
}

extension View {
    /// Subtitle under the large title on iOS 26, nothing before.
    @ViewBuilder
    func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            navigationSubtitle(subtitle)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Prominent Liquid Glass button on iOS 26, filled bordered button before.
    @ViewBuilder
    func glassProminentButton() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    /// Liquid Glass button on iOS 26, bordered button before.
    @ViewBuilder
    func glassButton() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
        #else
        buttonStyle(.bordered)
        #endif
    }
}
