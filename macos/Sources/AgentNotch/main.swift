import AppKit
import SwiftUI

let commandNotification = Notification.Name("com.agentnotch.command")
let commands = ["toggle", "ask", "close", "last", "client"]

// `agent-notch ask|toggle|close|last` talks to the running instance.
if CommandLine.arguments.count > 1 {
    let cmd = CommandLine.arguments[1]
    guard commands.contains(cmd) else {
        FileHandle.standardError.write(Data("usage: agent-notch [\(commands.joined(separator: "|"))]\n".utf8))
        exit(2)
    }
    DistributedNotificationCenter.default().postNotificationName(
        commandNotification, object: cmd, userInfo: nil, deliverImmediately: true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    exit(0)
}

// Single instance.
let stateDir = home + "/.local/state/myzk-agents"
try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
let lockFD = open(stateDir + "/notch-mac.lock", O_CREAT | O_RDWR, 0o644)
if flock(lockFD, LOCK_EX | LOCK_NB) != 0 { exit(0) }

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { MainActor.assumeIsolated { NotchModel.shared.mode == .input || NotchModel.shared.mode == .answer } }
    override var canBecomeMain: Bool { false }
}

/// Only the drawn notch takes mouse events; the rest of the window lets clicks through.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let size = MainActor.assumeIsolated { NotchModel.shared.hitSize }
        let local = convert(point, from: superview)
        let y = isFlipped ? 0 : bounds.height - size.height
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: y,
                          width: size.width, height: size.height).insetBy(dx: -2, dy: -2)
        return rect.contains(local) ? super.hitTest(point) : nil
    }
}

