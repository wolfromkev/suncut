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
        #if !APP_STORE
        AppUpdateChecker.refreshAvailability()
        #endif
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

    func windowDidBecomeKey(_ notification: Notification) {
        (notification.object as? SettingsCardWindow)?.applyCardChrome()
    }

    func windowDidResignKey(_ notification: Notification) {
        (notification.object as? SettingsCardWindow)?.applyCardChrome()
    }
}

/// Settings window drawn as the mock’s 680pt card: 12pt corners and the real
/// traffic lights 16pt from the left, 20pt from the top.
private final class SettingsCardWindow: NSWindow {
    private var isApplyingChrome = false
    private var chromeFollowUp: DispatchWorkItem?
    private let shadowView = CardShadowView()

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        applyCardChrome()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        applyCardChrome()
    }

    func applyCardChrome() {
        guard !isApplyingChrome else { return }
        isApplyingChrome = true
        defer { isApplyingChrome = false }
        clipToCard()
        allowTrafficLightsToDrawPastTitlebar()
        placeTrafficLights()
        scheduleChromeFollowUp()
    }

    /// AppKit lays the titlebar out again after `layoutIfNeeded` returns. A second
    /// pass puts the buttons back if that pass parked them at the bottom.
    private func scheduleChromeFollowUp() {
        chromeFollowUp?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.contentView != nil else { return }
            guard !self.isApplyingChrome else { return }
            self.isApplyingChrome = true
            defer { self.isApplyingChrome = false }
            self.allowTrafficLightsToDrawPastTitlebar()
            self.placeTrafficLights()
        }
        chromeFollowUp = work
        DispatchQueue.main.async(execute: work)
    }

    private func clipToCard() {
        guard let content = contentView, let frameView = content.superview else { return }
        content.wantsLayer = true
        content.layer?.cornerRadius = SettingsPanelMetrics.cornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        // Layer-backing the theme frame drops the titlebar container to the
        // bottom of the window, which is where the traffic lights were landing.
        // The card shadow lives on its own view instead.
        if shadowView.superview !== frameView {
            frameView.addSubview(shadowView, positioned: .below, relativeTo: content)
        }
        shadowView.frame = content.frame
        let radius = SettingsPanelMetrics.cornerRadius
        shadowView.layer?.cornerRadius = radius
        shadowView.layer?.shadowPath = CGPath(
            roundedRect: shadowView.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }

    /// Buttons sit 20pt down, which is below a short titlebar strip. Don't clip them.
    private func allowTrafficLightsToDrawPastTitlebar() {
        guard let theme = contentView?.superview,
              let close = standardWindowButton(.closeButton) else { return }
        var view: NSView? = close.superview
        while let current = view, current !== theme {
            current.clipsToBounds = false
            view = current.superview
        }
    }

    private func placeTrafficLights() {
        guard let theme = contentView?.superview else { return }
        let buttons = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ].compactMap { $0 }
        guard let sample = buttons.first else { return }
        let size = sample.frame.size
        for (index, button) in buttons.enumerated() {
            guard let superview = button.superview else { continue }
            superview.clipsToBounds = false
            let x = SettingsPanelMetrics.trafficLightLeft
                + CGFloat(index) * (size.width + SettingsPanelMetrics.trafficLightGap)
            let origin = buttonOrigin(x: x, buttonSize: size, theme: theme, superview: superview)
            let target = NSRect(origin: origin, size: button.frame.size)
            guard button.frame.integral != target.integral else { continue }
            button.setFrameOrigin(origin)
        }
    }

    /// Origin of a button whose top edge is `trafficLightTop` below the window top.
    ///
    /// The previous math used `contentHeight - top - buttonHeight` in the hosting
    /// view. That view is flipped (top-left origin), so the point is the bottom
    /// edge, and `convert` kept the buttons there.
    private func buttonOrigin(x: CGFloat, buttonSize: CGSize, theme: NSView, superview: NSView) -> NSPoint {
        let top = SettingsPanelMetrics.trafficLightTop
        func themePoint(visualFromTop: CGFloat) -> NSPoint {
            if theme.isFlipped {
                return NSPoint(x: x, y: visualFromTop)
            }
            return NSPoint(x: x, y: theme.bounds.height - visualFromTop)
        }
        let topLeft = superview.convert(themePoint(visualFromTop: top), from: theme)
        let bottomLeft = superview.convert(themePoint(visualFromTop: top + buttonSize.height), from: theme)
        return superview.isFlipped ? topLeft : bottomLeft
    }
}

/// Draws the card shadow without layer-backing the theme frame. Clicks pass through.
private final class CardShadowView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.55).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 35
        layer?.shadowOffset = NSSize(width: 0, height: -24)
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
