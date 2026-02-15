import AppKit
import ScreenSaver

final class ConstellationsPreviewWindowController: NSWindowController {
    private var saverView: ConstellationsView?

    convenience init(size: NSSize = NSSize(width: 800, height: 600)) {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: style,
                              backing: .buffered,
                              defer: false)
        window.title = "Constellations Preview"
        self.init(window: window)
        setupContent()
    }

    private func setupContent() {
        guard let window = self.window else { return }
        // Create the ScreenSaverView in non-preview mode
        let saverFrame = window.contentView?.bounds ?? window.frame
        let view = ConstellationsView(frame: saverFrame, isPreview: false)
        self.saverView = view

        // Use a hosting NSView to handle autoresizing
        let container = NSView(frame: saverFrame)
        container.autoresizingMask = [.width, .height]
        view?.autoresizingMask = [.width, .height]
        if let saver = view {
            container.addSubview(saver)
        }
        window.contentView = container

        // Ensure animation is scheduled
        view?.animationTimeInterval = 1.0 / 60.0
        view?.startAnimation()
    }

    public func show() {
        guard let window = self.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
