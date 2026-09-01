import Foundation
import AppKit

/// Every preference lives in UserDefaults under one key. Views bind with @AppStorage,
/// engine code reads the computed accessors below. One source of truth, no sync layer.
enum D {
    // General
    static let launchAtLogin = "launchAtLogin"
    static let pasteOnSelect = "pasteOnSelect"
    static let playSound = "playSound"
    static let moveToTopOnUse = "moveToTopOnUse"
    static let searchMode = "searchMode"                 // contains | fuzzy | regex | exact
    static let quickPasteModifier = "quickPasteModifier" // command | option | control
    // Storage
    static let retentionDays = "retentionDays"
    static let maxItems = "maxItems"
    static let keepPinnedForever = "keepPinnedForever"
    static let storeText = "storeText"
    static let storeImages = "storeImages"
    static let storeFiles = "storeFiles"
    static let maxImageMB = "maxImageMB"
    static let maxTextKB = "maxTextKB"
    // Appearance
    static let theme = "theme"                           // system | light | dark
    static let popupAt = "popupAt"                       // cursor | center | menubar | lastPosition
    static let imageHeight = "imageHeight"
    static let previewDelay = "previewDelay"
    static let highlightMatches = "highlightMatches"     // bold | underline | accent | none
    static let showMenuIcon = "showMenuIcon"
    static let menuIconStyle = "menuIconStyle"           // clipboard | scissors | vault | tray
    static let showAppIcons = "showAppIcons"
    static let showTimestamps = "showTimestamps"
    static let showFooter = "showFooter"
    static let showPreviewPane = "showPreviewPane"
    static let popupWidth = "popupWidth"
    static let rowsVisible = "rowsVisible"
    static let fontSize = "fontSize"
    static let showRecentInMenuBar = "showRecentInMenuBar"
    static let compactRows = "compactRows"
    // Ignore
    static let ignoredApps = "ignoredApps"               // newline separated bundle ids
    static let ignoreRegexes = "ignoreRegexes"           // newline separated
    static let ignoreTransient = "ignoreTransient"
    static let ignoreConfidential = "ignoreConfidential"
    static let minLength = "minLength"
    static let maxLength = "maxLength"
    static let ignoreOnlyWhitespace = "ignoreOnlyWhitespace"
    // Security
    static let autoLockMinutes = "autoLockMinutes"
    static let lockOnSleep = "lockOnSleep"
    static let lockOnScreensaver = "lockOnScreensaver"
    static let detectSecrets = "detectSecrets"
    static let sensitiveMinutes = "sensitiveMinutes"
    static let maskSensitive = "maskSensitive"
    static let clearSystemClipboardOnQuit = "clearSystemClipboardOnQuit"
    // Advanced
    static let pollInterval = "pollInterval"
    static let dedupe = "dedupe"
    static let stripFormatting = "stripFormatting"
    static let previewLines = "previewLines"
    static let firstRunDone = "firstRunDone"
    // Hotkeys (stored as "keyCode,modifierFlagsRaw")
    static let hkPopup = "hk.popup"
    static let hkPasteLast = "hk.pasteLast"
    static let hkPasteLastPlain = "hk.pasteLastPlain"
    static let hkClear = "hk.clear"
    static let hkLock = "hk.lock"
    static let hkPanic = "hk.panic"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            launchAtLogin: false, pasteOnSelect: true, playSound: false, moveToTopOnUse: true,
            searchMode: "fuzzy", quickPasteModifier: "command",
            retentionDays: 15, maxItems: 0, keepPinnedForever: true,
            storeText: true, storeImages: true, storeFiles: true, maxImageMB: 32, maxTextKB: 2048,
            theme: "system", popupAt: "cursor", imageHeight: 40.0, previewDelay: 700.0,
            highlightMatches: "bold", showMenuIcon: true, menuIconStyle: "vault",
            showAppIcons: true, showTimestamps: true, showFooter: true, showPreviewPane: false,
            popupWidth: 340.0,
            rowsVisible: 10, fontSize: 13.0, showRecentInMenuBar: false, compactRows: false,
            ignoredApps: "", ignoreRegexes: "", ignoreTransient: true, ignoreConfidential: true,
            minLength: 1, maxLength: 0, ignoreOnlyWhitespace: true,
            autoLockMinutes: 0, lockOnSleep: false, lockOnScreensaver: false,
            detectSecrets: true, sensitiveMinutes: 0, maskSensitive: true,
            clearSystemClipboardOnQuit: false,
            pollInterval: 0.35, dedupe: true, stripFormatting: false, previewLines: 12,
            firstRunDone: false,
            hkPopup: "9,1179648",       // ⌘⇧V
            hkPasteLast: "", hkPasteLastPlain: "", hkClear: "", hkLock: "", hkPanic: ""
        ])
    }

    private static let u = UserDefaults.standard
    static func str(_ k: String) -> String { u.string(forKey: k) ?? "" }
    static func int(_ k: String) -> Int { u.integer(forKey: k) }
    static func dbl(_ k: String) -> Double { u.double(forKey: k) }
    static func bool(_ k: String) -> Bool { u.bool(forKey: k) }
    static func set(_ k: String, _ v: Any) { u.set(v, forKey: k) }

    static var lines: (String) -> [String] = { k in
        str(k).split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func resetAll() {
        for (k, _) in u.dictionaryRepresentation() where k.hasPrefix("hk.") || allKeys.contains(k) {
            u.removeObject(forKey: k)
        }
        registerDefaults()
    }

    static let allKeys: Set<String> = [
        launchAtLogin, pasteOnSelect, playSound, moveToTopOnUse, searchMode, quickPasteModifier,
        retentionDays, maxItems, keepPinnedForever, storeText, storeImages, storeFiles, maxImageMB, maxTextKB,
        theme, popupAt, imageHeight, previewDelay, highlightMatches, showMenuIcon, menuIconStyle,
        showAppIcons, showTimestamps, showFooter, showPreviewPane, popupWidth, rowsVisible, fontSize,
        showRecentInMenuBar, compactRows,
        ignoredApps, ignoreRegexes, ignoreTransient, ignoreConfidential, minLength, maxLength,
        ignoreOnlyWhitespace, autoLockMinutes, lockOnSleep, lockOnScreensaver, detectSecrets,
        sensitiveMinutes, maskSensitive, clearSystemClipboardOnQuit,
        pollInterval, dedupe, stripFormatting, previewLines
    ]
}

