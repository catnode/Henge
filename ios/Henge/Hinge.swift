import SwiftUI
import UIKit

/// How an unfolding phone (iPhone Duo) is held open, from its hinge. Half folded it is a laptop: the Mac
/// above the hinge, keyboard and trackpad below. Opened flat, the Mac fills the screen. A device without a
/// hinge, or an iOS that doesn't report one, stays `.unknown` and the session follows how it is turned.
final class HingeMonitor: ObservableObject {
    enum Posture: String { case unknown, laptop, flat }

    @Published private(set) var posture = Posture.unknown
    private var logged = 0

    /// `angle` in degrees, or nil when the hinge doesn't say.
    func update(status: Int, angle: Double?) {
        let next: Posture
        if let angle {
            // Past this the two halves read as one flat screen; under it the lower half is a deck.
            next = angle >= 166 ? .flat : angle >= 30 ? .laptop : .unknown
        } else {
            // UIHinge's states as iOS 27.1 numbers them: 1 closed, 2 partly open, 3 fully open.
            next = status == 3 ? .flat : status == 2 ? .laptop : .unknown
        }
        if logged < 24 {
            logged += 1
            HengeLog.log("input", "hinge: status \(status), angle \(angle.map { String(format: "%.0f", $0) } ?? "none") -> \(next.rawValue)")
        }
        if next != posture { posture = next }
    }

    /// Turns the session to suit the posture: upright for a laptop, so the hinge runs across the middle,
    /// and on its side when flat, where the Mac fills the screen.
    static func turn(for posture: Posture) {
        let mask: UIInterfaceOrientationMask
        switch posture {
        case .laptop: mask = .portrait
        case .flat: mask = .landscape
        case .unknown: return
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            HengeLog.log("input", "hinge: turning refused: \(error.localizedDescription)")
        }
    }
}

/// An invisible view that listens to the hinge for a HingeMonitor.
struct HingeSensor: UIViewRepresentable {
    let monitor: HingeMonitor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        if #available(iOS 27.1, *) {
            let monitor = monitor
            let interaction = UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    monitor.update(status: 0, angle: nil)
                    return
                }
                monitor.update(status: hinge.status.rawValue, angle: Double(hinge.angle) * 180 / .pi)
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
