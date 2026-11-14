import SwiftUI
import UIKit
import Combine
import GameController

/// A MacBook's keyboard drawn on the screen, for the half of an unfolded phone below its hinge: with the
/// trackpad under it, the phone half folded is a small laptop. The rows, the key widths and the legends
/// are a MacBook's. Every finger has its own key, so several go down together and a held key is repeated
/// by the Mac itself. A key sinks and the phone clicks when it is pressed. Shift, Control, Option, Command
/// and fn are held like any key for a shortcut; tapped alone, they stay down until the next key, so a
/// shortcut also takes one finger.
struct MacKeyboard: UIViewRepresentable {
    /// A MacBook's look: black keys with white legends, for the aluminium deck under them.
    var macBook = false

    func makeUIView(context: Context) -> KeyboardPad { KeyboardPad(macBook: macBook) }

    func updateUIView(_ pad: KeyboardPad, context: Context) { pad.macBook = macBook }

    static func dismantleUIView(_ pad: KeyboardPad, coordinator: ()) { pad.releaseAll() }
}

/// What one key of the drawn keyboard is.
private struct KeySpec {
    enum Kind { case plain, modifier, fn, blank }
    enum Slot { case full, top, bottom }
    enum Side { case left, centre, right }

    var legend = ""            // in the middle of the key
    var upper = ""             // above the legend: what shift gives
    var name = ""              // along the bottom, small: "shift", "return"
    var side = Side.centre     // where the name is
    var corner = ""            // top right, small: ⌃ ⌥ ⌘
    var code: UInt16 = 0       // a Linux input key code, as in Keys
    var fnCode: UInt16 = 0     // what it is with fn held, when that differs
    var weight: CGFloat = 1
    var kind = Kind.plain
    var slot = Slot.full
    var said = ""              // for VoiceOver, when the legend doesn't say it

    static func letter(_ legend: String, _ code: UInt16) -> KeySpec { KeySpec(legend: legend, code: code) }
    static func pair(_ upper: String, _ legend: String, _ code: UInt16) -> KeySpec { KeySpec(legend: legend, upper: upper, code: code) }
    static func word(_ name: String, _ code: UInt16, _ weight: CGFloat, _ side: Side, fn: UInt16 = 0) -> KeySpec {
        KeySpec(name: name, side: side, code: code, fnCode: fn, weight: weight)
    }
    static func held(_ name: String, _ corner: String, _ code: UInt16, _ weight: CGFloat, _ side: Side) -> KeySpec {
        KeySpec(name: name, side: side, corner: corner, code: code, weight: weight, kind: .modifier)
    }
    static func function(_ legend: String, _ code: UInt16, fn: UInt16 = 0, said: String = "") -> KeySpec {
        KeySpec(legend: legend, code: code, fnCode: fn, said: said)
    }
    static func arrow(_ legend: String, _ code: UInt16, fn: UInt16, _ slot: Slot, said: String) -> KeySpec {
        KeySpec(legend: legend, code: code, fnCode: fn, slot: slot, said: said)
    }

