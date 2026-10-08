#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct Key(pub u16);

pub const MOD_CMD: u8 = 1;
pub const MOD_ALT: u8 = 2;
pub const MOD_CTRL: u8 = 4;
pub const MOD_SHIFT: u8 = 8;

#[rustfmt::skip]
pub const NAMES: &[&str] = &[
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "return", "tab", "space", "delete", "escape", "forwarddelete", "help", "insert",
    "home", "end", "pageup", "pagedown", "left", "right", "up", "down",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10",
    "f11", "f12", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20",
    "`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/",
    "pad0", "pad1", "pad2", "pad3", "pad4", "pad5", "pad6", "pad7", "pad8", "pad9",
    "pad.", "pad*", "pad+", "pad-", "pad/", "pad=", "padclear", "padenter",
    "capslock", "fn",
    "shift", "rightshift", "ctrl", "rightctrl", "alt", "rightalt", "cmd", "rightcmd",
];

impl Key {
    pub fn from_name(name: &str) -> Option<Key> {
        let lower = name.to_ascii_lowercase();
        let n = match lower.as_str() {
            "enter" => "return",
            "backspace" => "delete",
            "esc" => "escape",
            "option" | "opt" | "lalt" => "alt",
            "control" | "lctrl" => "ctrl",
            "command" | "win" | "super" | "lcmd" => "cmd",
            "lshift" => "shift",
            other => other,
        };
        NAMES.iter().position(|&k| k == n).map(|i| Key(i as u16))
    }

    pub fn name(self) -> &'static str {
        NAMES.get(self.0 as usize).copied().unwrap_or("?")
    }

    pub fn modifier_bit(self) -> Option<u8> {
        match self.name() {
            "cmd" | "rightcmd" => Some(MOD_CMD),
            "alt" | "rightalt" => Some(MOD_ALT),
            "ctrl" | "rightctrl" => Some(MOD_CTRL),
            "shift" | "rightshift" => Some(MOD_SHIFT),
            _ => None,
        }
    }

    pub fn is_modifier(self) -> bool {
        self.modifier_bit().is_some() || matches!(self.name(), "capslock" | "fn")
    }
}

pub fn mods_from_names<S: AsRef<str>>(names: &[S]) -> u8 {
    names.iter().fold(0, |m, n| {
        m | match n.as_ref().to_ascii_lowercase().as_str() {
            "cmd" | "command" | "win" | "super" => MOD_CMD,
            "alt" | "option" | "opt" => MOD_ALT,
            "ctrl" | "control" => MOD_CTRL,
            "shift" => MOD_SHIFT,
            _ => 0,
        }
    })
}

#[cfg_attr(not(any(target_os = "macos", windows)), allow(dead_code))]
pub struct NativeMap([Option<Key>; 256]);

#[cfg_attr(not(any(target_os = "macos", windows)), allow(dead_code))]
impl NativeMap {
    pub fn build(pairs: &[(u16, &str)]) -> NativeMap {
        let mut t = [None; 256];
        for &(code, name) in pairs {
            let k = Key::from_name(name).unwrap_or_else(|| panic!("unknown key name {name}"));
            t[code as usize & 0xff] = Some(k);
        }
        NativeMap(t)
    }
    pub fn key(&self, code: u32) -> Option<Key> {
        if code < 256 {
            self.0[code as usize]
        } else {
            None
        }
    }
    pub fn code(&self, key: Key) -> Option<u16> {
        self.0.iter().position(|k| *k == Some(key)).map(|i| i as u16)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names_roundtrip_and_unique() {
        for (i, n) in NAMES.iter().enumerate() {
            assert_eq!(Key::from_name(n), Some(Key(i as u16)), "{n}");
        }
        assert_eq!(Key::from_name("Enter").unwrap().name(), "return");
        assert!(Key::from_name("insert").is_some());
        assert!(Key::from_name("pad=").is_some());
        assert_eq!(mods_from_names(&["cmd", "shift"]), MOD_CMD | MOD_SHIFT);
    }
}
