use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::{Arc, OnceLock};

use crate::engine::{Inject, Input};
use crate::keys::NativeMap;
use crate::protocol::Event;
use crate::{Shared, SYNTHETIC_TAG};

pub const NAME: &str = "macos";

type CFTypeRef = *const c_void;
type CGEventRef = *mut c_void;
type CFMachPortRef = *mut c_void;
type CFRunLoopRef = *mut c_void;
type CFRunLoopSourceRef = *mut c_void;
type TapCallback = extern "C" fn(*mut c_void, u32, CGEventRef, *mut c_void) -> CGEventRef;

#[repr(C)]
#[derive(Clone, Copy)]
struct CGPoint {
    x: f64,
    y: f64,
}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        mask: u64,
        cb: TapCallback,
        info: *mut c_void,
    ) -> CFMachPortRef;
    fn CGEventTapEnable(tap: CFMachPortRef, enable: bool);
    fn CGEventGetIntegerValueField(ev: CGEventRef, field: u32) -> i64;
    fn CGEventSetIntegerValueField(ev: CGEventRef, field: u32, value: i64);
    fn CGEventGetFlags(ev: CGEventRef) -> u64;
    fn CGEventSetType(ev: CGEventRef, t: u32);
    fn CGEventCreate(src: *mut c_void) -> CGEventRef;
    fn CGEventGetLocation(ev: CGEventRef) -> CGPoint;
    fn CGEventCreateKeyboardEvent(src: *mut c_void, code: u16, down: bool) -> CGEventRef;
    fn CGEventCreateMouseEvent(src: *mut c_void, t: u32, at: CGPoint, button: u32) -> CGEventRef;
    fn CGEventPost(tap: u32, ev: CGEventRef);
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    static kCFRunLoopCommonModes: CFTypeRef;
    fn CFMachPortCreateRunLoopSource(
        alloc: *const c_void,
        port: CFMachPortRef,
        order: isize,
    ) -> CFRunLoopSourceRef;
    fn CFRunLoopGetCurrent() -> CFRunLoopRef;
    fn CFRunLoopAddSource(rl: CFRunLoopRef, src: CFRunLoopSourceRef, mode: CFTypeRef);
    fn CFRunLoopRun();
    fn CFRelease(cf: CFTypeRef);
}

const LEFT_DOWN: u32 = 1;
const LEFT_UP: u32 = 2;
const RIGHT_DOWN: u32 = 3;
const RIGHT_UP: u32 = 4;
const MOUSE_MOVED: u32 = 5;
const LEFT_DRAGGED: u32 = 6;
const RIGHT_DRAGGED: u32 = 7;
const KEY_DOWN: u32 = 10;
const KEY_UP: u32 = 11;
const FLAGS_CHANGED: u32 = 12;
const SCROLL: u32 = 22;
const OTHER_DOWN: u32 = 25;
const OTHER_UP: u32 = 26;
const OTHER_DRAGGED: u32 = 27;
const TAP_DISABLED_TIMEOUT: u32 = 0xFFFF_FFFE;
const TAP_DISABLED_USER: u32 = 0xFFFF_FFFF;

const F_MOUSE_BUTTON: u32 = 3;
const F_KEYCODE: u32 = 9;
const F_SCROLL_Y: u32 = 11;
const F_USER_DATA: u32 = 42;

const SESSION_TAP: u32 = 1;
const HID_TAP: u32 = 0;
const HEAD_INSERT: u32 = 0;
const DEFAULT_OPTIONS: u32 = 0;

static SHARED: OnceLock<Arc<Shared>> = OnceLock::new();
static TAP: AtomicPtr<c_void> = AtomicPtr::new(ptr::null_mut());
static KEYMAP: OnceLock<NativeMap> = OnceLock::new();

