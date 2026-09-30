(function() {
    "use strict";

// Styles //
    var CSS = [
        ".ms-pop-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 320; opacity: 0; transition: opacity 0.18s; }",
        ".ms-pop-overlay.open { opacity: 1; }",
        ".ms-pop-card { background: var(--surface); border-top: 2px solid var(--accent); border-radius: var(--radius); padding: 16px 18px; width: 340px; max-height: 82vh; overflow-y: auto; scrollbar-width: thin; scrollbar-color: var(--surface2) transparent; box-shadow: 0 16px 48px rgba(0,0,0,0.7), 0 0 0 1px var(--border); transform: scale(0.96); transition: transform 0.18s; }",
        ".ms-pop-overlay.open .ms-pop-card { transform: scale(1); }",
        ".ms-pop-title { font-size: 14px; font-weight: 700; color: var(--text); }",
        ".ms-pop-sub { font-size: 11px; color: var(--text2); margin: 2px 0 10px; line-height: 1.5; }",
        ".ms-pop-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 9px 0; border-bottom: 1px solid var(--border-dim, var(--border)); }",
        ".ms-pop-row:last-child { border-bottom: none; }",
        ".ms-pop-label { min-width: 0; flex: 1; font-size: 12px; color: var(--text); }",
        ".ms-pop-hint { font-size: 10px; color: var(--text3); margin-top: 2px; line-height: 1.4; }",
        ".ms-pop-btn { background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text2); font-family: inherit; font-size: 11px; font-weight: 600; padding: 5px 10px; cursor: pointer; white-space: nowrap; transition: color 0.1s, border-color 0.1s; }",
        ".ms-pop-btn:hover { color: var(--accent); border-color: var(--accent); }",
        ".ms-pop-btn.danger { color: var(--danger); }",
        ".ms-pop-btn.danger:hover { background: var(--danger-bg); border-color: var(--danger); }",
        "body > .macro-select-menu { z-index: 330; }",
        ".ms-pop-actions { display: flex; justify-content: space-between; gap: 8px; margin-top: 14px; }",
    ].join("\n");

    function injectStyles() {
        if (document.getElementById("ms-pop-styles")) return;
        var s = document.createElement("style");
        s.id = "ms-pop-styles";
        s.textContent = CSS;
        document.head.appendChild(s);
    }
// END Styles //

// Controls //
    function sound(slot) {
        if (window.playSlot) playSlot(slot);
    }

    function toggle(checked, onChange) {
        var wrap = document.createElement("label");
        wrap.className = "toggle";
        var input = document.createElement("input");
        input.type = "checkbox";
        input.checked = !!checked;
        var track = document.createElement("span");
        track.className = "toggle-track";
        var thumb = document.createElement("span");
        thumb.className = "toggle-thumb";
        wrap.appendChild(input);
        wrap.appendChild(track);
        wrap.appendChild(thumb);
        input.addEventListener("change", function() {
            sound(input.checked ? "toggleOn" : "toggleOff");
            onChange(input.checked);
        });
        return wrap;
    }

    function seg(options, active, onSelect) {
        var wrap = document.createElement("div");
        wrap.className = "seg";
        options.forEach(function(o) {
            var b = document.createElement("button");
            b.className = "seg-btn" + (o.value === active ? " active" : "");
            b.textContent = o.label;
            b.addEventListener("click", function() {
                sound("interact");
                Array.prototype.forEach.call(wrap.children, function(c) { c.classList.remove("active"); });
                b.classList.add("active");
                onSelect(o.value);
            });
            wrap.appendChild(b);
        });
        return wrap;
    }

    function button(label, onClick, danger) {
        var b = document.createElement("button");
        b.className = "ms-pop-btn" + (danger ? " danger" : "");
        b.textContent = label;
        b.addEventListener("mouseenter", function() { sound("hover"); });
        b.addEventListener("click", function() {
            sound("interact");
            onClick();
        });
        return b;
    }

    function select(options, value, onChange) {
        if (typeof window.createSelect !== "function") return document.createElement("span");
        return window.createSelect({ options: options, value: value, minWidth: 150, onChange: onChange });
    }
// END Controls //

// Popup //
    var _open = null;

    function close() {
        if (!_open) return;
        var ov = _open.overlay;
        document.removeEventListener("keydown", _open.onKey, true);
        _open = null;
        ov.classList.remove("open");
        setTimeout(function() { ov.remove(); }, 200);
    }

    function open(title, sub, build) {
        close();
        injectStyles();
        var overlay = document.createElement("div");
        overlay.className = "ms-pop-overlay";
        var card = document.createElement("div");
        card.className = "ms-pop-card";
        overlay.appendChild(card);

        var t = document.createElement("div");
        t.className = "ms-pop-title";
        t.textContent = title;
        card.appendChild(t);
        if (sub) {
            var s = document.createElement("div");
            s.className = "ms-pop-sub";
            s.textContent = sub;
            card.appendChild(s);
        }

        var body = document.createElement("div");
        card.appendChild(body);
        var actions = document.createElement("div");
        actions.className = "ms-pop-actions";

        var api = {
            close:  close,
            toggle: toggle,
            seg:    seg,
            button: button,
            select: select,
            row: function(label, hint, control) {
                var r = document.createElement("div");
                r.className = "ms-pop-row";
                var l = document.createElement("div");
                l.className = "ms-pop-label";
                l.textContent = label;
                if (hint) {
                    var hEl = document.createElement("div");
                    hEl.className = "ms-pop-hint";
                    hEl.textContent = hint;
                    l.appendChild(hEl);
                }
                r.appendChild(l);
                if (control) r.appendChild(control);
                body.appendChild(r);
                return r;
            },
            action: function(el) {
                actions.appendChild(el);
            },
        };
        build(api);
        actions.appendChild(button("Done", close));
        card.appendChild(actions);

        overlay.addEventListener("click", function(e) {
            if (e.target === overlay) {
                sound("back");
                close();
            }
        });
        var onKey = function(e) {
            if (e.key === "Escape") {
                e.stopPropagation();
                close();
            }
        };
        document.addEventListener("keydown", onKey, true);
        document.body.appendChild(overlay);
        _open = { overlay: overlay, onKey: onKey };
        requestAnimationFrame(function() { overlay.classList.add("open"); });
        sound("interact");
    }

    window.msPopup = { open: open, close: close };
// END Popup //
})();