// MARK: - Secret detection

/// Cheap, high-signal patterns. A hit only changes how the item is *displayed* and how
/// long it lives — the content is encrypted either way.
enum SecretScanner {
    static let patterns: [(String, NSRegularExpression)] = {
        let raw: [(String, String)] = [
            ("AWS access key", #"\bAKIA[0-9A-Z]{16}\b"#),
            ("AWS secret", #"(?i)aws(.{0,20})?(secret|private).{0,20}['\"][0-9a-zA-Z/+]{40}['\"]"#),
            ("GitHub token", #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#),
            ("Slack token", #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#),
            ("Google API key", #"\bAIza[0-9A-Za-z_\-]{35}\b"#),
            ("Stripe key", #"\b[sr]k_(live|test)_[0-9a-zA-Z]{16,}\b"#),
            ("OpenAI/Anthropic key", #"\b(sk-ant-|sk-proj-|sk-)[A-Za-z0-9_\-]{20,}\b"#),
            ("JWT", #"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b"#),
            ("Private key block", #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#),
            ("Bearer token", #"(?i)\bbearer\s+[A-Za-z0-9_\-\.=]{20,}"#),
            ("Password assignment", #"(?i)\b(password|passwd|pwd|secret|api[_\-]?key|token)\b\s*[:=]\s*\S{6,}"#),
            ("Card number", #"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b"#),
            ("Connection string", #"(?i)\b(postgres|postgresql|mysql|mongodb(\+srv)?|redis|amqp)://[^\s:]+:[^\s@]+@"#),
        ]
        return raw.compactMap { name, p in
            (try? NSRegularExpression(pattern: p)).map { (name, $0) }
        }
    }()

    static func match(_ s: String) -> String? {
        guard s.count < 100_000 else { return nil }   // ponytail: don't regex a novel
        let r = NSRange(s.startIndex..., in: s)
        for (name, re) in patterns where re.firstMatch(in: s, options: [], range: r) != nil { return name }
        return nil
    }
}
