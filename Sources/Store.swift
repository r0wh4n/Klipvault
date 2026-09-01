import AppKit
import SwiftUI
import Combine

/// The one object the UI observes. Owns the vault, the watcher and the current query.
final class AppState: ObservableObject {
    static let shared = AppState()

    let vault = Vault()
    lazy var watcher = Watcher(vault: vault)

    @Published var items: [ClipRecord] = []
    @Published var query: String = ""
    @Published var selected: Int = 0
    @Published var locked: Bool = true
    @Published var focusToken: Int = 0

    private var lastActiveApp: NSRunningApplication?
    private var idleTimer: Timer?

    // MARK: lifecycle

    func boot() {
        D.registerDefaults()
        if vault.usesPassphrase {
            locked = true
        } else if vault.unlockLocal() {
            finishUnlock()
        } else if vault.keyMissingForExistingHistory {
            locked = true
            reportOrphanedHistory()
        } else {
            locked = true
            let al = NSAlert()
            al.messageText = "Klipvault could not create its vault"
            al.informativeText = "The key file could not be written to \(vault.dir.path). Check that the folder is writable."
            al.runModal()
        }
        watcher.onCapture = { [weak self] rec in self?.record(rec) }
        watcher.start()
    }

    /// The key that encrypted the existing history is gone. Never silently start over —
    /// the old file is unreadable but it is still the user's data.
    private func reportOrphanedHistory() {
        let a = NSAlert()
        a.messageText = "Klipvault cannot read your history"
        a.informativeText = """
        The encryption key for this vault is missing, so the existing \
        history cannot be decrypted. This usually means key.local was deleted, or \
        only part of the vault folder was restored from a backup.

        You can start a new history — the old file is kept, renamed, in case the key turns up.
        """
        a.addButton(withTitle: "Start a New History")
        a.addButton(withTitle: "Quit")
        if a.runModal() == .alertFirstButtonReturn, vault.resetWithNewKey() {
            finishUnlock()
        } else {
            NSApp.terminate(nil)
        }
    }

    /// Try Touch ID first. Any failure — cancelled, no match, Keychain item gone after an
    /// app update — falls back to the passphrase field rather than blocking the user out.
    func unlockWithBiometrics(_ done: @escaping (Bool) -> Void) {
        guard vault.usesBiometrics else { done(false); return }
        Biometry.retrieve(reason: "unlock your Klipvault history") { [weak self] key in
            guard let self, let key else { done(false); return }
            self.vault.unlock(withKey: key)
            self.finishUnlock()
            done(true)
        }
    }

    func unlock(passphrase: String) -> Bool {
        guard vault.unlock(passphrase: passphrase) else { return false }
        finishUnlock()
        return true
    }

    private func finishUnlock() {
        vault.load()
        vault.purgeExpired(days: D.int(D.retentionDays),
                           keepPinnedForever: D.bool(D.keepPinnedForever),
                           sensitiveMinutes: D.int(D.sensitiveMinutes))
        items = vault.items
        locked = false
        scheduleIdleLock()
    }

    func lock() {
        vault.lock()
        items = []
        query = ""
        locked = true
    }

