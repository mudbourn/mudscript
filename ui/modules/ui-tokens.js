(function () {
    "use strict";

// Theme //
    function hexToRgb(hex) {
        hex = hex.replace(/^#/, "");
        if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
        else if (hex.length === 4) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2]+hex[3]+hex[3];
        const n = parseInt(hex.slice(0, 6), 16);
        const a = hex.length >= 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1;
        return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255, a: a };
    }

    function applyTheme(t) {
        if (!t) return;
        const r = document.documentElement.style;
        if (t.bg) r.setProperty("--bg", t.bg);
        if (t.surface) r.setProperty("--surface", t.surface);
        if (t.surface2) r.setProperty("--surface2", t.surface2);
        if (t.hover) r.setProperty("--hover", t.hover);
        if (t.accent) r.setProperty("--accent", t.accent);
        if (t.accentHi) r.setProperty("--accent-hi", t.accentHi);
        if (t.success) r.setProperty("--success", t.success);
        if (t.dangerBg) r.setProperty("--danger-bg", t.dangerBg);
        if (t.danger) r.setProperty("--danger", t.danger);
        if (t.warning) r.setProperty("--warning", t.warning);
        if (t.text) r.setProperty("--text", t.text);
        if (t.text && !t.text2) {
            const c = hexToRgb(t.text);
            if (c) r.setProperty("--text2", `rgba(${c.r},${c.g},${c.b},${0.85 * c.a})`);
        }
        if (t.text && !t.text3) {
            const c = hexToRgb(t.text);
            if (c) r.setProperty("--text3", `rgba(${c.r},${c.g},${c.b},${0.55 * c.a})`);
        }
        if (t.accent && t.hover && !t.border) {
            const a = hexToRgb(t.accent);
            const h = hexToRgb(t.hover);
            if (a && h) {
                const mr = Math.round(a.r * 0.5 + h.r * 0.5);
                const mg = Math.round(a.g * 0.5 + h.g * 0.5);
                const mb = Math.round(a.b * 0.5 + h.b * 0.5);
                const ma = a.a * 0.5 + h.a * 0.5;
                r.setProperty("--border", `rgba(${mr},${mg},${mb},${0.55 * ma})`);
                r.setProperty("--border-dim", `rgba(${mr},${mg},${mb},${0.18 * ma})`);
            }
        }
        if (t.accent && !t.accentGlow) {
            const a = hexToRgb(t.accent);
            if (a) r.setProperty("--accent-glow", `rgba(${a.r},${a.g},${a.b},${0.4 * a.a})`);
        }
        if (t.accent && !t.accentGlowFaint) {
            const a = hexToRgb(t.accent);
            if (a) r.setProperty("--accent-glow-faint", `rgba(${a.r},${a.g},${a.b},${0.12 * a.a})`);
        }
        if (t.danger && !t.dangerGlow) {
            const d = hexToRgb(t.danger);
            if (d) r.setProperty("--danger-glow", `rgba(${d.r},${d.g},${d.b},${0.6 * d.a})`);
        }
        if (t.danger && !t.dangerBorder) {
            const d = hexToRgb(t.danger);
            if (d) r.setProperty("--danger-border", `rgba(${d.r},${d.g},${d.b},${0.3 * d.a})`);
        }
        if (t.text2) r.setProperty("--text2", t.text2);
        if (t.text3) r.setProperty("--text3", t.text3);
        if (t.border) r.setProperty("--border", t.border);
        if (t.borderDim) r.setProperty("--border-dim", t.borderDim);
        if (t.accentGlow) r.setProperty("--accent-glow", t.accentGlow);
        if (t.accentGlowFaint) r.setProperty("--accent-glow-faint", t.accentGlowFaint);
        if (t.dangerGlow) r.setProperty("--danger-glow", t.dangerGlow);
        if (t.dangerBorder) r.setProperty("--danger-border", t.dangerBorder);
        if (t.key) r.setProperty("--key", t.key);
        if (t.mouse) r.setProperty("--mouse", t.mouse);
        if (t.scroll) r.setProperty("--scroll", t.scroll);
        if (t.radius !== undefined) {
            r.setProperty("--radius", t.radius + "px");
            r.setProperty("--radius-s", Math.max(0, t.radius - 1) + "px");
            var wr = (t.windowRadius !== undefined) ? t.windowRadius : t.radius;
            r.setProperty("--ms-window-radius", wr + "px");
        }
        if (t.font) {
            if (t.fontURL) {
                let el = document.getElementById("_ms-custom-font");
                if (!el) {
                    el = document.createElement("style");
                    el.id = "_ms-custom-font";
                    document.head.appendChild(el);
                }
                el.textContent = `@font-face { font-family: "${t.font}"; src: url("${t.fontURL}"); }`;
            }
            document.documentElement.style.setProperty("--font", `"${t.font}", Arial, Helvetica, sans-serif`);
        }
    }

    window.msTheme = { hexToRgb: hexToRgb, apply: applyTheme };
// END Theme //

    if (document.getElementById("ui-tokens-css")) return;

    var css =
        ":root{" +
        "--bg:#0d0f09;--surface:#141810;--surface2:#1c2116;--surface3:#24291a;--hover:#2d3523;" +
        "--accent:#6b8c3a;--accent-hi:#8db84e;--success:#7aa63c;" +
        "--danger-bg:#1c130f;--danger:#c0492e;--warning:#c4a030;" +
        "--text:#d4cfb6;--text2:rgba(212,207,182,0.85);--text3:rgba(212,207,182,0.55);" +
        "--border:rgba(141,184,78,0.30);--border-dim:rgba(141,184,78,0.14);" +
        "--border-faint:color-mix(in srgb,var(--border-dim) 50%,transparent);" +
        "--accent-glow:rgba(107,140,58,0.4);--accent-glow-faint:rgba(107,140,58,0.12);" +
        "--danger-glow:rgba(192,73,46,0.6);--danger-border:rgba(192,73,46,0.3);" +
        "--recording:#dc3232;--recording-text:#ff6b6b;--recording-bg:rgba(220,50,50,0.2);" +
        "--running:#64a0ff;--running-text:#88bbff;--running-bg:rgba(100,160,255,0.15);" +
        "--success-state:#7aa63c;--success-text:#8db84e;--success-bg:rgba(122,166,60,0.15);" +
        "--error-state:#c0492e;--error-text:#c0492e;--error-bg:rgba(192,73,46,0.15);" +
        "--radius:2px;--radius-s:1px;" +
        '--font:Arial,Helvetica,sans-serif;' +
        '--font-mono:"JetBrains Mono","SF Mono","Menlo",monospace;' +
        "--transition:120ms ease;" +
        "--rail-w:140px;" +
        "}";

    var s = document.createElement("style");
    s.id = "ui-tokens-css";
    s.textContent = css;
    var head = document.head || document.documentElement;
    head.insertBefore(s, head.firstChild);

// Accelerator key //
    function windowsKeys() {
        if (typeof window.msWindowsMode === "boolean") return window.msWindowsMode;
        return /Win/i.test(navigator.platform || "");
    }

    window.msMod = function (e) {
        if (windowsKeys()) return !!e.ctrlKey;
        return !!(e.metaKey || e.ctrlKey);
    };

    window.msKeyLabel = function (text) {
        if (!windowsKeys()) return text;
        return String(text).replace(/Cmd/g, "Ctrl");
    };
// END Accelerator key //
})();
