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
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private weak var appModel: AppModel?
    private var visibilityObserver: NSObjectProtocol?
    private var popover: NSPopover?
    private lazy var statusMenu: NSMenu = makeStatusMenu()
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var dismissObserver: NSObjectProtocol?
    private var captureBeganObserver: NSObjectProtocol?
    private var captureEndedObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    /// While a snip overlay or in-flight capture is up, AppKit will otherwise order this popover in front of it.
    private var captureChromeActive = false

    func start(appModel: AppModel) {
        self.appModel = appModel

        let center = NotificationCenter.default
        // Deliver on the posting thread. queue: .main runs later, after the snip
        // overlay has already forced this popover to the top of the screen.
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
        if popover?.isShown == true {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !captureChromeActive else { return }
        guard let appModel, let button = statusItem?.button else { return }

        let popover = ensurePopover(appModel: appModel)
        if popover.isShown {
            return
        }

        if let hosting = popover.contentViewController as? NSHostingController<MenuBarControlsView> {
            hosting.rootView = makeControlsView(appModel: appModel)
        }

        popover.behavior = .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.alphaValue = 1
            window.ignoresMouseEvents = false
            window.level = .popUpMenu
        }
        button.isHighlighted = true
        NSApp.activate(ignoringOtherApps: true)
        startOutsideClickMonitoring()
    }

    private func hidePopover() {
        hidePopover(animated: true)
    }

    /// Close without the popover animation. An animated close is still ordering front when a snip activates the app.
    private func hidePopoverImmediately() {
        hidePopover(animated: false)
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
        popover?.behavior = .transient
    }

    private func hidePopover(animated: Bool) {
        stopOutsideClickMonitoring()
        statusItem?.button?.isHighlighted = false
        guard let popover else { return }

        let wasAnimating = popover.animates
        popover.animates = false
        // Leave the window level alone. Changing it detaches the popover and AppKit parks it at the top of the screen.
        if let window = popover.contentViewController?.view.window {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.orderOut(nil)
        }
        if popover.isShown {
            popover.performClose(nil)
        }
        if captureChromeActive {
            popover.behavior = .applicationDefined
        }
        popover.animates = animated || wasAnimating
    }

    private func makeControlsView(appModel: AppModel) -> MenuBarControlsView {
        MenuBarControlsView(
            brightnessFeature: appModel.brightnessFeature,
            snipFeature: appModel.simpleSnipFeature,
            onOpenSettings: { [weak self] in
                self?.hidePopover()
                self?.openSettings()
            },
            onRunCapture: { [weak self] action in
                self?.hidePopoverImmediately()
                action()
            }
        )
    }

    private func ensurePopover(appModel: AppModel) -> NSPopover {
        if let popover {
            return popover
        }

        let content = makeControlsView(appModel: appModel)

        let hosting = NSHostingController(rootView: content)
        // Let the SwiftUI layout decide the height so the pinned Settings row is included.
        hosting.sizingOptions = [.preferredContentSize]

        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover
        return popover
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
        guard popover?.isShown == true else { return }

        let location = NSEvent.mouseLocation

        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let buttonScreenRect = buttonWindow.convertToScreen(buttonRect).insetBy(dx: -2, dy: -2)
            if buttonScreenRect.contains(location) {
                return
            }
        }

        if let popoverWindow = popover?.contentViewController?.view.window {
            if popoverWindow.frame.contains(location) {
                return
            }
        }

        hidePopover()
    }

    func popoverDidShow(_ notification: Notification) {
        guard captureChromeActive else { return }
        hidePopoverImmediately()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        statusItem?.button?.isHighlighted = false
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
