import SwiftUI

struct TrafficLightIconView: View {
    enum LoadLevel {
        case low
        case medium
        case high
    }
    
    let loadLevel: LoadLevel
    
    var body: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(loadLevel == .low ? Color(red: 0.18, green: 0.8, blue: 0.44) : Color.gray.opacity(0.3))
                .frame(width: 4, height: 4)
            
            Circle()
                .fill(loadLevel == .medium ? Color(red: 0.95, green: 0.76, blue: 0.06) : Color.gray.opacity(0.3))
                .frame(width: 4, height: 4)
            
            Circle()
                .fill(loadLevel == .high ? Color(red: 0.91, green: 0.3, blue: 0.24) : Color.gray.opacity(0.3))
                .frame(width: 4, height: 4)
        }
        .padding(.horizontal, 3)
        // 适配暗模式：使用 .aqua 和 .darkAqua
        .environment(\.colorScheme, NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
    }
}

extension NSImage {
    convenience init<V: View>(view: V, size: NSSize) {
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(origin: .zero, size: size)
        let image = NSImage(size: size)
        image.lockFocus()
        hosting.view.draw(hosting.view.bounds)
        image.unlockFocus()
        self.init(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, size: size)
        self.isTemplate = false
    }
}
