import SwiftUI
import UIKit
import GameController

/// What this device is, for what the app says and suggests.
enum Device {
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static let name = isPad ? "iPad" : "iPhone"

    /// A Mac's screen that fills this device on its side: 1920 wide, as tall as the shape asks. iPads and
    /// squarer phones (iPhone Duo, about 1.46:1) would get bars above and below at 16:9. Phones wider
    /// than 16:9 come out at 1920×1080, as before.
    static var fittingScreen: (width: Int, height: Int) {
        let size = UIScreen.main.bounds.size
        let shape = max(size.width, size.height) / max(min(size.width, size.height), 1)
        return (1920, min(max(Int((1920 / shape / 8).rounded()) * 8, 1080), 1440))
    }

    /// A phone that unfolds (iPhone Duo): opened, even its shorter side is wider than any other phone
    /// is tall across. Held upright, its hinge runs across the middle of the screen.
    static let foldWidth: CGFloat = 600
    static var isFoldable: Bool {
        guard !isPad else { return false }
        let size = UIScreen.main.bounds.size
        return HengeLog.deviceModel == "iPhone19,4" || min(size.width, size.height) >= foldWidth
    }

    /// A Mac's screen for the half above the hinge: the shape of the room SessionView's layout leaves it
    /// there (from the status bar down to the fold, the full width), so it fills that half edge to edge.
    static var laptopScreen: (width: Int, height: Int) {
        // The whole half, edge to edge: what full screen shows there. Out of full screen the status bar
        // takes some of the half's height, and the Mac is a little narrower than the phone.
        let size = UIScreen.main.bounds.size
        let wide = min(size.width, size.height), tall = max(size.width, size.height)
        let shape = max(wide, 1) / max(tall / 2, 120)
        return (1920, min(max(Int((1920 / shape / 8).rounded()) * 8, 900), 1440))
    }

    /// How large the Mac draws everything, in percent: an unfolded phone is far smaller than the monitor
    /// 1920 pixels across are meant for. The Mac gets that many fewer pixels in the same shape, and the
    /// phone shows each larger. Only phones that unfold have the choice.
    static let zoomKey = "henge.display.zoom"
    static let zooms = [100, 125, 150, 175]
    static var zoom: Int {
        guard isFoldable else { return 100 }
        let chosen = UserDefaults.standard.integer(forKey: zoomKey)
        return zooms.contains(chosen) ? chosen : 125
    }
    static func zoomed(_ screen: (width: Int, height: Int)) -> (width: Int, height: Int) {
        let percent = zoom
        guard percent != 100 else { return screen }
        func fewer(_ pixels: Int) -> Int { Int((Double(pixels) * 100 / Double(percent) / 8).rounded()) * 8 }
        return (fewer(screen.width), fewer(screen.height))
    }

    /// The safe area above the Mac when an unfolded phone is upright, as the session last saw it (the
    /// screen's shape must not change with how the phone is turned while Settings is open).
    /// Whether a running Mac's screen changes shape with how an unfolding phone is held (experimental).
    static let followPostureKey = "henge.display.followPosture"
    static let foldTopInsetKey = "henge.fold.topInset"
    static var foldTopInset: CGFloat {
        let seen = UserDefaults.standard.double(forKey: foldTopInsetKey)
        return seen > 0 ? CGFloat(seen) : 86
    }

    /// Preserve the iPad's shape while reducing the virtual GPU's pixel work.
    static var performanceScreen: (width: Int, height: Int) {
        let fit = fittingScreen
        return (1600, Int((Double(fit.height) * 5 / 6 / 8).rounded()) * 8)
    }

    /// The panel itself, on its side: every physical pixel, and its real size in mm so that macOS
    /// sees a Retina density and draws at 2x (looks like half the pixels, sharp as the iPad's own UI).
    /// Every iPad with an M chip is 264 ppi.
    static var retinaScreen: (width: Int, height: Int) {
        let n = UIScreen.main.nativeBounds.size
        return (Int(max(n.width, n.height)) / 8 * 8, Int(min(n.width, n.height)) / 8 * 8)
    }
    static var retinaMM: (width: Int, height: Int) {
        let s = retinaScreen
        return (Int((Double(s.width) / 264 * 25.4).rounded()), Int((Double(s.height) / 264 * 25.4).rounded()))
    }

