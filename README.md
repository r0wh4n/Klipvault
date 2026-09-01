<div align="center">

# Klipvault

**Every copy, sealed.**

A macOS clipboard manager that lives in your menu bar, remembers everything you copy for as long as you tell it to, and encrypts all of it with AES-256 before a single byte reaches your disk.

`⌘⇧V` · text, images and files · 15-day memory · pins · zero network code

</div>

---

## Why this exists

Clipboard managers are the most-used, least-examined tool on a developer's Mac. You paste API keys, database URLs, one-time codes, customer emails, and half-finished paragraphs through them all day. Then you go look at where that history is stored, and it's a plain SQLite file or a plain plist sitting in your Library folder — readable by anything, backed up to iCloud, synced to Time Machine, and restored onto whatever machine you set up next.

Klipvault starts from the opposite end. The history file is encrypted first, and everything else is built on top of that. Copy something today and read it back in two weeks; hand someone the file and they get 227 kilobytes of noise.

```
$ xxd ~/Library/Application\ Support/Klipvault/history.vault | head -2
00000000: 434c 5056 3100 0001 a2cf 4379 897f d13f  CLPV1.....Cy...?
00000010: 5f37 e258 7860 7b32 f059 760d ae79 44ba  _7.Xx`{2.Yv..yD.
```

That's the whole product philosophy in one hexdump.

---

## How Klipvault compares to Maccy

[Maccy](https://github.com/p0deje/Maccy) is an excellent, well-loved app and the reason this one exists — it set the bar for what a lightweight Mac clipboard manager should feel like. Klipvault keeps that shape and rebuilds the parts that matter most when your clipboard holds credentials.

| | **Klipvault** | Maccy |
|---|---|---|
| **History encrypted at rest** | **AES-256-GCM, always on, no configuration** | Plain Core Data store |
| **Passphrase protection** | **Optional — key derived with 310,000 rounds of PBKDF2 and stored nowhere** | — |
| **Lock the vault** | **On idle, on sleep, on screen lock, or on a hotkey** | — |
| **Secret detection** | **13 patterns — AWS, GitHub, Slack, Stripe, Google, OpenAI/Anthropic, JWTs, PEM blocks, bearer tokens, DB connection strings, cards — flagged, masked in the list, optionally auto-expired in minutes** | — |
| **Panic wipe** | **One hotkey erases the vault and the system clipboard** | — |
| **Retention** | **By age (15 days by default) *and* by count, with pins exempt** | By count |
| **Per-item expiry, visible** | **Every item shows the date it will be deleted** | — |
| **Pins** | Yes — with a one-key shortcut each, and never expire | Yes |
| **Preview pane** | **Live pane with source app, size, dimensions, use count and expiry** | Hover popover |
| **Search** | **Fuzzy, contains, exact, or regex — switchable** | Fuzzy/exact |
| **Images** | **Stored as separate encrypted blobs, thumbnail inline — a 4K screenshot doesn't bloat the index or your RAM** | Inline |
| **Files** | Yes, with Finder icons | Yes |
| **Ignore rules** | **By app, by regex, by length, plus transient/password-manager markers** | By app, by regex |
| **Quick paste** | **⌘1–9 for rows, ⌘+letter for pins** | ⌘1–9 |
| **Preference tabs** | **7 — General, Storage, Appearance, Pins, Ignore, Security, Advanced** | 6 |
| **Diagnostics** | **`--probe` tells you exactly why a copy was or wasn't kept** | — |
| **Dependencies** | **None. Apple frameworks only** | Sparkle, KeyboardShortcuts, Settings |
| **Build** | **One `./build.sh`, no Xcode project, no package manager** | Xcode + SPM |
| **Network code** | **None. There is no URLSession in this codebase** | Sparkle update checks |

**Where Maccy is still ahead, honestly:** it's notarized, it ships through Homebrew and the App Store, it auto-updates, it's been hammered on by thousands of users for years, and it's translated into a dozen languages. Klipvault is version 1.0 of a single-developer app you build yourself. Pick accordingly.

---

## Features

### It remembers, safely
- **AES-256-GCM authenticated encryption** on every record and every image, always — there is no "off" switch, because a switch is something you forget to flip.
- **15-day memory by default.** Set it to 30, to 365, or to *forever*. Set a maximum item count too, or leave it unlimited.
- **Pins never expire.** Pin your standup link, your SSH one-liner, your address. Give each one a letter and paste it with `⌘` + that letter from anywhere.
- **Expiry is visible.** Select any item and the preview pane tells you the exact date it disappears.

### It knows what a secret looks like
Klipvault scans every copied string against 13 high-signal patterns — AWS access keys, GitHub and Slack tokens, Stripe and Google keys, OpenAI/Anthropic keys, JWTs, PEM private-key blocks, bearer tokens, database connection strings, and credit-card numbers.

A match gets a 🔒 in the list instead of its contents, and can be set to self-destruct after a few minutes while everything else keeps its normal 15 days. The content is encrypted either way — this is about what's readable over your shoulder in a meeting.

### It locks
- **Add a passphrase** and the encryption key stops existing on your Mac entirely. It's derived from your passphrase, 310,000 PBKDF2 rounds each time, and held only in memory.
- Klipvault will **suggest a six-word passphrase** — roughly 77 bits of entropy and actually memorable — or take one of your own.
- **Auto-lock** after idle minutes, when the Mac sleeps, or when the screen locks.
- **Panic wipe:** bind a hotkey that erases the entire vault and the system clipboard, instantly, no confirmation. It has no default binding, so it only exists once you deliberately create it.

### It's fast to drive
- `⌘⇧V` anywhere. Type to filter. `↑↓` or `⌃N`/`⌃P` to move. `⏎` to paste.
- `⌘⏎` copies without pasting · `⌥⏎` pastes as plain text · `⌘P` pins · `⌘⌫` deletes · `⇥` toggles the preview pane · `⎋` clears the search, then closes.
- `⌘1`–`⌘9` paste that row directly. `⌘`+a pin's letter pastes it without even looking.
- Every shortcut is rebindable, including six global ones: open, paste-last, paste-last-as-plain-text, clear, lock, and panic wipe.

### It handles everything you copy
- **Text** with its rich formatting preserved — or stripped on demand, per paste or globally.
- **Images** stored as individually encrypted blobs, with a small thumbnail in the index. Copy a 4K screenshot and the list stays instant.
- **Files and folders**, with their real Finder icons, re-copied as proper file references so Finder pastes them as files.

### It stays out of the way
- **Menu bar only.** No Dock icon, no main window, no splash screen. `LSUIElement`, as intended.
- Left-click the icon for the popup, right-click for a menu with your pins and recents.
- Four menu-bar icon styles, an optional "most recent copy" label next to it, or hide the icon entirely and live on the hotkey.

### It respects other people's secrets too
Klipvault honours `org.nspasteboard.TransientType` and `ConcealedType`, and the private markers used by 1Password, KeePass and friends. When your password manager says "don't remember this," it doesn't.

You can also ignore specific apps by bundle ID, ignore anything matching your own regexes, and set minimum and maximum lengths.

---

## Install

```bash
git clone https://github.com/r0wh4n/Klipvault.git
cd Klipvault
./install.sh
```

That is the whole installation. `install.sh` checks your macOS version, offers to fetch the Command Line Tools if they're missing, builds, replaces any running copy, installs to `/Applications`, clears the quarantine flag, and launches it — about ten seconds on an Apple Silicon Mac.

Changed your mind? `./install.sh --uninstall` removes the app and asks — separately, and only once — whether to delete your encrypted history too.

Requires macOS 14 or later. Nothing else: no Homebrew, no CocoaPods, no Swift Package Manager, no Xcode project, no account. `build.sh` calls `swiftc` on eight source files, draws its own icon, assembles the bundle, ad-hoc signs it, and runs the test suite. You can run it on its own if you just want the `.app` without installing.

On first launch Klipvault offers to open **System Settings → Privacy & Security → Accessibility**. Grant it there and Klipvault can press `⌘V` for you. Decline and everything still works — selecting an item puts it on the clipboard and you paste it yourself.

To start it at login, tick **Launch at login** in the General tab. That is the only other thing worth configuring; the encryption and the 15-day memory are already on.

---

## Keyboard reference

**Global** — works anywhere on the system

| | |
|---|---|
| `⌘⇧V` | Open Klipvault |
| *(unbound)* | Paste last copied item |
| *(unbound)* | Paste last item as plain text |
| *(unbound)* | Clear history |
| *(unbound)* | Lock the vault |
| *(unbound)* | Panic wipe |

**In the popup**

| | |
|---|---|
| type | Filter |
| `↑` `↓` / `⌃P` `⌃N` | Move |
| `⇞` `⇟` `↖` `↘` | Page and jump |
| `⏎` | Paste |
| `⌘⏎` | Copy without pasting |
| `⌥⏎` | Paste as plain text |
| `⌘1`–`⌘9` | Paste that row |
| `⌘` + pin letter | Paste that pin |
| `⌘P` | Pin / unpin |
| `⌘⌫` | Delete item |
| `⌘K` | Clear the search |
| `⇥` | Toggle the preview pane |
| `⌘,` | Preferences |
| `⎋` | Clear search, then close |

---

## Preferences

**General** — six rebindable global hotkeys, the quick-paste modifier, launch at login, paste-on-select, move-to-top-on-reuse, capture sound, and the search mode (fuzzy, contains, exact, regex).

**Storage** — retention in days, maximum items, pins-never-expire, which types to capture, size caps for images and text, live vault statistics, compact-now, encrypted or plain export, import, clear, and erase.

**Appearance** — theme, popup position (cursor, centre, menu bar, or where you left it), visible rows, compact mode, image height, text size, preview delay, match-highlight style, app icons, timestamps, menu-bar icon style, recent-copy label, preview pane, and footer.

**Pins** — every pinned item with an editable one-key shortcut, and an unpin button.

**Ignore** — ignored apps (with an app picker), ignore regexes, transient and password-manager markers, whitespace-only copies, and length bounds.

**Security** — what's encrypting your data and where the key lives, set/change/remove passphrase with a generated suggestion, idle/sleep/screen-lock auto-locking, clear-system-clipboard-on-quit, the full secret-detection panel, and your Accessibility permission status.

**Advanced** — clipboard poll interval, duplicate collapsing, always-paste-plain, preview line limit, open the data folder, restart capture, and reset every preference (never touches your history).

---

## The security model, stated plainly

Security claims are worth exactly as much as their threat model, so here is Klipvault's, without marketing.

**Where your data lives**

```
~/Library/Application Support/Klipvault/     (0700)
├── history.vault      (0600)  encrypted append-only log, one sealed record per entry
├── key.local          (0600)  the 256-bit key — default mode only
├── key.wrapped                the key encrypted under your passphrase — passphrase mode only
└── blobs/             (0700)
    └── <uuid>.bin     (0600)  one encrypted image each
```

**Default mode.** A random 256-bit key is generated on first run and written to `key.local` with `0600` permissions. Every record and every image is sealed with AES-256-GCM before it's written.

*This protects you against:* the history file being copied, synced to a cloud folder, pulled out of a Time Machine backup, recovered from a drive you sold, or read by another account on the machine. Any of those yield ciphertext.

*This does not protect you against:* anything already running as you. A process with your file permissions can read `key.local` next to `history.vault`. That is an honest limitation of any zero-friction design — the key has to be somewhere.

**Passphrase mode.** Turn it on in Security and the key is re-derived from your passphrase with 310,000 rounds of PBKDF2-HMAC-SHA256 and a random 16-byte salt, then `key.local` is deleted. Only a wrapped copy remains, useless without the passphrase, alongside a small verifier so a wrong passphrase fails instantly instead of producing garbage.

*Now:* full-disk access isn't enough. Neither is your unlocked laptop, if the vault is locked. There is no recovery, no backdoor, no reset link. Lose the passphrase and the history is gone — that is the feature, not a bug. **Write it down somewhere physical before you enable it.**

**What Klipvault never does**

- No network requests. There is no `URLSession`, no analytics, no crash reporting, no update check. Point Little Snitch at it and watch nothing happen.
- No account, no cloud, no sync.
- No third-party dependencies — nothing to audit but Apple's frameworks and these 2,700 lines.
- No plaintext temp files. Images go straight from the pasteboard into a sealed blob.

**Known limitations, up front**

- The app is ad-hoc signed, not notarized. Gatekeeper will need a right-click → Open the first time, or a `xattr -d com.apple.quarantine` if you moved it around.
- Auto-paste needs Accessibility permission. Without it you paste manually.
- Deleting an item rewrites the log. That's `O(history)` — fine at any human clipboard volume, and the hot path (copying) is a pure append, but it is a real ceiling and it's marked as such in the source.
- Encryption protects data at rest. It does not protect a clipboard that is, by design, being read and written by every app you use.

---

## Verifying it does what this README says

The shipped binary carries its own test suite. It isn't a mock — it builds a real vault in a temp directory, encrypts real records, and checks the bytes on disk.

```
$ ./Klipvault.app/Contents/MacOS/Klipvault --selftest
  ok   wrong passphrase is rejected
  ok   correct passphrase unlocks
  ok   history file was written
  ok   no plaintext on disk
  ok   2 records reloaded (got 2)
  ok   record content survives a reload
  ok   duplicate collapsed (got 2)
  ok   retention dropped exactly the unpinned old item (dropped 1)
  ok   pinned item survived retention
  ok   maxItems capped unpinned history
  ok   blob round-trips
  ok   blob is encrypted at rest
  ok   locked vault reads nothing
  ok   detects AWS key
  ok   detects GitHub token
  ok   detects private key block
  ok   leaves ordinary prose alone
  ok   fuzzy matches a subsequence
  ok   fuzzy rejects a non-match
  ok   fuzzy ranks consecutive matches higher
  ok   hotkey round-trips
  ok   hotkey renders as ⇧⌘V (got ⇧⌘V)
selftest: all checks passed
```

Two of those are the ones that matter: **no plaintext on disk** greps the raw `history.vault` bytes for a secret string that was just copied, and **blob is encrypted at rest** does the same for an image. If encryption ever silently broke, the build would fail.

Klipvault also ships two diagnostics, because "it didn't save my copy" should never be a mystery:

```
$ Klipvault --probe        # what would it do with the clipboard right now, and why
$ Klipvault --test-ui      # build the popup and preferences for real, confirm they render
```

---

## How it's built

Eight Swift files, ~2,700 lines, no dependencies.

| | |
|---|---|
| `Vault.swift` | Encryption, key management, the append-only log, the blob store, retention |
| `Watcher.swift` | Pasteboard polling, capture rules, writing back, sending `⌘V` |
| `Store.swift` | The observable app state, search and ranking, item actions |
| `Panel.swift` | The popup window, keyboard handling, list, preview pane |
| `Prefs.swift` | All seven preference tabs, the hotkey recorder, backup, passphrase generation |
| `Settings.swift` | Every preference key and default, and the secret scanner |
| `Hotkey.swift` | Carbon global hotkeys — they work without Accessibility permission and can't be swallowed by the focused app |
| `main.swift` | Menu bar, unlock window, app delegate, self-test, icon generation |

Plus `build.sh` (compile and bundle) and `install.sh` (build, install, launch, uninstall).

**The storage format** is deliberately dull: a five-byte magic header, then repeating `[4-byte big-endian length][AES-GCM sealed box]` frames. Copying appends one frame — the cheapest possible hot path. Deleting or pinning rewrites the file. Images never enter the log; they get their own sealed file, with a 256-pixel thumbnail inline so the list renders instantly without touching them.

---

## FAQ

**Does it sync between Macs?**
No, and it won't. Sync means a server or a shared folder, and both undermine the point. Copy the vault folder yourself if you want it elsewhere — with a passphrase set, it's safe to put in Dropbox.

**What if I forget my passphrase?**
The history is unrecoverable. There is no key escrow and no reset. If that's too much risk, don't enable passphrase mode — the default already protects the file itself.

**Will it slow down my Mac?**
It polls the pasteboard every 0.35s (adjustable from 0.1 to 2.0) and does nothing at all unless the change counter moved. Encrypting a copied paragraph takes microseconds.

**Can I get my data out?**
Yes, two ways: an encrypted backup, or a plain JSON export that warns you it's plain before writing it.

**Why not a database?**
A database would need a dependency or Core Data, and would store your clipboard in a format designed to be readable. An encrypted append-only log is fewer moving parts and stronger by default. If it ever becomes the bottleneck, the source says exactly where.

**Is it really zero-network?**
`grep -r URLSession Sources/` returns nothing. Check it yourself — that's the point of shipping 2,700 readable lines.

---

## License

MIT. Take it, fork it, ship it.

Klipvault owes its shape to [Maccy](https://github.com/p0deje/Maccy) by Alex Rodionov — an excellent app that has served a lot of people well for a long time.
