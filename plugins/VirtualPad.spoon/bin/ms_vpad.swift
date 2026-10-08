import CoreHID
import Foundation
import IOKit.hid

let virtualSerial = "ms-vpad"

let outQueue = DispatchQueue(label: "ms_vpad.out")

let socketPath: String? = {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--socket"), i + 1 < args.count else { return nil }
    return args[i + 1]
}()

let buildStamp: Double = {
    let attrs = try? FileManager.default.attributesOfItem(atPath: CommandLine.arguments[0])
    return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
}()

var clientFD: Int32 = -1

func emit(_ obj: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    data.append(0x0A)
    outQueue.async {
        if socketPath == nil {
            FileHandle.standardOutput.write(data)
        } else if clientFD >= 0 {
            data.withUnsafeBytes { buf in
                var off = 0
                while off < buf.count {
                    let n = write(clientFD, buf.baseAddress! + off, buf.count - off)
                    if n <= 0 { break }
                    off += n
                }
            }
        }
    }
}

// Socket Server //
    func socketAddress(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            let bytes = Array(path.utf8.prefix(dst.count - 1))
            dst.copyBytes(from: bytes)
        }
        return addr
    }

    func withSockaddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) } }
    }

    func claimSocket(_ path: String) -> Int32 {
        var addr = socketAddress(path)
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        let alive = withSockaddr(&addr) { connect(probe, $0, $1) } == 0
        close(probe)
        if alive { exit(0) }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withSockaddr(&addr, { bind(fd, $0, $1) }) == 0, listen(fd, 4) == 0 else { exit(1) }
        return fd
    }

    let listenFD: Int32 = socketPath.map { claimSocket($0) } ?? -1
