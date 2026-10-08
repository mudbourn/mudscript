use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};

use crate::keys::{mods_from_names, Key};
use crate::protocol::{BindSpec, Config, Event};

const HOTKEY_COOLDOWN: Duration = Duration::from_millis(150);
const LIVENESS_DEADLINE: Duration = Duration::from_millis(1000);

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Input {
    Key { key: Key, down: bool },
    Button { button: u8, down: bool },
    Scroll { up: bool },
    Move,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Inject {
    Key { key: Key, down: bool },
    Button { button: u8, down: bool },
}

#[derive(Default, Debug, PartialEq)]
pub struct Verdict {
    pub swallow: bool,
    pub inject: Vec<Inject>,
    pub drag: Option<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum ModMode {
    Exact,
    Subset,
    Any,
}

#[derive(Debug)]
struct Bind {
    id: u32,
    mods: u8,
    mode: ModMode,
    also: Vec<Key>,
    swallow: bool,
    system: bool,
    release: bool,
}

impl Bind {
    fn mods_ok(&self, held: u8) -> bool {
        match self.mode {
            ModMode::Any => true,
            ModMode::Subset => held & self.mods == self.mods,
            ModMode::Exact => held == self.mods,
        }
    }
}

#[derive(Debug)]
struct ModBind {
    id: u32,
    mods: u8,
    system: bool,
    fired: bool,
}

#[derive(Debug)]
struct Panic {
    key: Key,
    mods: u8,
    any: bool,
    latched: bool,
    cooldown_until: Option<Instant>,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum SocdMode {
    LastWins,
    FirstWins,
    Neutral,
}

#[derive(Debug, Default)]
pub struct Engine {
    enabled: bool,
    target: bool,
    held: HashSet<Key>,
    buttons: HashSet<u8>,

    keys: HashMap<Key, Vec<Bind>>,
    mod_binds: Vec<ModBind>,
    mouse: HashMap<u8, Bind>,
    scroll: HashMap<bool, Bind>,
    swallowed: HashSet<Key>,
    pressed: HashMap<Key, (u32, bool)>,
    swallowed_buttons: HashSet<u8>,

    panic: Option<Panic>,
    swallow_hotkeys: bool,

    socd: Option<SocdMode>,
    socd_pairs: Vec<(Key, Key)>,
    socd_suppressed: HashSet<Key>,
    socd_blocked: HashSet<Key>,

    trackpad_on: bool,
    trackpad_keys: [Option<Key>; 2],
    trackpad_active: [bool; 2],

    trace: bool,
    last_command: Option<Instant>,

    outbox: Vec<Event>,
}

impl Engine {
    pub fn new() -> Engine {
        Engine::default()
    }

    pub fn touch(&mut self, now: Instant) {
        self.last_command = Some(now);
    }

    fn expired(&self, now: Instant) -> bool {
        self.last_command
            .is_some_and(|t| now.saturating_duration_since(t) > LIVENESS_DEADLINE)
    }

    fn track_only(&mut self, input: Input) -> Verdict {
        self.swallowed.clear();
        self.swallowed_buttons.clear();
        match input {
            Input::Key { key, down } => {
                if down {
                    self.held.insert(key);
                } else {
                    self.held.remove(&key);
                }
            }
            Input::Button { button, down } => {
                if down {
                    self.buttons.insert(button);
                } else {
                    self.buttons.remove(&button);
                }
            }
            Input::Scroll { .. } | Input::Move => {}
        }
        Verdict::default()
    }

    pub fn drain_events(&mut self) -> Vec<Event> {
        std::mem::take(&mut self.outbox)
    }

    fn warn(&mut self, msg: String) {
        self.outbox.push(Event::Warn { msg });
    }

    pub fn mods(&self) -> u8 {
        self.held
            .iter()
            .filter_map(|k| k.modifier_bit())
            .fold(0, |a, b| a | b)
    }

    fn fire(&mut self, id: u32, edge: &'static str) {
        let m = self.mods();
        self.outbox.push(Event::Fire { id, edge, m });
    }

    pub fn configure(&mut self, cfg: Config) -> Vec<Inject> {
        self.keys.clear();
        self.mod_binds.clear();
        self.mouse.clear();
        self.scroll.clear();

        for spec in cfg.binds {
            if let Err(msg) = self.add_bind(&spec) {
                self.warn(format!("bind {}: {msg}", spec.id));
            }
        }

        self.panic = cfg.panic.and_then(|p| match Key::from_name(&p.key) {
            Some(key) => Some(Panic {
                key,
                mods: mods_from_names(&p.mods),
                any: p.any,
                latched: false,
                cooldown_until: None,
            }),
            None => {
                self.warn(format!("panic hotkey: unknown key {:?}", p.key));
                None
            }
        });
        self.swallow_hotkeys = cfg.swallow_hotkeys;
        self.trace = cfg.trace;

        let mut out = self.reset_socd();
        self.socd = if cfg.socd.on {
            match cfg.socd.mode.as_str() {
                "firstWins" => Some(SocdMode::FirstWins),
                "neutral" => Some(SocdMode::Neutral),
                "lastWins" => Some(SocdMode::LastWins),
                other => {
                    self.warn(format!("socd: unknown mode {other:?}, using lastWins"));
                    Some(SocdMode::LastWins)
                }
            }
        } else {
            None
        };
        self.socd_pairs = cfg
            .socd
            .pairs
            .iter()
            .filter_map(|[a, b]| Some((Key::from_name(a)?, Key::from_name(b)?)))
            .collect();

        let tp = [
            cfg.trackpad.left.as_deref().and_then(Key::from_name),
            cfg.trackpad.right.as_deref().and_then(Key::from_name),
        ];
        if !cfg.trackpad.on || tp != self.trackpad_keys {
            out.extend(self.release_trackpad());
        }
        self.trackpad_on = cfg.trackpad.on;
        self.trackpad_keys = tp;
        out
    }

    fn add_bind(&mut self, s: &BindSpec) -> Result<(), String> {
        let mode = match s.mode.as_deref().unwrap_or("exact") {
            "exact" => ModMode::Exact,
            "subset" => ModMode::Subset,
            "any" => ModMode::Any,
            m => return Err(format!("unknown mode {m:?}")),
        };
        let mut also = Vec::new();
        for n in &s.also {
            also.push(Key::from_name(n).ok_or_else(|| format!("unknown key {n:?}"))?);
        }
        let bind = Bind {
            id: s.id,
            mods: mods_from_names(&s.mods),
            mode,
            also,
            swallow: s.swallow,
            system: s.system,
            release: s.release,
        };
        match s.t.as_str() {
            "key" => {
                let name = s.key.as_deref().ok_or("missing key")?;
                let key = Key::from_name(name).ok_or_else(|| format!("unknown key {name:?}"))?;
                self.keys.entry(key).or_default().push(bind);
            }
            "mods" => {
                if bind.mods == 0 {
                    return Err("empty modifier set".into());
                }
                self.mod_binds.push(ModBind {
                    id: s.id,
                    mods: bind.mods,
                    system: s.system,
                    fired: false,
                });
            }
            "mouse" => {
                let b = s.button.ok_or("missing button")?;
                self.mouse.insert(b, bind);
            }
            "scroll" => {
                let up = match s.dir.as_deref().unwrap_or("up") {
                    "up" => true,
                    "down" => false,
                    d => return Err(format!("unknown scroll dir {d:?}")),
                };
                self.scroll.insert(up, bind);
            }
            t => return Err(format!("unknown bind type {t:?}")),
        }
        Ok(())
    }

    pub fn set_state(&mut self, enabled: bool, target: bool) -> Vec<Inject> {
        let mut out = Vec::new();
        if !enabled || !target {
            out.extend(self.release_trackpad());
        }
        if !enabled {
            out.extend(self.reset_socd());
        }
        self.enabled = enabled;
        self.target = target;
        out
    }

    fn release_trackpad(&mut self) -> Vec<Inject> {
        let mut out = Vec::new();
        for (i, active) in self.trackpad_active.iter_mut().enumerate() {
            if *active {
                *active = false;
                out.push(Inject::Button {
                    button: i as u8,
                    down: false,
                });
            }
        }
        out
    }

    fn reset_socd(&mut self) -> Vec<Inject> {
        let out = self
            .socd_suppressed
            .drain()
            .filter(|k| self.held.contains(k))
            .map(|key| Inject::Key { key, down: true })
            .collect();
        self.socd_blocked.clear();
        out
    }

    pub fn handle(&mut self, input: Input, now: Instant) -> Verdict {
        if self.expired(now) {
            return self.track_only(input);
        }
        match input {
            Input::Key { key, down } => self.on_key(key, down, now),
            Input::Button { button, down } => self.on_button(button, down),
            Input::Scroll { up } => self.on_scroll(up),
            Input::Move => Verdict {
                drag: self.drag_button(),
                ..Verdict::default()
            },
        }
    }

    fn drag_button(&self) -> Option<u8> {
        if self.trackpad_active[1] {
            Some(1)
        } else if self.trackpad_active[0] {
            Some(0)
        } else {
            None
        }
    }

    fn on_key(&mut self, key: Key, down: bool, now: Instant) -> Verdict {
        let repeat = down && self.held.contains(&key);
        if down {
            self.held.insert(key);
        } else {
            self.held.remove(&key);
        }
        let mods = self.mods();
        if !repeat && self.trace {
            self.outbox.push(Event::K {
                k: key.name(),
                d: down,
                m: mods,
            });
        }

        let mut v = Verdict::default();

        if key.modifier_bit().is_some() && !repeat {
            self.on_modifiers_changed(mods);
        }

        if self.on_panic(key, down, repeat, mods, now) {
            v.swallow = true;
            return v;
        }
        if self.on_trackpad(key, down, &mut v) {
            return v;
        }
        if self.on_socd(key, down, repeat, &mut v) {
            return v;
        }
        if key.is_modifier() {
            return v;
        }
        v.swallow = self.on_key_bind(key, down, repeat, mods);
        v
    }

    fn on_modifiers_changed(&mut self, mods: u8) {
        if let Some(p) = &mut self.panic {
            if !p.any && mods & p.mods != p.mods {
                p.latched = false;
                p.cooldown_until = None;
            }
        }
        let real_key_held = self.held.iter().any(|k| !k.is_modifier());
        if real_key_held || self.mod_binds.is_empty() {
            return;
        }
        let enabled = self.enabled;
        let mut fires = Vec::new();
        for mb in &mut self.mod_binds {
            if mb.mods == mods {
                if !mb.fired {
                    mb.fired = true;
                    if enabled || mb.system {
                        fires.push(mb.id);
                    }
                }
            } else {
                mb.fired = false;
            }
        }
        for id in fires {
            self.fire(id, "down");
        }
    }

    fn on_panic(&mut self, key: Key, down: bool, repeat: bool, mods: u8, now: Instant) -> bool {
        let swallow = self.swallow_hotkeys;
        let Some(p) = &mut self.panic else { return false };
        if key != p.key {
            return false;
        }
        if down {
            if repeat {
                return swallow && p.latched;
            }
            let cooling = p.cooldown_until.is_some_and(|t| now < t);
            if (p.any || mods == p.mods) && !p.latched && !cooling {
                p.latched = true;
                self.outbox.push(Event::Panic);
                return swallow;
            }
            false
        } else {
            let was = p.latched;
            p.latched = false;
            if was {
                p.cooldown_until = Some(now + HOTKEY_COOLDOWN);
            }
            swallow && was
        }
    }

    fn on_trackpad(&mut self, key: Key, down: bool, v: &mut Verdict) -> bool {
        if !self.trackpad_on {
            return false;
        }
        let Some(side) = self.trackpad_keys.iter().position(|k| *k == Some(key)) else {
            return false;
        };
        if !down && self.trackpad_active[side] {
            self.trackpad_active[side] = false;
            v.inject.push(Inject::Button {
                button: side as u8,
                down: false,
            });
            v.swallow = true;
            return true;
        }
        if !self.enabled {
            return false;
        }
        if down && !self.trackpad_active[side] && self.target {
            self.trackpad_active[side] = true;
            v.inject.push(Inject::Button {
                button: side as u8,
                down: true,
            });
        }
        v.swallow = true;
        true
    }

    fn socd_opposite(&self, key: Key) -> Option<Key> {
        self.socd_pairs.iter().find_map(|&(a, b)| {
            if a == key {
                Some(b)
            } else if b == key {
                Some(a)
            } else {
                None
            }
        })
    }

    fn on_socd(&mut self, key: Key, down: bool, repeat: bool, v: &mut Verdict) -> bool {
        let Some(mode) = self.socd else { return false };
        if !self.enabled {
            return false;
        }
        let Some(opp) = self.socd_opposite(key) else {
            return false;
        };

        if down {
            if repeat {
                if self.socd_blocked.contains(&key) || self.socd_suppressed.contains(&key) {
                    v.swallow = true;
                    return true;
                }
                return false;
            }
            if !self.held.contains(&opp) {
                return false;
            }
            let opp_live = !self.socd_blocked.contains(&opp) && !self.socd_suppressed.contains(&opp);
            match mode {
                SocdMode::LastWins => {
                    if opp_live {
                        v.inject.push(Inject::Key {
                            key: opp,
                            down: false,
                        });
                        self.socd_suppressed.insert(opp);
                    }
                    false
                }
                SocdMode::FirstWins => {
                    self.socd_blocked.insert(key);
                    v.swallow = true;
                    true
                }
                SocdMode::Neutral => {
                    if opp_live {
                        v.inject.push(Inject::Key {
                            key: opp,
                            down: false,
                        });
                        self.socd_suppressed.insert(opp);
                    }
                    self.socd_blocked.insert(key);
                    v.swallow = true;
                    true
                }
            }
        } else {
            let opp_held = self.held.contains(&opp);
            if self.socd_blocked.remove(&key) || self.socd_suppressed.remove(&key) {
                if mode == SocdMode::Neutral && opp_held && self.socd_suppressed.remove(&opp) {
                    v.inject.push(Inject::Key { key: opp, down: true });
                }
                v.swallow = true;
                return true;
            }
            if opp_held && (self.socd_suppressed.remove(&opp) || self.socd_blocked.remove(&opp)) {
                v.inject.push(Inject::Key { key: opp, down: true });
            }
            false
        }
    }

    fn on_key_bind(&mut self, key: Key, down: bool, repeat: bool, mods: u8) -> bool {
        if repeat {
            return self.swallowed.contains(&key);
        }
        if !down {
            if let Some((id, release)) = self.pressed.remove(&key) {
                if release {
                    self.fire(id, "up");
                }
            }
            return self.swallowed.remove(&key);
        }
        let hit = self.keys.get(&key).and_then(|bucket| {
            let b = bucket
                .iter()
                .find(|b| b.mods_ok(mods) && b.also.iter().all(|k| self.held.contains(k)))?;
            (self.enabled || b.system).then_some((b.id, b.swallow, b.release))
        });
        let Some((id, swallow, release)) = hit else {
            return false;
        };
        self.fire(id, "down");
        self.pressed.insert(key, (id, release));
        if swallow {
            self.swallowed.insert(key);
        }
        swallow
    }

    fn on_button(&mut self, button: u8, down: bool) -> Verdict {
        let mut v = Verdict::default();
        if down == self.buttons.contains(&button) {
        } else {
            if down {
                self.buttons.insert(button);
            } else {
                self.buttons.remove(&button);
            }
            if self.trace {
                self.outbox.push(Event::M { b: button, d: down });
            }
        }
        if !down {
            v.swallow = self.swallowed_buttons.remove(&button);
            return v;
        }
        let hit = self
            .mouse
            .get(&button)
            .filter(|b| self.enabled || b.system)
            .map(|b| (b.id, b.swallow));
        if let Some((id, swallow)) = hit {
            self.fire(id, "down");
            if swallow {
                self.swallowed_buttons.insert(button);
            }
            v.swallow = swallow;
        }
        v
    }

    fn on_scroll(&mut self, up: bool) -> Verdict {
        let hit = self
            .scroll
            .get(&up)
            .filter(|b| self.enabled || b.system)
            .map(|b| (b.id, b.swallow));
        let mut v = Verdict::default();
        if let Some((id, swallow)) = hit {
            self.fire(id, "down");
            v.swallow = swallow;
        }
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::{HotkeySpec, SocdSpec, TrackpadSpec};

    fn k(n: &str) -> Key {
        Key::from_name(n).unwrap()
    }
    fn bind(id: u32, t: &str, key: &str, mods: &[&str]) -> BindSpec {
        BindSpec {
            id,
            t: t.into(),
            key: Some(key.into()),
            button: None,
            dir: None,
            mods: mods.iter().map(|s| s.to_string()).collect(),
            mode: None,
            also: vec![],
            swallow: false,
            system: false,
            release: false,
        }
    }
    fn engine(cfg: Config) -> Engine {
        let mut e = Engine::new();
        e.configure(cfg);
        e.set_state(true, true);
        e.drain_events();
        e
    }
    fn press(e: &mut Engine, n: &str, down: bool) -> Verdict {
        e.handle(Input::Key { key: k(n), down }, Instant::now())
    }
    fn fires(e: &mut Engine) -> Vec<(u32, &'static str)> {
        e.drain_events()
            .into_iter()
            .filter_map(|ev| match ev {
                Event::Fire { id, edge, .. } => Some((id, edge)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn exact_mods_and_swallow() {
        let mut b = bind(1, "key", "e", &["shift"]);
        b.swallow = true;
        let mut e = engine(Config {
            binds: vec![b],
            ..Default::default()
        });
        assert!(!press(&mut e, "e", true).swallow);
        press(&mut e, "e", false);
        assert!(fires(&mut e).is_empty());

        press(&mut e, "shift", true);
        assert!(press(&mut e, "e", true).swallow);
        assert!(press(&mut e, "e", true).swallow, "repeat of swallowed key");
        assert!(press(&mut e, "e", false).swallow, "up of swallowed key");
        assert_eq!(fires(&mut e), vec![(1, "down")]);

        press(&mut e, "cmd", true);
        press(&mut e, "e", true);
        assert!(fires(&mut e).is_empty(), "extra modifier breaks exact match");
    }

    #[test]
    fn disabled_only_fires_system_binds_and_keeps_tracking() {
        let mut sys = bind(2, "key", "f", &[]);
        sys.system = true;
        let mut e = engine(Config {
            binds: vec![bind(1, "key", "g", &[]), sys],
            ..Default::default()
        });
        e.set_state(false, false);
        press(&mut e, "w", true);
        press(&mut e, "g", true);
        press(&mut e, "f", true);
        assert_eq!(fires(&mut e), vec![(2, "down")]);
        e.set_state(true, true);
        assert!(e.held.contains(&k("w")), "held keys survive disable");
    }

    #[test]
    fn combo_requires_other_key_held_and_release_fires() {
        let mut c = bind(3, "key", "x", &[]);
        c.also = vec!["z".into()];
        c.release = true;
        let mut e = engine(Config {
            binds: vec![c],
            ..Default::default()
        });
        press(&mut e, "x", true);
        press(&mut e, "x", false);
        assert!(fires(&mut e).is_empty());
        press(&mut e, "z", true);
        press(&mut e, "x", true);
        press(&mut e, "x", false);
        assert_eq!(fires(&mut e), vec![(3, "down"), (3, "up")]);
    }

    #[test]
    fn modifier_only_bind_fires_once_per_press() {
        let mut m = bind(4, "mods", "", &["ctrl", "alt"]);
        m.key = None;
        let mut e = engine(Config {
            binds: vec![m],
            ..Default::default()
        });
        press(&mut e, "ctrl", true);
        press(&mut e, "alt", true);
        press(&mut e, "alt", false);
        press(&mut e, "alt", true);
        assert_eq!(fires(&mut e), vec![(4, "down"), (4, "down")]);
        press(&mut e, "a", true);
        press(&mut e, "alt", false);
        press(&mut e, "alt", true);
        assert!(fires(&mut e).is_empty(), "no fire while a real key is held");
    }

    #[test]
    fn panic_latches_and_cools_down() {
        let mut e = engine(Config {
            panic: Some(HotkeySpec {
                key: "p".into(),
                mods: vec!["ctrl".into()],
                any: false,
            }),
            swallow_hotkeys: true,
            ..Default::default()
        });
        let t0 = Instant::now();
        let ctrl = k("ctrl");
        e.handle(
            Input::Key {
                key: ctrl,
                down: true,
            },
            t0,
        );
        assert!(
            e.handle(
                Input::Key {
                    key: k("p"),
                    down: true
                },
                t0
            )
            .swallow
        );
        assert!(
            e.handle(
                Input::Key {
                    key: k("p"),
                    down: true
                },
                t0
            )
            .swallow
        );
        assert!(
            e.handle(
                Input::Key {
                    key: k("p"),
                    down: false
                },
                t0
            )
            .swallow
        );
        let n = e.drain_events().iter().filter(|e| **e == Event::Panic).count();
        assert_eq!(n, 1);
        e.handle(
            Input::Key {
                key: k("p"),
                down: true,
            },
            t0 + Duration::from_millis(50),
        );
        e.handle(
            Input::Key {
                key: k("p"),
                down: false,
            },
            t0 + Duration::from_millis(60),
        );
        e.handle(
            Input::Key {
                key: k("p"),
                down: true,
            },
            t0 + Duration::from_millis(400),
        );
        let n = e.drain_events().iter().filter(|e| **e == Event::Panic).count();
        assert_eq!(n, 1, "second press inside cooldown ignored, third fires");
    }

    fn socd(mode: &str) -> Engine {
        engine(Config {
            socd: SocdSpec {
                on: true,
                mode: mode.into(),
                ..Default::default()
            },
            ..Default::default()
        })
    }

    #[test]
    fn socd_last_wins_releases_and_restores() {
        let mut e = socd("lastWins");
        assert_eq!(press(&mut e, "a", true), Verdict::default());
        let v = press(&mut e, "d", true);
        assert!(!v.swallow);
        assert_eq!(
            v.inject,
            vec![Inject::Key {
                key: k("a"),
                down: false
            }]
        );
        let v = press(&mut e, "d", false);
        assert!(!v.swallow);
        assert_eq!(
            v.inject,
            vec![Inject::Key {
                key: k("a"),
                down: true
            }]
        );
        assert_eq!(press(&mut e, "a", false), Verdict::default());
    }

    #[test]
    fn socd_last_wins_swallows_up_of_suppressed_key() {
        let mut e = socd("lastWins");
        press(&mut e, "a", true);
        press(&mut e, "d", true);
        assert!(press(&mut e, "a", false).swallow);
        assert_eq!(press(&mut e, "d", false), Verdict::default());
    }

    #[test]
    fn socd_first_wins_blocks_then_hands_over() {
        let mut e = socd("firstWins");
        press(&mut e, "w", true);
        assert!(press(&mut e, "s", true).swallow);
        let v = press(&mut e, "w", false);
        assert_eq!(
            v.inject,
            vec![Inject::Key {
                key: k("s"),
                down: true
            }]
        );
        assert!(!press(&mut e, "s", false).swallow);
    }

    #[test]
    fn socd_neutral_cancels_both() {
        let mut e = socd("neutral");
        press(&mut e, "a", true);
        let v = press(&mut e, "d", true);
        assert!(v.swallow);
        assert_eq!(
            v.inject,
            vec![Inject::Key {
                key: k("a"),
                down: false
            }]
        );
        let v = press(&mut e, "d", false);
        assert!(v.swallow);
        assert_eq!(
            v.inject,
            vec![Inject::Key {
                key: k("a"),
                down: true
            }]
        );
    }

    #[test]
    fn disable_restores_socd_suppressed_keys() {
        let mut e = socd("lastWins");
        press(&mut e, "a", true);
        press(&mut e, "d", true);
        assert_eq!(
            e.set_state(false, true),
            vec![Inject::Key {
                key: k("a"),
                down: true
            }]
        );
    }

    #[test]
    fn trackpad_hold_presses_and_releases_button() {
        let mut e = engine(Config {
            trackpad: TrackpadSpec {
                on: true,
                left: Some("n".into()),
                right: Some("j".into()),
            },
            ..Default::default()
        });
        let v = press(&mut e, "j", true);
        assert!(v.swallow);
        assert_eq!(
            v.inject,
            vec![Inject::Button {
                button: 1,
                down: true
            }]
        );
        assert!(
            press(&mut e, "j", true).inject.is_empty(),
            "repeat does not re-press"
        );
        assert_eq!(e.handle(Input::Move, Instant::now()).drag, Some(1));
        let v = press(&mut e, "j", false);
        assert_eq!(
            v.inject,
            vec![Inject::Button {
                button: 1,
                down: false
            }]
        );
        assert_eq!(e.handle(Input::Move, Instant::now()).drag, None);
    }

    #[test]
    fn trackpad_released_on_disable() {
        let mut e = engine(Config {
            trackpad: TrackpadSpec {
                on: true,
                left: Some("n".into()),
                right: None,
            },
            ..Default::default()
        });
        press(&mut e, "n", true);
        assert_eq!(
            e.set_state(false, false),
            vec![Inject::Button {
                button: 0,
                down: false
            }]
        );
        assert!(!press(&mut e, "n", false).swallow);
    }

    #[test]
    fn mouse_bind_swallows_matching_up() {
        let mut m = bind(9, "mouse", "", &[]);
        m.key = None;
        m.button = Some(3);
        m.swallow = true;
        let mut e = engine(Config {
            binds: vec![m],
            ..Default::default()
        });
        assert!(
            e.handle(
                Input::Button {
                    button: 3,
                    down: true
                },
                Instant::now()
            )
            .swallow
        );
        assert!(
            e.handle(
                Input::Button {
                    button: 3,
                    down: false
                },
                Instant::now()
            )
            .swallow
        );
        assert!(
            !e.handle(
                Input::Button {
                    button: 0,
                    down: true
                },
                Instant::now()
            )
            .swallow
        );
        assert_eq!(fires(&mut e), vec![(9, "down")]);
    }

    #[test]
    fn bad_bind_warns_instead_of_failing() {
        let mut e = Engine::new();
        e.configure(Config {
            binds: vec![bind(1, "key", "nope", &[])],
            ..Default::default()
        });
        assert!(matches!(e.drain_events()[0], Event::Warn { .. }));
    }

    #[test]
    fn trace_gates_key_and_button_events() {
        let mut e = engine(Config::default());
        press(&mut e, "a", true);
        e.handle(
            Input::Button {
                button: 0,
                down: true,
            },
            Instant::now(),
        );
        assert!(e.drain_events().is_empty());
        e.configure(Config {
            trace: true,
            ..Default::default()
        });
        press(&mut e, "a", false);
        e.handle(
            Input::Button {
                button: 0,
                down: false,
            },
            Instant::now(),
        );
        let evs = e.drain_events();
        assert!(evs.iter().any(|ev| matches!(ev, Event::K { .. })));
        assert!(evs.iter().any(|ev| matches!(ev, Event::M { .. })));
    }

    #[test]
    fn stale_host_stops_swallowing_until_next_command() {
        let t0 = Instant::now();
        let mut b = bind(1, "key", "e", &[]);
        b.swallow = true;
        let mut e = engine(Config {
            binds: vec![b],
            ..Default::default()
        });
        e.touch(t0);
        let key = Input::Key {
            key: k("e"),
            down: true,
        };
        assert!(e.handle(key, t0 + Duration::from_millis(500)).swallow);
        let late = t0 + Duration::from_millis(1500);
        assert!(!e.handle(key, late).swallow);
        let up = Input::Key {
            key: k("e"),
            down: false,
        };
        e.handle(up, late);
        e.touch(late);
        assert!(e.handle(key, late + Duration::from_millis(10)).swallow);
    }
}
