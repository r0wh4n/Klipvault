import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon. Deliberately not NSEvent global monitors: Carbon hotkeys
/// work without Accessibility permission and cannot be swallowed by the focused app.
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    struct Combo: Equatable {
        var keyCode: UInt16
        var flags: NSEvent.ModifierFlags

        var isEmpty: Bool { keyCode == 0 && flags.isEmpty }
        var stored: String { "\(keyCode),\(flags.intersection(.deviceIndependentFlagsMask).rawValue)" }

        static func parse(_ s: String) -> Combo? {
            let p = s.split(separator: ",")
            guard p.count == 2, let k = UInt16(p[0]), let f = UInt(p[1]), f != 0 else { return nil }
            return Combo(keyCode: k, flags: NSEvent.ModifierFlags(rawValue: f))
        }

        var display: String {
            var s = ""
            if flags.contains(.control) { s += "⌃" }
            if flags.contains(.option) { s += "⌥" }
            if flags.contains(.shift) { s += "⇧" }
            if flags.contains(.command) { s += "⌘" }
            return s + Combo.keyName(keyCode)
        }

        var carbonMods: UInt32 {
            var m: UInt32 = 0
            if flags.contains(.command) { m |= UInt32(cmdKey) }
            if flags.contains(.shift)   { m |= UInt32(shiftKey) }
            if flags.contains(.option)  { m |= UInt32(optionKey) }
            if flags.contains(.control) { m |= UInt32(controlKey) }
            return m
        }

        static func keyName(_ c: UInt16) -> String {
            let map: [UInt16: String] = [
                0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",
                14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",
                26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",
                38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",
                50:"`",51:"⌫",53:"⎋",65:".",67:"*",69:"+",75:"/",76:"⌤",78:"-",81:"=",
                82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9",
                96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",107:"F14",
                109:"F10",111:"F12",113:"F15",114:"↖",115:"↖",116:"⇞",117:"⌦",118:"F4",119:"↘",
                120:"F2",121:"⇟",122:"F1",123:"←",124:"→",125:"↓",126:"↑"
            ]
            return map[c] ?? "key\(c)"
        }
    }

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotkeyCenter.shared.fire(hkID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    fileprivate func fire(_ id: UInt32) { actions[id]?() }

    /// Registers `combo`, replacing whatever was registered under `name`.
    func bind(_ name: String, _ combo: Combo?, action: @escaping () -> Void) {
        install()
        unbind(name)
        guard let c = combo, !c.isEmpty, c.carbonMods != 0 else { return }
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let sig = OSType(0x434C5056) // 'CLPV'
        let status = RegisterEventHotKey(UInt32(c.keyCode), c.carbonMods,
                                         EventHotKeyID(signature: sig, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else { return }
        refs[id] = r
        actions[id] = action
        names[name] = id
    }

    private var names: [String: UInt32] = [:]

    func unbind(_ name: String) {
        guard let id = names.removeValue(forKey: name) else { return }
        if let r = refs.removeValue(forKey: id) { UnregisterEventHotKey(r) }
        actions[id] = nil
    }
}