    /// A MacBook's six rows, each 14.5 keys wide. The first is the half-height function row; its last
    /// three keys are the sound keys, and F10 to F12 with fn. The key in its corner, Touch ID on a
    /// MacBook, does nothing here. With fn, delete deletes forwards and the arrows are home, end, page
    /// up and page down.
    static let rows: [[KeySpec]] = [
        [KeySpec(legend: "esc", code: 1, weight: 1.5),
         function("F1", 59), function("F2", 60), function("F3", 61), function("F4", 62), function("F5", 63),
         function("F6", 64), function("F7", 65), function("F8", 66), function("F9", 67),
         function("🔇", 113, fn: 68, said: "mute"), function("🔉", 114, fn: 87, said: "volume down"),
         function("🔊", 115, fn: 88, said: "volume up"),
         KeySpec(kind: .blank)],
        [pair("~", "`", 41), pair("!", "1", 2), pair("@", "2", 3), pair("#", "3", 4), pair("$", "4", 5),
         pair("%", "5", 6), pair("^", "6", 7), pair("&", "7", 8), pair("*", "8", 9), pair("(", "9", 10),
         pair(")", "0", 11), pair("_", "-", 12), pair("+", "=", 13), word("delete", 14, 1.5, .right, fn: 111)],
        [word("tab", 15, 1.5, .left), letter("Q", 16), letter("W", 17), letter("E", 18), letter("R", 19),
         letter("T", 20), letter("Y", 21), letter("U", 22), letter("I", 23), letter("O", 24), letter("P", 25),
         pair("{", "[", 26), pair("}", "]", 27), pair("|", "\\", 43)],
        [word("caps lock", 58, 1.75, .left), letter("A", 30), letter("S", 31), letter("D", 32), letter("F", 33),
         letter("G", 34), letter("H", 35), letter("J", 36), letter("K", 37), letter("L", 38),
         pair(":", ";", 39), pair("\"", "'", 40), word("return", 28, 1.75, .right)],
        [held("shift", "", 42, 2.25, .left), letter("Z", 44), letter("X", 45), letter("C", 46), letter("V", 47),
         letter("B", 48), letter("N", 49), letter("M", 50), pair("<", ",", 51), pair(">", ".", 52),
         pair("?", "/", 53), held("shift", "", 54, 2.25, .right)],
        [KeySpec(name: "fn", side: .left, kind: .fn),
         held("control", "⌃", 29, 1, .right), held("option", "⌥", 56, 1, .right),
         held("command", "⌘", 125, 1.25, .right),
         KeySpec(code: 57, weight: 5, said: "space"),
         held("command", "⌘", 126, 1.25, .left), held("option", "⌥", 100, 1, .left),
         arrow("◀", 105, fn: 102, .bottom, said: "left"),
         arrow("▲", 103, fn: 104, .top, said: "up"), arrow("▼", 108, fn: 109, .bottom, said: "down"),
         arrow("▶", 106, fn: 107, .bottom, said: "right")],
    ]
    static let functionRow: CGFloat = 0.55   // its height, in rows
    static let across: CGFloat = 14.5        // a row, in keys
}

/// One drawn key: a cap that sinks when pressed.
private final class KeyCap: UIView {
    let spec: KeySpec
    var cell = CGRect.zero     // the key and half the gap around it: where a finger counts as on it
    private let legend = UILabel(), upper = UILabel(), name = UILabel(), corner = UILabel()
    private(set) var pressed = false
    var lit = false { didSet { if lit != oldValue { paint() } } }
    var macBook = false { didSet { if macBook != oldValue { paint() } } }

    init(_ spec: KeySpec) {
        self.spec = spec
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0.6
        for (label, text) in [(legend, spec.legend), (upper, spec.upper), (name, spec.name), (corner, spec.corner)] {
            label.text = text
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.5
            label.baselineAdjustment = .alignCenters
            label.isHidden = text.isEmpty
            addSubview(label)
        }
        legend.textAlignment = .center
        upper.textAlignment = .center
        corner.textAlignment = .right
        name.textAlignment = spec.side == .left ? .left : spec.side == .right ? .right : .center
        if spec.kind != .blank {
            isAccessibilityElement = true
            accessibilityTraits = .keyboardKey
            accessibilityLabel = !spec.said.isEmpty ? spec.said : !spec.name.isEmpty ? spec.name : spec.legend
        }
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        layer.cornerRadius = min(min(w, h) * 0.17, 7)
        let small = max(min(h * 0.24, w * 0.3, 11), 6)
        let pad = max(min(w, h) * 0.12, 3)
        name.font = .systemFont(ofSize: small, weight: .medium)
        corner.font = .systemFont(ofSize: small * 1.25, weight: .medium)
        name.frame = CGRect(x: pad, y: h - pad - small * 1.3, width: w - pad * 2, height: small * 1.3)
        corner.frame = CGRect(x: pad, y: pad * 0.7, width: w - pad * 2, height: small * 1.5)
        if spec.upper.isEmpty {
            let words = spec.legend.count > 1
            legend.font = .systemFont(ofSize: words ? min(h * 0.42, w * 0.34, 12) : min(h * 0.42, w * 0.5, 18), weight: .medium)
            legend.frame = bounds.insetBy(dx: 2, dy: 1)
        } else {
            let size = min(h * 0.3, w * 0.42, 14)
            legend.font = .systemFont(ofSize: size, weight: .medium)
            upper.font = .systemFont(ofSize: size, weight: .medium)
            upper.frame = CGRect(x: 2, y: h * 0.1, width: w - 4, height: h * 0.4)
            legend.frame = CGRect(x: 2, y: h * 0.5, width: w - 4, height: h * 0.4)
        }
    }

