import SwiftUI
import SwiftData
import Charts

/// Body measurements and body fat, as in Hevy: latest value and change for each one.
struct MeasurementsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @State private var adding: MeasurementKind?

    var body: some View {
        List {
            Section {
                ForEach(MeasurementKind.allCases) { kind in
                    let values = measurements.filter { $0.kind == kind }
                    NavigationLink {
                        MeasurementDetailView(kind: kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.teal.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label)
                                if let last = values.first {
                                    Text(last.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let last = values.first {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(kind.text(last.value)).font(.headline.monospacedDigit())
                                    if values.count > 1 {
                                        let delta = last.value - values[values.count - 1].value
                                        let good = kind.lowerIsBetter ? delta <= 0 : delta >= 0
                                        Text((delta > 0 ? "+" : "") + kind.text(delta))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(delta == 0 ? Color.secondary : (good ? Color.green : Color.orange))
                                    }
                                }
                            } else {
                                Text("—").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("Ajouter", systemImage: "plus") { adding = kind }
                            .tint(.teal)
                    }
                }
            } footer: {
                Text("Mesure-toi le matin, au même endroit, une fois par semaine ou par mois. Glisse vers la droite pour ajouter une valeur.")
            }
        }
        .navigationTitle("Mensurations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(MeasurementKind.allCases) { kind in
                        Button(kind.label, systemImage: kind.symbol) { adding = kind }
                    }
                } label: {
                    Label("Ajouter", systemImage: "plus")
                }
            }
        }
        .sheet(item: $adding) { kind in
            AddMeasurementSheet(kind: kind, last: measurements.first { $0.kind == kind }?.value)
        }
    }
}

private struct AddMeasurementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let kind: MeasurementKind
    let last: Double?
    @State private var value: Double?
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField(last.map { kind.text($0) } ?? kind.unit, value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text(kind.unit).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        if let value, value > 0 {
                            context.insert(BodyMeasurement(date: date, kind: kind, value: value))
                            try? context.save()
                        }
                        dismiss()
                    }
                    .disabled((value ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct MeasurementDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var all: [BodyMeasurement]
    let kind: MeasurementKind
    @State private var isAdding = false

    var body: some View {
        let values = all.filter { $0.kind == kind }
        List {
            if values.count > 1 {
                Section {
                    Chart(values.reversed()) { m in
                        LineMark(x: .value("Date", m.date), y: .value(kind.unit, m.value))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", m.date), y: .value(kind.unit, m.value))
                    }
                    .foregroundStyle(Color.teal)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
            }
            Section {
                ForEach(values) { m in
                    LabeledContent(m.date.formatted(date: .abbreviated, time: .omitted), value: kind.text(m.value))
                }
                .onDelete { offsets in
                    offsets.map { values[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
                if values.isEmpty {
                    Text("Aucune mesure pour l'instant.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(kind.label)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ajouter", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            AddMeasurementSheet(kind: kind, last: values.first?.value)
        }
    }
}
