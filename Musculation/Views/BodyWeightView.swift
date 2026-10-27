import SwiftUI
import SwiftData
import Charts

struct BodyWeightView: View {
    @Environment(\.modelContext) private var context
    @Environment(NutritionStore.self) private var nutrition
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var entries: [BodyWeightEntry]

    @State private var newWeight: Double?
    @State private var newDate = Date.now

    var body: some View {
        List {
            if entries.count > 1 {
                Section {
                    Chart(entries) { entry in
                        LineMark(x: .value("Date", entry.date), y: .value("Poids", entry.weight))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", entry.date), y: .value("Poids", entry.weight))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .padding(.vertical, 8)

                    if let latest = entries.first, let oldest = entries.last {
                        let change = latest.weight - oldest.weight
                        LabeledContent(
                            "Évolution",
                            value: "\(change >= 0 ? "+" : "−")\(abs(change).kgText)"
                        )
                    }
                }
            }

            Section("Nouvelle pesée") {
                HStack {
                    TextField("Poids", value: $newWeight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                    Text("kg").foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $newDate, in: ...Date.now, displayedComponents: .date)
                Button("Ajouter") {
                    guard let newWeight, newWeight > 0 else { return }
                    context.insert(BodyWeightEntry(date: newDate, weight: newWeight))
                    try? context.save()
                    nutrition.checkAdjustment(entries: (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? entries)
                    self.newWeight = nil
                    newDate = .now
                    hideKeyboard()
                }
                .disabled((newWeight ?? 0) <= 0)
            }

            Section("Historique") {
                ForEach(entries) { entry in
                    LabeledContent(
                        entry.date.formatted(date: .abbreviated, time: .omitted),
                        value: entry.weight.kgText
                    )
                }
                .onDelete { offsets in
                    offsets.map { entries[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            }
        }
        .navigationTitle("Poids de corps")
        .navigationBarTitleDisplayMode(.inline)
    }
}