    func press(_ down: Bool) {
        guard down != pressed else { return }
        pressed = down
        UIView.animate(withDuration: down ? 0.04 : 0.11, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, down ? .curveEaseOut : .curveEaseIn]) {
            self.transform = down ? CGAffineTransform(translationX: 0, y: 1.5).scaledBy(x: 0.955, y: 0.955) : .identity
            self.paint()
        }
    }

    private func paint() {
        let ink: UIColor, cap: UIColor
        if macBook {
            ink = .white
            cap = lit ? UIColor(Desk.accent) : UIColor(pressed ? MacBookDeck.keyDown : MacBookDeck.key)
        } else {
            ink = lit ? .white : UIColor(Desk.text)
            cap = lit ? UIColor(Desk.accent) : pressed ? UIColor(Desk.faint) : UIColor(Desk.raised)
        }
        backgroundColor = cap
        layer.shadowOpacity = pressed ? 0 : macBook ? 0.45 : 0.18
        for label in [legend, upper, name, corner] { label.textColor = ink }
    }
}

/// The drawn keyboard itself: it follows every finger on it by hand, which is what lets several keys be
/// down at once.
final class KeyboardPad: UIView {
    var macBook: Bool { didSet { caps.forEach { $0.macBook = macBook } } }
    private let caps: [KeyCap]
    private let rows: [[KeyCap]]

    private struct Press {
        let cap: KeyCap
        let sent: UInt16        // the code that went down, to send up again
        let began: TimeInterval
        var used = false        // a modifier: another key went down while it was held
    }
    private var presses: [UITouch: Press] = [:]
    private var fnLatched = false { didSet { relight() } }
    private var fnHeld: Bool { presses.values.contains { $0.cap.spec.kind == .fn } }
    private var watching: AnyCancellable?

    private let click = UIImpactFeedbackGenerator(style: .rigid)
    private let lift = UIImpactFeedbackGenerator(style: .soft)
    /// A modifier let go within this long, and with no other key pressed meanwhile, stays down for the next key.
    private static let tap: TimeInterval = 0.4

    init(macBook: Bool) {
        self.macBook = macBook
        rows = KeySpec.rows.map { $0.map(KeyCap.init) }
        caps = rows.flatMap { $0 }
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        for cap in caps {
            cap.macBook = macBook
            addSubview(cap)
        }
        watching = StickyKeys.shared.$down.receive(on: RunLoop.main).sink { [weak self] _ in self?.relight() }
        click.prepare()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let high = CGFloat(rows.count - 1) + KeySpec.functionRow
        let pitch = bounds.width / KeySpec.across
        let rowPitch = min(bounds.height / high, pitch)     // never taller than a key is wide
        let gap = max(pitch * 0.1, 3)
        var y = ((bounds.height - rowPitch * high) / 2).rounded()
        for (index, row) in rows.enumerated() {
            let height = index == 0 ? rowPitch * KeySpec.functionRow : rowPitch
            var x: CGFloat = 0
            for cap in row {
                let width = cap.spec.weight * pitch
                var cell = CGRect(x: x, y: y, width: width, height: height)
                switch cap.spec.slot {
                case .full: break
                case .top: cell.size.height = height / 2
                case .bottom: cell.origin.y += height / 2; cell.size.height = height / 2
                }
                cap.cell = cell
                let halves = cap.spec.slot != .full
                let was = cap.transform
                cap.transform = .identity
                cap.frame = cell.insetBy(dx: gap / 2, dy: halves ? gap / 4 : gap / 2)
                if halves {     // the arrows: half keys, with the row's gap around the four of them
                    cap.frame.origin.y += cap.spec.slot == .top ? gap / 4 : -gap / 4
                }
                cap.transform = was
                if cap.spec.slot != .top { x += width }   // up sits above down
            }
            y += height
        }
    }

