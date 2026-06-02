import SwiftUI
import AppKit

struct TrafficLightIconView: View {
    enum LoadLevel {
        case low    // 绿灯 <30%
        case medium // 黄灯 30~70%
        case high   // 红灯 >70%
    }

    let loadLevel: LoadLevel

    private var dotColor: Color {
        switch loadLevel {
        case .low:    return Color(red: 0.18, green: 0.80, blue: 0.44)
        case .medium: return Color(red: 0.95, green: 0.76, blue: 0.06)
        case .high:   return Color(red: 0.91, green: 0.30, blue: 0.24)
        }
    }

    var body: some View {
        ZStack {
            // 最外层：大范围柔和扩散光晕（由色到透明）
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            dotColor.opacity(0.35),
                            dotColor.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 9
                    )
                )
                .frame(width: 18, height: 18)

            // 中层：主灯体，带内部高光（模拟 LED 玻璃感）
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.75),
                            dotColor
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 5
                    )
                )
                .frame(width: 9, height: 9)
        }
        .frame(width: 18, height: 18)
        .environment(
            \.colorScheme,
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        )
    }
}
