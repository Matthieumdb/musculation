import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Water

/// Glasses of water today, with a button to add one.
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaterWidget", provider: TodayProvider()) { entry in
            WaterWidgetView(snapshot: entry.snapshot ?? .placeholder)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Eau")
        .description("Ajoute un verre d'eau sans ouvrir l'app.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        let water = snapshot.waterToday
        let goal = max(snapshot.waterGoal ?? 8, 1)
        if family == .accessoryCircular {
            Button(intent: AddWaterIntent()) {
                Gauge(value: Double(min(water, goal)), in: 0...Double(goal)) {
                    Image(systemName: "drop.fill")
                } currentValueLabel: {
                    Text("\(water)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(water) verres sur \(goal). Ajouter un verre d'eau")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Eau", systemImage: "drop.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(water)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text("/\(goal)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(water >= goal ? "Objectif atteint" : "verres de 25 cl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(intent: AddWaterIntent()) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.cyan, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajouter un verre d'eau")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Quick start

/// Starts a template or a free workout in one tap.
struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickStartWidget", provider: TodayProvider()) { _ in
            QuickStartWidgetView(templates: SharedTemplates.load())
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Démarrer une séance")
        .description("Lance un de tes modèles en un geste.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct QuickStartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let templates: [String]

    var body: some View {
        let shown = Array(templates.prefix(family == .systemMedium ? 4 : 2))
        VStack(alignment: .leading, spacing: 6) {
            Label("Séance", systemImage: "dumbbell.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer(minLength: 0)
            if family == .systemMedium {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(shown, id: \.self) { name in startButton(name) }
                    startButton(nil)
                }
            } else {
                ForEach(shown, id: \.self) { name in startButton(name) }
                startButton(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startButton(_ name: String?) -> some View {
        Button(intent: StartWorkoutIntent(template: name)) {
            HStack(spacing: 6) {
                Image(systemName: name == nil ? "bolt.fill" : "play.fill").font(.caption)
                Text(name ?? "Séance libre")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.accentColor.opacity(name == nil ? 0.12 : 0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Macros

/// Protein, carbs and fat left today.
struct MacrosWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacrosWidget", provider: TodayProvider()) { entry in
            MacrosWidgetView(snapshot: entry.snapshot ?? .placeholder)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Macros")
        .description("Protéines, glucides et lipides restants aujourd'hui.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

private struct MacrosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private struct Macro: Identifiable {
        var name: String
        var left: Int
        var target: Int
        var tint: Color
        var id: String { name }
    }

    private var macros: [Macro] {
        let s = snapshot
        let today = s.isToday
        return [
            Macro(name: "Protéines", left: today ? s.proteinLeft : s.proteinTarget ?? 0, target: s.proteinTarget ?? 0, tint: .blue),
            Macro(name: "Glucides", left: today ? s.carbsLeft ?? 0 : s.carbsTarget ?? 0, target: s.carbsTarget ?? 0, tint: .orange),
            Macro(name: "Lipides", left: today ? s.fatLeft ?? 0 : s.fatTarget ?? 0, target: s.fatTarget ?? 0, tint: .pink),
        ]
    }

    var body: some View {
        if family == .accessoryRectangular {
            HStack(spacing: 6) {
                ForEach(macros) { macro in
                    Gauge(value: Double(max(0, macro.target - macro.left)), in: 0...Double(max(macro.target, 1))) {
                        Text(String(macro.name.prefix(1)))
                    } currentValueLabel: {
                        Text("\(macro.left)").monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(macros.map { "\($0.name) : \($0.left) grammes restants" }.joined(separator: ", "))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Restant", systemImage: "chart.pie.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ForEach(macros) { macro in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(macro.name).font(.caption)
                            Spacer()
                            Text("\(macro.left) g").font(.caption.weight(.semibold).monospacedDigit())
                        }
                        ProgressView(value: Double(max(0, macro.target - macro.left)), total: Double(max(macro.target, 1)))
                            .tint(macro.tint)
                    }
                }
            }
        }
    }
}

// MARK: - Control Center

@available(iOS 18.0, *)
struct WaterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.matthieumdb.musculation.water") {
            ControlWidgetButton(action: AddWaterIntent()) {
                Label("Verre d'eau", systemImage: "drop.fill")
            }
        }
        .displayName("Verre d'eau")
        .description("Ajoute un verre d'eau de 25 cl.")
    }
}

@available(iOS 18.0, *)
struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.matthieumdb.musculation.start") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Séance", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Démarrer une séance")
        .description("Ouvre Musculation sur une nouvelle séance.")
    }
}
