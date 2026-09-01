import Foundation
import CryptoKit
import CommonCrypto
import Security

// MARK: - Key derivation

enum KDF {
    static let defaultIterations = 310_000

    static func derive(passphrase: String, salt: Data, iterations: Int) -> SymmetricKey {
        var out = [UInt8](repeating: 0, count: 32)
        let pass = Array(passphrase.utf8)
        _ = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                 pass, pass.count,
                                 saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                 UInt32(iterations),
                                 &out, out.count)
        }
        return SymmetricKey(data: Data(out))
    }

    static func randomSalt(_ n: Int = 16) -> Data {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return Data(b)
    }
}

/// Master key wrapped by a passphrase-derived KEK. Stored next to the history so
/// the history file and its key are both useless without the passphrase.
struct WrappedKey: Codable {
    var salt: Data
    var iterations: Int
    var blob: Data          // AES-GCM(masterKey) under KEK
    var verifier: Data      // AES-GCM("klipvault") under KEK — lets us check a passphrase cheaply
}

// MARK: - Crypto helpers

enum Crypt {
    static func seal(_ data: Data, _ key: SymmetricKey) throws -> Data {
        guard let c = try AES.GCM.seal(data, using: key).combined else { throw VaultError.crypto }
        return c
    }
    static func open(_ data: Data, _ key: SymmetricKey) throws -> Data {
        try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
    }
}

enum VaultError: Error { case crypto, locked, badPassphrase, corrupt }

// MARK: - Record

enum ClipKind: String, Codable { case text, image, files }

struct ClipRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: ClipKind = .text
    var created: Double = Date().timeIntervalSince1970
    var lastUsed: Double = Date().timeIntervalSince1970
    var uses: Int = 0
    var title: String = ""          // one-line display string
    var text: String? = nil         // plain text, or newline-joined file paths
    var rtf: Data? = nil            // rich text flavour, if any
    var html: Data? = nil
    var blob: String? = nil         // full image lives in blobs/<blob>.bin (encrypted)
    var thumb: Data? = nil          // small PNG preview, inline
    var pixelW: Int = 0
    var pixelH: Int = 0
    var bytes: Int = 0
    var appBundle: String? = nil
    var appName: String? = nil
    var pinned: Bool = false
    var pinKey: String? = nil       // "1"..."9", "a"..."z"
    var sensitive: Bool = false     // matched a secret pattern -> masked + short TTL
    var hash: String = ""           // dedupe key

    static func == (a: ClipRecord, b: ClipRecord) -> Bool { a.id == b.id }
}

// MARK: - Vault (encrypted append-only log + encrypted blob store)

final class Vault {
    static let magic = Data("CLPV1".utf8)

    let dir: URL
    private(set) var items: [ClipRecord] = []
    private var key: SymmetricKey?

    var isLocked: Bool { key == nil }
    var historyURL: URL { dir.appendingPathComponent("history.vault") }
    var wrappedKeyURL: URL { dir.appendingPathComponent("key.wrapped") }
    var keyFileURL: URL { dir.appendingPathComponent("key.local") }
    var blobsURL: URL { dir.appendingPathComponent("blobs") }
    var usesPassphrase: Bool { FileManager.default.fileExists(atPath: wrappedKeyURL.path) }

