import CoreHID
import Foundation
import IOKit.hid

let virtualSerial = "ms-vpad"

let outQueue = DispatchQueue(label: "ms_vpad.out")

func emit(_ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    data.append(0x0A)
    outQueue.async { FileHandle.standardOutput.write(data) }
}

// Descriptor Parser //
    struct Field {
        var reportID: UInt8
        var bitOffset: Int
        var size: Int
        var page: UInt32
        var usage: UInt32
        var min: Int
        var max: Int
    }

    func parseInputFields(_ d: [UInt8]) -> (fields: [Field], usesIDs: Bool) {
        var fields: [Field] = []
        var page: UInt32 = 0
        var lmin = 0
        var lmax = 0
        var size = 0
        var count = 0
        var reportID: UInt8 = 0
        var usesIDs = false
        var usages: [UInt32] = []
        var umin: UInt32? = nil
        var umax: UInt32? = nil
        var offsets: [UInt8: Int] = [:]
        var stack: [(UInt32, Int, Int, Int, Int)] = []
        var i = 0
        while i < d.count {
            let prefix = d[i]
            if prefix == 0xFE {
                i += 3 + (i + 1 < d.count ? Int(d[i + 1]) : 0)
                continue
            }
            let sizeCode = Int(prefix & 0x03)
            let n = sizeCode == 3 ? 4 : sizeCode
            let tag = prefix & 0xFC
            var u: UInt32 = 0
            for k in 0..<n where i + 1 + k < d.count {
                u |= UInt32(d[i + 1 + k]) << (8 * k)
            }
            var s = Int(u)
            if n == 1 { s = Int(Int8(bitPattern: UInt8(u & 0xFF))) }
            if n == 2 { s = Int(Int16(bitPattern: UInt16(u & 0xFFFF))) }
            if n == 4 { s = Int(Int32(bitPattern: u)) }
            switch tag {
            case 0x04: page = u
            case 0x14: lmin = s
            case 0x24: lmax = (lmin >= 0 && n < 4) ? Int(u) : s
            case 0x74: size = Int(u)
            case 0x94: count = Int(u)
            case 0x84:
                reportID = UInt8(u & 0xFF)
                usesIDs = true
            case 0xA4: stack.append((page, lmin, lmax, size, count))
            case 0xB4:
                if let top = stack.popLast() {
                    (page, lmin, lmax, size, count) = top
                }
            case 0x08: usages.append(n == 4 ? u : (page << 16) | u)
            case 0x18: umin = n == 4 ? u : (page << 16) | u
            case 0x28: umax = n == 4 ? u : (page << 16) | u
            case 0x80:
                let isConst = (u & 0x01) != 0
                let isVar = (u & 0x02) != 0
                var off = offsets[reportID] ?? 0
                if !isConst && isVar {
                    var list = usages
                    if let a = umin, let b = umax, b >= a {
                        list = Array(a...b)
                    }
                    for k in 0..<count {
                        let full = list.isEmpty ? 0 : list[min(k, list.count - 1)]
                        fields.append(Field(
                            reportID: reportID,
                            bitOffset: off + k * size,
                            size: size,
                            page: full >> 16,
                            usage: full & 0xFFFF,
                            min: lmin,
                            max: lmax
                        ))
                    }
                }
                off += size * count
                offsets[reportID] = off
                usages = []
                umin = nil
                umax = nil
            case 0x90, 0xB0, 0xA0, 0xC0:
                usages = []
                umin = nil
                umax = nil
            default: break
            }
            i += 1 + n
        }
        return (fields, usesIDs)
    }
// END Descriptor Parser //

