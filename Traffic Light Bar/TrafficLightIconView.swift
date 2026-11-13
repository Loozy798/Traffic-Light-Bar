import SwiftUI

/// SwiftUI version of the same discrete status used by the menu bar icon.
struct TrafficLightIconView: View {
    let level: ResourceLevel
    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: 9, height: 9)
            .padding(4)
            .background(level.color.opacity(0.12), in: Circle())
            .accessibilityLabel(level.title)
    }
}