    init(dir: URL? = nil) {
        self.dir = dir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klipvault")
        try? FileManager.default.createDirectory(at: self.dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    // MARK: unlock / key lifecycle

    /// Default mode: a random 256-bit key in a 0600 file beside the vault. Nothing to
    /// remember, survives app updates, and the history file on its own stays unreadable.
    /// Add a passphrase to get the key off the disk entirely.
    @discardableResult
    func unlockLocal() -> Bool {
        if usesPassphrase { return false }
        if let d = try? Data(contentsOf: keyFileURL), d.count == 32 {
            key = SymmetricKey(data: d); return true
        }
        // No key, but a history file exists: minting a fresh key here would append records
        // the old ones can never be read beside, silently orphaning everything already
        // stored. Refuse, and let the caller explain the situation.
        if FileManager.default.fileExists(atPath: historyURL.path) {
            keyMissingForExistingHistory = true
            return false
        }
        let fresh = SymmetricKey(size: .bits256)
        guard writeKeyFile(fresh) else { return false }
        key = fresh
        return true
    }

    @discardableResult
    private func writeKeyFile(_ k: SymmetricKey) -> Bool {
        do {
            try k.withUnsafeBytes { Data($0) }.write(to: keyFileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
            return true
        } catch { return false }
    }

    /// Set when the key that encrypted an existing history is gone — the key file was
    /// deleted, or only part of the vault folder was restored from a backup.
    private(set) var keyMissingForExistingHistory = false

    /// Explicit, user-confirmed recovery: archive the unreadable history and start clean.
    func resetWithNewKey() -> Bool {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? FileManager.default.moveItem(at: historyURL,
                                          to: dir.appendingPathComponent("history.unreadable-\(stamp).vault"))
        keyMissingForExistingHistory = false
        return unlockLocal()
    }

    @discardableResult
    func unlock(passphrase: String) -> Bool {
        guard let d = try? Data(contentsOf: wrappedKeyURL),
              let w = try? JSONDecoder().decode(WrappedKey.self, from: d) else { return false }
        let kek = KDF.derive(passphrase: passphrase, salt: w.salt, iterations: w.iterations)
        guard let v = try? Crypt.open(w.verifier, kek), String(data: v, encoding: .utf8) == "klipvault",
              let mk = try? Crypt.open(w.blob, kek), mk.count == 32 else { return false }
        key = SymmetricKey(data: mk)
        return true
    }

    func lock() { key = nil; items = [] }

    /// Test hook: unlock with a throwaway key so the self-test never touches a real vault.
    func unlockEphemeral() { key = SymmetricKey(size: .bits256) }

    /// Turn on passphrase protection. Master key is unchanged, so history stays readable.
    func setPassphrase(_ pass: String) throws {
        guard let k = key else { throw VaultError.locked }
        let salt = KDF.randomSalt()
        let kek = KDF.derive(passphrase: pass, salt: salt, iterations: KDF.defaultIterations)
        let w = WrappedKey(salt: salt, iterations: KDF.defaultIterations,
                           blob: try Crypt.seal(k.withUnsafeBytes { Data($0) }, kek),
                           verifier: try Crypt.seal(Data("klipvault".utf8), kek))
        try JSONEncoder().encode(w).write(to: wrappedKeyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: wrappedKeyURL.path)
        try? FileManager.default.removeItem(at: keyFileURL)   // the key now exists only in your head
    }

    /// Back to keychain mode (convenience over paranoia).
    func removePassphrase() throws {
        guard let k = key else { throw VaultError.locked }
        guard writeKeyFile(k) else { throw VaultError.crypto }
        try? FileManager.default.removeItem(at: wrappedKeyURL)
    }

    // MARK: log I/O

    func load() {
        guard let k = key else { return }
        items = []
        guard let fh = try? FileHandle(forReadingFrom: historyURL) else { return }
        defer { try? fh.close() }
        guard let head = try? fh.read(upToCount: 5), head == Vault.magic else { return }
        var out: [ClipRecord] = []
        while let lenD = try? fh.read(upToCount: 4), lenD.count == 4 {
            let len = lenD.withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).bigEndian) }
            guard len > 0, len < 64 << 20, let body = try? fh.read(upToCount: len), body.count == len else { break }
            guard let plain = try? Crypt.open(body, k),
                  let rec = try? JSONDecoder().decode(ClipRecord.self, from: plain) else { continue }
            out.append(rec)
        }
        items = out.sorted { $0.lastUsed > $1.lastUsed }
    }

