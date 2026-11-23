import AppKit
import SwiftUI

extension Notification.Name {
    static let menuBarIconVisibilityChanged = Notification.Name("menuBarIconVisibilityChanged")
    /// Hide the menu immediately. Does not block it from opening again.
    static let umbrellaDismissMenuBarPopover = Notification.Name("umbrellaDismissMenuBarPopover")
    /// Selection or capture UI is up. Keep the menu from ordering itself in front.
    static let umbrellaCaptureChromeBegan = Notification.Name("umbrellaCaptureChromeBegan")
    static let umbrellaCaptureChromeEnded = Notification.Name("umbrellaCaptureChromeEnded")
}

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private static let panelSizeKey = "umbrella.menuPanelSize"
    private static let defaultPanelWidth: CGFloat = 280
    private static let minimumPanelWidth: CGFloat = 260
    /// Low enough that a saved or default height cannot force an empty band under the rows.
    private static let minimumPanelHeight: CGFloat = 120

    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    private var visibilityObserver: NSObjectProtocol?
    private var panel: MenuBarPanel?
    private lazy var statusMenu: NSMenu = makeStatusMenu()
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
    private var captureBeganObserver: NSObjectProtocol?
    private var captureEndedObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    /// While a snip overlay or in-flight capture is up, keep the menu from ordering itself in front.
    private var captureChromeActive = false
    /// The open menu scrolls only when its rows are taller than the screen.
    private var menuScrolls = false
    private var lastReportedContentHeight: CGFloat = 0
    private var isFittingPanel = false

    func start(appModel: AppModel) {
        self.appModel = appModel

        let center = NotificationCenter.default
        // Deliver on the posting thread. queue: .main runs later, after the snip
        // overlay has already ordered the menu in front.
        dismissObserver = center.addObserver(
            forName: .umbrellaDismissMenuBarPopover,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.hidePopoverImmediately()
            }
        }
        captureBeganObserver = center.addObserver(
            forName: .umbrellaCaptureChromeBegan,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.beginCaptureChrome()
            }
        }
        captureEndedObserver = center.addObserver(
            forName: .umbrellaCaptureChromeEnded,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endCaptureChrome()
            }
        }
        resignActiveObserver = center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // System screenshot UI activates another process. Close so this menu cannot cover it.
                self?.hidePopoverImmediately()
            }
        }

        visibilityObserver = NotificationCenter.default.addObserver(
            forName: .menuBarIconVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let visible = notification.userInfo?["visible"] as? Bool ?? AppSettings.shared.showMenuBarIcon
            Task { @MainActor in
                self?.setVisible(visible)
            }
        }

        setVisible(AppSettings.shared.showMenuBarIcon)
    }

    func setVisible(_ visible: Bool) {
        AppSettings.shared.showMenuBarIcon = visible

        if visible {
            installIfNeeded()
            statusItem?.isVisible = true
        } else {
            hidePopover()
            statusItem?.isVisible = false
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "UmbrellaStatusItem"
        if let button = item.button {
            button.imageScaling = .scaleProportionallyUpOrDown
            button.image = MenuBarIcon.image()
            button.title = ""
            button.toolTip = "Suncut — click for controls, right-click for menu"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Settings…", action: #selector(openSettings)))
        #if !APP_STORE
        menu.addItem(menuItem("Check for Updates…", action: #selector(checkForUpdates)))
        #endif
        menu.addItem(.separator())
        menu.addItem(menuItem("Restart", action: #selector(restartApp)))

        let quitItem = menuItem("Quit Suncut", action: #selector(quitApp))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    #if !APP_STORE
    @objc private func checkForUpdates() {
        AppUpdateChecker.prompt()
    }
    #endif

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            hidePopover()
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        statusMenu.popUp(positioning: nil, at: point, in: button)
    }

    private func togglePopover() {
        if panel?.wantsVisible == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !captureChromeActive else { return }
        guard let appModel, let button = statusItem?.button else { return }

        let panel = ensurePanel(appModel: appModel)
        if panel.wantsVisible {
            return
        }

        menuScrolls = false
        lastReportedContentHeight = 0
        if let hosting = panel.contentViewController as? NSHostingController<MenuBarControlsView> {
            hosting.rootView = makeControlsView(appModel: appModel, scrolls: false, reportHeight: true)
        }

        let screen = button.window?.screen ?? NSScreen.main
        applyFittedPanelSize(screen: screen)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.level = .popUpMenu
        panel.wantsVisible = true
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        button.isHighlighted = true
        startOutsideClickMonitoring()
    }

    private func hidePopover() {
        hidePopoverImmediately()
    }

    /// Close before a snip activates the app. An `NSPopover` close still orders itself in front.
    private func hidePopoverImmediately() {
        stopOutsideClickMonitoring()
        statusItem?.button?.isHighlighted = false
        guard let panel else { return }
        panel.wantsVisible = false
        panel.ignoresMouseEvents = true
        // Drop below the snip overlay before ordering out, so a late order-front cannot cover the selection.
        panel.level = .normal
        panel.orderOut(nil)
    }

    private func beginCaptureChrome() {
        captureChromeActive = true
        hidePopoverImmediately()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.captureChromeActive else { return }
            self.hidePopoverImmediately()
        }
    }

    private func endCaptureChrome() {
        captureChromeActive = false
    }

    private func makeControlsView(appModel: AppModel, scrolls: Bool, reportHeight: Bool) -> MenuBarControlsView {
        MenuBarControlsView(
            brightnessFeature: appModel.brightnessFeature,
            snipFeature: appModel.simpleSnipFeature,
            onOpenSettings: { [weak self] in
                self?.hidePopover()
                self?.openSettings()
            },
            onRestart: { [weak self] in
                self?.hidePopoverImmediately()
                self?.restartApp()
            },
            onQuit: { [weak self] in
                self?.hidePopoverImmediately()
                self?.quitApp()
            },
            onRunCapture: { [weak self] action in
                self?.hidePopoverImmediately()
                action()
            },
            scrolls: scrolls,
            onContentHeightChange: reportHeight ? { [weak self] height in
                self?.refitPanelToContent(reportedHeight: height)
            } : nil
        )
    }

    private func ensurePanel(appModel: AppModel) -> MenuBarPanel {
        if let panel {
            return panel
        }

        let hosting = NSHostingController(rootView: makeControlsView(appModel: appModel, scrolls: false, reportHeight: true))
        hosting.sizingOptions = []
        // The hidden title bar still reserves a safe area, which shows up as empty space above the menu.
        hosting.safeAreaRegions = []

        let panel = MenuBarPanel(contentViewController: hosting)
        panel.contentMinSize = NSSize(width: Self.minimumPanelWidth, height: Self.minimumPanelHeight)
        panel.delegate = self
        self.panel = panel
        return panel
    }

    /// Saved width only. A saved height is what left the empty band above Restart.
    private func savedPanelWidth() -> CGFloat? {
        guard let raw = UserDefaults.standard.string(forKey: Self.panelSizeKey) else { return nil }
        let size = NSSizeFromString(raw)
        guard size.width >= Self.minimumPanelWidth else { return nil }
        return size.width
    }

    private func visibleBounds(on screen: NSScreen?) -> CGRect {
        (screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600))
            .insetBy(dx: 8, dy: 8)
    }

    /// Hug the rows at `width`. This SDK has `fittingSize` on `NSView`, not `sizeThatFits` on `NSHostingView`.
    private func probeContentHeight(appModel: AppModel, width: CGFloat) -> CGFloat {
        let probe = NSHostingView(
            rootView: makeControlsView(appModel: appModel, scrolls: false, reportHeight: false)
        )
        probe.safeAreaRegions = []
        probe.translatesAutoresizingMaskIntoConstraints = false
        probe.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        probe.widthAnchor.constraint(equalToConstant: width).isActive = true
        probe.layoutSubtreeIfNeeded()
        return probe.fittingSize.height
    }

    private func refitPanelToContent(reportedHeight: CGFloat) {
        guard panel?.wantsVisible == true else { return }
        guard reportedHeight > 1, reportedHeight < 9_000 else { return }
        guard abs(reportedHeight - lastReportedContentHeight) > 0.5 else { return }
        lastReportedContentHeight = reportedHeight
        applyFittedPanelSize(fittedHeight: reportedHeight, screen: nil)
    }

    /// Size the panel to the menu rows so a fixed window height cannot open a gap above Restart.
    private func applyFittedPanelSize(screen explicitScreen: NSScreen?) {
        guard let appModel else { return }
        let screen = explicitScreen ?? statusItem?.button?.window?.screen ?? NSScreen.main
        let visible = visibleBounds(on: screen)
        let width = min(max(savedPanelWidth() ?? Self.defaultPanelWidth, Self.minimumPanelWidth), visible.width)
        let fitted = probeContentHeight(appModel: appModel, width: width)
        guard fitted > 1, fitted < 9_000 else { return }
        lastReportedContentHeight = fitted
        applyFittedPanelSize(fittedHeight: fitted, screen: screen)
    }

    private func applyFittedPanelSize(fittedHeight: CGFloat, screen explicitScreen: NSScreen?) {
        guard let panel, let appModel, !isFittingPanel else { return }
        isFittingPanel = true
        defer { isFittingPanel = false }

        let button = statusItem?.button
        let screen = explicitScreen ?? button?.window?.screen ?? NSScreen.main
        let visible = visibleBounds(on: screen)
        let width = min(max(savedPanelWidth() ?? panel.frame.width, Self.minimumPanelWidth), visible.width)
        let scrolls = fittedHeight > visible.height + 1
        if scrolls != menuScrolls, let hosting = panel.contentViewController as? NSHostingController<MenuBarControlsView> {
            menuScrolls = scrolls
            hosting.rootView = makeControlsView(appModel: appModel, scrolls: scrolls, reportHeight: true)
        }

        let height = min(max(ceil(fittedHeight), Self.minimumPanelHeight), visible.height)
        panel.contentMinSize = NSSize(
            width: Self.minimumPanelWidth,
            height: scrolls ? Self.minimumPanelHeight : height
        )
        panel.contentMaxSize = NSSize(
            width: visible.width,
            height: scrolls ? visible.height : height
        )
        var frame = panel.frame
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: panel.wantsVisible)
        if let button {
            position(panel, under: button)
        }
    }

    private func position(_ panel: NSPanel, under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(
            x: buttonRect.midX - size.width / 2,
            y: buttonRect.minY - size.height - 4
        )
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = max(origin.y, visible.minY)
        }
        panel.setFrameOrigin(origin)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.panelSizeKey)
        guard let appModel, let panel, window === panel else { return }
        let fitted = probeContentHeight(appModel: appModel, width: window.frame.width)
        guard fitted > 1 else { return }
        lastReportedContentHeight = 0
        refitPanelToContent(reportedHeight: fitted)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.dismissIfClickOutside()
            }
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfClickOutside()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }
        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func dismissIfClickOutside() {
        guard panel?.wantsVisible == true else { return }

        let location = NSEvent.mouseLocation

        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let buttonScreenRect = buttonWindow.convertToScreen(buttonRect).insetBy(dx: -2, dy: -2)
            if buttonScreenRect.contains(location) {
                return
            }
        }

        if let panel, panel.frame.contains(location) {
            return
        }

        hidePopover()
    }

    @objc private func openSettings() {
        appModel?.showSettings()
    }

    @objc private func restartApp() {
        AppRelauncher.restart()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

/// Menu window we own. `NSPopover` reorders itself in front of a screenshot and parks at the top of the screen.
private final class MenuBarPanel: NSPanel {
    /// When false, AppKit cannot bring this window forward. A snip sets this before it activates the app.
    var wantsVisible = false

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 280, height: 500)),
            styleMask: [.titled, .resizable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .normal
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        if let contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 12
            contentView.layer?.masksToBounds = true
            // Same fill as the menu, so a one-point size mismatch is not a transparent strip.
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if !wantsVisible, place != .out {
            super.order(.out, relativeTo: otherWin)
            return
        }
        super.order(place, relativeTo: otherWin)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        guard wantsVisible else { return }
        super.makeKeyAndOrderFront(sender)
    }

    override func orderFrontRegardless() {
        guard wantsVisible else { return }
        super.orderFrontRegardless()
    }
}
