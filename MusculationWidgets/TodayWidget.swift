import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        // The app reloads the widget after each change; midnight resets the day's calories.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [TodayEntry(date: .now, snapshot: WidgetSnapshot.load())], policy: .after(midnight)))
    }
}

/// Calories left today and workouts this week, on the home and lock screens.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Aujourd'hui")
        .description("Calories restantes et séances de la semaine.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        if let s = entry.snapshot {
            let left = s.isToday ? s.kcalLeft : s.kcalTarget
            switch family {
            case .accessoryInline:
                Label("\(left) kcal · \(s.workoutsThisWeek) séance\(s.workoutsThisWeek > 1 ? "s" : "")", systemImage: "flame.fill")
            case .accessoryCircular:
                Gauge(value: Double(max(0, s.kcalTarget - left)), in: 0...Double(max(s.kcalTarget, 1))) {
                    Image(systemName: "flame.fill")
                } currentValueLabel: {
                    Text("\(left)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Musculation", systemImage: "dumbbell.fill").font(.caption2.weight(.semibold))
                    Text("\(left) kcal restantes").font(.headline)
                    Text("\(s.workoutsThisWeek) séance\(s.workoutsThisWeek > 1 ? "s" : "") cette semaine").font(.caption)
                }
            case .systemMedium:
                HStack(spacing: 16) {
                    calories(s, left: left)
                    Divider()
                    workouts(s)
                }
            default:
                calories(s, left: left)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "dumbbell.fill").foregroundStyle(.tint)
                Text("Ouvre Musculation pour afficher tes chiffres.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calories(_ s: WidgetSnapshot, left: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Calories", systemImage: "flame.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Spacer(minLength: 0)
            Text("\(abs(left))")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(left >= 0 ? "kcal restantes" : "kcal en trop")
                .font(.caption)
                .foregroundStyle(.secondary)
            if s.isToday && s.proteinLeft > 0 {
                Text("\(s.proteinLeft) g de protéines").font(.caption2).foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workouts(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Activité", systemImage: "dumbbell.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            Text("\(s.workoutsThisWeek)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(s.workoutsThisWeek > 1 ? "séances cette semaine" : "séance cette semaine")
                .font(.caption)
                .foregroundStyle(.secondary)
            if s.weekStreak > 1 {
                Text("\(s.weekStreak) semaines d'affilée").font(.caption2).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
