import SwiftUI

/// 仿 macOS 原生电池图标
/// 电量随百分比实时减少，颜色：≤10% 红、≤20% 橙、≤40% 黄、>40% 绿
/// 充电时叠加闪电 ⚡ 图标
struct BatteryIcon: View {
    let percent: Double
    let charging: Bool

    private var fillColor: Color {
        if percent <= 10 { return Color(red: 0.91, green: 0.22, blue: 0.21) }
        if percent <= 20 { return Color(red: 0.96, green: 0.52, blue: 0.15) }
        if percent <= 40 { return Color(red: 0.95, green: 0.76, blue: 0.06) }
        return Color(red: 0.30, green: 0.78, blue: 0.40)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // 主体区域（留出右侧帽子空间）
            let bodyW  = w * 0.88
            let bodyH  = h
            let capW   = w * 0.08
            let capH   = h * 0.38
            let radius = min(bodyW, bodyH) * 0.22
            let inset: CGFloat = 1.5
            let fillW  = max(0, (bodyW - inset * 2) * min(percent / 100, 1.0))

            ZStack(alignment: .leading) {
                // 电池外壳
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.primary.opacity(0.55), lineWidth: 1.2)
                    .frame(width: bodyW, height: bodyH)

                // 电量填充
                RoundedRectangle(cornerRadius: max(radius - inset, 1))
                    .fill(fillColor)
                    .frame(width: fillW, height: bodyH - inset * 2)
                    .offset(x: inset)
                    .animation(.easeInOut(duration: 0.4), value: percent)

                // 右侧帽子（正极凸起）
                RoundedRectangle(cornerRadius: capW * 0.4)
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: capW, height: capH)
                    .offset(x: bodyW + 1, y: 0)

                // 充电闪电
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: bodyH * 0.55, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 0.5, x: 0, y: 0.5)
                        .frame(width: bodyW, height: bodyH)
                }
            }
            .frame(width: w, height: h, alignment: .leading)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 20) {
            BatteryIcon(percent: 100, charging: false).frame(width: 28, height: 14)
            BatteryIcon(percent: 65, charging: false).frame(width: 28, height: 14)
            BatteryIcon(percent: 35, charging: true).frame(width: 28, height: 14)
            BatteryIcon(percent: 15, charging: false).frame(width: 28, height: 14)
            BatteryIcon(percent: 5, charging: false).frame(width: 28, height: 14)
        }
    }
    .padding(30)
}