    /// How much memory to suggest for a new Mac: what leaves this device room for iOS.
    static var suggestedRAMGB: Int {
        let mb = ProcessInfo.processInfo.physicalMemory >> 20
        // m4 fork: an 8 GB iPad (7.4 GB usable) thrashes and kills the Mac at 6 GB: 16 GB devices only.
        // A 6 GB device (5.7 GB usable) could not build a 4 GB Mac, and installed a 3 GB one (#70); 4 GB devices, 2.
        return mb >= 14_000 ? 8 : mb >= 10_000 ? 6 : mb >= 7_000 ? 4 : mb >= 5_000 ? 3 : 2
    }

    /// The choices for a Mac's memory, in GB.
    static let memoryChoices = 1...16

    /// What a choice risks on this device, if anything. An install always gets at least 2 GB (Installer.install).
    static func memoryNote(_ gb: Int) -> String? {
        if gb < 4 { return "macOS has little room under 4 GB, so it can be very slow." }
        if gb > suggestedRAMGB { return "More than \(suggestedRAMGB) GB is a lot for this \(name): iOS may close Henge when macOS gets busy." }
        return nil
    }

    /// The virtual CPU offers Armv8.5 instructions (core/sysreg.c), and macOS uses them. They run as
    /// they are, so the chip needs them too: A14, M1 and later, which is iPhone13,x and iPad13,x up.
    static let chipTooOld: Bool = {
        let model = HengeLog.deviceModel
        guard model.hasPrefix("iPhone") || model.hasPrefix("iPad"),
              let major = Int(model.drop { !$0.isNumber }.prefix { $0.isNumber }) else { return false }
        return major < 13
    }()

    static let chipTooOldText = "macOS won't run on this \(name). Henge needs an A14 or M1 chip or newer."
}

/// A keyboard attached to the device. iOS reports each key going down and coming up by its HID usage,
/// which is what the Mac's USB keyboard sends, so every key and modifier goes straight across.
enum HardwareKeys {
    private static var held: Set<UInt8> = []
    private static var lastKey: CFTimeInterval = 0

    /// With the on-screen keyboard's view holding the keyboard, iOS may also offer a hardware key as
    /// text, and again as it repeats. The Mac has the key already, and repeats it itself.
    static var keyJustPressed: Bool {
        held.contains { $0 < 0xe0 } || CACurrentMediaTime() - lastKey < 0.1
    }

    /// Sends the presses that are keys, and returns the rest.
    static func send(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var rest = Set<UIPress>()
        // A chord can arrive in one unordered Set. Press modifiers first and
        // release them last so the guest sees the intended shortcut.
        let ordered = presses.sorted { a, b in
            let aCode = a.key?.keyCode.rawValue ?? 0
            let bCode = b.key?.keyCode.rawValue ?? 0
            let aModifier = (0xe0...0xe7).contains(aCode)
            let bModifier = (0xe0...0xe7).contains(bCode)
            if aModifier != bModifier { return down ? aModifier : !aModifier }
            return aCode < bCode
        }
        for press in ordered {
            guard let raw = press.key?.keyCode.rawValue, raw >= 0x04, raw <= 0xe7 else {
                rest.insert(press)
                continue
            }
            let usage = UInt8(raw)
            henge_vm_key_hid(usage, down ? 1 : 0)
            if usage < 0xe0 { lastKey = CACurrentMediaTime() }
            if down {
                held.insert(usage)
            } else {
                held.remove(usage)
                if usage < 0xe0 { StickyKeys.shared.releaseAll() } // one key after a tap on ⌃, ⌥ or ⌘
            }
        }
        return rest
    }

