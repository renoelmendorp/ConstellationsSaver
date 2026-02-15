//
//  Constellations_PreviewApp.swift
//  Constellations Preview
//
//  Created by Reno Elmendorp on 15/02/2026.
//

import SwiftUI
import AppKit

@main
struct ConstellationsPreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible SwiftUI windows; the NSWindowController handles the UI.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ConstellationsPreviewWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = ConstellationsPreviewWindowController(size: NSSize(width: 1000, height: 700))
        self.windowController = controller
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
