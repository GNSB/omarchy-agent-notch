import AppKit
import SwiftUI

let commandNotification = Notification.Name("com.agentnotch.command")
let commands = ["toggle", "ask", "close", "last"]

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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var panel: NotchPanel!
    let model = NotchModel.shared
    let panelSize = CGSize(width: 720, height: 420)

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
        NSApp.mainMenu = main
    }

    /// ⌘V with an image (or copied image files) on the clipboard attaches it instead of pasting.
    /// Plain text falls through to the normal paste.
    private func installPasteMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, e.charactersIgnoringModifiers == "v" else { return e }
            return MainActor.assumeIsolated { () -> NSEvent? in
                guard let self, self.model.mode == .input || self.model.mode == .answer else { return e }
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