// Name Map //
    enum Family { case xbox, sony, generic }

    func family(vid: Int) -> Family {
        if vid == 0x045E { return .xbox }
        if vid == 0x054C { return .sony }
        return .generic
    }

    func buttonUsage(_ name: String, _ f: Family) -> UInt32? {
        let xbox: [String: UInt32] = [
            "a": 1, "b": 2, "x": 4, "y": 5, "l1": 7, "r1": 8,
            "options": 11, "menu": 12, "home": 13, "l3": 14, "r3": 15,
        ]
        let sony: [String: UInt32] = [
            "x": 1, "a": 2, "b": 3, "y": 4, "l1": 5, "r1": 6,
            "l2": 7, "r2": 8, "options": 9, "menu": 10, "l3": 11, "r3": 12, "home": 13,
        ]
        let generic: [String: UInt32] = [
            "a": 1, "b": 2, "x": 3, "y": 4, "l1": 5, "r1": 6,
            "l2": 7, "r2": 8, "options": 9, "menu": 10, "l3": 11, "r3": 12, "home": 13,
        ]
        switch f {
        case .xbox: return xbox[name]
        case .sony: return sony[name]
        case .generic: return generic[name]
        }
    }

    func axisUsages(_ name: String, _ f: Family) -> [(UInt32, UInt32)] {
        switch name {
        case "lx": return [(0x01, 0x30)]
        case "ly": return [(0x01, 0x31)]
        case "rx": return [(0x01, 0x32)]
        case "ry": return [(0x01, 0x35)]
        case "l2": return f == .xbox ? [(0x02, 0xC5), (0x01, 0x33)] : [(0x01, 0x33)]
        case "r2": return f == .xbox ? [(0x02, 0xC4), (0x01, 0x34)] : [(0x01, 0x34)]
        default: return []
        }
    }
// END Name Map //

// Report Patching //
    func writeBits(_ buf: inout [UInt8], _ bitOffset: Int, _ size: Int, _ value: Int) {
        let v = UInt64(bitPattern: Int64(value))
        for b in 0..<size {
            let bit = bitOffset + b
            let idx = bit / 8
            guard idx < buf.count else { return }
            let mask = UInt8(1 << (bit % 8))
            if (v >> UInt64(b)) & 1 == 1 { buf[idx] |= mask } else { buf[idx] &= ~mask }
        }
    }

    func readBits(_ buf: [UInt8], _ bitOffset: Int, _ size: Int) -> Int {
        var v = 0
        for b in 0..<size {
            let bit = bitOffset + b
            let idx = bit / 8
            guard idx < buf.count else { break }
            if (buf[idx] >> UInt8(bit % 8)) & 1 == 1 { v |= 1 << b }
        }
        return v
    }

    func hatDirs(_ raw: Int, f: Field) -> (Bool, Bool, Bool, Bool) {
        let steps = f.max - f.min + 1
        let idx = raw - f.min
        guard idx >= 0, idx < steps else { return (false, false, false, false) }
        let oct = steps >= 8 ? idx : idx * 2
        let up = oct == 7 || oct == 0 || oct == 1
        let right = oct >= 1 && oct <= 3
        let down = oct >= 3 && oct <= 5
        let left = oct >= 5 && oct <= 7
        return (up, down, left, right)
    }

    func signed(_ raw: Int, _ f: Field) -> Int {
        guard f.min < 0, f.size < 64, raw >= (1 << (f.size - 1)) else { return raw }
        return raw - (1 << f.size)
    }

    func hatValue(up: Bool, down: Bool, left: Bool, right: Bool, f: Field) -> Int? {
        let dirs: [(Bool, Bool, Bool, Bool)] = [
            (true, false, false, false), (true, false, false, true),
            (false, false, false, true), (false, true, false, true),
            (false, true, false, false), (false, true, true, false),
            (false, false, true, false), (true, false, true, false),
        ]
        guard let idx = dirs.firstIndex(where: { $0 == (up, down, left, right) }) else { return nil }
        let steps = f.max - f.min + 1
        if steps >= 8 { return f.min + idx }
        return f.min + idx / 2
    }
// END Report Patching //

