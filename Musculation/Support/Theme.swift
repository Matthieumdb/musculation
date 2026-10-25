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
                .font(.title2.bold())
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(red: 0.84, green: 0.13, blue: 0.24).opacity(0.3), radius: 10, y: 5)
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