    /// iPadOS can keep a key's release when it takes over, as it does for ⌘-Tab: the Mac must not
    /// go on thinking the key is down.
    static func releaseAll() {
        for usage in held { henge_vm_key_hid(usage, 0) }
        held.removeAll()
    }
}

/// Asks iPadOS to hand the pointer over, so a trackpad or mouse drives only the Mac's pointer. It does
/// that only for an app filling the screen. SwiftUI has no way to ask, so the answer is added to the
/// class of the window's root view controller, which is who iPadOS asks.
enum PointerLock {
    private static var wanted = false
    private static var patched: Set<ObjectIdentifier> = []

    static func set(_ on: Bool) {
        wanted = on
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            guard let root = window.rootViewController else { continue }
            let kind: AnyClass = type(of: root)
            if patched.insert(ObjectIdentifier(kind)).inserted {
                let answer: @convention(block) (UIViewController) -> Bool = { _ in wanted }
                class_replaceMethod(kind, #selector(getter: UIViewController.prefersPointerLocked), imp_implementationWithBlock(answer), "B@:")
            }
            root.setNeedsUpdateOfPrefersPointerLocked()
        }
    }

    /// iPadOS only locks the pointer to an app that fills the screen: in a window (Stage Manager, or iPadOS 26's windows)
    /// the request is ignored and the system pointer stays separate from the Mac's (#18). An iPhone never locks it, and
    /// its apps are always full screen, so the hint is for iPad only.
    static var refused: Bool {
        guard Device.isPad, wanted, GCMouse.current != nil else { return false }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
        return !scenes.isEmpty && !scenes.contains { $0.pointerLockState?.isLocked == true }
    }
}

/// A Magic Keyboard's trackpad or a mouse, while a Mac is running. GameController gives the raw motion,
/// which macOS then accelerates as it would for its own mouse.
final class HardwareMouse {
    static let shared = HardwareMouse()
    static let speedKey = "henge.mouse.speed"
    static let reverseKey = "henge.mouse.reverse"
    static let scrollSpeedKey = "henge.mouse.scrollSpeed"
    static let followKey = "henge.mouse.followPointer"
    /// Off unless asked for: it gives the Mac one more USB device, and a session reads it when the Mac starts.
    static var followsSystemPointer: Bool {
        guard !Device.isPad else { return false }
        let defaults = UserDefaults.standard
        return defaults.object(forKey: followKey) == nil ? true : defaults.bool(forKey: followKey)
    }

    /// Where the Mac's picture is in the window, in points: the session's layout keeps it current.
    /// Null while the Mac is on another display.
    var screen = CGRect.null

    private var observers: [NSObjectProtocol] = []
    private var mice: [GCMouse] = []
    private var buttons = PhysicalMouseButtons(swapsRightAndMiddle: false)
    private var buttonsLogged = 0
    private var restX: Float = 0, restY: Float = 0
    private var speed: Float = 1
    private var reverse = false
    private var scrollsLogged = 0 // the first few, to see what a device's raw values look like
    private var lastScrollFirst: Float = 0, lastScrollSecond: Float = 0
    private var lastRawMove = Date.distantPast
    private var movesLogged = 0
    private let pointerDrag = PointerDrag()
    /// A phone keeps its own pointer on screen (it never locks it), so the Mac's pointer goes where that
    /// one is, through the Mac's absolute pointing device, instead of both wandering apart.
    private var follow = false
    private var pointerAt: CGPoint? // the system pointer, in the window; nil until iOS says where it is
    private var lastPlace = Date.distantPast
    private var unplaced = 0 // raw moves in a row that came with no word of where the pointer is
    private var placesLogged = 0
    private var swallowed: Set<Int32> = [] // buttons pressed with the pointer off the Mac's screen
    private var forwarded: Set<Int32> = []
    private var onPointer: Set<Int32> = [] // the Mac's buttons held through its absolute pointer, not its mouse

