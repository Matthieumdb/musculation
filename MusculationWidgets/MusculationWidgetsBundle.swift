import SwiftUI
import WidgetKit

@main
struct MusculationWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        MacrosWidget()
        WaterWidget()
        QuickStartWidget()
        WorkoutLiveActivity()
        if #available(iOS 18.0, *) {
            WaterControl()
            StartWorkoutControl()
        }
    }
}
