import SwiftUI
import UIKit
import GameController

/// A Mac's keyboard drawn on the screen, for the half of an unfolded phone below its hinge: with the
/// trackpad under it, the phone half folded is a small laptop. Each key goes down when touched and up
/// when let go, so the Mac repeats a held key itself and several can be held together. Shift, Control,
/// Option and Command stay down from a tap until the next key, so a shortcut takes one finger.
struct MacKeyboard: View {
    /// A MacBook's look: black keys with white legends, for the aluminium deck under them.
    var macBook = false
    @ObservedObject private var sticky = StickyKeys.shared

    private struct Key: Identifiable {
        let label: String
        let code: UInt16
        var weight: CGFloat = 1
        var sticks = false
        var id: String { "\(label)-\(code)-\(weight)" }
    }

    /// Linux input key codes, as in Keys.
    private static let rows: [[Key]] = [
        [Key(label: "esc", code: 1), Key(label: "`", code: 41), Key(label: "1", code: 2), Key(label: "2", code: 3),
         Key(label: "3", code: 4), Key(label: "4", code: 5), Key(label: "5", code: 6), Key(label: "6", code: 7),
         Key(label: "7", code: 8), Key(label: "8", code: 9), Key(label: "9", code: 10), Key(label: "0", code: 11),
         Key(label: "-", code: 12), Key(label: "=", code: 13), Key(label: "⌫", code: 14, weight: 1.5)],
        [Key(label: "tab", code: 15, weight: 1.5), Key(label: "Q", code: 16), Key(label: "W", code: 17),
         Key(label: "E", code: 18), Key(label: "R", code: 19), Key(label: "T", code: 20), Key(label: "Y", code: 21),
         Key(label: "U", code: 22), Key(label: "I", code: 23), Key(label: "O", code: 24), Key(label: "P", code: 25),
         Key(label: "[", code: 26), Key(label: "]", code: 27), Key(label: "\\", code: 43)],
        [Key(label: "⇪", code: 58, weight: 1.75), Key(label: "A", code: 30), Key(label: "S", code: 31),
         Key(label: "D", code: 32), Key(label: "F", code: 33), Key(label: "G", code: 34), Key(label: "H", code: 35),
         Key(label: "J", code: 36), Key(label: "K", code: 37), Key(label: "L", code: 38), Key(label: ";", code: 39),
         Key(label: "'", code: 40), Key(label: "return", code: 28, weight: 1.75)],
        [Key(label: "⇧", code: 42, weight: 2.25, sticks: true), Key(label: "Z", code: 44), Key(label: "X", code: 45),
         Key(label: "C", code: 46), Key(label: "V", code: 47), Key(label: "B", code: 48), Key(label: "N", code: 49),
         Key(label: "M", code: 50), Key(label: ",", code: 51), Key(label: ".", code: 52), Key(label: "/", code: 53),
         Key(label: "↑", code: 103), Key(label: "⇧", code: 42, weight: 1.25, sticks: true)],
        [Key(label: "⌃", code: 29, weight: 1.25, sticks: true), Key(label: "⌥", code: 56, weight: 1.25, sticks: true),
         Key(label: "⌘", code: 125, weight: 1.5, sticks: true), Key(label: "", code: 57, weight: 5.5),
         Key(label: "⌘", code: 125, weight: 1.25, sticks: true), Key(label: "⌥", code: 56, sticks: true),
         Key(label: "←", code: 105), Key(label: "↓", code: 108), Key(label: "→", code: 106)],
    ]

    private static let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let rows = Self.rows
            let rowHeight = max((geo.size.height - Self.gap * CGFloat(rows.count - 1)) / CGFloat(rows.count), 1)
            VStack(spacing: Self.gap) {
                ForEach(rows.indices, id: \.self) { index in
                    row(rows[index], width: geo.size.width, height: rowHeight)
                }
            }
        }
    }

    private func row(_ keys: [Key], width: CGFloat, height: CGFloat) -> some View {
        let total = keys.reduce(CGFloat(0)) { $0 + $1.weight }
        let unit = max((width - Self.gap * CGFloat(keys.count - 1)) / max(total, 1), 1)
        return HStack(spacing: Self.gap) {
            ForEach(keys.indices, id: \.self) { index in
                let key = keys[index]
                if key.sticks {
                    stickyKey(key).frame(width: unit * key.weight, height: height)
                } else {
                    PressedKey(label: key.label, code: key.code, macBook: macBook).frame(width: unit * key.weight, height: height)
                }
            }
        }
    }

    private func stickyKey(_ key: Key) -> some View {
        let on = sticky.down.contains(key.code)
        return Button {
            sticky.toggle(key.code)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(key.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on || macBook ? Color.white : Desk.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(on ? Desk.accent : macBook ? MacBookDeck.key : Desk.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One key of the drawn keyboard: down when touched, up when let go.
private struct PressedKey: View {
    let label: String
    let code: UInt16
    var macBook = false
    @State private var down = false

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 11 : 15, weight: .medium))
            .foregroundStyle(down || macBook ? Color.white : Desk.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(down ? (macBook ? MacBookDeck.keyDown : Desk.accent) : macBook ? MacBookDeck.key : Desk.raised,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !down else { return }
                        down = true
                        henge_vm_key(code, 1)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .onEnded { _ in
                        down = false
                        henge_vm_key(code, 0)
                        StickyKeys.shared.releaseAll()
                    }
            )
            .accessibilityLabel(label.isEmpty ? "space" : label)
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