    private func appendToLog(_ rec: ClipRecord) {
        guard let k = key else { return }
        guard let plain = try? JSONEncoder().encode(rec), let sealed = try? Crypt.seal(plain, k) else { return }
        var frame = Data()
        withUnsafeBytes(of: UInt32(sealed.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(sealed)
        let fm = FileManager.default
        if !fm.fileExists(atPath: historyURL.path) {
            try? (Vault.magic + frame).write(to: historyURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
            return
        }
        if let fh = try? FileHandle(forWritingTo: historyURL) {
            defer { try? fh.close() }
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: frame)
        }
    }

    /// ponytail: full rewrite on delete/pin/purge. O(history) but those are user-paced,
    /// while the hot path (a copy) is a pure append. Move to a real DB only if this
    /// ever shows up in a profile.
    func rewrite() {
        guard let k = key else { return }
        var data = Vault.magic
        for rec in items {
            guard let plain = try? JSONEncoder().encode(rec), let sealed = try? Crypt.seal(plain, k) else { continue }
            withUnsafeBytes(of: UInt32(sealed.count).bigEndian) { data.append(contentsOf: $0) }
            data.append(sealed)
        }
        try? data.write(to: historyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }

    // MARK: blobs

    func writeBlob(_ data: Data) -> String? {
        guard let k = key, let sealed = try? Crypt.seal(data, k) else { return nil }
        let name = UUID().uuidString
        let url = blobsURL.appendingPathComponent(name + ".bin")
        do {
            try sealed.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    func readBlob(_ name: String) -> Data? {
        guard let k = key,
              let d = try? Data(contentsOf: blobsURL.appendingPathComponent(name + ".bin")) else { return nil }
        return try? Crypt.open(d, k)
    }

    private func deleteBlob(_ name: String?) {
        guard let n = name else { return }
        try? FileManager.default.removeItem(at: blobsURL.appendingPathComponent(n + ".bin"))
    }

    // MARK: mutations

    func insert(_ rec: ClipRecord, dedupe: Bool, maxItems: Int) {
        var rec = rec
        if dedupe, let dup = items.first(where: { $0.hash == rec.hash && !$0.hash.isEmpty }) {
            // Same content copied again: bump it instead of growing the history.
            deleteBlob(rec.blob)
            var moved = dup
            moved.lastUsed = Date().timeIntervalSince1970
            moved.uses += 1
            items.removeAll { $0.id == dup.id }
            items.insert(moved, at: 0)
            rewrite()
            return
        }
        rec.pinned = false
        items.insert(rec, at: 0)
        appendToLog(rec)
        if maxItems > 0 {
            let unpinned = items.filter { !$0.pinned }
            if unpinned.count > maxItems {
                let doomed = Set(unpinned.suffix(unpinned.count - maxItems).map { $0.id })
                for it in items where doomed.contains(it.id) { deleteBlob(it.blob) }
                items.removeAll { doomed.contains($0.id) }
                rewrite()
            }
        }
    }

    func delete(_ id: UUID) {
        if let it = items.first(where: { $0.id == id }) { deleteBlob(it.blob) }
        items.removeAll { $0.id == id }
        rewrite()
    }

    func update(_ id: UUID, _ mutate: (inout ClipRecord) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[i])
        rewrite()
    }

    func touch(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var r = items.remove(at: i)
        r.lastUsed = Date().timeIntervalSince1970
        r.uses += 1
        items.insert(r, at: 0)
        rewrite()
    }

    /// Retention sweep. Pinned items are exempt when `keepPinnedForever`.
    @discardableResult
    func purgeExpired(days: Int, keepPinnedForever: Bool, sensitiveMinutes: Int) -> Int {
        let now = Date().timeIntervalSince1970
        let cutoff = now - Double(days) * 86400
        let sensCutoff = now - Double(sensitiveMinutes) * 60
        let doomed = items.filter { r in
            if r.pinned && keepPinnedForever { return false }
            if r.sensitive && sensitiveMinutes > 0 && r.created < sensCutoff { return true }
            return days > 0 && r.created < cutoff
        }
        guard !doomed.isEmpty else { return 0 }
        for r in doomed { deleteBlob(r.blob) }
        let ids = Set(doomed.map { $0.id })
        items.removeAll { ids.contains($0.id) }
        rewrite()
        return doomed.count
    }

    func wipe() {
        for r in items { deleteBlob(r.blob) }
        items = []
        try? FileManager.default.removeItem(at: historyURL)
        try? FileManager.default.removeItem(at: blobsURL)
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    var diskBytes: Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey]
        if let s = try? historyURL.resourceValues(forKeys: Set(keys)).fileSize { total += Int64(s) }
        if let e = FileManager.default.enumerator(at: blobsURL, includingPropertiesForKeys: keys) {
            for case let u as URL in e { total += Int64((try? u.resourceValues(forKeys: Set(keys)).fileSize) ?? 0) }
        }
        return total
    }
}