    func start() {
        let defaults = UserDefaults.standard
        speed = defaults.object(forKey: Self.speedKey) == nil ? 1 : Float(defaults.double(forKey: Self.speedKey))
        reverse = defaults.bool(forKey: Self.reverseKey)
        releaseButtons()
        let swapButtons = defaults.bool(forKey: PhysicalMouseButtons.swapKey)
        buttons = PhysicalMouseButtons(swapsRightAndMiddle: swapButtons)
        buttonsLogged = 0
        HengeLog.log("input", "physical mouse: swap right/middle \(swapButtons ? "on" : "off")")
        lastScrollFirst = 0
        lastScrollSecond = 0
        GCMouse.mice().forEach(attach)
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            if let mouse = note.object as? GCMouse { self?.attach(mouse) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCMouseDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, let mouse = note.object as? GCMouse else { return }
            self.releaseButtons()
            self.mice.removeAll { $0 === mouse }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIPointerLockState.didChangeNotification, object: nil, queue: .main) { note in
            // The scene comes in the user info: the notification's object isn't it.
            let scene = note.userInfo?[UIPointerLockState.sceneUserInfoKey] as? UIScene
            let locked = scene?.pointerLockState?.isLocked ?? false
            HengeLog.log("input", "pointer lock: \(locked ? "on" : "off")")
        })
        PointerLock.set(true)
        movesLogged = 0
        follow = Self.followsSystemPointer
        pointerAt = nil
        unplaced = 0
        placesLogged = 0
        swallowed.removeAll()
        forwarded.removeAll()
        HengeLog.log("input", "physical mouse: the Mac's pointer follows the system's \(follow ? "on" : "off")")
        pointerDrag.moved = { [weak self] dx, dy in self?.dragged(dx, dy) }
        pointerDrag.placed = { [weak self] p in self?.placed(p) }
        pointerDrag.install()
    }

    func stop() {
        pointerDrag.remove()
        PointerLock.set(false)
        releaseButtons()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for mouse in mice {
            guard let input = mouse.mouseInput else { continue }
            input.mouseMovedHandler = nil
            input.leftButton.pressedChangedHandler = nil
            input.rightButton?.pressedChangedHandler = nil
            input.middleButton?.pressedChangedHandler = nil
            input.scroll.valueChangedHandler = nil
        }
        mice.removeAll()
    }

    func releaseButtons() {
        for button in buttons.releaseAll() {
            if onPointer.remove(button) != nil { henge_vm_mouse_at_button(button, 0) } else { henge_vm_mouse_button(button, 0) }
        }
        onPointer.removeAll()
        swallowed.removeAll()
        forwarded.removeAll()
    }

    /// Whether the system's pointer should stay visible over a view centred at this point of the window:
    /// it should wherever the Mac's pointer does not stand in for it.
    func showsSystemPointer(at point: CGPoint) -> Bool {
        follow && !screen.isNull && !screen.contains(point)
    }

    private var overScreen: Bool {
        guard let p = pointerAt, !screen.isNull else { return false }
        return screen.insetBy(dx: -1, dy: -1).contains(p)
    }

    /// iOS said where its pointer is. Over the Mac's picture, the Mac's pointer goes to the same spot;
    /// with a button held there, it stays at the picture's nearest edge when the system's pointer leaves.
    private func placed(_ p: CGPoint) {
        guard follow else { return }
        if pointerAt == nil { HengeLog.log("input", "physical mouse: iOS reports its pointer's place; the Mac's pointer follows it") }
        pointerAt = p
        lastPlace = Date()
        unplaced = 0
        guard !screen.isNull, screen.width > 1, screen.height > 1, overScreen || !forwarded.isEmpty else { return }
        let x = min(max((p.x - screen.minX) / screen.width, 0), 1), y = min(max((p.y - screen.minY) / screen.height, 0), 1)
        if placesLogged < 6 {
            placesLogged += 1
            HengeLog.log("input", "physical mouse: pointer at \(p) in the window, \(x), \(y) of the Mac's screen \(screen)")
        }
        henge_vm_mouse_at(Int32((x * 32767).rounded()), Int32((y * 32767).rounded()))
    }

    /// Raw motion. While the Mac's pointer follows the system's, it only counts when iOS has stopped
    /// saying where its pointer is (it can during a held button), so the Mac's pointer never stalls.
    private func rawMoved(_ dx: Float, _ dy: Float) {
        let now = Date(), continuing = now.timeIntervalSince(lastRawMove) < 0.1
        lastRawMove = now
        if follow, pointerAt != nil {
            guard continuing, now.timeIntervalSince(lastPlace) > 0.25 else { return }
            unplaced += 1
            // A press is followed by its own recognizer, so a few silent moves are a hand's tremble on the button,
            // not iOS keeping the pointer's place to itself: moving on them pushed the Mac's pointer off the system's.
            guard unplaced > 20 else { return }
            if unplaced > 60 {
                HengeLog.log("input", "physical mouse: iOS stopped reporting its pointer's place; back to raw motion")
                pointerAt = nil
            }
            guard overScreen || !forwarded.isEmpty || pointerAt == nil else { return }
        }
        moved(dx, dy)
    }

    private func attach(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput, !mice.contains(where: { $0 === mouse }) else { return }
        mice.append(mouse)
        HengeLog.log("input", "mouse: \(mouse.vendorName ?? "?"), right button \(input.rightButton != nil), middle \(input.middleButton != nil)")
        input.mouseMovedHandler = { [weak self] _, dx, dy in self?.rawMoved(dx, dy) }
        input.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(0, pressed) }
        input.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(1, pressed) }
        input.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in self?.button(2, pressed) }
        input.scroll.valueChangedHandler = { [weak self] _, first, second in self?.scrolled(first, second) }
    }

    /// GameController's Y runs upward. What doesn't make a whole step yet waits for the next move.
    private func moved(_ dx: Float, _ dy: Float) {
        restX += dx * speed
        restY -= dy * speed
        let x = restX.rounded(), y = restY.rounded()
        guard x != 0 || y != 0 else { return }
        restX -= x
        restY -= y
        henge_vm_mouse_move(Int32(x), Int32(y))
    }

    /// Without the pointer locked (an iPhone never locks it), iOS can keep a held button's motion to itself
    /// as a drag of its own pointer, and GameController then reports none: a held icon would not move.
    /// The drag's own travel stands in, only while GameController is silent. In points, so about doubled.
    private func dragged(_ dx: CGFloat, _ dy: CGFloat) {
        guard !(follow && pointerAt != nil), Date().timeIntervalSince(lastRawMove) > 0.15 else { return }
        if movesLogged < 8 {
            movesLogged += 1
            HengeLog.log("input", "physical mouse: held motion taken from the pointer's drag (\(dx), \(dy))")
        }
        moved(Float(dx) * 2, Float(-dy) * 2)
    }

    private func button(_ physicalButton: Int32, _ pressed: Bool) {
        // The system's pointer is over something of the app's own (the drawn keyboard, a control): the click is for that.
        if pressed, follow, pointerAt != nil, !screen.isNull, !overScreen {
            swallowed.insert(physicalButton)
            if buttonsLogged < 32 {
                buttonsLogged += 1
                HengeLog.log("input", "physical mouse button: raw=\(physicalButton) down off the Mac's screen, kept from the Mac")
            }
            return
        }
        if !pressed, swallowed.remove(physicalButton) != nil { return }
        if pressed { forwarded.insert(physicalButton) } else { forwarded.remove(physicalButton) }
        guard let guestButton = buttons.event(physicalButton, pressed: pressed) else { return }
        if buttonsLogged < 32 {
            buttonsLogged += 1
            HengeLog.log("input", "physical mouse button: raw=\(physicalButton) guest=\(guestButton) \(pressed ? "down" : "up")")
        }
        // While the Mac's pointer follows the system's, the button is that same pointing device's: the click is
        // then exactly where the pointer was put. From the Mac's other mouse, the pointer jumped at a click.
        if pressed, follow, let p = pointerAt, overScreen {
            placed(p)
            onPointer.insert(guestButton)
            henge_vm_mouse_at_button(guestButton, 1)
        } else if !pressed, onPointer.remove(guestButton) != nil {
            henge_vm_mouse_at_button(guestButton, 0)
        } else {
            henge_vm_mouse_button(guestButton, pressed ? 1 : 0)
        }
        if !pressed { StickyKeys.shared.releaseAll() }
    }

    /// GameController puts vertical motion on the first axis and horizontal on the second.
    /// macOS accelerates wheel units roughly quadratically, so use a tunable square root
    /// and cap each event to keep a small pad gesture from jumping across a page.
    private func scrolled(_ first: Float, _ second: Float) {
        // GameController reports both axis states when either one changes. On a
        // Magic Keyboard it calls us twice per movement, with one stale axis in
        // each call; sending both values doubles the scroll and adds sideways drift.
        let verticalChanged = first != lastScrollFirst
        let horizontalChanged = second != lastScrollSecond
        lastScrollFirst = first
        lastScrollSecond = second
        let mostlyVertical = abs(first) > 2 * abs(second)
        let mostlyHorizontal = abs(second) > 2 * abs(first)
        let verticalRaw = verticalChanged && !mostlyHorizontal ? -first : 0
        let horizontalRaw = horizontalChanged && !mostlyVertical ? second : 0
        let defaults = UserDefaults.standard
        let configured = defaults.object(forKey: Self.scrollSpeedKey) == nil
            ? 0.3 : defaults.double(forKey: Self.scrollSpeedKey)
        let scale = Float(configured.isFinite ? min(max(configured, 0.1), 1.5) : 0.3)
        let way: Int32 = reverse ? -1 : 1
        let horizontal = way * Self.wheelUnits(horizontalRaw, scale: scale)
        let vertical = way * Self.wheelUnits(verticalRaw, scale: scale)
        if scrollsLogged < 24 {
            scrollsLogged += 1
            HengeLog.log("input", "scroll raw: \(first), \(second); units: \(horizontal), \(vertical)")
        }
        if horizontal != 0 || vertical != 0 { henge_vm_mouse_scroll(horizontal, vertical) }
    }

    private static func wheelUnits(_ value: Float, scale: Float) -> Int32 {
        guard value.isFinite else { return 0 }
        let units = Int32(min(32, (22 * scale * abs(value).squareRoot()).rounded()))
        return value < 0 ? -units : units
    }
}