// END Socket Server //

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

    func twinPID(vid: Int, pid: Int) -> Int? {
        guard vid == 0x054C else { return nil }
        let twins: [Int: Int] = [
            0x05C4: 0x09CC,
            0x09CC: 0x05C4,
            0x0CE6: 0x0DF2,
            0x0DF2: 0x0CE6,
        ]
        return twins[pid]
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

// Real Pad Hiding //
    let ignoreKeys = [
        "SDL_GAMECONTROLLER_IGNORE_DEVICES",
        "SDL_HIDAPI_IGNORE_DEVICES",
    ]

    func launchctl(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }

    func hideReal(vid: Int, pid: Int) {
        guard twinPID(vid: vid, pid: pid) != nil else { return }
        let entry = String(format: "0x%04x/0x%04x", vid, pid)
        for key in ignoreKeys { launchctl(["setenv", key, entry]) }
    }

    func unhideReal() {
        for key in ignoreKeys { launchctl(["unsetenv", key]) }
    }

    func shutdown() -> Never {
        unhideReal()
        if let path = socketPath { unlink(path) }
        exit(0)
    }
// END Real Pad Hiding //

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

    func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var c: UInt32 = 0xFFFFFFFF
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB88320 : c >> 1 }
        }
        return ~c
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
        var real: IOHIDDevice?

        func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType, id: HIDReportID?, data: Data) throws {
            let t: IOHIDReportType = type == .feature ? kIOHIDReportTypeFeature : kIOHIDReportTypeOutput
            let rid = CFIndex(id?.rawValue ?? 0)
            data.withUnsafeBytes { raw in
                guard let p = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                guard let real = self.real else { return }
                _ = IOHIDDeviceSetReport(real, t, rid, p, data.count)
            }
        }

        func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType, id: HIDReportID?, maxSize: size_t) throws -> Data {
            let t: IOHIDReportType = type == .feature ? kIOHIDReportTypeFeature : (type == .input ? kIOHIDReportTypeInput : kIOHIDReportTypeOutput)
            guard let real = self.real else { return Data() }
            var buf = [UInt8](repeating: 0, count: max(maxSize, 1))
            var len = CFIndex(buf.count)
            let rid = CFIndex(id?.rawValue ?? 0)
            let r = IOHIDDeviceGetReport(real, t, rid, &buf, &len)
            if r != kIOReturnSuccess { return Data() }
            return Data(buf.prefix(Int(len)))
        }
    }

    struct Identity: Codable, Equatable {
        var descriptor: Data
        var vid: Int
        var pid: Int
        var name: String
        var maker: String?
        var version: Int
        var bluetooth: Bool
        var reportSize: Int

        init(descriptor: Data, vid: Int, pid: Int, name: String, maker: String?, version: Int, bluetooth: Bool, reportSize: Int) {
            self.descriptor = descriptor
            self.vid = vid
            self.pid = pid
            self.name = name
            self.maker = maker
            self.version = version
            self.bluetooth = bluetooth
            self.reportSize = reportSize
        }

        init?(real: IOHIDDevice) {
            guard let desc = IOHIDDeviceGetProperty(real, kIOHIDReportDescriptorKey as CFString) as? Data else { return nil }
            descriptor = desc
            vid = (IOHIDDeviceGetProperty(real, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            pid = (IOHIDDeviceGetProperty(real, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            name = (IOHIDDeviceGetProperty(real, kIOHIDProductKey as CFString) as? String) ?? "Controller"
            maker = IOHIDDeviceGetProperty(real, kIOHIDManufacturerKey as CFString) as? String
            version = (IOHIDDeviceGetProperty(real, kIOHIDVersionNumberKey as CFString) as? Int) ?? 0
            bluetooth = (IOHIDDeviceGetProperty(real, kIOHIDTransportKey as CFString) as? String ?? "").lowercased().contains("bluetooth")
            reportSize = max((IOHIDDeviceGetProperty(real, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64, 1)
        }

        func sameController(_ o: Identity) -> Bool {
            descriptor == o.descriptor && vid == o.vid && pid == o.pid
        }
    }

    let cachePath: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--cache"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    func loadIdentity() -> Identity? {
        guard let path = cachePath, let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(Identity.self, from: data)
    }

    func saveIdentity(_ id: Identity) {
        guard let path = cachePath, let data = try? JSONEncoder().encode(id) else { return }
        FileManager.default.createFile(atPath: path, contents: data)
    }

    final class Pad {
        var real: IOHIDDevice?
        let ident: Identity
        let fam: Family
        let fields: [Field]
        let usesIDs: Bool
        var device: HIDVirtualDevice?
        var delegate: Delegate?
        var last: [UInt8: [UInt8]] = [:]
        var fullLast: [UInt8]?
        var buttons: Set<String> = []
        var owned: Set<String> = []
        var axes: [String: Double] = [:]
        var reportBuf: UnsafeMutablePointer<UInt8>
        let reportSize: Int
        var queue: AsyncStream<Data>.Continuation?
        let ctype: String
        var physButtons: Set<String> = []
        var physAxes: [String: Double] = [:]
        var padRIDs: Set<UInt8> = []
        var simpleLen = 0
        var emittedAt: [String: UInt64] = [:]
        var pendingEv: [String: [String: Any]] = [:]

        init?(ident id: Identity) {
            ident = id
            reportSize = id.reportSize
            reportBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
            fam = family(vid: id.vid)
            ctype = fam == .xbox ? "xbox" : (fam == .sony ? "ds4" : "generic")
            let parsed = parseInputFields([UInt8](id.descriptor))
            fields = parsed.fields
            usesIDs = parsed.usesIDs
            padRIDs = Set(fields.filter { $0.page == 0x01 || $0.page == 0x09 }.map { $0.reportID })
            let props = HIDVirtualDevice.Properties(
                descriptor: id.descriptor,
                vendorID: UInt32(id.vid),
                productID: UInt32(twinPID(vid: id.vid, pid: id.pid) ?? id.pid),
                transport: id.bluetooth ? .bluetooth : .usb,
                product: id.name,
                manufacturer: id.maker,
                versionNumber: UInt64(id.version),
                serialNumber: virtualSerial
            )
            guard let dev = HIDVirtualDevice(properties: props) else {
                emit(["e": "error", "m": "virtual device refused (entitlement or AMFI)"])
                return nil
            }
            device = dev
            hideReal(vid: id.vid, pid: id.pid)
            if fam == .sony && usesIDs && padRIDs.contains(1) {
                simpleLen = neutral(for: 1).count
            }
            let del = Delegate()
            delegate = del
            let (stream, cont) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(2))
            queue = cont
            Task {
                await dev.activate(delegate: del)
                for await report in stream {
                    try? await dev.dispatchInputReport(data: report, timestamp: SuspendingClock.now)
                }
            }
            emit(["e": "virtual", "name": id.name])
        }

        func bind(_ d: IOHIDDevice) {
            real = d
            delegate?.real = d
            emit(["e": "ready", "name": ident.name, "vid": ident.vid, "pid": ident.pid])
            emit(["e": "pad", "ev": ["e": "connect", "c": ctype, "p": 1]])
        }

        func unbind() {
            real = nil
            delegate?.real = nil
            last = [:]
            fullLast = nil
            physButtons = []
            physAxes = [:]
            resend()
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
                    for name in owned where buttonUsage(name, fam) == f.usage {
                        writeBits(&out, at, f.size, buttons.contains(name) ? 1 : 0)
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
                    for name in ["l2", "r2"] where owned.contains(name) && axes[name] == nil {
                        if axisUsages(name, fam).contains(where: { $0.0 == f.page && $0.1 == f.usage }) {
                            writeBits(&out, at, f.size, buttons.contains(name) ? f.max : f.min)
                        }
                    }
                }
            }
            return out
        }

        func send(_ rid: UInt8) {
            if rid == 0x01, let full = fullLast {
                queue?.yield(Data(patchFull(full)))
                return
            }
            let base = last[rid] ?? neutral(for: rid)
            queue?.yield(Data(patch(base)))
        }

        func resend() {
            for rid in padRIDs { send(rid) }
        }

        func throttled(_ key: String, _ ev: [String: Any]) {
            let gap: UInt64 = 8_000_000
            let now = DispatchTime.now().uptimeNanoseconds
            let since = now - (emittedAt[key] ?? 0)
            if pendingEv[key] == nil && since >= gap {
                emittedAt[key] = now
                physical(ev)
                return
            }
            let first = pendingEv[key] == nil
            pendingEv[key] = ev
            guard first else { return }
            let wait = since >= gap ? 0 : gap - since
            DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(wait))) { [weak self] in
                guard let self, let e = self.pendingEv.removeValue(forKey: key) else { return }
                self.emittedAt[key] = DispatchTime.now().uptimeNanoseconds
                self.physical(e)
            }
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
            for n in physButtons.subtracting(pressed) {
                if !buttons.contains(n) { owned.remove(n) }
                physical(["e": "release", "b": n])
            }
            physButtons = pressed
            func dz(_ v: Double) -> Double { abs(v) < 0.05 ? 0 : v }
            for side in ["l", "r"] {
                guard let x = axes[side + "x"], let y = axes[side + "y"] else { continue }
                let ox = physAxes[side + "x"] ?? 9
                let oy = physAxes[side + "y"] ?? 9
                if abs(x - ox) > 0.01 || abs(y - oy) > 0.01 {
                    physAxes[side + "x"] = x
                    physAxes[side + "y"] = y
                    let b = side == "l" ? "left" : "right"
                    throttled(b, ["e": "move", "b": b, "x": dz(x), "y": dz(-y)])
                }
            }
            for t in ["l2", "r2"] {
                guard let v = axes[t] else { continue }
                if abs(v - (physAxes[t] ?? 9)) > 0.01 {
                    physAxes[t] = v
                    throttled(t, ["e": "trigger", "b": t, "v": v])
                }
            }
        }

        func normalize(_ report: [UInt8]) -> [UInt8] {
            guard simpleLen > 1, report.first == 0x11, report.count >= simpleLen + 2 else { return report }
            return [0x01] + Array(report[3..<(simpleLen + 2)])
        }

        func patchFull(_ full: [UInt8]) -> [UInt8] {
            var out = full
            let simple = patch(normalize(full))
            out.replaceSubrange(3..<(simpleLen + 2), with: simple[1...])
            if out.count >= 78 {
                let n = out.count - 4
                let crc = crc32([0xA1] + out[0..<n])
                for k in 0..<4 { out[n + k] = UInt8((crc >> (8 * UInt32(k))) & 0xFF) }
            }
            return out
        }

        func onReal(_ raw: [UInt8]) {
            let report = normalize(raw)
            let rid: UInt8 = usesIDs ? (report.first ?? 0) : 0
            guard padRIDs.contains(rid) else {
                queue?.yield(Data(report))
                return
            }
            last[rid] = report
            if report.count != raw.count {
                fullLast = raw
                queue?.yield(Data(patchFull(raw)))
            } else {
                queue?.yield(Data(patch(report)))
            }
            decode(report)
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
        guard let p = pad, p.real != nil else { return }
        p.onReal(Array(UnsafeBufferPointer(start: report, count: length)))
    }

    func attach(_ d: IOHIDDevice) {
        guard pad?.real == nil, !isVirtual(d) else { return }
        guard let id = Identity(real: d) else { return }
        guard IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess else {
            emit(["e": "error", "m": "could not seize controller"])
            return
        }
        if let p = pad, !p.ident.sameController(id) { pad = nil }
        if pad == nil { pad = Pad(ident: id) }
        guard let p = pad else {
            IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }
        saveIdentity(id)
        p.bind(d)
        IOHIDDeviceRegisterInputReportCallback(d, p.reportBuf, p.reportSize, inputCallback, nil)
        p.resend()
    }

    func detach(_ d: IOHIDDevice) {
        guard let p = pad, p.real == d else { return }
        p.unbind()
        emit(["e": "pad", "ev": ["e": "disconnect", "c": p.ctype, "p": 1]])
        emit(["e": "lost"])
        if let next = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first(where: { $0 != d && !isVirtual($0) }) {
            attach(next)
        }
    }

    if let id = loadIdentity(), let p = Pad(ident: id) {
        pad = p
        p.resend()
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
        if cmd == "quit" { shutdown() }
        guard let p = pad else {
            emit(["e": "error", "m": "no controller connected"])
            return
        }
        switch cmd {
        case "btn" where parts.count == 3:
            if parts[2] == "1" {
                p.buttons.insert(parts[1])
                p.owned.insert(parts[1])
            } else {
                p.buttons.remove(parts[1])
                if p.physButtons.contains(parts[1]) { p.owned.insert(parts[1]) } else { p.owned.remove(parts[1]) }
            }
        case "axis" where parts.count == 3:
            p.axes[parts[1]] = parts[2] == "off" ? nil : Double(parts[2])
        case "reset":
            p.buttons = []
            p.owned = []
            p.axes = [:]
        default:
            return
        }
        p.resend()
    }

    func replay() {
        emit(["e": "hello", "build": buildStamp])
        guard let p = pad else {
            emit(["e": "waiting"])
            return
        }
        guard p.real != nil else {
            emit(["e": "virtual", "name": p.ident.name])
            return
        }
        emit(["e": "ready", "name": p.ident.name, "vid": p.ident.vid, "pid": p.ident.pid])
        emit(["e": "pad", "ev": ["e": "connect", "c": p.ctype, "p": 1]])
    }

    func clientGone() {
        guard let p = pad else { return }
        p.buttons = []
        p.owned = []
        p.axes = [:]
        p.resend()
    }

    var clientSource: DispatchSourceRead?
    var clientBuf = ""

    func adopt(_ c: Int32) {
        var on: Int32 = 1
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        clientSource?.cancel()
        outQueue.sync { clientFD = c }
        clientBuf = ""
        let src = DispatchSource.makeReadSource(fileDescriptor: c, queue: .main)
        src.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(c, &chunk, chunk.count)
            if n <= 0 {
                src.cancel()
                return
            }
            clientBuf += String(decoding: chunk[0..<n], as: UTF8.self)
            while let nl = clientBuf.firstIndex(of: "\n") {
                let line = String(clientBuf[..<nl])
                clientBuf = String(clientBuf[clientBuf.index(after: nl)...])
                if !line.isEmpty { handle(line) }
            }
        }
        src.setCancelHandler {
            outQueue.sync { if clientFD == c { clientFD = -1 } }
            close(c)
            if clientSource === src {
                clientSource = nil
                clientGone()
            }
        }
        clientSource = src
        src.resume()
        replay()
    }

    var stopSources: [DispatchSourceSignal] = []
    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        s.setEventHandler { shutdown() }
        s.resume()
        stopSources.append(s)
    }

    if listenFD >= 0 {
        signal(SIGPIPE, SIG_IGN)
        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
        acceptSource.setEventHandler {
            let c = accept(listenFD, nil, nil)
            if c >= 0 { adopt(c) }
        }
        acceptSource.resume()
        withExtendedLifetime(acceptSource) { RunLoop.main.run() }
    } else {
        FileHandle.standardInput.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { shutdown() }
            guard let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                for line in text.split(separator: "\n") { handle(String(line)) }
            }
        }
        emit(["e": "waiting"])
        RunLoop.main.run()
    }
// END Command Input //
