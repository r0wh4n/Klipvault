import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Window

final class PrefsWindow {
    static let shared = PrefsWindow()
    private var window: NSWindow?

    func show(tab: String = "general") {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "Klipvault Preferences"
            w.center()
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: PrefsView(initialTab: tab).environmentObject(AppState.shared))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PrefsView: View {
    let initialTab: String
    @State private var tab: String = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            StorageTab().tabItem { Label("Storage", systemImage: "internaldrive") }.tag("storage")
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintbrush") }.tag("appearance")
            PinsTab().tabItem { Label("Pins", systemImage: "pin") }.tag("pins")
            IgnoreTab().tabItem { Label("Ignore", systemImage: "nosign") }.tag("ignore")
            SecurityTab().tabItem { Label("Security", systemImage: "lock.shield") }.tag("security")
            AdvancedTab().tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }.tag("advanced")
        }
        .frame(width: 640, height: 560)
        .onAppear { tab = initialTab }
    }
}

// MARK: - General

struct GeneralTab: View {
    @AppStorage(D.launchAtLogin) private var launchAtLogin = false
    @AppStorage(D.pasteOnSelect) private var pasteOnSelect = true
    @AppStorage(D.moveToTopOnUse) private var moveToTop = true
    @AppStorage(D.playSound) private var playSound = false
    @AppStorage(D.searchMode) private var searchMode = "fuzzy"
    @AppStorage(D.quickPasteModifier) private var quickMod = "command"

