use std::mem::size_of;
use std::ptr;
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::{Arc, OnceLock};

use windows_sys::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, INPUT_MOUSE, KEYBDINPUT, KEYEVENTF_EXTENDEDKEY,
    KEYEVENTF_KEYUP, MOUSEEVENTF_LEFTDOWN, MOUSEEVENTF_LEFTUP, MOUSEEVENTF_MIDDLEDOWN, MOUSEEVENTF_MIDDLEUP,
    MOUSEEVENTF_RIGHTDOWN, MOUSEEVENTF_RIGHTUP, MOUSEEVENTF_XDOWN, MOUSEEVENTF_XUP, MOUSEINPUT,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage, HC_ACTION,
    KBDLLHOOKSTRUCT, LLKHF_EXTENDED, MSG, MSLLHOOKSTRUCT, WH_KEYBOARD_LL, WH_MOUSE_LL, WM_KEYDOWN, WM_KEYUP,
    WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_RBUTTONDOWN,
    WM_RBUTTONUP, WM_SYSKEYDOWN, WM_SYSKEYUP, WM_XBUTTONDOWN, WM_XBUTTONUP,
};

use crate::engine::{Inject, Input};
use crate::keys::{Key, NativeMap};
use crate::{Shared, SYNTHETIC_TAG};

pub const NAME: &str = "windows";

static SHARED: OnceLock<Arc<Shared>> = OnceLock::new();
static KEYMAP: OnceLock<NativeMap> = OnceLock::new();
static KB_HOOK: AtomicPtr<core::ffi::c_void> = AtomicPtr::new(ptr::null_mut());
static MOUSE_HOOK: AtomicPtr<core::ffi::c_void> = AtomicPtr::new(ptr::null_mut());

#[rustfmt::skip]
const KEYCODES: &[(u16, &str)] = &[
    (0x41, "a"), (0x42, "b"), (0x43, "c"), (0x44, "d"), (0x45, "e"), (0x46, "f"),
    (0x47, "g"), (0x48, "h"), (0x49, "i"), (0x4A, "j"), (0x4B, "k"), (0x4C, "l"),
    (0x4D, "m"), (0x4E, "n"), (0x4F, "o"), (0x50, "p"), (0x51, "q"), (0x52, "r"),
    (0x53, "s"), (0x54, "t"), (0x55, "u"), (0x56, "v"), (0x57, "w"), (0x58, "x"),
    (0x59, "y"), (0x5A, "z"),
    (0x30, "0"), (0x31, "1"), (0x32, "2"), (0x33, "3"), (0x34, "4"),
    (0x35, "5"), (0x36, "6"), (0x37, "7"), (0x38, "8"), (0x39, "9"),
    (0x0D, "return"), (0x09, "tab"), (0x20, "space"), (0x08, "delete"), (0x1B, "escape"),
    (0x2E, "forwarddelete"), (0x2F, "help"), (0x24, "home"), (0x23, "end"),
    (0x21, "pageup"), (0x22, "pagedown"), (0x25, "left"), (0x26, "up"), (0x27, "right"),
    (0x28, "down"),
    (0x70, "f1"), (0x71, "f2"), (0x72, "f3"), (0x73, "f4"), (0x74, "f5"), (0x75, "f6"),
    (0x76, "f7"), (0x77, "f8"), (0x78, "f9"), (0x79, "f10"), (0x7A, "f11"), (0x7B, "f12"),
    (0x7C, "f13"), (0x7D, "f14"), (0x7E, "f15"), (0x7F, "f16"), (0x80, "f17"),
    (0x81, "f18"), (0x82, "f19"), (0x83, "f20"),
    (0xC0, "`"), (0xBD, "-"), (0xBB, "="), (0xDB, "["), (0xDD, "]"), (0xDC, "\\"),
    (0xBA, ";"), (0xDE, "'"), (0xBC, ","), (0xBE, "."), (0xBF, "/"),
    (0x60, "pad0"), (0x61, "pad1"), (0x62, "pad2"), (0x63, "pad3"), (0x64, "pad4"),
    (0x65, "pad5"), (0x66, "pad6"), (0x67, "pad7"), (0x68, "pad8"), (0x69, "pad9"),
    (0x6E, "pad."), (0x6A, "pad*"), (0x6B, "pad+"), (0x6D, "pad-"), (0x6F, "pad/"),
    (0x0C, "padclear"),
    (0x14, "capslock"),
    (0xA0, "shift"), (0xA1, "rightshift"), (0xA2, "ctrl"), (0xA3, "rightctrl"),
    (0xA4, "alt"), (0xA5, "rightalt"), (0x5B, "cmd"), (0x5C, "rightcmd"),
];

fn keymap() -> &'static NativeMap {
    KEYMAP.get_or_init(|| NativeMap::build(KEYCODES))
}

fn pad_enter() -> Option<Key> {
    Key::from_name("padenter")
}

unsafe extern "system" fn keyboard_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    let hook = KB_HOOK.load(Ordering::Acquire);
    if code != HC_ACTION as i32 {
        return CallNextHookEx(hook, code, wparam, lparam);
    }
    let info = &*(lparam as *const KBDLLHOOKSTRUCT);
    let msg = wparam as u32;
    let down = matches!(msg, WM_KEYDOWN | WM_SYSKEYDOWN);
    let up = matches!(msg, WM_KEYUP | WM_SYSKEYUP);
    if info.dwExtraInfo as i64 == SYNTHETIC_TAG || !(down || up) {
        return CallNextHookEx(hook, code, wparam, lparam);
    }
    let key = if info.vkCode == 0x0D && info.flags & LLKHF_EXTENDED != 0 {
        pad_enter()
    } else {
        keymap().key(info.vkCode)
    };
    let (Some(key), Some(shared)) = (key, SHARED.get()) else {
        return CallNextHookEx(hook, code, wparam, lparam);
    };
    let v = shared.handle(Input::Key { key, down });
    inject(&v.inject);
    if v.swallow {
        1
    } else {
        CallNextHookEx(hook, code, wparam, lparam)
    }
}

