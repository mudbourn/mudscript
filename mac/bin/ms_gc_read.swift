import Foundation
import GameController

func controllerType(_ controller: GCController) -> String {
    let v = (controller.vendorName ?? "").lowercased()
    if v.contains("dualshock") || v.contains("dualsense") || v.contains("sony") { return "ds4" }
    if v.contains("xbox") || v.contains("microsoft") { return "xbox" }
    if v.contains("switch") || v.contains("nintendo") || v.contains("pro controller") { return "switch" }
    return "generic"
}

func playerSlot(_ controller: GCController) -> Int {
    let raw = controller.playerIndex.rawValue
    return raw >= 0 ? raw : 0
}

struct ButtonTracker {
    var a = false; var b = false; var x = false; var y = false
    var l1 = false; var r1 = false; var l2 = false; var r2 = false
    var l3 = false; var r3 = false
    var up = false; var down = false; var left = false; var right = false
    var menu = false; var options = false; var home = false
    var lx: Float = 0; var ly: Float = 0
    var rx: Float = 0; var ry: Float = 0

    subscript(key: String) -> Bool {
        get {
            switch key {
            case "a": return a; case "b": return b; case "x": return x; case "y": return y
            case "l1": return l1; case "r1": return r1; case "l2": return l2; case "r2": return r2
            case "l3": return l3; case "r3": return r3
            case "up": return up; case "down": return down
            case "left": return left; case "right": return right
            case "menu": return menu; case "options": return options; case "home": return home
            default: return false
            }
        }
        set {
            switch key {
            case "a": a = newValue; case "b": b = newValue; case "x": x = newValue; case "y": y = newValue
            case "l1": l1 = newValue; case "r1": r1 = newValue; case "l2": l2 = newValue; case "r2": r2 = newValue
            case "l3": l3 = newValue; case "r3": r3 = newValue
            case "up": up = newValue; case "down": down = newValue
            case "left": left = newValue; case "right": right = newValue
            case "menu": menu = newValue; case "options": options = newValue; case "home": home = newValue
            default: break
            }
        }
    }
}

var outputLock = NSLock()

func emit(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let line = String(data: data, encoding: .utf8) else { return }
    outputLock.lock()
    print(line)
    fflush(stdout)
    outputLock.unlock()
}

var trackers: [ObjectIdentifier: ButtonTracker] = [:]

func setupController(_ controller: GCController) {
    let ctype = controllerType(controller)
    let p = playerSlot(controller)
    emit(["e": "connect", "c": ctype, "p": p])

    guard let gp = controller.extendedGamepad else { return }

    let id = ObjectIdentifier(controller)
    trackers[id] = ButtonTracker()

    gp.valueChangedHandler = { (gamepad: GCExtendedGamepad, element: GCControllerElement) in
        let tracker = trackers[id] ?? ButtonTracker()
        var t = tracker

        // Face buttons
        var buttons: [(GCControllerButtonInput, String)] = [
            (gamepad.buttonA, "a"), (gamepad.buttonB, "b"),
            (gamepad.buttonX, "x"), (gamepad.buttonY, "y"),
            (gamepad.leftShoulder, "l1"), (gamepad.rightShoulder, "r1"),
            (gamepad.leftTrigger, "l2"), (gamepad.rightTrigger, "r2"),
            (gamepad.dpad.up, "up"), (gamepad.dpad.down, "down"),
            (gamepad.dpad.left, "left"), (gamepad.dpad.right, "right"),
            (gamepad.buttonMenu, "menu"),
        ]
        if let opt = gamepad.buttonOptions { buttons.append((opt, "options")) }
        if let l3 = gamepad.leftThumbstickButton { buttons.append((l3, "l3")) }
        if let r3 = gamepad.rightThumbstickButton { buttons.append((r3, "r3")) }

        for (btn, name) in buttons {
            let pressed = btn.isPressed
            if pressed != t[name] {
                t[name] = pressed
                emit(["e": pressed ? "press" : "release", "b": name, "c": ctype, "p": p])
            }
        }

        // Analog sticks (emit on any change, 0.05 deadzone)
        let deadzone: Float = 0.05
        let lx = gamepad.leftThumbstick.xAxis.value
        let ly = gamepad.leftThumbstick.yAxis.value
        let rx = gamepad.rightThumbstick.xAxis.value
        let ry = gamepad.rightThumbstick.yAxis.value

        if abs(lx - t.lx) > 0.01 || abs(ly - t.ly) > 0.01 {
            let sx = abs(lx) < deadzone ? 0.0 : lx
            let sy = abs(ly) < deadzone ? 0.0 : ly
            t.lx = lx; t.ly = ly
            emit(["e": "move", "b": "left", "x": sx, "y": sy, "c": ctype, "p": p])
        }
        if abs(rx - t.rx) > 0.01 || abs(ry - t.ry) > 0.01 {
            let sx = abs(rx) < deadzone ? 0.0 : rx
            let sy = abs(ry) < deadzone ? 0.0 : ry
            t.rx = rx; t.ry = ry
            emit(["e": "move", "b": "right", "x": sx, "y": sy, "c": ctype, "p": p])
        }

        trackers[id] = t
    }
}

func removeController(_ controller: GCController) {
    let ctype = controllerType(controller)
    let p = playerSlot(controller)
    let id = ObjectIdentifier(controller)
    trackers.removeValue(forKey: id)
    emit(["e": "disconnect", "c": ctype, "p": p])
}

let args = CommandLine.arguments

if args.contains("--list") {
    let controllers = GCController.controllers()
    if controllers.isEmpty {
        fputs("No controllers connected.\n", stderr)
    } else {
        for (i, c) in controllers.enumerated() {
            let type = controllerType(c)
            let name = c.vendorName ?? "Unknown"
            let hasExtended = c.extendedGamepad != nil
            print("[\(i)] \(name) (\(type)) extended=\(hasExtended)")
        }
    }
    exit(0)
}

fputs("ms_gc_read: ready\n", stderr)

// Set up notifications for controller connect/disconnect.
NotificationCenter.default.addObserver(
    forName: .GCControllerDidConnect,
    object: nil,
    queue: .main
) { notification in
    if let controller = notification.object as? GCController {
        setupController(controller)
    }
}

NotificationCenter.default.addObserver(
    forName: .GCControllerDidDisconnect,
    object: nil,
    queue: .main
) { notification in
    if let controller = notification.object as? GCController {
        removeController(controller)
    }
}

// Set up any already-connected controllers.
for controller in GCController.controllers() {
    setupController(controller)
}

// Run forever.
RunLoop.main.run()
