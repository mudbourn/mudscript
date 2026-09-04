(function() {
"use strict";

    var GLYPHS = window.MSGlyphs;

    var LABELS = {
        xbox: {
            confirm: "A",
            back: "B",
            x: "X",
            y: "Y",
            l1: "LB",
            r1: "RB",
            l2: "LT",
            r2: "RT",
            start: "Menu",
            view: "View",
            lstick: "L-stick",
            dpad: "D-pad",
            rstick: "R-stick",
            home: "Home",
        },
        ds4: {
            confirm: "Cross",
            back: "Circle",
            x: "Square",
            y: "Triangle",
            l1: "L1",
            r1: "R1",
            l2: "L2",
            r2: "R2",
            start: "Options",
            view: "Create",
            lstick: "L-stick",
            dpad: "D-pad",
            rstick: "R-stick",
            home: "PS",
        },
        switch: {
            confirm: "B",
            back: "A",
            x: "Y",
            y: "X",
            l1: "L",
            r1: "R",
            l2: "ZL",
            r2: "ZR",
            start: "Plus",
            view: "Minus",
            lstick: "L-stick",
            dpad: "D-pad",
            rstick: "R-stick",
            home: "Home",
        },
    };

    // Modifier glyphs annotate the button they follow rather than naming a
    // second button: repeat = tap again, hold = press and hold.
    var MODS = {
        "@repeat": '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M18 4L21 7M21 7L18 10M21 7H7C4.79086 7 3 8.79086 3 11M6 20L3 17M3 17L6 14M3 17H17C19.2091 17 21 15.2091 21 13" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
        "@hold": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" xmlns="http://www.w3.org/2000/svg"><path d="M9 5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v6a1 1 0 0 0 1 1h3.293a.707.707 0 0 1 .5 1.207l-7.086 7.086a1 1 0 0 1-1.414 0l-7.086-7.086a.707.707 0 0 1 .5-1.207H8a1 1 0 0 0 1-1z"/></svg>',
    };

    var GENERAL = [
        { badge: ["start", "+", "view"], title: function(L) { return L.start + " + " + L.view; }, desc: "Open or close the shell (or the Home button)" },
        { badge: ["lstick", "/", "dpad"], title: function(L) { return L.lstick + " / " + L.dpad; }, desc: "Move between items" },
        { badge: ["rstick"], title: function(L) { return L.rstick; }, desc: "Scroll the panel" },
        { badge: ["confirm"], title: function(L) { return L.confirm; }, desc: "Select the focused item" },
        { badge: ["back"], title: function(L) { return L.back; }, desc: "Back out, then close" },
        { badge: ["l1", "/", "r1"], title: function(L) { return L.l1 + " / " + L.r1; }, desc: "Previous / next panel" },
        { badge: ["l2", "/", "r2"], title: function(L) { return L.l2 + " / " + L.r2; }, desc: "Previous / next tab" },
        { badge: ["start"], title: function(L) { return L.start; }, desc: "Show or hide the sidebar" },
        { badge: ["view"], title: function(L) { return L.view; }, desc: "Jump to the top bar (double-tap pops out a dev tool)" },
        { badge: ["view", "@hold", "+", "dpad"], title: function(L) { return L.view + " + " + L.dpad; }, desc: "Scale the UI up or down" },
        { badge: ["y"], title: function(L) { return L.y; }, desc: "Copy the selection in a log panel" },
    ];

    var MACRO = [
        { badge: ["confirm"], title: function(L) { return L.confirm; }, desc: "Select the focused block" },
        { badge: ["confirm", "@hold"], title: function(L) { return L.confirm; }, desc: "Grab the block, steer with " + "D-pad, release to drop" },
        { badge: ["y"], title: function(L) { return L.y; }, desc: "Add a step from the palette" },
        { badge: ["x"], title: function(L) { return L.x; }, desc: "Open the block's context menu" },
        { badge: ["x", "@repeat"], title: function(L) { return L.x; }, desc: "Double-tap to duplicate the selection" },
        { badge: ["x", "@hold"], title: function(L) { return L.x; }, desc: "Delete the selected blocks" },
        { badge: ["l1", "/", "r1"], title: function(L) { return L.l1 + " / " + L.r1; }, desc: "Previous / next panel" },
        { badge: ["l2", "/", "r2"], title: function(L) { return L.l2 + " / " + L.r2; }, desc: "Previous / next tab" },
    ];

    var OSK = [
        { badge: ["lstick", "/", "dpad"], title: function(L) { return L.lstick + " / " + L.dpad; }, desc: "Pick a key" },
        { badge: ["confirm"], title: function(L) { return L.confirm; }, desc: "Press the highlighted key" },
        { badge: ["back"], title: function(L) { return L.back; }, desc: "Close the keyboard" },
        { badge: ["y"], title: function(L) { return L.y; }, desc: "Space" },
        { badge: ["x"], title: function(L) { return L.x; }, desc: "Backspace" },
        { badge: ["l1", "/", "r1"], title: function(L) { return L.l1 + " / " + L.r1; }, desc: "Move the caret left / right" },
        { badge: ["l2"], title: function(L) { return L.l2; }, desc: "Symbol layer" },
        { badge: ["r2"], title: function(L) { return L.r2; }, desc: "Shift" },
    ];

    var TABS = [
        { id: "general", label: "General", groups: [{ entries: GENERAL }] },
        { id: "macro", label: "Macro Lab", groups: [{ title: "Builder canvas", entries: MACRO }, { title: "On-screen keyboard", entries: OSK }] },
    ];

    function ensureCss() {
        if (document.getElementById("gp-map-css")) return;
        var s = document.createElement("style");
        s.id = "gp-map-css";
        s.textContent =
            ".gp-map-overlay { position: fixed; inset: 0; z-index: 60; display: none; align-items: center; justify-content: center;"
            + " background: rgba(0,0,0,0.55); opacity: 0; transition: opacity 0.15s ease; }"
            + ".gp-map-overlay.open { display: flex; opacity: 1; }"
            + ".gp-map-modal { display: flex; flex-direction: column; width: 640px; max-width: 92vw; max-height: 88vh;"
            + " background: var(--surface); border: 1px solid var(--border-dim); border-radius: var(--radius);"
            + " box-shadow: 0 12px 40px rgba(0,0,0,0.45); overflow: hidden; }"
            + ".gp-map-head { display: flex; align-items: center; justify-content: space-between; gap: 10px;"
            + " padding: 10px 12px; border-bottom: 1px solid var(--border-dim); flex-shrink: 0; }"
            + ".gp-map-head-l { display: flex; align-items: center; gap: 8px; min-width: 0; }"
            + ".gp-map-head svg { width: 30px; height: 30px; color: var(--text2); flex-shrink: 0; }"
            + ".gp-map-heading { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.8px; color: var(--text3); }"
            + ".gp-map-close { width: 24px; height: 24px; display: flex; align-items: center; justify-content: center;"
            + " border: none; background: transparent; border-radius: var(--radius); cursor: pointer; color: var(--text);"
            + " opacity: 0.5; font-size: 15px; transition: opacity 0.1s, background 0.1s; }"
            + ".gp-map-close:hover { opacity: 1; background: var(--hover); }"
            + ".gp-map-tabs { display: flex; gap: 4px; padding: 8px 12px 0; flex-shrink: 0; }"
            + ".gp-map-tab { padding: 5px 12px; border: 1px solid var(--border-dim); border-bottom: none;"
            + " background: var(--surface2); color: var(--text3); border-radius: var(--radius-s) var(--radius-s) 0 0;"
            + " font-size: 11px; font-weight: 700; cursor: pointer; }"
            + ".gp-map-tab.active { background: var(--surface); color: var(--accent); }"
            + ".gp-map-body { padding: 12px; overflow-y: auto; border-top: 1px solid var(--border-dim);"
            + " scrollbar-width: thin; scrollbar-color: var(--border) transparent; }"
            + ".gp-map-body::-webkit-scrollbar { width: 5px; }"
            + ".gp-map-body::-webkit-scrollbar-thumb { background: var(--border); border-radius: var(--radius-s); }"
            + ".gp-map-body::-webkit-scrollbar-track { background: transparent; }"
            + ".gp-map-group-title { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.6px;"
            + " color: var(--text3); margin: 4px 0 8px; }"
            + ".gp-map-group + .gp-map-group { margin-top: 14px; }"
            + ".gp-map-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 14px; }"
            + ".gp-map-item { display: flex; align-items: center; gap: 10px; padding: 6px 9px;"
            + " background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius-s); }"
            + ".gp-map-badge { display: flex; align-items: center; gap: 3px; flex-shrink: 0; color: var(--text); }"
            + ".gp-map-badge svg { width: 26px; height: 26px; display: block; }"
            + ".gp-map-mod { display: inline-flex; align-items: center; color: var(--text3); }"
            + ".gp-map-mod svg { width: 15px; height: 15px; }"
            + ".gp-map-key { display: inline-flex; align-items: center; justify-content: center; min-width: 20px; height: 22px;"
            + " padding: 0 6px; background: var(--surface); border: 1px solid var(--border-dim); border-radius: var(--radius-s);"
            + " font: 700 11px/1 var(--font-mono); color: var(--text); }"
            + ".gp-map-sep { color: var(--text3); font: 600 11px/1 var(--font-mono); }"
            + ".gp-map-txt { min-width: 0; }"
            + ".gp-map-title { font-size: 11px; font-weight: 700; color: var(--text); }"
            + ".gp-map-desc { font-size: 10px; color: var(--text3); line-height: 1.35; }"
            + "@media (max-width: 520px) { .gp-map-grid { grid-template-columns: 1fr; } }";
        (document.head || document.documentElement).appendChild(s);
    }

    function el(tag, cls) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        return e;
    }

    function badgeNode(tokens, g, L) {
        var badge = el("div", "gp-map-badge");
        var labels = [];
        tokens.forEach(function(tok) {
            if (tok === "+" || tok === "/") {
                var sep = el("span", "gp-map-sep");
                sep.textContent = tok;
                badge.appendChild(sep);
                return;
            }
            if (MODS[tok]) {
                var mod = el("span", "gp-map-mod");
                mod.innerHTML = MODS[tok];
                badge.appendChild(mod);
                return;
            }
            labels.push(L[tok] || tok);
            if (g[tok]) {
                var span = el("span");
                span.innerHTML = g[tok];
                badge.appendChild(span);
                return;
            }
            var key = el("span", "gp-map-key");
            key.textContent = L[tok] || tok;
            badge.appendChild(key);
        });
        badge._label = labels.join("");
        return badge;
    }

    function gridNode(entries, g, L) {
        var grid = el("div", "gp-map-grid");
        entries.forEach(function(entry) {
            var item = el("div", "gp-map-item");
            var badge = badgeNode(entry.badge, g, L);
            item.appendChild(badge);

            var txt = el("div", "gp-map-txt");
            var title = entry.title(L);
            if (title.replace(/[^a-z0-9]/gi, "") !== badge._label.replace(/[^a-z0-9]/gi, "")) {
                var ti = el("div", "gp-map-title");
                ti.textContent = title;
                txt.appendChild(ti);
            }
            var de = el("div", "gp-map-desc");
            de.textContent = entry.desc;
            txt.appendChild(de);
            item.appendChild(txt);

            grid.appendChild(item);
        });
        return grid;
    }

    function renderTab(body, tab, g, L) {
        body.innerHTML = "";
        tab.groups.forEach(function(group) {
            var wrap = el("div", "gp-map-group");
            if (group.title) {
                var gt = el("div", "gp-map-group-title");
                gt.textContent = group.title;
                wrap.appendChild(gt);
            }
            wrap.appendChild(gridNode(group.entries, g, L));
            body.appendChild(wrap);
        });
    }

    var overlay = null;

    function buildOverlay() {
        ensureCss();
        overlay = el("div", "gp-map-overlay");
        overlay.addEventListener("click", function(e) {
            if (e.target === overlay) window.closeGamepadMap();
        });

        var modal = el("div", "gp-map-modal");

        var head = el("div", "gp-map-head");
        var headL = el("div", "gp-map-head-l");
        var hero = el("span");
        var heading = el("span", "gp-map-heading");
        heading.textContent = "Controller Map";
        headL.appendChild(hero);
        headL.appendChild(heading);
        var close = el("button", "gp-map-close fn-picker-overlay-close");
        close.type = "button";
        close.textContent = "✕";
        close.addEventListener("click", function() { window.closeGamepadMap(); });
        head.appendChild(headL);
        head.appendChild(close);

        var tabsBar = el("div", "gp-map-tabs");
        var body = el("div", "gp-map-body");

        modal.appendChild(head);
        modal.appendChild(tabsBar);
        modal.appendChild(body);
        overlay.appendChild(modal);
        document.body.appendChild(overlay);

        overlay._hero = hero;
        overlay._tabsBar = tabsBar;
        overlay._body = body;
        overlay._active = 0;
        return overlay;
    }

    function selectTab(idx) {
        if (!overlay) return;
        var type = overlay._type;
        var g = GLYPHS[type], L = LABELS[type];
        idx = (idx + TABS.length) % TABS.length;
        overlay._active = idx;

        var btns = overlay._tabsBar.children;
        for (var i = 0; i < btns.length; i++) {
            btns[i].classList.toggle("active", i === idx);
        }

        renderTab(overlay._body, TABS[idx], g, L);
        overlay._body.scrollTop = 0;
        if (window.gpSetFocus && btns[idx]) window.gpSetFocus(btns[idx]);
    }

    window.openGamepadMap = function(type) {
        if (!overlay) buildOverlay();
        var t = GLYPHS[type] ? type : "xbox";
        overlay._type = t;

        overlay._hero.innerHTML = GLYPHS[t].silhouette;
        overlay._tabsBar.innerHTML = "";
        TABS.forEach(function(tab, i) {
            var btn = el("button", "gp-map-tab");
            btn.type = "button";
            btn.textContent = tab.label;
            btn.addEventListener("click", function() { selectTab(i); });
            overlay._tabsBar.appendChild(btn);
        });

        overlay.gpTab = function(dir) { selectTab(overlay._active + dir); };
        selectTab(0);
        overlay.classList.add("open");
        return overlay;
    };

    window.closeGamepadMap = function() {
        if (overlay) overlay.classList.remove("open");
    };

    window.buildGamepadMap = function(type) {
        return window.openGamepadMap(type);
    };
})();