    func scheduleIdleLock() {
        idleTimer?.invalidate()
        let mins = D.int(D.autoLockMinutes)
        guard mins > 0, vault.usesPassphrase else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, !self.locked else { return }
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
            if idle > Double(mins * 60) { self.lock() }
        }
    }

    // MARK: capture

    private func record(_ rec: ClipRecord) {
        vault.insert(rec, dedupe: D.bool(D.dedupe), maxItems: D.int(D.maxItems))
        items = vault.items
        if D.bool(D.showRecentInMenuBar) { MenuBar.shared.refreshIcon() }
        if D.bool(D.playSound) { NSSound(named: "Tink")?.play() }
    }

    // MARK: search

    var filtered: [ClipRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let pinned = items.filter { $0.pinned }.sorted { ($0.pinKey ?? "~") < ($1.pinKey ?? "~") }
        let rest = items.filter { !$0.pinned }
        guard !q.isEmpty else { return pinned + rest }

        let mode = D.str(D.searchMode)
        let all = pinned + rest
        if mode == "regex" {
            guard let re = try? NSRegularExpression(pattern: q, options: [.caseInsensitive]) else { return [] }
            return all.filter { r in
                let s = r.haystack
                return re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) != nil
            }
        }
        if mode == "exact" { return all.filter { $0.haystack.contains(q) } }
        if mode == "contains" { return all.filter { $0.haystack.localizedCaseInsensitiveContains(q) } }
        // fuzzy: subsequence match, ranked by tightness then recency
        return all.compactMap { r -> (ClipRecord, Int)? in
            Self.fuzzyScore(needle: q, haystack: r.haystack).map { (r, $0 + (r.pinned ? 500 : 0)) }
        }
        .sorted { $0.1 == $1.1 ? $0.0.created > $1.0.created : $0.1 > $1.1 }
        .map { $0.0 }
    }

    /// Subsequence match. Higher = better: rewards consecutive hits and early matches.
    static func fuzzyScore(needle: String, haystack: String) -> Int? {
        let n = Array(needle.lowercased()), h = Array(haystack.lowercased().prefix(2000))
        guard !n.isEmpty else { return 0 }
        var score = 0, ni = 0, lastHit = -2
        for (hi, c) in h.enumerated() where ni < n.count {
            if c == n[ni] {
                score += (hi == lastHit + 1) ? 8 : 1
                if hi == 0 { score += 6 }
                lastHit = hi
                ni += 1
            }
        }
        guard ni == n.count else { return nil }
        return score - min(h.count / 40, 20)
    }

    // MARK: actions

    func rememberFrontApp() {
        let me = NSRunningApplication.current.processIdentifier
        if let f = NSWorkspace.shared.frontmostApplication, f.processIdentifier != me { lastActiveApp = f }
    }

    func use(_ rec: ClipRecord, paste: Bool, plain: Bool = false) {
        watcher.writeToPasteboard(rec, plain: plain || D.bool(D.stripFormatting))
        if D.bool(D.moveToTopOnUse) {
            vault.touch(rec.id)
            items = vault.items
        }
        guard paste else { return }
        let prev = lastActiveApp
        PanelController.shared.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            prev?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { Watcher.sendPaste() }
        }
    }

    func togglePin(_ rec: ClipRecord) {
        vault.update(rec.id) { r in
            r.pinned.toggle()
            r.pinKey = r.pinned ? self.nextPinKey() : nil
        }
        items = vault.items
    }

    func setPinKey(_ rec: ClipRecord, _ key: String?) {
        vault.update(rec.id) { r in r.pinKey = key; if key != nil { r.pinned = true } }
        items = vault.items
    }

    private func nextPinKey() -> String? {
        let used = Set(items.compactMap { $0.pinKey })
        for c in "123456789abcdefghijklmnopqrstuvwxyz" where !used.contains(String(c)) { return String(c) }
        return nil
    }

    func delete(_ rec: ClipRecord) {
        vault.delete(rec.id)
        items = vault.items
        selected = min(selected, max(0, filtered.count - 1))
    }

    func clearHistory(keepPinned: Bool = true) {
        if keepPinned {
            for r in vault.items where !r.pinned { vault.delete(r.id) }
        } else {
            vault.wipe()
        }
        items = vault.items
    }

    func fullImage(_ rec: ClipRecord) -> NSImage? {
        if let b = rec.blob, let d = vault.readBlob(b) { return NSImage(data: d) }
        if let t = rec.thumb { return NSImage(data: t) }
        return nil
    }
}

extension ClipRecord {
    var haystack: String { (text ?? "") + " " + title + " " + (appName ?? "") }

    var relativeTime: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: Date(timeIntervalSince1970: created), relativeTo: Date())
    }

    var glyph: String {
        switch kind {
        case .text: return sensitive ? "lock.shield" : "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }
}
