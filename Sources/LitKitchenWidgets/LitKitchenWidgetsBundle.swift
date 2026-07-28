import SwiftUI
import WidgetKit

@main
struct LitKitchenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CookingLiveActivity()
        if #available(iOS 18.0, *) {
            BurnerControl()
        }
    }
}