/// Follows a drag made with the system's pointer (a mouse button held), anywhere in the app's windows,
/// without taking it from the views under it.
final class PointerDrag: NSObject, UIGestureRecognizerDelegate {
    var moved: ((CGFloat, CGFloat) -> Void)?
    /// Where the pointer is, in the window, whether or not a button is held.
    var placed: ((CGPoint) -> Void)?
    private var recognizers: [UIGestureRecognizer] = []

    func install() {
        remove()
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            recognizers.append(pan)
            // A press says where it is from the moment it starts, and at every move: a pan only once it has travelled.
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0
            press.allowableMovement = .greatestFiniteMagnitude
            press.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            press.delegate = self
            window.addGestureRecognizer(press)
            recognizers.append(press)
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
            hover.cancelsTouchesInView = false
            hover.delegate = self
            window.addGestureRecognizer(hover)
            recognizers.append(hover)
        }
    }

    func remove() {
        for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizers.removeAll()
    }

    @objc private func hovered(_ hover: UIHoverGestureRecognizer) {
        guard hover.state == .began || hover.state == .changed, let view = hover.view else { return }
        placed?(hover.location(in: view))
    }

    @objc private func pressed(_ press: UILongPressGestureRecognizer) {
        guard let view = press.view else { return }
        placed?(press.location(in: view))
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        if pan.state == .began || pan.state == .changed { placed?(pan.location(in: view)) }
        guard pan.state == .changed else { return }
        let travel = pan.translation(in: view)
        pan.setTranslation(.zero, in: view)
        if travel != .zero { moved?(travel.x, travel.y) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
