(function () {
    "use strict";
    if (document.getElementById("ui-tokens-css")) return;

    var css =
        ":root{" +
        "--bg:#0d0f09;--surface:#141810;--surface2:#1c2116;--surface3:#24291a;--hover:#2d3523;" +
        "--accent:#6b8c3a;--accent-hi:#8db84e;--success:#7aa63c;" +
        "--danger-bg:#1c130f;--danger:#c0492e;--warning:#c4a030;" +
        "--text:#d4cfb6;--text2:rgba(212,207,182,0.85);--text3:rgba(212,207,182,0.55);" +
        "--border:rgba(141,184,78,0.30);--border-dim:rgba(141,184,78,0.14);" +
        "--border-faint:rgba(141,184,78,0.07);" +
        "--accent-glow:rgba(107,140,58,0.4);--accent-glow-faint:rgba(107,140,58,0.12);" +
        "--danger-glow:rgba(192,73,46,0.6);--danger-border:rgba(192,73,46,0.3);" +
        "--recording:#dc3232;--recording-text:#ff6b6b;--recording-bg:rgba(220,50,50,0.2);" +
        "--running:#64a0ff;--running-text:#88bbff;--running-bg:rgba(100,160,255,0.15);" +
        "--success-state:#7aa63c;--success-text:#8db84e;--success-bg:rgba(122,166,60,0.15);" +
        "--error-state:#c0492e;--error-text:#c0492e;--error-bg:rgba(192,73,46,0.15);" +
        "--radius:2px;--radius-s:1px;" +
        '--font:Arial,"Almendra",sans-serif;' +
        '--font-mono:"JetBrains Mono","SF Mono","Menlo",monospace;' +
        "--transition:120ms ease;" +
        "--rail-w:140px;" +
        "}";

    var s = document.createElement("style");
    s.id = "ui-tokens-css";
    s.textContent = css;
    var head = document.head || document.documentElement;
    head.insertBefore(s, head.firstChild);
})();
