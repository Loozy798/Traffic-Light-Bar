//
//  Traffic_Light_BarApp.swift
//  Traffic Light Bar
//

import SwiftUI

@main
struct Traffic_Light_BarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // This scene is never shown because we set LSUIElement = YES
        WindowGroup {
            EmptyView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
