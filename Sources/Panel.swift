import AppKit
import SwiftUI

// MARK: - Panel window

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()
    static let previewWidth: CGFloat = 280
    private var panel: FloatingPanel?
    private var monitor: Any?
    private var outsideMonitor: Any?
    private let state = AppState.shared

    var isVisible: Bool { panel?.isVisible ?? false }
    var contentView: NSView? { panel?.contentView }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        state.rememberFrontApp()
        if state.locked {
            UnlockWindow.shared.show()
            return
        }
        state.query = ""
        state.selected = 0
        state.focusToken &+= 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingPanel {
        let p = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                              styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                              backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = NSHostingView(rootView: ClipListView().environmentObject(state))
        p.delegate = self
        p.minSize = NSSize(width: 260, height: 200)
        return p
    }

    private func position(_ p: NSPanel) {
        let showPreview = D.bool(D.showPreviewPane)
        let rows = max(4, D.int(D.rowsVisible))
        let rowH: CGFloat = D.bool(D.compactRows) ? 28 : 42
        let h = min(700, 44 + CGFloat(rows) * rowH + (D.bool(D.showFooter) ? 26 : 0))
        let w = CGFloat(D.dbl(D.popupWidth)) + (showPreview ? PanelController.previewWidth : 0)
        var frame = NSRect(x: 0, y: 0, width: w, height: h)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        switch D.str(D.popupAt) {
        case "center":
            frame.origin = NSPoint(x: vis.midX - w / 2, y: vis.midY - h / 2)
        case "menubar":
            frame.origin = NSPoint(x: min(vis.maxX - w - 12, max(vis.minX + 12, NSEvent.mouseLocation.x - w / 2)),
                                   y: vis.maxY - h - 6)
        case "lastPosition":
            if let existing = panel?.frame, existing.width > 0 {
                frame.origin = existing.origin
            } else {
                frame.origin = NSPoint(x: vis.midX - w / 2, y: vis.midY - h / 2)
            }
        default: // cursor
            let m = NSEvent.mouseLocation
            frame.origin = NSPoint(x: min(max(vis.minX + 8, m.x - 40), vis.maxX - w - 8),
                                   y: min(max(vis.minY + 8, m.y - h + 20), vis.maxY - h - 8))
        }
        p.setFrame(frame, display: false)
    }

    // MARK: keyboard

    private func installMonitors() {
        removeMonitors()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e) == true ? nil : e
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
    }

    private var quickModifier: NSEvent.ModifierFlags {
        switch D.str(D.quickPasteModifier) {
        case "option": return .option
        case "control": return .control
        default: return .command
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ e: NSEvent) -> Bool {
        guard isVisible else { return false }
        let list = state.filtered
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)
        func clamp(_ i: Int) -> Int { list.isEmpty ? 0 : max(0, min(i, list.count - 1)) }

        switch e.keyCode {
        case 53: // esc
            if !state.query.isEmpty { state.query = "" } else { hide() }
            return true
        case 125: state.selected = clamp(state.selected + 1); return true          // ↓
        case 126: state.selected = clamp(state.selected - 1); return true          // ↑
        case 121: state.selected = clamp(state.selected + max(4, D.int(D.rowsVisible) - 1)); return true
        case 116: state.selected = clamp(state.selected - max(4, D.int(D.rowsVisible) - 1)); return true
        case 115: state.selected = 0; return true                                  // home
        case 119: state.selected = clamp(list.count - 1); return true              // end
        case 36, 76: // return
            guard let item = list[safe: state.selected] else { return true }
            state.use(item, paste: cmd ? false : D.bool(D.pasteOnSelect), plain: opt)
            if cmd { hide() }
            return true
        case 51 where cmd: // ⌘⌫
            if let item = list[safe: state.selected] { state.delete(item) }
            return true
        case 35 where cmd: // ⌘P
            if let item = list[safe: state.selected] { state.togglePin(item) }
            return true
        case 40 where cmd: // ⌘K
            state.query = ""; return true
        case 48: // tab
            D.set(D.showPreviewPane, !D.bool(D.showPreviewPane))
            hide(); show()
            return true
        case 43 where cmd: // ⌘,
            hide(); PrefsWindow.shared.show(); return true
        default: break
        }

        if ctrl, let c = e.charactersIgnoringModifiers?.lowercased() {
            if c == "n" { state.selected = clamp(state.selected + 1); return true }
            if c == "p" { state.selected = clamp(state.selected - 1); return true }
        }

        // Quick paste: modifier + 1…9, or modifier + a pin key.
        if flags.contains(quickModifier), let c = e.charactersIgnoringModifiers?.lowercased(), c.count == 1 {
            if let n = Int(c), n >= 1, n <= 9, let item = list[safe: n - 1] {
                state.use(item, paste: D.bool(D.pasteOnSelect), plain: opt); return true
            }
            if let pinned = state.items.first(where: { $0.pinKey == c }) {
                state.use(pinned, paste: D.bool(D.pasteOnSelect), plain: opt); return true
            }
        }
        return false
    }

    func windowDidResignKey(_ n: Notification) { hide() }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - List UI

