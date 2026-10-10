use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::{Duration, Instant};

use windows::core::BSTR;
use windows::Win32::Foundation::POINT;
use windows::Win32::Graphics::Gdi::{GetDC, GetPixel, ReleaseDC};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
};
use windows::Win32::UI::Accessibility::{
    CUIAutomation, IUIAutomation, IUIAutomationCacheRequest, UIA_AutomationIdPropertyId,
    UIA_BoundingRectanglePropertyId, UIA_ControlTypePropertyId, UIA_IsPasswordPropertyId,
    UIA_LocalizedControlTypePropertyId, UIA_NamePropertyId, UIA_ValueValuePropertyId,
};
use windows::Win32::UI::HiDpi::{
    GetDpiForSystem, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;

use crate::protocol::{
    clamp_interval, emit, text_field, Command, Element, Event, Frame, Pixel, Snapshot,
    DEFAULT_INTERVAL_MS,
};

pub const NAME: &str = "windows";

const STATIONARY_REFRESH: Duration = Duration::from_millis(250);
const CLR_INVALID: u32 = 0xFFFF_FFFF;

pub fn role_for(control_type: i32) -> String {
    let role = match control_type {
        50000 => "AXButton",
        50001 => "AXGroup",
        50002 => "AXCheckBox",
        50003 => "AXComboBox",
        50004 => "AXTextField",
        50005 => "AXLink",
        50006 => "AXImage",
        50007 => "AXCell",
        50008 => "AXList",
        50009 => "AXMenu",
        50010 => "AXMenuBar",
        50011 => "AXMenuItem",
        50012 => "AXProgressIndicator",
        50013 => "AXRadioButton",
        50014 => "AXScrollBar",
        50015 => "AXSlider",
        50016 => "AXIncrementor",
        50017 => "AXGroup",
        50018 => "AXTabGroup",
        50019 => "AXRadioButton",
        50020 => "AXStaticText",
        50021 => "AXToolbar",
        50022 => "AXHelpTag",
        50023 => "AXOutline",
        50024 => "AXRow",
        50025 => "AXGroup",
        50026 => "AXGroup",
        50027 => "AXHandle",
        50028 => "AXTable",
        50029 => "AXRow",
        50030 => "AXTextArea",
        50031 => "AXMenuButton",
        50032 => "AXWindow",
        50033 => "AXGroup",
        50034 => "AXGroup",
        50035 => "AXButton",
        50036 => "AXTable",
        50037 => "AXGroup",
        50038 => "AXSplitter",
        50039 => "AXGroup",
        50040 => "AXToolbar",
        other => return format!("AX{other}"),
    };

    role.to_string()
}

fn logical(v: i32, scale: f64) -> i64 {
    (v as f64 / scale).floor() as i64
}

fn bstr_field(b: windows::core::Result<BSTR>) -> Option<String> {
    b.ok().and_then(|s| text_field(&s.to_string()))
}

fn build_cache(auto: &IUIAutomation) -> windows::core::Result<IUIAutomationCacheRequest> {
    let cache = unsafe { auto.CreateCacheRequest()? };

    for id in [
        UIA_ControlTypePropertyId,
        UIA_LocalizedControlTypePropertyId,
        UIA_NamePropertyId,
        UIA_AutomationIdPropertyId,
        UIA_BoundingRectanglePropertyId,
        UIA_ValueValuePropertyId,
        UIA_IsPasswordPropertyId,
    ] {
        unsafe { cache.AddProperty(id)? };
    }

    Ok(cache)
}

fn read_element(
    auto: &IUIAutomation,
    cache: &IUIAutomationCacheRequest,
    pt: POINT,
    scale: f64,
) -> Option<Element> {
    let el = unsafe { auto.ElementFromPointBuildCache(pt, cache).ok()? };

    let role = unsafe { el.CachedControlType().ok() }.map(|c| role_for(c.0));
    let role_description = bstr_field(unsafe { el.CachedLocalizedControlType() });
    let title = bstr_field(unsafe { el.CachedName() });
    let identifier = bstr_field(unsafe { el.CachedAutomationId() });

    let is_password = unsafe { el.GetCachedPropertyValue(UIA_IsPasswordPropertyId) }
        .ok()
        .and_then(|v| bool::try_from(&v).ok())
        .unwrap_or(false);

    let value = if is_password {
        None
    } else {
        unsafe { el.GetCachedPropertyValue(UIA_ValueValuePropertyId) }
            .ok()
            .and_then(|v| BSTR::try_from(&v).ok())
            .and_then(|s| text_field(&s.to_string()))
    };

    let frame = unsafe { el.CachedBoundingRectangle().ok() }.and_then(|r| {
        if r.right <= r.left && r.bottom <= r.top {
            None
        } else {
            Some(Frame {
                x: logical(r.left, scale),
                y: logical(r.top, scale),
                w: logical(r.right - r.left, scale),
                h: logical(r.bottom - r.top, scale),
            })
        }
    });

    Some(Element {
        role,
        role_description,
        title,
        value,
        identifier,
        frame,
    })
}

fn read_pixel(pt: POINT) -> Option<Pixel> {
    unsafe {
        let hdc = GetDC(None);

        if hdc.is_invalid() {
            return None;
        }

        let c = GetPixel(hdc, pt.x, pt.y).0;

        ReleaseDC(None, hdc);

        if c == CLR_INVALID {
            return None;
        }

        let r = (c & 0xFF) as u8;
        let g = ((c >> 8) & 0xFF) as u8;
        let b = ((c >> 16) & 0xFF) as u8;

        Some(Pixel {
            r,
            g,
            b,
            hex: format!("#{r:02X}{g:02X}{b:02X}"),
        })
    }
}

pub fn run(rx: Receiver<Command>) -> Result<(), String> {
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

        CoInitializeEx(None, COINIT_MULTITHREADED)
            .ok()
            .map_err(|e| format!("COM init failed: {e}"))?;
    }

    let auto: IUIAutomation = unsafe {
        CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)
            .map_err(|e| format!("UI Automation unavailable: {e}"))?
    };

    let cache = build_cache(&auto).map_err(|e| format!("cache request failed: {e}"))?;

    let scale = (unsafe { GetDpiForSystem() } as f64 / 96.0).max(1.0);

    emit(&Event::Ready {
        version: env!("CARGO_PKG_VERSION"),
        platform: NAME,
    });

    let mut interval = Duration::from_millis(DEFAULT_INTERVAL_MS);
    let mut paused = false;
    let mut last: Option<Snapshot> = None;
    let mut last_phys: Option<(i32, i32)> = None;
    let mut last_element: Option<Element> = None;
    let mut last_query = Instant::now();

    loop {
        let cmd = if paused {
            match rx.recv() {
                Ok(c) => Some(c),
                Err(_) => return Ok(()),
            }
        } else {
            match rx.recv_timeout(interval) {
                Ok(c) => Some(c),
                Err(RecvTimeoutError::Timeout) => None,
                Err(RecvTimeoutError::Disconnected) => return Ok(()),
            }
        };

        if let Some(c) = cmd {
            match c {
                Command::Config { interval_ms } => {
                    if let Some(ms) = interval_ms {
                        interval = Duration::from_millis(clamp_interval(ms));
                    }
                }
                Command::Pause => paused = true,
                Command::Resume => paused = false,
                Command::Quit => return Ok(()),
            }

            last = None;
            last_phys = None;

            continue;
        }

        let mut pt = POINT::default();

        if unsafe { GetCursorPos(&mut pt) }.is_err() {
            continue;
        }

        let moved = last_phys != Some((pt.x, pt.y));
        let due = last_query.elapsed() >= STATIONARY_REFRESH;

        if moved || due || last_element.is_none() {
            last_element = read_element(&auto, &cache, pt, scale);
            last_query = Instant::now();
            last_phys = Some((pt.x, pt.y));
        }

        let snap = Snapshot {
            sx: logical(pt.x, scale),
            sy: logical(pt.y, scale),
            pixel: read_pixel(pt),
            element: last_element.clone(),
        };

        if last.as_ref() != Some(&snap) {
            emit(&Event::Spy(snap.clone()));
            last = Some(snap);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_control_types() {
        assert_eq!(role_for(50000), "AXButton");
        assert_eq!(role_for(50004), "AXTextField");
        assert_eq!(role_for(50005), "AXLink");
        assert_eq!(role_for(50030), "AXTextArea");
        assert_eq!(role_for(50033), "AXGroup");
        assert_eq!(role_for(50032), "AXWindow");
        assert_eq!(role_for(1), "AX1");
    }

    #[test]
    fn maps_every_known_id() {
        for id in 50000..=50040 {
            assert!(!role_for(id).starts_with("AX5"));
        }
    }

    #[test]
    fn converts_to_logical() {
        assert_eq!(logical(150, 1.5), 100);
        assert_eq!(logical(-1, 1.0), -1);
    }
}