/// Minimizing doesn't go to the Dock — it folds the client back into the notch.
final class ClientWindow: NSWindow {
    var onMinimize: (() -> Void)?
    override func miniaturize(_ sender: Any?) { MainActor.assumeIsolated { onMinimize?() } }
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var panel: NotchPanel!
    let model = NotchModel.shared
    let panelSize = CGSize(width: 720, height: 420)
    var clientWindow: NSWindow?
    private var pinSink: Any?

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.shared = self
        model.start()
        installEditMenu()
        installPasteMonitor()

        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = NotchHostingView(rootView: NotchRoot(m: model))
        reposition()
        panel.orderFrontRegardless()
        // Pinning the notch open (click / `agent-notch toggle`) hands over to the client.
        pinSink = model.$pinned.dropFirst().sink { [weak self] on in
            guard on else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let self, !self.model.customOpen, !self.model.detectOpen else { return }
                self.showClient()
            } }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.closeInput() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: commandNotification, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let cmd = n.object as? String else { return }
                switch cmd {
                case "toggle": self.model.toggle()
                case "ask": self.model.openInput()
                case "close": self.model.closeAll()
                case "last": self.model.showLast()
                case "client": self.showClient()
                default: break
                }
            }
        }
    }

    /// An accessory app has no menu bar, and ⌘V/⌘C/⌘A/⌘Z are dispatched through the Edit
    /// menu's key equivalents — without one, text fields can't paste, copy or undo.
    private func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Agent Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window"); winItem.submenu = win
        win.addItem(withTitle: "Minimize to Notch", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = win
        NSApp.mainMenu = main
    }

    /// ⌘V with an image (or copied image files) on the clipboard attaches it instead of pasting.
    /// Plain text falls through to the normal paste.
    private func installPasteMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, e.charactersIgnoringModifiers == "v" else { return e }
            return MainActor.assumeIsolated { () -> NSEvent? in
                guard let self else { return e }
                let inClient = self.clientWindow?.isKeyWindow == true
                guard inClient || self.model.mode == .input || self.model.mode == .answer else { return e }
                return self.model.attachFromPasteboard() ? nil : e
            }
        }
    }

    private func targetScreen() -> NSScreen? {
        let want = model.cfg.str("screen", "")
        if !want.isEmpty, let s = NSScreen.screens.first(where: { $0.localizedName == want }) { return s }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func reposition() {
        guard let screen = targetScreen() else { return }
        var g = NotchGeometry()
        if screen.safeAreaInsets.top > 0 {
            g.hasNotch = true
            g.notchH = screen.safeAreaInsets.top
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                g.notchW = screen.frame.width - l.width - r.width
            } else {
                g.notchW = 200
            }
        } else {
            g.notchH = 32
        }
        model.geometry = g
        let f = screen.frame
        panel.setFrame(NSRect(x: f.midX - panelSize.width / 2, y: f.maxY - panelSize.height,
                              width: panelSize.width, height: panelSize.height), display: true)
    }

    // MARK: client window
    // Notch and client are one surface: expanding the notch morphs it into the client (notch hides),
    // minimizing the client shrinks it back into the notch, which pops open.

    private var transition: NSWindow?
    private var clientFrame: NSRect?
    private var morphing = false

    /// Where the drawn notch sits on screen right now.
    private func notchRect() -> NSRect {
        let s = model.hitSize, f = panel.frame
        return NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: max(s.width, 120), height: max(s.height, 32))
    }

    private func makeClient() -> NSWindow {
        let w = ClientWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        w.title = "Agent Notch"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ClientView(m: model))
        w.center()
        w.onMinimize = { [weak self] in self?.collapseToNotch() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.clientFrame = w.frame
                self.showNotch(open: false)
                NSApp.setActivationPolicy(.accessory)
            }
        }
        return w
    }

    /// A borderless stand-in that flies between the notch and the client frame.
    private func flyer(_ image: NSImage?, from: NSRect) -> NSWindow {
        let t = NSWindow(contentRect: from, styleMask: .borderless, backing: .buffered, defer: false)
        t.isOpaque = false; t.backgroundColor = .clear; t.hasShadow = true
        t.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        t.ignoresMouseEvents = true
        let v = NSView(frame: NSRect(origin: .zero, size: from.size))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(model.notchColor).cgColor
        v.layer?.cornerRadius = 22
        v.layer?.masksToBounds = true
        if let image { v.layer?.contents = image; v.layer?.contentsGravity = .resize }
        v.autoresizingMask = [.width, .height]
        t.contentView = v
        return t
    }

    private func snapshot(_ w: NSWindow) -> NSImage? {
        guard let v = w.contentView?.superview ?? w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        let img = NSImage(size: v.bounds.size); img.addRepresentation(rep)
        return img
    }

    func showClient() {
        guard !morphing else { return }
        let w = clientWindow ?? makeClient()
        clientWindow = w
        NSApp.setActivationPolicy(.regular)
        model.closeAll()
        if w.isVisible { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); hideNotch(); return }

        let target = clientFrame ?? w.frame
        let start = notchRect()
        morphing = true
        let t = flyer(clientFrame == nil ? nil : snapshot(w), from: start)
        t.alphaValue = 1
        t.orderFrontRegardless()
        transition = t
        hideNotch()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            t.animator().setFrame(target, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                w.setFrame(target, display: true)
                w.alphaValue = 0
                w.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.14
                    w.animator().alphaValue = 1
                    t.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { t.orderOut(nil); self.transition = nil; self.morphing = false }
                })
            }
        })
    }

    /// The yellow button: shrink the client into the notch and open the notch.
    func collapseToNotch() {
        guard let w = clientWindow, w.isVisible, !morphing else { return }
        morphing = true
        clientFrame = w.frame
        let t = flyer(snapshot(w), from: w.frame)
        t.orderFrontRegardless()
        transition = t
        w.orderOut(nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
            t.animator().setFrame(self.notchRect(), display: true)
            t.animator().alphaValue = 0.6
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.showNotch(open: true)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    t.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        t.orderOut(nil); self.transition = nil; self.morphing = false
                        NSApp.setActivationPolicy(.accessory)
                    }
                })
            }
        })
    }

    private func hideNotch() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { if self.clientWindow?.isVisible == true || self.morphing { self.panel.orderOut(nil) } }
        })
    }

    private func showNotch(open: Bool) {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if open { model.peek() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showClient(); return true
    }

    /// Lets the text fields take keyboard input (the panel is otherwise non-activating).
    func makeKey() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
