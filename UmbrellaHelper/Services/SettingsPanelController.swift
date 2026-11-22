import AppKit
import SwiftUI

enum SettingsPanelMetrics {
    static let defaultWidth: CGFloat = 680
    static let defaultHeight: CGFloat = 640
    static let minWidth: CGFloat = 680
    static let minHeight: CGFloat = 560
    static let cornerRadius: CGFloat = 12
    static let trafficLightLeft: CGFloat = 16
    static let trafficLightTop: CGFloat = 20
    static let trafficLightGap: CGFloat = 8
}

@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?

    func configure(model: AppModel) {
        self.model = model
    }

    func showPanel() {
        if window == nil {
            let contentView = SettingsView()
                .environmentObject(model!)
                .environmentObject(model!)
                .frame(
                    minWidth: SettingsPanelMetrics.defaultWidth,
                    idealWidth: SettingsPanelMetrics.defaultWidth,
                    maxWidth: SettingsPanelMetrics.defaultWidth,
                    minHeight: SettingsPanelMetrics.minHeight,
                    idealHeight: SettingsPanelMetrics.defaultHeight
                )

            let hosting = NSHostingController(rootView: contentView)
            hosting.sizingOptions = []
            hosting.preferredContentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )
            hosting.view.setContentHuggingPriority(.defaultLow, for: .horizontal)
            hosting.view.setContentHuggingPriority(.defaultLow, for: .vertical)
            hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

            let contentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )

            let window = SettingsCardWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Suncut Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.delegate = self
            window.contentViewController = hosting
            window.setContentSize(contentSize)
            window.minSize = NSSize(
                width: SettingsPanelMetrics.minWidth,
                height: SettingsPanelMetrics.minHeight
            )
            window.maxSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: 4000
            )
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            window.applyCardChrome()
            self.window = window
        } else if let window, window.frame.height < SettingsPanelMetrics.minHeight {
            let contentSize = NSSize(
                width: SettingsPanelMetrics.defaultWidth,
                height: SettingsPanelMetrics.defaultHeight
            )
            window.setContentSize(contentSize)
            window.center()
        }

        window?.makeKeyAndOrderFront(nil)
        (window as? SettingsCardWindow)?.applyCardChrome()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePanel() {
        window?.orderOut(nil)
        model?.isSettingsVisible = false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.isSettingsVisible = false
        sender.orderOut(nil)
        return false
    }

    func windowDidResize(_ notification: Notification) {
        (notification.object as? SettingsCardWindow)?.applyCardChrome()
    }
}

/// Settings window drawn as the mock’s 680pt card: 12pt corners and the real
/// traffic lights 16pt from the left, 20pt from the top.
private final class SettingsCardWindow: NSWindow {
    private var isApplyingChrome = false

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        applyCardChrome()
    }

    func applyCardChrome() {
        guard !isApplyingChrome else { return }
        isApplyingChrome = true
        defer { isApplyingChrome = false }
        clipToCard()
        placeTrafficLights()
    }

    private func clipToCard() {
        guard let content = contentView else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = SettingsPanelMetrics.cornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        guard let frameView = content.superview else { return }
        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.clear.cgColor
        frameView.layer?.masksToBounds = false
        frameView.layer?.cornerRadius = SettingsPanelMetrics.cornerRadius
        frameView.layer?.borderWidth = 1
        frameView.layer?.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
        let card = content.convert(content.bounds, to: frameView)
        frameView.layer?.shadowPath = CGPath(
            roundedRect: card,
            cornerWidth: SettingsPanelMetrics.cornerRadius,
            cornerHeight: SettingsPanelMetrics.cornerRadius,
            transform: nil
        )
        frameView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.55).cgColor
        frameView.layer?.shadowOpacity = 1
        frameView.layer?.shadowRadius = 35
        frameView.layer?.shadowOffset = NSSize(width: 0, height: -24)
    }

    private func placeTrafficLights() {
        guard let content = contentView else { return }
        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        guard let sample = buttons.first else { return }
        let size = sample.frame.size
        for (index, button) in buttons.enumerated() {
            guard let superview = button.superview else { continue }
            let x = SettingsPanelMetrics.trafficLightLeft
                + CGFloat(index) * (size.width + SettingsPanelMetrics.trafficLightGap)
            let y = content.bounds.height - SettingsPanelMetrics.trafficLightTop - size.height
            let origin = superview.convert(NSPoint(x: x, y: y), from: content)
            let target = NSRect(origin: origin, size: button.frame.size)
            guard button.frame.integral != target.integral else { continue }
            button.setFrameOrigin(origin)
        }
    }
}