#[rustfmt::skip]
const KEYCODES: &[(u16, &str)] = &[
    (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"), (6, "z"), (7, "x"),
    (8, "c"), (9, "v"), (11, "b"), (12, "q"), (13, "w"), (14, "e"), (15, "r"),
    (16, "y"), (17, "t"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (22, "6"),
    (23, "5"), (24, "="), (25, "9"), (26, "7"), (27, "-"), (28, "8"), (29, "0"),
    (30, "]"), (31, "o"), (32, "u"), (33, "["), (34, "i"), (35, "p"), (36, "return"),
    (37, "l"), (38, "j"), (39, "'"), (40, "k"), (41, ";"), (42, "\\"), (43, ","),
    (44, "/"), (45, "n"), (46, "m"), (47, "."), (48, "tab"), (49, "space"), (50, "`"),
    (51, "delete"), (53, "escape"), (54, "rightcmd"), (55, "cmd"), (56, "shift"),
    (57, "capslock"), (58, "alt"), (59, "ctrl"), (60, "rightshift"), (61, "rightalt"),
    (62, "rightctrl"), (63, "fn"), (64, "f17"), (65, "pad."), (67, "pad*"), (69, "pad+"),
    (71, "padclear"), (75, "pad/"), (76, "padenter"), (78, "pad-"), (79, "f18"),
    (80, "f19"), (81, "pad="), (82, "pad0"), (83, "pad1"), (84, "pad2"), (85, "pad3"),
    (86, "pad4"), (87, "pad5"), (88, "pad6"), (89, "pad7"), (90, "f20"), (91, "pad8"),
    (92, "pad9"), (96, "f5"), (97, "f6"), (98, "f7"), (99, "f3"), (100, "f8"),
    (101, "f9"), (103, "f11"), (105, "f13"), (106, "f16"), (107, "f14"), (109, "f10"),
    (111, "f12"), (113, "f15"), (114, "help"), (115, "home"), (116, "pageup"),
    (117, "forwarddelete"), (118, "f4"), (119, "end"), (120, "f2"), (121, "pagedown"),
    (122, "f1"), (123, "left"), (124, "right"), (125, "down"), (126, "up"),
];

fn keymap() -> &'static NativeMap {
    KEYMAP.get_or_init(|| NativeMap::build(KEYCODES))
}

fn modifier_flag(code: i64) -> Option<u64> {
    Some(match code {
        59 => 0x0000_0001,
        56 => 0x0000_0002,
        60 => 0x0000_0004,
        55 => 0x0000_0008,
        54 => 0x0000_0010,
        58 => 0x0000_0020,
        61 => 0x0000_0040,
        62 => 0x0000_2000,
        57 => 0x0001_0000,
        63 => 0x0080_0000,
        _ => return None,
    })
}

unsafe fn translate(etype: u32, ev: CGEventRef) -> Option<Input> {
    Some(match etype {
        KEY_DOWN | KEY_UP => {
            let code = CGEventGetIntegerValueField(ev, F_KEYCODE);
            let key = keymap().key(code as u32)?;
            Input::Key {
                key,
                down: etype == KEY_DOWN,
            }
        }
        FLAGS_CHANGED => {
            let code = CGEventGetIntegerValueField(ev, F_KEYCODE);
            let key = keymap().key(code as u32)?;
            let bit = modifier_flag(code)?;
            Input::Key {
                key,
                down: CGEventGetFlags(ev) & bit != 0,
            }
        }
        LEFT_DOWN | LEFT_UP => Input::Button {
            button: 0,
            down: etype == LEFT_DOWN,
        },
        RIGHT_DOWN | RIGHT_UP => Input::Button {
            button: 1,
            down: etype == RIGHT_DOWN,
        },
        OTHER_DOWN | OTHER_UP => Input::Button {
            button: CGEventGetIntegerValueField(ev, F_MOUSE_BUTTON).clamp(0, 31) as u8,
            down: etype == OTHER_DOWN,
        },
        SCROLL => {
            let dy = CGEventGetIntegerValueField(ev, F_SCROLL_Y);
            if dy == 0 {
                return None;
            }
            Input::Scroll { up: dy > 0 }
        }
        MOUSE_MOVED => Input::Move,
        _ => return None,
    })
}

extern "C" fn callback(_proxy: *mut c_void, etype: u32, ev: CGEventRef, _info: *mut c_void) -> CGEventRef {
    let Some(shared) = SHARED.get() else { return ev };
    if etype == TAP_DISABLED_TIMEOUT || etype == TAP_DISABLED_USER {
        let tap = TAP.load(Ordering::Acquire);
        if !tap.is_null() {
            unsafe { CGEventTapEnable(tap, true) };
            if etype == TAP_DISABLED_TIMEOUT {
                shared.emit(Event::Revived);
            }
        }
        return ev;
    }
    unsafe {
        if CGEventGetIntegerValueField(ev, F_USER_DATA) == SYNTHETIC_TAG {
            return ev;
        }
        let Some(input) = translate(etype, ev) else {
            return ev;
        };
        let v = shared.handle(input);
        if let Some(button) = v.drag {
            let (t, b) = match button {
                0 => (LEFT_DRAGGED, 0),
                1 => (RIGHT_DRAGGED, 1),
                n => (OTHER_DRAGGED, n as i64),
            };
            CGEventSetType(ev, t);
            CGEventSetIntegerValueField(ev, F_MOUSE_BUTTON, b);
        }
        inject(&v.inject);
        if v.swallow {
            ptr::null_mut()
        } else {
            ev
        }
    }
}

fn mask(types: &[u32]) -> u64 {
    types.iter().fold(0, |m, t| m | (1u64 << t))
}

pub fn run(shared: Arc<Shared>) -> Result<(), (&'static str, String)> {
    let _ = SHARED.set(Arc::clone(&shared));
    keymap();
    let m = mask(&[
        KEY_DOWN,
        KEY_UP,
        FLAGS_CHANGED,
        LEFT_DOWN,
        LEFT_UP,
        RIGHT_DOWN,
        RIGHT_UP,
        OTHER_DOWN,
        OTHER_UP,
        SCROLL,
        MOUSE_MOVED,
    ]);
    unsafe {
        let tap = CGEventTapCreate(
            SESSION_TAP,
            HEAD_INSERT,
            DEFAULT_OPTIONS,
            m,
            callback,
            ptr::null_mut(),
        );
        if tap.is_null() {
            return Err((
                "permission",
                "CGEventTapCreate failed: grant ms_layer Accessibility and Input Monitoring access".into(),
            ));
        }
        TAP.store(tap, Ordering::Release);
        let src = CFMachPortCreateRunLoopSource(ptr::null(), tap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);
        shared.ready();
        CFRunLoopRun();
    }
    Ok(())
}

pub fn inject(events: &[Inject]) {
    for e in events {
        unsafe {
            let ev = match *e {
                Inject::Key { key, down } => {
                    let Some(code) = keymap().code(key) else { continue };
                    CGEventCreateKeyboardEvent(ptr::null_mut(), code, down)
                }
                Inject::Button { button, down } => {
                    let here = CGEventCreate(ptr::null_mut());
                    let at = CGEventGetLocation(here);
                    CFRelease(here as CFTypeRef);
                    let t = match (button, down) {
                        (0, true) => LEFT_DOWN,
                        (0, false) => LEFT_UP,
                        (1, true) => RIGHT_DOWN,
                        (1, false) => RIGHT_UP,
                        (_, true) => OTHER_DOWN,
                        (_, false) => OTHER_UP,
                    };
                    CGEventCreateMouseEvent(ptr::null_mut(), t, at, button as u32)
                }
            };
            if ev.is_null() {
                continue;
            }
            CGEventSetIntegerValueField(ev, F_USER_DATA, SYNTHETIC_TAG);
            CGEventPost(HID_TAP, ev);
            CFRelease(ev as CFTypeRef);
        }
    }
}

pub fn rehook() {}
