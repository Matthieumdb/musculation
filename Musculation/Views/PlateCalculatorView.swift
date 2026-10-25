import SwiftUI

struct PlateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.barWeightKey) private var barWeight = AppSettings.defaultBarWeight
    @State var target: Double

    private static let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    private struct PlateCount: Identifiable {
        let plate: Double
        let count: Int
        var id: Double { plate }
    }

    /// Plates for one side of the bar, heaviest first, plus the weight that cannot be loaded.
    private var loading: (plates: [PlateCount], missing: Double) {
        var remaining = max(0, (target - barWeight) / 2)
        var counts: [PlateCount] = []
        for plate in Self.plates {
            let count = Int((remaining + 0.001) / plate)
            if count > 0 {
                counts.append(PlateCount(plate: plate, count: count))
                remaining -= Double(count) * plate
            }
        }
        return (counts, remaining * 2)
    }

    var body: some View {
        let loading = self.loading
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Charge totale")
                        Spacer()
                        TextField("0", value: $target, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    Picker("Barre", selection: $barWeight) {
                        ForEach(AppSettings.barOptions, id: \.self) { weight in
                            Text(weight == 0 ? "Sans barre" : weight.kgText).tag(weight)
                        }
                    }
                }

                Section("De chaque côté") {
                    if loading.plates.isEmpty {
                        Text(target > 0 ? "Barre seule" : "Entre une charge")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(loading.plates) { item in
                        HStack {
                            Circle()
                                .fill(color(for: item.plate))
                                .frame(width: 18, height: 18)
                            Text(item.plate.kgText)
                            Spacer()
                            Text("× \(item.count)")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    if loading.missing > 0.01 {
                        Text("Impossible de faire le compte exact : il reste \(loading.missing.kgText).")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Calculateur de disques")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func color(for plate: Double) -> Color {
        switch plate {
        case 25: .red
        case 20: .blue
        case 15: .yellow
        case 10: .green
        case 5: .white
        default: .gray
        }
    }
}