// Virtual Pad //
    final class Delegate: HIDVirtualDeviceDelegate, @unchecked Sendable {
        let real: IOHIDDevice
        init(real: IOHIDDevice) { self.real = real }

        func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType, id: HIDReportID?, data: Data) throws {
            let t: IOHIDReportType = type == .feature ? kIOHIDReportTypeFeature : kIOHIDReportTypeOutput
            let rid = CFIndex(id?.rawValue ?? 0)
            data.withUnsafeBytes { raw in
                guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                _ = IOHIDDeviceSetReport(real, t, rid, p, data.count)
            }
        }

        func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType, id: HIDReportID?, maxSize: size_t) throws -> Data {
            let t: IOHIDReportType = type == .feature ? kIOHIDReportTypeFeature : (type == .input ? kIOHIDReportTypeInput : kIOHIDReportTypeOutput)
            var buf = [UInt8](repeating: 0, count: max(maxSize, 1))
            var len = CFIndex(buf.count)
            let rid = CFIndex(id?.rawValue ?? 0)
            let r = IOHIDDeviceGetReport(real, t, rid, &buf, &len)
            if r != kIOReturnSuccess { return Data() }
            return Data(buf.prefix(Int(len)))
        }
    }

    final class Pad {
        let real: IOHIDDevice
        let fam: Family
        let fields: [Field]
        let usesIDs: Bool
        var device: HIDVirtualDevice?
        var delegate: Delegate?
        var last: [UInt8: [UInt8]] = [:]
        var buttons: Set<String> = []
        var axes: [String: Double] = [:]
        var reportBuf: UnsafeMutablePointer<UInt8>
        let reportSize: Int
        var queue: AsyncStream<Data>.Continuation?
        let ctype: String
        var physButtons: Set<String> = []
        var physAxes: [String: Double] = [:]

        init?(real: IOHIDDevice) {
            self.real = real
            guard let desc = IOHIDDeviceGetProperty(real, kIOHIDReportDescriptorKey as CFString) as? Data else { return nil }
            let vid = (IOHIDDeviceGetProperty(real, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let pid = (IOHIDDeviceGetProperty(real, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            let name = (IOHIDDeviceGetProperty(real, kIOHIDProductKey as CFString) as? String) ?? "Controller"
            let maker = IOHIDDeviceGetProperty(real, kIOHIDManufacturerKey as CFString) as? String
            let version = (IOHIDDeviceGetProperty(real, kIOHIDVersionNumberKey as CFString) as? Int) ?? 0
            let transportName = (IOHIDDeviceGetProperty(real, kIOHIDTransportKey as CFString) as? String ?? "").lowercased()
            reportSize = max((IOHIDDeviceGetProperty(real, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 1)
            reportBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
            fam = family(vid: vid)
            ctype = fam == .xbox ? "xbox" : (fam == .sony ? "ds4" : "generic")
            let parsed = parseInputFields([UInt8](desc))
            fields = parsed.fields
            usesIDs = parsed.usesIDs
            let transport: HIDDeviceTransport = transportName.contains("bluetooth") ? .bluetooth : .usb
            let props = HIDVirtualDevice.Properties(
                descriptor: desc,
                vendorID: UInt32(vid),
                productID: UInt32(pid),
                transport: transport,
                product: name,
                manufacturer: maker,
                versionNumber: UInt64(version),
                serialNumber: virtualSerial
            )
            guard let dev = HIDVirtualDevice(properties: props) else {
                emit(["e": "error", "m": "virtual device refused (entitlement or AMFI)"])
                return nil
            }
            device = dev
            let del = Delegate(real: real)
            delegate = del
            let (stream, cont) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(2))
            queue = cont
            Task {
                await dev.activate(delegate: del)
                for await report in stream {
                    try? await dev.dispatchInputReport(data: report, timestamp: SuspendingClock.now)
                }
            }
            emit(["e": "ready", "name": name, "vid": vid, "pid": pid])
            emit(["e": "pad", "ev": ["e": "connect", "c": ctype, "p": 1]])
        }

        deinit {
            queue?.finish()
            reportBuf.deallocate()
        }

        func neutral(for rid: UInt8) -> [UInt8] {
            let bytes = ((fields.filter { $0.reportID == rid }.map { $0.bitOffset + $0.size }.max() ?? 0) + 7) / 8
            var body = [UInt8](repeating: 0, count: max(bytes, 1))
            for f in fields where f.reportID == rid {
                if f.page == 0x01 && f.usage == 0x39 {
                    writeBits(&body, f.bitOffset, f.size, f.max + 1)
                } else if f.page == 0x01 && (0x30...0x35).contains(f.usage) && f.usage != 0x33 && f.usage != 0x34 {
                    writeBits(&body, f.bitOffset, f.size, (f.min + f.max) / 2)
                }
            }
            return usesIDs ? [rid] + body : body
        }

        func patch(_ report: [UInt8]) -> [UInt8] {
            var out = report
            let rid: UInt8 = usesIDs ? (report.first ?? 0) : 0
            let base = usesIDs ? 8 : 0
            for f in fields where f.reportID == rid {
                let at = base + f.bitOffset
                if f.page == 0x09 {
                    for name in buttons where buttonUsage(name, fam) == f.usage {
                        writeBits(&out, at, f.size, 1)
                    }
                } else if f.page == 0x01 && f.usage == 0x39 {
                    let dirs = ["up", "down", "left", "right"].map { buttons.contains($0) }
                    if dirs.contains(true), let v = hatValue(up: dirs[0], down: dirs[1], left: dirs[2], right: dirs[3], f: f) {
                        writeBits(&out, at, f.size, v)
                    }
                } else {
                    for (name, value) in axes where axisUsages(name, fam).contains(where: { $0.0 == f.page && $0.1 == f.usage }) {
                        let isTrigger = name == "l2" || name == "r2"
                        let t = isTrigger ? max(0, min(1, value)) : (max(-1, min(1, value)) + 1) / 2
                        let v = f.min + Int((Double(f.max - f.min) * t).rounded())
                        writeBits(&out, at, f.size, v)
                    }
                    for name in ["l2", "r2"] where buttons.contains(name) && axes[name] == nil {
                        if axisUsages(name, fam).contains(where: { $0.0 == f.page && $0.1 == f.usage }) {
                            writeBits(&out, at, f.size, f.max)
                        }
                    }
                }
            }
            return out
        }

        func send(_ rid: UInt8) {
            let base = last[rid] ?? neutral(for: rid)
            queue?.yield(Data(patch(base)))
        }

        func resend() {
            let ids = Set(fields.map { $0.reportID })
            for rid in ids { send(rid) }
        }

        func physical(_ ev: [String: Any]) {
            var e = ev
            e["c"] = ctype
            e["p"] = 1
            emit(["e": "pad", "ev": e])
        }

        func decode(_ report: [UInt8]) {
            let rid: UInt8 = usesIDs ? (report.first ?? 0) : 0
            let base = usesIDs ? 8 : 0
            var pressed: Set<String> = []
            var axes: [String: Double] = [:]
            var touched = false
            let names = ["a", "b", "x", "y", "l1", "r1", "l2", "r2", "l3", "r3", "menu", "options", "home"]
            for f in fields where f.reportID == rid {
                touched = true
                let raw = signed(readBits(report, base + f.bitOffset, f.size), f)
                if f.page == 0x09 {
                    if raw != 0, let n = names.first(where: { buttonUsage($0, fam) == f.usage }) { pressed.insert(n) }
                } else if f.page == 0x01 && f.usage == 0x39 {
                    let d = hatDirs(raw, f: f)
                    if d.0 { pressed.insert("up") }
                    if d.1 { pressed.insert("down") }
                    if d.2 { pressed.insert("left") }
                    if d.3 { pressed.insert("right") }
                } else {
                    for name in ["lx", "ly", "rx", "ry", "l2", "r2"] where axisUsages(name, fam).contains(where: { $0.0 == f.page && $0.1 == f.usage }) {
                        let span = Double(max(f.max - f.min, 1))
                        let t = Double(raw - f.min) / span
                        axes[name] = (name == "l2" || name == "r2") ? t : t * 2 - 1
                    }
                }
            }
            guard touched else { return }
            for (name, v) in axes where name == "l2" || name == "r2" {
                if v > 0.5 { pressed.insert(name) }
            }
            for n in pressed.subtracting(physButtons) { physical(["e": "press", "b": n]) }
            for n in physButtons.subtracting(pressed) { physical(["e": "release", "b": n]) }
            physButtons = pressed
            func dz(_ v: Double) -> Double { abs(v) < 0.05 ? 0 : v }
            for side in ["l", "r"] {
                guard let x = axes[side + "x"], let y = axes[side + "y"] else { continue }
                let ox = physAxes[side + "x"] ?? 9
                let oy = physAxes[side + "y"] ?? 9
                if abs(x - ox) > 0.01 || abs(y - oy) > 0.01 {
                    physAxes[side + "x"] = x
                    physAxes[side + "y"] = y
                    physical(["e": "move", "b": side == "l" ? "left" : "right", "x": dz(x), "y": dz(-y)])
                }
            }
            for t in ["l2", "r2"] {
                guard let v = axes[t] else { continue }
                if abs(v - (physAxes[t] ?? 9)) > 0.01 {
                    physAxes[t] = v
                    physical(["e": "trigger", "b": t, "v": v])
                }
            }
        }

        func onReal(_ report: [UInt8]) {
            let rid: UInt8 = usesIDs ? (report.first ?? 0) : 0
            last[rid] = report
            decode(report)
            queue?.yield(Data(patch(report)))
        }
    }
// END Virtual Pad //

// Physical Pad Tracking //
    var pad: Pad?
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    func isVirtual(_ d: IOHIDDevice) -> Bool {
        (IOHIDDeviceGetProperty(d, kIOHIDSerialNumberKey as CFString) as? String) == virtualSerial
    }

    let inputCallback: IOHIDReportCallback = { _, _, _, _, _, report, length in
        guard let p = pad else { return }
        p.onReal(Array(UnsafeBufferPointer(start: report, count: length)))
    }

    func attach(_ d: IOHIDDevice) {
        guard pad == nil, !isVirtual(d) else { return }
        guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else {
            emit(["e": "error", "m": "could not seize controller"])
            return
        }
        guard let p = Pad(real: d) else {
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }
        pad = p
        IOHIDDeviceRegisterInputReportCallback(d, p.reportBuf, p.reportSize, inputCallback, nil)
        p.resend()
    }

    func detach(_ d: IOHIDDevice) {
        guard let p = pad, p.real == d else { return }
        pad = nil
        emit(["e": "pad", "ev": ["e": "disconnect", "c": p.ctype, "p": 1]])
        emit(["e": "lost"])
        if let next = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first(where: { $0 != d && !isVirtual($0) }) {
            attach(next)
        }
    }

    let matching: [[String: Any]] = [
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, d in attach(d) }, nil)
    IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, d in detach(d) }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
// END Physical Pad Tracking //

// Command Input //
    func handle(_ line: String) {
        let parts = line.split(separator: " ").map(String.init)
        guard let cmd = parts.first else { return }
        guard let p = pad else {
            emit(["e": "error", "m": "no controller connected"])
            return
        }
        switch cmd {
        case "btn" where parts.count == 3:
            if parts[2] == "1" { p.buttons.insert(parts[1]) } else { p.buttons.remove(parts[1]) }
        case "axis" where parts.count == 3:
            p.axes[parts[1]] = parts[2] == "off" ? nil : Double(parts[2])
        case "reset":
            p.buttons = []
            p.axes = [:]
        default:
            return
        }
        p.resend()
    }

    FileHandle.standardInput.readabilityHandler = { h in
        let data = h.availableData
        if data.isEmpty { exit(0) }
        guard let text = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            for line in text.split(separator: "\n") { handle(String(line)) }
        }
    }

    emit(["e": "waiting"])
    RunLoop.main.run()
// END Command Input //