    private func cap(at point: CGPoint) -> KeyCap? {
        caps.first { $0.spec.kind != .blank && $0.cell.contains(point) }
    }

    private func relight() {
        let latched = StickyKeys.shared.down
        for cap in caps {
            switch cap.spec.kind {
            case .modifier: cap.lit = latched.contains(cap.spec.code)
            case .fn: cap.lit = fnLatched
            default: break
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let cap = cap(at: touch.location(in: self)), !cap.pressed else { continue }
            let now = touch.timestamp
            var sent: UInt16 = 0
            switch cap.spec.kind {
            case .blank:
                continue
            case .fn:
                if fnLatched { fnLatched = false; feel(down: true); tapOnly(cap); continue }
            case .modifier:
                let code = cap.spec.code
                if StickyKeys.shared.down.contains(code) {     // a second tap lets it go
                    StickyKeys.shared.toggle(code)
                    feel(down: true)
                    tapOnly(cap)
                    continue
                }
                henge_vm_key(code, 1)
                sent = code
            case .plain:
                for key in presses.keys where presses[key]?.cap.spec.kind != .plain { presses[key]?.used = true }
                sent = (fnHeld || fnLatched) && cap.spec.fnCode != 0 ? cap.spec.fnCode : cap.spec.code
                henge_vm_key(sent, 1)
            }
            presses[touch] = Press(cap: cap, sent: sent, began: now)
            cap.press(true)
            feel(down: true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: true) }

    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            guard let press = presses.removeValue(forKey: touch) else { continue }
            press.cap.press(false)
            let tapped = !cancelled && !press.used && touch.timestamp - press.began < Self.tap
            switch press.cap.spec.kind {
            case .blank:
                break
            case .fn:
                if tapped { fnLatched = true }
            case .modifier:
                if tapped {
                    StickyKeys.shared.adopt(press.sent)     // stays down for the next key
                } else {
                    henge_vm_key(press.sent, 0)
                }
            case .plain:
                henge_vm_key(press.sent, 0)
                StickyKeys.shared.releaseAll()
                fnLatched = false
            }
            if !cancelled { feel(down: false) }
        }
    }

    /// A key that only shows its press: the tap that lets a held modifier go.
    private func tapOnly(_ cap: KeyCap) {
        cap.press(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { cap.press(false) }
    }

    private func feel(down: Bool) {
        if down {
            click.impactOccurred(intensity: 1)
            click.prepare()
        } else {
            lift.impactOccurred(intensity: 0.45)
        }
    }

    /// Every key up: the keyboard is going away.
    func releaseAll() {
        for press in presses.values {
            press.cap.press(false)
            if press.sent != 0 { henge_vm_key(press.sent, 0) }
        }
        presses.removeAll()
        fnLatched = false
    }

    override func willMove(toWindow window: UIWindow?) {
        super.willMove(toWindow: window)
        if window == nil { releaseAll() }
    }
}

/// The half of an unfolded phone below its hinge, in full screen: a MacBook's aluminium deck, with the
/// hinge's shadow along its top edge.
struct MacBookDeck: View {
    static let key = Color(white: 0.09)
    static let keyDown = Color(white: 0.32)

    var body: some View {
        LinearGradient(colors: [Color(white: 0.80), Color(white: 0.84), Color(white: 0.78)], startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .top) {
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 7)
            }
            .allowsHitTesting(false)
    }
}

/// Whether a keyboard is attached to the device: with one, the drawn keyboard gives its room to the trackpad.
final class AttachedKeyboard: ObservableObject {
    @Published private(set) var present = GCKeyboard.coalesced != nil
    private var observers: [NSObjectProtocol] = []

    init() {
        for name in [Notification.Name.GCKeyboardDidConnect, Notification.Name.GCKeyboardDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.present = GCKeyboard.coalesced != nil
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
