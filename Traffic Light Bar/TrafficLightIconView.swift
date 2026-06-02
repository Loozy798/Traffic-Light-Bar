import SwiftUI
import AppKit

struct TrafficLightIconView: View {
    /// 综合压力值 0.0（空闲绿色）→ 1.0（高负载红色）
    let loadRatio: Double

    /// HSL 连续渐变：绿(hue 0.35) → 黄 → 红(hue 0)
    var dotColor: Color {
        let r = min(max(loadRatio, 0), 1.0)
        return Color(hue: (1.0 - r) * 0.35, saturation: 0.88, brightness: 0.88)
    }

    var body: some View {
        ZStack {
            // 外发光：由亮到暗向外扩散
            Circle()
                .fill(
                    RadialGradient(
                        colors: [dotColor.opacity(0.5), dotColor.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 9
                    )
                )
                .frame(width: 18, height: 18)

            // 主灯：白色高光 + 渐变色，模拟 LED 玻璃质感
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.75), dotColor],
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

    /// 共用颜色计算（供其他 View 调用）
    static func color(for ratio: Double) -> Color {
        let r = min(max(ratio, 0), 1.0)
        return Color(hue: (1.0 - r) * 0.35, saturation: 0.88, brightness: 0.85)
    }
}