    var body: some View {
        Form {
            Section("Shortcuts") {
                HotkeyRow("Open Klipvault", D.hkPopup)
                HotkeyRow("Paste last copied item", D.hkPasteLast)
                HotkeyRow("Paste last item as plain text", D.hkPasteLastPlain)
                HotkeyRow("Clear history", D.hkClear)
                HotkeyRow("Lock vault", D.hkLock)
                HotkeyRow("Panic wipe (erase everything)", D.hkPanic)
                Picker("Quick-paste modifier", selection: $quickMod) {
                    Text("⌘ Command").tag("command")
                    Text("⌥ Option").tag("option")
                    Text("⌃ Control").tag("control")
                }
                Text("Hold the modifier and press 1–9 to paste that row, or a pin's letter to paste it instantly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Behaviour") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { NSSound.beep() }
                    }
                Toggle("Paste immediately on selection", isOn: $pasteOnSelect)
                Toggle("Move an item to the top when reused", isOn: $moveToTop)
                Toggle("Play a sound when something is captured", isOn: $playSound)
                Picker("Search", selection: $searchMode) {
                    Text("Fuzzy (recommended)").tag("fuzzy")
                    Text("Contains").tag("contains")
                    Text("Exact, case-sensitive").tag("exact")
                    Text("Regular expression").tag("regex")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct HotkeyRow: View {
    let label: String
    let key: String
    init(_ label: String, _ key: String) { self.label = label; self.key = key }
    var body: some View {
        LabeledContent(label) { HotkeyField(key: key).frame(width: 130, height: 22) }
    }
}

// MARK: - Storage

struct StorageTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(D.retentionDays) private var days = 15
    @AppStorage(D.maxItems) private var maxItems = 0
    @AppStorage(D.keepPinnedForever) private var keepPinned = true
    @AppStorage(D.storeText) private var storeText = true
    @AppStorage(D.storeImages) private var storeImages = true
    @AppStorage(D.storeFiles) private var storeFiles = true
    @AppStorage(D.maxImageMB) private var maxImageMB = 32
    @AppStorage(D.maxTextKB) private var maxTextKB = 2048
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section("Retention") {
                Stepper(value: $days, in: 0...3650) {
                    Text(days == 0 ? "Keep history forever" : "Keep history for **\(days)** days")
                }
                Text(days == 0
                     ? "Nothing is ever deleted automatically."
                     : "Anything copied more than \(days) days ago is erased on the next sweep — file and encrypted blob together.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pinned items never expire", isOn: $keepPinned)
                LabeledContent("Maximum items") {
                    HStack {
                        TextField("", value: $maxItems, format: .number).frame(width: 70)
                        Text(maxItems == 0 ? "unlimited" : "items").foregroundStyle(.secondary)
                    }
                }
            }
            Section("What to capture") {
                Toggle("Text", isOn: $storeText)
                Toggle("Images", isOn: $storeImages)
                Toggle("Files and folders", isOn: $storeFiles)
                LabeledContent("Skip images larger than") {
                    HStack { TextField("", value: $maxImageMB, format: .number).frame(width: 60); Text("MB") }
                }
                LabeledContent("Skip text larger than") {
                    HStack { TextField("", value: $maxTextKB, format: .number).frame(width: 60); Text("KB") }
                }
            }
            Section("Vault") {
                LabeledContent("Items stored", value: "\(state.items.count)")
                LabeledContent("On disk", value: Watcher.human(Int(state.vault.diskBytes)))
                LabeledContent("Location", value: state.vault.dir.path)
                    .lineLimit(1).truncationMode(.head)
                HStack {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([state.vault.dir]) }
                    Button("Compact now") {
                        state.vault.purgeExpired(days: days, keepPinnedForever: keepPinned,
                                                 sensitiveMinutes: D.int(D.sensitiveMinutes))
                        state.vault.rewrite()
                        state.items = state.vault.items
                    }
                    Spacer()
                }
                HStack {
                    Button("Export…") { Backup.export(state) }
                    Button("Import…") { Backup.importVault(state) }
                    Spacer()
                    Button("Clear history") { state.clearHistory(keepPinned: true) }
                    Button("Erase everything") { confirmWipe = true }.foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Erase the entire vault?", isPresented: $confirmWipe) {
            Button("Erase", role: .destructive) { state.clearHistory(keepPinned: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every item, pin and encrypted blob is deleted from disk. This cannot be undone.")
        }
    }
}

// MARK: - Appearance

struct AppearanceTab: View {
    @AppStorage(D.theme) private var theme = "system"
    @AppStorage(D.popupAt) private var popupAt = "cursor"
    @AppStorage(D.imageHeight) private var imageHeight = 40.0
    @AppStorage(D.previewDelay) private var previewDelay = 700.0
    @AppStorage(D.highlightMatches) private var highlight = "bold"
    @AppStorage(D.showMenuIcon) private var showMenuIcon = true
    @AppStorage(D.menuIconStyle) private var menuIconStyle = "vault"
    @AppStorage(D.showRecentInMenuBar) private var showRecent = false
    @AppStorage(D.showAppIcons) private var showAppIcons = true
    @AppStorage(D.showTimestamps) private var showTimestamps = true
    @AppStorage(D.showPreviewPane) private var showPreview = false
    @AppStorage(D.popupWidth) private var popupWidth = 340.0
    @AppStorage(D.showFooter) private var showFooter = true
    @AppStorage(D.rowsVisible) private var rows = 10
    @AppStorage(D.fontSize) private var fontSize = 13.0
    @AppStorage(D.compactRows) private var compact = false

    var body: some View {
        Form {
            Section("Window") {
                Picker("Theme", selection: $theme) {
                    Text("Match system").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                .onChange(of: theme) { _, t in Theme.apply(t) }
                Picker("Pop up at", selection: $popupAt) {
                    Text("Cursor").tag("cursor"); Text("Screen centre").tag("center")
                    Text("Menu bar").tag("menubar"); Text("Where I left it").tag("lastPosition")
                }
                LabeledContent("Popup width") {
                    HStack { Slider(value: $popupWidth, in: 280...700, step: 10)
                             Text("\(Int(popupWidth))pt").monospacedDigit() }
                }
                Stepper("Visible rows: **\(rows)**", value: $rows, in: 4...30)
                Toggle("Compact rows", isOn: $compact)
            }
            Section("Rows") {
                LabeledContent("Image height") {
                    HStack { Slider(value: $imageHeight, in: 20...120); Text("\(Int(imageHeight))pt").monospacedDigit() }
                }
                LabeledContent("Text size") {
                    HStack { Slider(value: $fontSize, in: 10...20); Text("\(Int(fontSize))pt").monospacedDigit() }
                }
                LabeledContent("Preview delay") {
                    HStack { Slider(value: $previewDelay, in: 0...3000, step: 50)
                             Text("\(Int(previewDelay))ms").monospacedDigit() }
                }
                Picker("Highlight matches", selection: $highlight) {
                    Text("Bold").tag("bold"); Text("Underline").tag("underline")
                    Text("Accent colour").tag("accent"); Text("Don't highlight").tag("none")
                }
                Toggle("Show source app icons", isOn: $showAppIcons)
                Toggle("Show timestamps and sizes", isOn: $showTimestamps)
            }
            Section("Chrome") {
                Toggle("Show menu bar icon", isOn: $showMenuIcon)
                    .onChange(of: showMenuIcon) { _, _ in MenuBar.shared.refreshIcon() }
                Picker("Menu bar icon", selection: $menuIconStyle) {
                    Text("Vault").tag("vault"); Text("Clipboard").tag("clipboard")
                    Text("Scissors").tag("scissors"); Text("Tray").tag("tray")
                }
                .onChange(of: menuIconStyle) { _, _ in MenuBar.shared.refreshIcon() }
                Toggle("Show most recent copy next to the icon", isOn: $showRecent)
                    .onChange(of: showRecent) { _, _ in MenuBar.shared.refreshIcon() }
                Toggle("Show preview pane", isOn: $showPreview)
                Text("Adds a \(Int(PanelController.previewWidth))pt column beside the list. Off by default — ⇥ toggles it while the popup is open.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show footer with shortcut hints", isOn: $showFooter)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pins

struct PinsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let pins = state.items.filter { $0.pinned }.sorted { ($0.pinKey ?? "~") < ($1.pinKey ?? "~") }
            if pins.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "pin.slash").font(.system(size: 34)).foregroundStyle(.tertiary)
                    Text("No pinned items yet").font(.headline)
                    Text("Open Klipvault, select anything and press ⌘P. Pinned items sit at the top of the list, never expire, and get their own one-key shortcut.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Hold \(modName()) and press a pin's key to paste it without opening the window.")
                    .font(.callout).foregroundStyle(.secondary).padding(12)
                Divider()
                List {
                    ForEach(pins) { p in
                        HStack(spacing: 10) {
                            TextField("", text: Binding(
                                get: { p.pinKey ?? "" },
                                set: { state.setPinKey(p, String($0.prefix(1)).lowercased()) }))
                                .frame(width: 34).multilineTextAlignment(.center)
                            Image(systemName: p.glyph).foregroundStyle(.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.title).lineLimit(1)
                                Text("\(p.appName ?? "Unknown") · \(p.relativeTime)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { state.togglePin(p) } label: { Image(systemName: "pin.slash") }
                                .buttonStyle(.borderless).help("Unpin")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func modName() -> String {
        switch D.str(D.quickPasteModifier) {
        case "option": return "⌥"; case "control": return "⌃"; default: return "⌘"
        }
    }
}

// MARK: - Ignore

struct IgnoreTab: View {
    @AppStorage(D.ignoredApps) private var apps = ""
    @AppStorage(D.ignoreRegexes) private var regexes = ""
    @AppStorage(D.ignoreTransient) private var transient = true
    @AppStorage(D.ignoreConfidential) private var confidential = true
    @AppStorage(D.minLength) private var minLength = 1
    @AppStorage(D.maxLength) private var maxLength = 0
    @AppStorage(D.ignoreOnlyWhitespace) private var ignoreWhitespace = true

    var body: some View {
        Form {
            Section("Never record from these apps") {
                TextEditor(text: $apps)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 90)
                HStack {
                    Button("Add app…") { pickApp() }
                    Spacer()
                    Text("One bundle identifier per line").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Never record text matching") {
                TextEditor(text: $regexes)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 70)
                Text("One regular expression per line, e.g. `^\\d{4} \\d{4} \\d{4} \\d{4}$` for card numbers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rules") {
                Toggle("Respect “transient” pasteboard markers", isOn: $transient)
                Toggle("Respect password-manager markers (1Password, KeePass, …)", isOn: $confidential)
                Toggle("Ignore whitespace-only copies", isOn: $ignoreWhitespace)
                LabeledContent("Minimum length") {
                    HStack { TextField("", value: $minLength, format: .number).frame(width: 60); Text("chars") }
                }
                LabeledContent("Maximum length") {
                    HStack { TextField("", value: $maxLength, format: .number).frame(width: 60)
                             Text(maxLength == 0 ? "unlimited" : "chars").foregroundStyle(.secondary) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        let ids = p.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        apps = (apps.split(whereSeparator: \.isNewline).map(String.init) + ids)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: "\n")
    }
}

// MARK: - Security

struct SecurityTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(D.autoLockMinutes) private var autoLock = 0
    @AppStorage(D.lockOnSleep) private var lockOnSleep = false
    @AppStorage(D.lockOnScreensaver) private var lockOnSaver = false
    @AppStorage(D.detectSecrets) private var detectSecrets = true
    @AppStorage(D.maskSensitive) private var maskSensitive = true
    @AppStorage(D.sensitiveMinutes) private var sensitiveMinutes = 0
    @AppStorage(D.clearSystemClipboardOnQuit) private var clearOnQuit = false
    @State private var pass1 = ""
    @State private var pass2 = ""
    @State private var note: String?
    @State private var suggested = Passphrase.generate()

    var body: some View {
        Form {
            Section("Encryption") {
                LabeledContent("Cipher", value: "AES-256-GCM (authenticated)")
                LabeledContent("Key derivation", value: "PBKDF2-HMAC-SHA256, \(KDF.defaultIterations.formatted()) rounds")
                LabeledContent("Key stored in",
                               value: state.vault.usesPassphrase ? "Your passphrase — nowhere else" : "key.local (this Mac, 0600)")
                Text(state.vault.usesPassphrase
                     ? "The key exists nowhere on this Mac. Lose the passphrase and the history is gone — that is the point."
                     : "There is nothing to type, and history.vault on its own is unreadable: copied to another machine, synced to a cloud folder or pulled from a backup, it gives up nothing. Anyone who can already read files as you can read key.local too — add a passphrase below to close that gap.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(state.vault.usesPassphrase ? "Change or remove passphrase" : "Add a passphrase") {
                if !state.vault.usesPassphrase {
                    LabeledContent("Suggested") {
                        HStack {
                            Text(suggested).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            Button { suggested = Passphrase.generate() } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless)
                            Button("Use") { pass1 = suggested; pass2 = suggested }
                        }
                    }
                    Text("Six random words — about 77 bits of entropy, and you can actually remember it. Write it down somewhere physical before you commit.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                SecureField("Passphrase", text: $pass1)
                SecureField("Repeat passphrase", text: $pass2)
                HStack {
                    Button(state.vault.usesPassphrase ? "Change passphrase" : "Enable passphrase") { setPass() }
                        .disabled(pass1.count < 8 || pass1 != pass2)
                    if state.vault.usesPassphrase {
                        Button("Remove passphrase") {
                            try? state.vault.removePassphrase()
                            note = "Passphrase removed — the key is back in your Keychain."
                        }
                    }
                    Spacer()
                    if let n = note { Text(n).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("Locking") {
                Stepper(autoLock == 0 ? "Never lock automatically" : "Lock after **\(autoLock)** min idle",
                        value: $autoLock, in: 0...240, step: 5)
                    .onChange(of: autoLock) { _, _ in state.scheduleIdleLock() }
                Toggle("Lock when the Mac sleeps", isOn: $lockOnSleep)
                Toggle("Lock when the screen saver starts", isOn: $lockOnSaver)
                Toggle("Clear the system clipboard when Klipvault quits", isOn: $clearOnQuit)
                if !state.vault.usesPassphrase {
                    Text("Locking only has teeth once a passphrase is set.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Secret detection") {
                Toggle("Flag API keys, tokens, private keys and card numbers", isOn: $detectSecrets)
                Toggle("Hide flagged items behind a lock in the list", isOn: $maskSensitive)
                Stepper(sensitiveMinutes == 0 ? "Flagged items follow the normal retention"
                                              : "Delete flagged items after **\(sensitiveMinutes)** min",
                        value: $sensitiveMinutes, in: 0...1440, step: 5)
                Text("\(SecretScanner.patterns.count) patterns: AWS, GitHub, Slack, Stripe, Google, OpenAI/Anthropic, JWTs, PEM blocks, bearer tokens, DB connection strings, credit cards.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack {
                        Text(AXIsProcessTrusted() ? "Granted" : "Not granted")
                            .foregroundStyle(AXIsProcessTrusted() ? .green : .orange)
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Text("Only needed to press ⌘V for you. Without it Klipvault still copies to the clipboard — you paste yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setPass() {
        do {
            try state.vault.setPassphrase(pass1)
            note = "Passphrase set. The key is no longer stored on this Mac."
            pass1 = ""; pass2 = ""
        } catch { note = "Could not set passphrase." }
    }
}

// MARK: - Advanced

struct AdvancedTab: View {
    @EnvironmentObject var state: AppState
    @AppStorage(D.pollInterval) private var poll = 0.35
    @AppStorage(D.dedupe) private var dedupe = true
    @AppStorage(D.stripFormatting) private var strip = false
    @AppStorage(D.previewLines) private var previewLines = 12
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Clipboard poll interval") {
                    HStack { Slider(value: $poll, in: 0.1...2.0, step: 0.05)
                             Text("\(poll, specifier: "%.2f")s").monospacedDigit() }
                }
                .onChange(of: poll) { _, _ in state.watcher.restart() }
                Toggle("Collapse duplicates instead of storing them twice", isOn: $dedupe)
                Toggle("Always paste as plain text", isOn: $strip)
                Stepper("Preview up to **\(previewLines)** lines", value: $previewLines, in: 3...100)
            }
            Section("Maintenance") {
                HStack {
                    Button("Open data folder") { NSWorkspace.shared.open(state.vault.dir) }
                    Button("Restart capture") { state.watcher.restart() }
                    Spacer()
                    Button("Reset all preferences") { confirmReset = true }
                }
                Text("Resetting preferences never touches your history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Klipvault", value: "1.0")
                LabeledContent("Storage format", value: "Encrypted append-only log + sealed blob store")
                Text("Everything stays on this Mac. No account, no sync, no telemetry, no network code at all.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Reset every preference?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { D.resetAll(); MenuBar.shared.refreshIcon() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Hotkey recorder

struct HotkeyField: NSViewRepresentable {
    let key: String
    func makeNSView(context: Context) -> HotkeyRecorderView { HotkeyRecorderView(key: key) }
    func updateNSView(_ v: HotkeyRecorderView, context: Context) { v.needsDisplay = true }
}

final class HotkeyRecorderView: NSView {
    private let key: String
    private var recording = false
    private var monitor: Any?

    init(key: String) {
        self.key = key
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirty: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlColor).setFill()
        bg.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        bg.stroke()
        let stored = D.str(key)
        let text = recording ? "Press keys…" : (HotkeyCenter.Combo.parse(stored)?.display ?? "Click to set")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: stored.isEmpty && !recording ? NSColor.tertiaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 || !D.str(key).isEmpty && recording == false && event.modifierFlags.contains(.option) {
            D.set(key, ""); MenuBar.shared.rebindHotkeys(); needsDisplay = true; return
        }
        startRecording()
    }

    private func startRecording() {
        guard !recording else { return }
        recording = true
        needsDisplay = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self else { return e }
            if e.type == .flagsChanged { return nil }
            if e.keyCode == 53 { self.stopRecording(); return nil }               // esc cancels
            if e.keyCode == 51 { D.set(self.key, ""); self.stopRecording(); return nil } // ⌫ clears
            let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.isEmpty else { NSSound.beep(); return nil }
            D.set(self.key, HotkeyCenter.Combo(keyCode: e.keyCode, flags: flags).stored)
            MenuBar.shared.rebindHotkeys()
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        needsDisplay = true
    }
}

// MARK: - Passphrase suggestion

enum Passphrase {
    /// Short, common, unambiguous words — a memorable passphrase beats a strong one
    /// you write on a sticky note.
    static let words = """
    anchor amber apple arrow autumn basil beacon birch bishop bramble bridge bronze cabin cactus \
    candle canyon cedar cinder cobalt comet copper coral cotton cypress dagger dahlia delta denim \
    domino ember falcon fennel fjord flint forest fossil garnet ginger glacier granite harbor hazel \
    heron indigo ivory jasper juniper kettle lantern larch lava ledger lemon lilac linen lotus lumen \
    maple marble meadow mesa mint mirror monsoon moss nectar nickel nimbus oak ochre onyx opal orbit \
    otter oxide paprika pebble pepper pewter pigeon pine plateau plum pollen poplar prairie quartz \
    quill radish raven reef ripple river rowan rust saffron sage salt sandal sapphire savanna sequoia \
    shale silk silver slate solar spruce steppe stone summit sycamore talon tangerine teak thistle \
    thunder timber topaz torch trellis tundra umber valley velvet vermilion violet walnut willow \
    wicker wolf zephyr zinc
    """.split(separator: " ").map(String.init)

    static func generate(_ n: Int = 6) -> String {
        (0..<n).map { _ in words[Int.random(in: 0..<words.count)] }.joined(separator: "-")
    }
}

// MARK: - Theme

enum Theme {
    static func apply(_ t: String) {
        switch t {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

// MARK: - Backup

enum Backup {
    static func export(_ state: AppState) {
        let a = NSAlert()
        a.messageText = "Export the vault"
        a.informativeText = "An encrypted backup can only be opened with this Mac's key or your passphrase. A plain export is readable by anyone who gets the file."
        a.addButton(withTitle: "Encrypted backup")
        a.addButton(withTitle: "Plain JSON")
        a.addButton(withTitle: "Cancel")
        let choice = a.runModal()
        guard choice != .alertThirdButtonReturn else { return }

        let p = NSSavePanel()
        let encrypted = choice == .alertFirstButtonReturn
        p.nameFieldStringValue = encrypted ? "klipvault-backup.vault" : "klipvault-export.json"
        guard p.runModal() == .OK, let url = p.url else { return }

        if encrypted {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: state.vault.historyURL, to: url)
        } else {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(state.vault.items) { try? d.write(to: url) }
        }
    }

    static func importVault(_ state: AppState) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let url = p.url, let d = try? Data(contentsOf: url) else { return }
        guard let recs = try? JSONDecoder().decode([ClipRecord].self, from: d) else {
            let a = NSAlert()
            a.messageText = "Could not read that file"
            a.informativeText = "Encrypted backups are restored by replacing history.vault in the data folder while Klipvault is not running."
            a.runModal(); return
        }
        for r in recs where !state.vault.items.contains(where: { $0.hash == r.hash }) {
            state.vault.insert(r, dedupe: false, maxItems: 0)
        }
        state.items = state.vault.items
    }
}