struct ClipListView: View {
    @EnvironmentObject var state: AppState
    @AppStorage(D.showPreviewPane) private var showPreview = true
    @AppStorage(D.showFooter) private var showFooter = true
    @AppStorage(D.fontSize) private var fontSize = 13.0
    @AppStorage(D.compactRows) private var compact = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let list = state.filtered
        VStack(spacing: 0) {
            SearchBar(count: list.count).focused($searchFocused)
            Divider()
            HStack(spacing: 0) {
                rows(list)
                if showPreview {
                    Divider()
                    PreviewPane(item: list[safe: state.selected])
                        .frame(width: PanelController.previewWidth)
                }
            }
            if showFooter {
                Divider()
                Footer()
            }
        }
        .background(VisualEffect())
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _, _ in searchFocused = true }
    }

    private func rows(_ list: [ClipRecord]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                        ClipRow(item: item, index: idx, selected: idx == state.selected, query: state.query)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.selected = idx
                                state.use(item, paste: D.bool(D.pasteOnSelect))
                            }
                            .contextMenu { rowMenu(item) }
                    }
                    if list.isEmpty { EmptyState(query: state.query) }
                }
            }
            .frame(minWidth: 240)
            .onChange(of: state.selected) { _, new in
                if let id = list[safe: new]?.id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
            }
        }
    }

    @ViewBuilder private func rowMenu(_ item: ClipRecord) -> some View {
        Button("Paste") { state.use(item, paste: true) }
        Button("Paste as Plain Text") { state.use(item, paste: true, plain: true) }
        Button("Copy Only") { state.use(item, paste: false) }
        Divider()
        Button(item.pinned ? "Unpin" : "Pin") { state.togglePin(item) }
        Button("Delete") { state.delete(item) }
    }
}

