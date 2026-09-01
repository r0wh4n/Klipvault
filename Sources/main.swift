import AppKit
import SwiftUI
import ApplicationServices
import CryptoKit

// MARK: - Menu bar

final class MenuBar: NSObject, NSMenuDelegate {
    static let shared = MenuBar()
    private var statusItem: NSStatusItem?
    private let state = AppState.shared

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = statusItem?.button else { return }
        statusItem?.isVisible = D.bool(D.showMenuIcon)
        let name: String
        switch D.str(D.menuIconStyle) {
        case "clipboard": name = "list.clipboard"
        case "scissors": name = "scissors"
        case "tray": name = "tray.full"
        default: name = "lock.rectangle.stack"
        }
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Klipvault")
        button.image?.isTemplate = true
        if D.bool(D.showRecentInMenuBar), let recent = state.items.first, !state.locked {
            button.title = " " + String(recent.title.prefix(18))
        } else {
            button.title = ""
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let rightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if rightClick {
            statusItem?.menu = buildMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            PanelController.shared.toggle()
        }
    }

    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: state.locked ? "Unlock Klipvault…" : "Open Klipvault",
                  action: #selector(openPanel), keyEquivalent: "").target = self

        if !state.locked {
            let pinned = state.items.filter { $0.pinned }
            if !pinned.isEmpty {
                m.addItem(.separator())
                let header = NSMenuItem(title: "Pinned", action: nil, keyEquivalent: "")
                header.isEnabled = false
                m.addItem(header)
                for p in pinned.prefix(10) { m.addItem(menuItem(for: p)) }
            }
            let recents = state.items.filter { !$0.pinned }.prefix(8)
            if !recents.isEmpty {
                m.addItem(.separator())
                let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
                header.isEnabled = false
                m.addItem(header)
                for r in recents { m.addItem(menuItem(for: r)) }
            }
            m.addItem(.separator())
            m.addItem(withTitle: "Clear History…", action: #selector(clearHistory), keyEquivalent: "").target = self
            if state.vault.usesPassphrase {
                m.addItem(withTitle: "Lock Vault", action: #selector(lockVault), keyEquivalent: "").target = self
            }
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Preferences…", action: #selector(openPrefs), keyEquivalent: ",").target = self
        m.addItem(withTitle: "Quit Klipvault", action: #selector(quit), keyEquivalent: "q").target = self
        return m
    }

    private func menuItem(for rec: ClipRecord) -> NSMenuItem {
        let i = NSMenuItem(title: String(rec.title.prefix(60)), action: #selector(pasteItem(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = rec.id.uuidString
        if let t = rec.thumb, let img = NSImage(data: t) {
            img.size = NSSize(width: 16, height: 16)
            i.image = img
        } else {
            i.image = NSImage(systemSymbolName: rec.glyph, accessibilityDescription: nil)
        }
        return i
    }

    @objc private func pasteItem(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let rec = state.items.first(where: { $0.id.uuidString == s }) else { return }
        state.rememberFrontApp()
        state.use(rec, paste: D.bool(D.pasteOnSelect))
    }

    @objc private func openPanel() { PanelController.shared.show() }
    @objc private func openPrefs() { PrefsWindow.shared.show() }
    @objc private func lockVault() { state.lock(); refreshIcon() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func clearHistory() {
        let a = NSAlert()
        a.messageText = "Clear clipboard history?"
        a.informativeText = "Pinned items are kept."
        a.addButton(withTitle: "Clear")
        a.addButton(withTitle: "Keep Everything")
        if a.runModal() == .alertFirstButtonReturn { state.clearHistory(keepPinned: true); refreshIcon() }
    }

    // MARK: hotkeys

    func rebindHotkeys() {
        let hk = HotkeyCenter.shared
        hk.bind("popup", HotkeyCenter.Combo.parse(D.str(D.hkPopup))) {
            PanelController.shared.toggle()
        }
        hk.bind("pasteLast", HotkeyCenter.Combo.parse(D.str(D.hkPasteLast))) { [weak self] in
            guard let self, let r = self.state.items.first else { return }
            self.state.rememberFrontApp(); self.state.use(r, paste: true)
        }
        hk.bind("pasteLastPlain", HotkeyCenter.Combo.parse(D.str(D.hkPasteLastPlain))) { [weak self] in
            guard let self, let r = self.state.items.first else { return }
            self.state.rememberFrontApp(); self.state.use(r, paste: true, plain: true)
        }
        hk.bind("clear", HotkeyCenter.Combo.parse(D.str(D.hkClear))) { [weak self] in
            self?.state.clearHistory(keepPinned: true); self?.refreshIcon()
        }
        hk.bind("lock", HotkeyCenter.Combo.parse(D.str(D.hkLock))) { [weak self] in
            self?.state.lock(); PanelController.shared.hide(); self?.refreshIcon()
        }
        // Panic wipe is deliberately unconfirmed — that is the entire point of a panic key.
        // It has no default binding, so it only exists once you deliberately set one.
        hk.bind("panic", HotkeyCenter.Combo.parse(D.str(D.hkPanic))) { [weak self] in
            PanelController.shared.hide()
            self?.state.clearHistory(keepPinned: false)
            NSPasteboard.general.clearContents()
            self?.refreshIcon()
        }
    }
}

// MARK: - Unlock window

final class UnlockWindow {
    static let shared = UnlockWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 210),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Klipvault"
            w.center()
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.contentView = NSHostingView(rootView: UnlockView(onDone: { [weak self] in
                self?.window?.orderOut(nil)
                MenuBar.shared.refreshIcon()
            }))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct UnlockView: View {
    let onDone: () -> Void
    @State private var pass = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.rectangle.stack.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Unlock your vault").font(.headline)
            SecureField("Passphrase", text: $pass)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(unlock)
            if wrong { Text("That passphrase does not open this vault.").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Unlock", action: unlock).keyboardShortcut(.defaultAction).disabled(pass.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { focused = true }
    }

    private func unlock() {
        if AppState.shared.unlock(passphrase: pass) { pass = ""; wrong = false; onDone() }
        else { wrong = true; NSSound.beep() }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sweep: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        D.registerDefaults()
        Theme.apply(D.str(D.theme))
        AppState.shared.boot()
        MenuBar.shared.install()
        MenuBar.shared.rebindHotkeys()

        // Retention sweep: once on launch (done in boot) then hourly.
        sweep = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let s = AppState.shared
            guard !s.locked else { return }
            s.vault.purgeExpired(days: D.int(D.retentionDays),
                                 keepPinnedForever: D.bool(D.keepPinnedForever),
                                 sensitiveMinutes: D.int(D.sensitiveMinutes))
            s.items = s.vault.items
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            if D.bool(D.lockOnSleep) { AppState.shared.lock(); MenuBar.shared.refreshIcon() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            if D.bool(D.lockOnScreensaver) { AppState.shared.lock(); MenuBar.shared.refreshIcon() }
        }

        if !D.bool(D.firstRunDone) {
            D.set(D.firstRunDone, true)
            firstRun()
        }
        if AppState.shared.locked { UnlockWindow.shared.show() }

        if CommandLine.arguments.contains("--test-ui") { runUITest() }
    }

    /// Headless smoke test: builds the popup and the preferences window for real and
    /// checks they make it onto the screen. Catches SwiftUI crashes a unit test cannot.
    private func runUITest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            PanelController.shared.show()
            PrefsWindow.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let pid = ProcessInfo.processInfo.processIdentifier
                let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
                let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
                for w in mine {
                    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    print("  window: \(w[kCGWindowName as String] as? String ?? "(popup)")  "
                          + "\(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
                }
                print(mine.count >= 2 ? "ui: popup and preferences both rendered"
                                      : "ui: FAILED — only \(mine.count) window(s) on screen")
                exit(mine.count >= 2 ? 0 : 1)
            }
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        if D.bool(D.clearSystemClipboardOnQuit) { NSPasteboard.general.clearContents() }
    }

    private func firstRun() {
        let a = NSAlert()
        a.messageText = "Klipvault is running in your menu bar"
        a.informativeText = """
        Press ⌘⇧V to open your clipboard history.

        Everything you copy is encrypted with AES-256 before it touches the disk, and kept for 15 days by default.

        To let Klipvault paste for you, grant Accessibility permission. Without it, selecting an item still copies it — you just press ⌘V yourself.
        """
        a.addButton(withTitle: "Open Accessibility Settings")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

// MARK: - Self-test  (`Klipvault --selftest`)

func selfTest() -> Int32 {
    var failures = 0
    // `assert` is compiled out under -O, taking its side effects with it. This runs
    // in the shipped binary, so every check must survive optimisation.
    func check(_ ok: Bool, _ what: String) {
        if ok { print("  ok   \(what)") } else { failures += 1; print("  FAIL \(what)") }
    }

    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("klipvault-test-\(UUID())")
    let v = Vault(dir: tmp)
    defer { try? FileManager.default.removeItem(at: tmp) }

    // 1. A passphrase-wrapped key round-trips; a wrong passphrase does not.
    v.unlockEphemeral()
    try! v.setPassphrase("correct-horse-battery-staple")
    v.lock()
    check(v.unlock(passphrase: "wrong") == false, "wrong passphrase is rejected")
    check(v.unlock(passphrase: "correct-horse-battery-staple"), "correct passphrase unlocks")

    // 2. Records survive an append + reload cycle, and never hit the disk in the clear.
    var a = ClipRecord(); a.title = "hello"; a.text = "hello world"; a.hash = "h1"
    var b = ClipRecord(); b.title = "second"; b.text = "SUPER-SECRET-VALUE"; b.hash = "h2"
    v.insert(a, dedupe: true, maxItems: 0)
    v.insert(b, dedupe: true, maxItems: 0)
    let raw = (try? Data(contentsOf: v.historyURL)) ?? Data()
    check(!raw.isEmpty, "history file was written")
    check(!String(decoding: raw, as: UTF8.self).contains("SUPER-SECRET-VALUE"), "no plaintext on disk")
    v.lock()
    _ = v.unlock(passphrase: "correct-horse-battery-staple")
    v.load()
    check(v.items.count == 2, "2 records reloaded (got \(v.items.count))")
    check(v.items.contains { $0.text == "SUPER-SECRET-VALUE" }, "record content survives a reload")

    // 3. Dedupe collapses a repeat copy instead of storing it twice.
    v.insert(a, dedupe: true, maxItems: 0)
    check(v.items.count == 2, "duplicate collapsed (got \(v.items.count))")

    // 4. Retention deletes old items but spares pins.
    var old = ClipRecord(); old.title = "ancient"; old.hash = "h3"
    old.created = Date().timeIntervalSince1970 - 40 * 86400
    var oldPin = ClipRecord(); oldPin.title = "ancient pin"; oldPin.hash = "h4"
    oldPin.created = old.created; oldPin.pinned = true
    v.insert(old, dedupe: false, maxItems: 0)
    v.insert(oldPin, dedupe: false, maxItems: 0)
    v.update(oldPin.id) { $0.pinned = true }        // insert() clears pinned by design
    let killed = v.purgeExpired(days: 15, keepPinnedForever: true, sensitiveMinutes: 0)
    check(killed == 1, "retention dropped exactly the unpinned old item (dropped \(killed))")
    check(v.items.contains { $0.title == "ancient pin" }, "pinned item survived retention")

    // 5. maxItems trims the tail.
    for i in 0..<5 {
        var r = ClipRecord(); r.title = "bulk\(i)"; r.hash = "bulk\(i)"
        v.insert(r, dedupe: true, maxItems: 3)
    }
    check(v.items.filter { !$0.pinned }.count == 3, "maxItems capped unpinned history")

    // 6. Reuse moves an item to the top, and that order survives a reload.
    let bulkLast = v.items.last { !$0.pinned }
    if let target = bulkLast {
        v.touch(target.id)
        check(v.items.first?.id == target.id, "reuse moved the item to the top")
        v.lock(); _ = v.unlock(passphrase: "correct-horse-battery-staple"); v.load()
        check(v.items.first?.id == target.id, "that order survived a reload")
    } else {
        check(false, "no item to reuse")
    }

    // 7. Blob store round-trips and is encrypted at rest.
    let name = v.writeBlob(Data("PIXELS-SECRET".utf8)) ?? ""
    check(v.readBlob(name) == Data("PIXELS-SECRET".utf8), "blob round-trips")
    let blobRaw = (try? Data(contentsOf: v.blobsURL.appendingPathComponent(name + ".bin"))) ?? Data()
    check(!String(decoding: blobRaw, as: UTF8.self).contains("PIXELS-SECRET"), "blob is encrypted at rest")

    // 8. A locked vault gives up nothing.
    v.lock()
    check(v.items.isEmpty && v.readBlob(name) == nil, "locked vault reads nothing")

    // 9. Secret detection catches the obvious ones and leaves prose alone.
    check(SecretScanner.match("AKIAIOSFODNN7EXAMPLE") != nil, "detects AWS key")
    check(SecretScanner.match("ghp_1234567890abcdefghijklmnopqrstuvwxyz") != nil, "detects GitHub token")
    check(SecretScanner.match("-----BEGIN RSA PRIVATE KEY-----") != nil, "detects private key block")
    check(SecretScanner.match("let us get lunch at one") == nil, "leaves ordinary prose alone")

    // 10. Fuzzy search matches subsequences, rejects non-matches, ranks tight matches higher.
    check(AppState.fuzzyScore(needle: "hlo", haystack: "hello world") != nil, "fuzzy matches a subsequence")
    check(AppState.fuzzyScore(needle: "zzz", haystack: "hello world") == nil, "fuzzy rejects a non-match")
    let tight = AppState.fuzzyScore(needle: "hell", haystack: "hello") ?? 0
    let loose = AppState.fuzzyScore(needle: "hell", haystack: "h e l l") ?? 0
    check(tight > loose, "fuzzy ranks consecutive matches higher")

    // 11. Hotkey combos survive a round-trip through their stored form.
    let combo = HotkeyCenter.Combo(keyCode: 9, flags: [.command, .shift])
    check(HotkeyCenter.Combo.parse(combo.stored) == combo, "hotkey round-trips")
    check(combo.display == "\u{21E7}\u{2318}V", "hotkey renders as \u{21E7}\u{2318}V (got \(combo.display))")

    print(failures == 0 ? "selftest: all checks passed" : "selftest: \(failures) FAILED")
    return failures == 0 ? 0 : 1
}

// MARK: - Icon generation  (`Klipvault --makeicon <dir>`, used by build.sh)

func makeIcon(_ dir: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),
                       (128,"128x128"),(256,"128x128@2x"),(256,"256x256"),
                       (512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
        let s = CGFloat(px)
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let inset = s * 0.06
        let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)
        NSGradient(colors: [NSColor(srgbRed: 0.36, green: 0.31, blue: 0.85, alpha: 1),
                            NSColor(srgbRed: 0.16, green: 0.12, blue: 0.44, alpha: 1)])?
            .draw(in: path, angle: -90)
        let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
        if let g = NSImage(systemSymbolName: "lock.rectangle.stack.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let gs = g.size
            g.draw(in: NSRect(x: (s - gs.width) / 2, y: (s - gs.height) / 2, width: gs.width, height: gs.height),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        img.unlockFocus()
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}

// MARK: - Entry point

D.registerDefaults()
if CommandLine.arguments.contains("--selftest") {
    exit(selfTest())
}
if CommandLine.arguments.contains("--probe") {
    // Diagnostic: what would Klipvault do with whatever is on the clipboard right now?
    Watcher.debug = true
    let v = Vault()
    let opened = v.usesPassphrase ? false : v.unlockLocal()
    print("vault:  \(v.dir.path)")
    print("opened: \(opened)")
    v.load()
    print("items:  \(v.items.count)")
    print("probe:")
    if let rec = Watcher(vault: v).capture() {
        print("  kept: \(rec.kind.rawValue) — \(rec.title)")
        print("  bytes: \(rec.bytes)  blob: \(rec.blob ?? "none")  thumb: \(rec.thumb?.count ?? 0)B  sensitive: \(rec.sensitive)")
    }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--makeicon"), i + 1 < CommandLine.arguments.count {
    makeIcon(CommandLine.arguments[i + 1])
    exit(0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only: no Dock icon, no app window
app.run()
