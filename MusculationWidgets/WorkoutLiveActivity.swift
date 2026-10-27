import ActivityKit
import SwiftUI
import WidgetKit

/// Running workout on the lock screen and in the Dynamic Island, with the rest countdown.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.startedAt, style: .timer)
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "dumbbell.fill")
                    }
                    .font(.headline)
                    .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.done)/\(context.state.total)")
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.exercise).font(.headline).lineLimit(1)
                        if let start = context.state.restStart, let end = context.state.restEnd, end > .now {
                            RestProgress(start: start, end: end)
                        } else {
                            Text(context.state.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                if let end = context.state.restEnd, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(.tint)
                } else {
                    Text("\(context.state.done)/\(context.state.total)")
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: context.state.restEnd == nil ? "dumbbell.fill" : "timer")
                    .foregroundStyle(.tint)
            }
            .keylineTint(.accentColor)
        }
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.title, systemImage: "dumbbell.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Spacer()
                Text(attributes.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80, alignment: .trailing)
            }
            if let start = state.restStart, let end = state.restEnd, end > .now {
                Text("Repos").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                RestProgress(start: start, end: end)
                Text("Ensuite : \(state.exercise) · \(state.detail)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(state.exercise).font(.title3.bold()).lineLimit(1)
                Text(state.detail).font(.subheadline).foregroundStyle(.secondary)
                ProgressView(value: Double(state.done), total: Double(max(state.total, 1)))
                    .tint(.accentColor)
            }
        }
    }
}

private struct RestProgress: View {
    let start: Date
    let end: Date

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(timerInterval: start...end, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.accentColor)
            Text(timerInterval: start...end, countsDown: true)
                .font(.title2.weight(.semibold).monospacedDigit())
                .frame(width: 70, alignment: .trailing)
        }
    }
}