struct SearchBar: View {
    @EnvironmentObject var state: AppState
    var count: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your clipboard…", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onChange(of: state.query) { _, _ in state.selected = 0 }
            if !state.query.isEmpty {
                Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Text("\(count)")
                .font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
}

struct ClipRow: View {
    @EnvironmentObject var state: AppState
    let item: ClipRecord
    let index: Int
    let selected: Bool
    let query: String
    @AppStorage(D.showAppIcons) private var showAppIcons = true
    @AppStorage(D.showTimestamps) private var showTimestamps = true
    @AppStorage(D.imageHeight) private var imageHeight = 40.0
    @AppStorage(D.compactRows) private var compact = false
    @AppStorage(D.fontSize) private var fontSize = 13.0

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Highlighted(text: item.title, query: query, size: fontSize)
                    .lineLimit(1)
                if !compact && showTimestamps {
                    HStack(spacing: 5) {
                        if let a = item.appName { Text(a) }
                        Text("·")
                        Text(item.relativeTime)
                        if item.bytes > 0 { Text("·"); Text(Watcher.human(item.bytes)) }
                        if item.sensitive { Label("secret", systemImage: "lock.fill").labelStyle(.titleAndIcon) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let k = item.pinKey {
                Text(k.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.tint.opacity(0.25)))
            } else if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.tint) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(selected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var icon: some View {
        if item.kind == .image, let t = item.thumb, let img = NSImage(data: t) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                .frame(width: imageHeight, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if showAppIcons, let b = item.appBundle,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: item.glyph).frame(width: 18)
                .foregroundStyle(item.sensitive ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
    }
}

/// Bolds (or underlines / tints) the characters that matched the query.
struct Highlighted: View {
    let text: String
    let query: String
    let size: Double
    @AppStorage(D.highlightMatches) private var style = "bold"

    var body: some View {
        Text(attributed).font(.system(size: size))
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, style != "none" else { return a }
        let needle = Array(q)
        var ni = 0
        for i in text.indices where ni < needle.count {
            guard text[i].lowercased() == String(needle[ni]) else { continue }
            if let r = Range(NSRange(i..<text.index(after: i), in: text), in: a) {
                switch style {
                case "underline": a[r].underlineStyle = .single
                case "accent": a[r].foregroundColor = .accentColor
                default: a[r].font = .system(size: size, weight: .bold)
                }
            }
            ni += 1
        }
        return a
    }
}

struct PreviewPane: View {
    @EnvironmentObject var state: AppState
    let item: ClipRecord?
    @AppStorage(D.previewLines) private var previewLines = 12
    @AppStorage(D.previewDelay) private var previewDelay = 700.0
    @State private var shown: ClipRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let it = shown {
                if it.kind == .image, let img = state.fullImage(it) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if it.sensitive && D.bool(D.maskSensitive) {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(.orange)
                        Text("Hidden — looks like a secret").font(.caption)
                        Text("Press ⏎ to paste it anyway").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        Text(it.text ?? "").font(.system(size: 12, design: .monospaced))
                            .lineLimit(previewLines)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    row("Source", it.appName ?? "Unknown")
                    row("Copied", Date(timeIntervalSince1970: it.created).formatted(date: .abbreviated, time: .shortened))
                    row("Size", Watcher.human(it.bytes))
                    if it.kind == .image { row("Dimensions", "\(it.pixelW) × \(it.pixelH)") }
                    if it.uses > 0 { row("Used", "\(it.uses)×") }
                    row("Expires", expiry(it))
                }
                .font(.system(size: 11))
                Spacer()
            } else {
                Spacer()
                Text("No selection").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: item?.id) {
            if shown == nil { shown = item; return }
            try? await Task.sleep(nanoseconds: UInt64(max(0, previewDelay) * 1_000_000))
            shown = item
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v)
        }
    }

    private func expiry(_ it: ClipRecord) -> String {
        if it.pinned && D.bool(D.keepPinnedForever) { return "never (pinned)" }
        let days = D.int(D.retentionDays)
        if it.sensitive, D.int(D.sensitiveMinutes) > 0 {
            return Date(timeIntervalSince1970: it.created + Double(D.int(D.sensitiveMinutes) * 60))
                .formatted(date: .omitted, time: .shortened)
        }
        guard days > 0 else { return "never" }
        return Date(timeIntervalSince1970: it.created + Double(days) * 86400)
            .formatted(date: .abbreviated, time: .omitted)
    }
}

struct Footer: View {
    var body: some View {
        // ponytail: ViewThatFits picks the richest hint set the window can actually show,
        // so the footer degrades on its own instead of needing a width breakpoint.
        ViewThatFits(in: .horizontal) {
            bar([("⏎","paste"),("⌘⏎","copy"),("⌥⏎","plain"),("⌘P","pin"),("⌘⌫","delete"),("⇥","preview")])
            bar([("⏎","paste"),("⌘⏎","copy"),("⌘P","pin"),("⌘⌫","delete")])
            bar([("⏎","paste"),("⌘P","pin"),("⌘⌫","delete")])
            bar([("⏎","paste"),("⌘P","pin")])
            bar([("⏎","paste")])
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    private func bar(_ keys: [(String, String)]) -> some View {
        HStack(spacing: 9) {
            ForEach(keys, id: \.0) { hint($0.0, $0.1) }
            Spacer(minLength: 6)
            Text("Klipvault").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func hint(_ k: String, _ t: String) -> some View {
        HStack(spacing: 3) {
            Text(k).font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
            Text(t).foregroundStyle(.secondary)
        }
    }
}

struct EmptyState: View {
    let query: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing copied yet" : "No matches for “\(query)”")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

enum Screenshot { static var active = false }

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        if Screenshot.active {
            let v = NSVisualEffectView()
            v.material = .windowBackground
            v.blendingMode = .withinWindow
            v.state = .active
            return v
        }
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