unsafe extern "system" fn mouse_proc(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    let hook = MOUSE_HOOK.load(Ordering::Acquire);
    if code != HC_ACTION as i32 {
        return CallNextHookEx(hook, code, wparam, lparam);
    }
    let info = &*(lparam as *const MSLLHOOKSTRUCT);
    if info.dwExtraInfo as i64 == SYNTHETIC_TAG {
        return CallNextHookEx(hook, code, wparam, lparam);
    }
    let hi = (info.mouseData >> 16) as u16;
    let input = match wparam as u32 {
        WM_LBUTTONDOWN => Some(Input::Button {
            button: 0,
            down: true,
        }),
        WM_LBUTTONUP => Some(Input::Button {
            button: 0,
            down: false,
        }),
        WM_RBUTTONDOWN => Some(Input::Button {
            button: 1,
            down: true,
        }),
        WM_RBUTTONUP => Some(Input::Button {
            button: 1,
            down: false,
        }),
        WM_MBUTTONDOWN => Some(Input::Button {
            button: 2,
            down: true,
        }),
        WM_MBUTTONUP => Some(Input::Button {
            button: 2,
            down: false,
        }),
        WM_XBUTTONDOWN => Some(Input::Button {
            button: 2 + hi as u8,
            down: true,
        }),
        WM_XBUTTONUP => Some(Input::Button {
            button: 2 + hi as u8,
            down: false,
        }),
        WM_MOUSEWHEEL if hi as i16 != 0 => Some(Input::Scroll { up: (hi as i16) > 0 }),
        WM_MOUSEMOVE => None,
        _ => None,
    };
    let (Some(input), Some(shared)) = (input, SHARED.get()) else {
        return CallNextHookEx(hook, code, wparam, lparam);
    };
    let v = shared.handle(input);
    inject(&v.inject);
    if v.swallow {
        1
    } else {
        CallNextHookEx(hook, code, wparam, lparam)
    }
}

pub fn run(shared: Arc<Shared>) -> Result<(), (&'static str, String)> {
    let _ = SHARED.set(Arc::clone(&shared));
    keymap();
    unsafe {
        let module = GetModuleHandleW(ptr::null());
        let kb = SetWindowsHookExW(WH_KEYBOARD_LL, Some(keyboard_proc), module, 0);
        if kb.is_null() {
            return Err(("hook", "SetWindowsHookExW(WH_KEYBOARD_LL) failed".into()));
        }
        KB_HOOK.store(kb, Ordering::Release);
        let mouse = SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_proc), module, 0);
        if mouse.is_null() {
            return Err(("hook", "SetWindowsHookExW(WH_MOUSE_LL) failed".into()));
        }
        MOUSE_HOOK.store(mouse, Ordering::Release);
        shared.ready();

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    Ok(())
}

fn key_input(vk: u16, down: bool, extended: bool) -> INPUT {
    let mut flags = if down { 0 } else { KEYEVENTF_KEYUP };
    if extended {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: SYNTHETIC_TAG as usize,
            },
        },
    }
}

fn button_input(button: u8, down: bool) -> INPUT {
    let (flags, data) = match (button, down) {
        (0, true) => (MOUSEEVENTF_LEFTDOWN, 0),
        (0, false) => (MOUSEEVENTF_LEFTUP, 0),
        (1, true) => (MOUSEEVENTF_RIGHTDOWN, 0),
        (1, false) => (MOUSEEVENTF_RIGHTUP, 0),
        (2, true) => (MOUSEEVENTF_MIDDLEDOWN, 0),
        (2, false) => (MOUSEEVENTF_MIDDLEUP, 0),
        (n, true) => (MOUSEEVENTF_XDOWN, (n as u32).saturating_sub(2)),
        (n, false) => (MOUSEEVENTF_XUP, (n as u32).saturating_sub(2)),
    };
    INPUT {
        r#type: INPUT_MOUSE,
        Anonymous: INPUT_0 {
            mi: MOUSEINPUT {
                dx: 0,
                dy: 0,
                mouseData: data,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: SYNTHETIC_TAG as usize,
            },
        },
    }
}

pub fn inject(events: &[Inject]) {
    if events.is_empty() {
        return;
    }
    let inputs: Vec<INPUT> = events
        .iter()
        .filter_map(|e| match *e {
            Inject::Key { key, down } => {
                if Some(key) == pad_enter() {
                    return Some(key_input(0x0D, down, true));
                }
                let vk = keymap().code(key)?;
                let extended = matches!(vk, 0x21..=0x28 | 0x2D | 0x2E | 0xA3 | 0xA5 | 0x5B | 0x5C | 0x6F);
                Some(key_input(vk, down, extended))
            }
            Inject::Button { button, down } => Some(button_input(button, down)),
        })
        .collect();
    unsafe {
        SendInput(inputs.len() as u32, inputs.as_ptr(), size_of::<INPUT>() as i32);
    }
}
