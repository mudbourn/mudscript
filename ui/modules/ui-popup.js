(function() {
    "use strict";

// Styles //
    var CSS = [
        ".ms-pop-overlay { position: fixed; inset: 0; border-radius: var(--ms-window-radius, 0px); background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; opacity: 0; transition: opacity 0.18s; }",
        ".ms-pop-overlay.open { opacity: 1; }",
        ".ms-pop-card { background: linear-gradient(var(--accent), var(--accent)) top / 100% 2px no-repeat, var(--surface); background-clip: padding-box; border: 1px solid var(--border); border-radius: var(--radius); padding: 16px 18px; width: 340px; max-width: calc(100% - 32px); max-height: 82vh; overflow-y: auto; scrollbar-width: thin; scrollbar-color: var(--surface2) transparent; box-shadow: 0 16px 48px rgba(0,0,0,0.7); transform: scale(0.96); transition: transform 0.18s; }",
        ".ms-pop-overlay.open .ms-pop-card { transform: scale(1); }",
        ".ms-pop-overlay.tone-danger .ms-pop-card { background: linear-gradient(var(--danger), var(--danger)) top / 100% 2px no-repeat, var(--surface); background-clip: padding-box; border-color: var(--danger-border, var(--danger)); width: 400px; }",
        ".ms-pop-overlay.tone-danger .ms-pop-title { color: var(--danger); display: flex; align-items: center; gap: 8px; }",
        ".ms-pop-title .icon { width: 18px; height: 18px; flex-shrink: 0; }",
        ".ms-pop-text { margin-top: 10px; font-size: 13px; line-height: 1.55; color: var(--text2); }",
        ".ms-pop-text p { margin: 0 0 10px; }",
        ".ms-pop-text p:last-child { margin-bottom: 0; }",
        ".ms-pop-text strong { color: var(--text); font-weight: 700; }",
        ".ms-pop-title { font-size: 14px; font-weight: 700; color: var(--text); }",
        ".ms-pop-sub { font-size: 12px; color: var(--text2); margin: 4px 0 10px; line-height: 1.5; white-space: pre-line; }",
        ".ms-pop-row { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 9px 0; border-bottom: 1px solid var(--border-dim, var(--border)); }",
        ".ms-pop-row:last-child { border-bottom: none; }",
        ".ms-pop-label { min-width: 0; flex: 1; font-size: 12px; color: var(--text); }",
        ".ms-pop-hint { font-size: 10px; color: var(--text3); margin-top: 2px; line-height: 1.4; }",
        ".ms-pop-btn { background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text2); font-family: inherit; font-size: 11px; font-weight: 600; padding: 5px 10px; cursor: pointer; white-space: nowrap; transition: color 0.1s, border-color 0.1s, background 0.1s; }",
        ".ms-pop-btn:hover { color: var(--accent); border-color: var(--accent); }",
        ".ms-pop-btn.primary { background: var(--accent); border-color: var(--accent); color: var(--bg); }",
        ".ms-pop-btn.primary:hover { background: var(--accent-hi); color: var(--bg); }",
        ".ms-pop-btn.danger { color: var(--danger); }",
        ".ms-pop-btn.danger:hover { background: var(--danger-bg); border-color: var(--danger); }",
        ".ms-pop-btn.danger-solid { background: var(--danger); border-color: var(--danger); color: var(--bg); }",
        ".ms-pop-btn.danger-solid:hover { opacity: 0.85; color: var(--bg); }",
        ".ms-pop-actions { display: flex; gap: 8px; margin-top: 14px; }",
        ".ms-pop-actions .ms-pop-btn { padding: 7px 12px; font-size: 12px; }",
        ".ms-pop-actions.fill .ms-pop-btn { flex: 1; }",
        ".ms-pop-spacer { flex: 1; }",
        ".ms-pop-input { margin-top: 10px; width: 100%; box-sizing: border-box; background: var(--surface2); border: 1px solid var(--border); border-radius: var(--radius-s); padding: 7px 10px; font-family: inherit; font-size: 13px; color: var(--text); }",
        ".ms-pop-keys { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; justify-content: center; margin: 16px 0 4px; }",
        ".ms-pop-key { min-width: 20px; padding: 7px 11px; border-radius: var(--radius); background: var(--surface3); border: 1px solid var(--accent); border-bottom-width: 2px; box-shadow: 0 0 0 3px var(--accent-glow-faint), 0 2px 5px rgba(0,0,0,0.35); color: var(--accent-hi); font: 600 13px/1 var(--font); text-align: center; }",
        ".ms-pop-key.placeholder { background: var(--surface2); border-color: var(--border); border-bottom-width: 1px; color: var(--text3); box-shadow: none; letter-spacing: 3px; padding-left: 14px; }",
        ".ms-pop-key-plus { color: var(--text3); font: 600 12px/1 var(--font); }",
        ".ms-pop-range { display: flex; align-items: center; gap: 10px; }",
        ".ms-pop-range input { flex: 1; min-width: 110px; accent-color: var(--accent); }",
        ".ms-pop-range span { font-size: 12px; color: var(--text2); min-width: 20px; text-align: right; font-variant-numeric: tabular-nums; }",
        "body > .macro-select-menu { z-index: 400; }",
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

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text != null) e.textContent = text;
        return e;
    }

    function toggle(checked, onChange) {
        var wrap = el("label", "toggle");
        var input = el("input");
        input.type = "checkbox";
        input.checked = !!checked;
        wrap.appendChild(input);
        wrap.appendChild(el("span", "toggle-track"));
        wrap.appendChild(el("span", "toggle-thumb"));
        input.addEventListener("change", function() {
            sound(input.checked ? "toggleOn" : "toggleOff");
            onChange(input.checked);
        });
        return wrap;
    }

    function seg(options, active, onSelect) {
        var wrap = el("div", "seg");
        options.forEach(function(o) {
            var b = el("button", "seg-btn" + (o.value === active ? " active" : ""), o.label);
            if (o.hint) b.title = o.hint;
            b.addEventListener("mouseenter", function() { sound("hover"); });
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

    function button(label, onClick, kind) {
        var b = el("button", "ms-pop-btn" + (kind ? " " + kind : ""), label);
        b.addEventListener("mouseenter", function() { sound("hover"); });
        b.addEventListener("click", function() {
            sound(kind === "back" ? "back" : "interact");
            onClick();
        });
        return b;
    }

    function select(options, value, onChange) {
        if (typeof window.createSelect !== "function") return el("span");
        return window.createSelect({ options: options, value: value, minWidth: 150, onChange: onChange });
    }

    function range(min, max, value, onChange) {
        var wrap = el("div", "ms-pop-range");
        var input = el("input");
        input.type = "range";
        input.min = String(min);
        input.max = String(max);
        input.step = "1";
        input.value = String(value != null ? value : min);
        var out = el("span", null, input.value);
        input.addEventListener("input", function() { out.textContent = input.value; });
        input.addEventListener("change", function() {
            sound("interact");
            onChange(parseInt(input.value, 10));
        });
        wrap.appendChild(input);
        wrap.appendChild(out);
        return wrap;
    }

    var WARN_SVG = '<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/></svg>';

    function text(paragraphs) {
        var wrap = el("div", "ms-pop-text");
        paragraphs.forEach(function(parts) {
            var para = el("p");
            (Array.isArray(parts) ? parts : [parts]).forEach(function(part) {
                if (typeof part === "string") para.appendChild(document.createTextNode(part));
                else para.appendChild(el("strong", null, part.strong));
            });
            wrap.appendChild(para);
        });
        return wrap;
    }

    function renderKeys(box, keys) {
        box.innerHTML = "";
        var arr = Array.isArray(keys) ? keys : [];
        if (!arr.length) {
            box.appendChild(el("kbd", "ms-pop-key placeholder", "..."));
            return;
        }
        arr.forEach(function(k, i) {
            if (i > 0) box.appendChild(el("span", "ms-pop-key-plus", "+"));
            box.appendChild(el("kbd", "ms-pop-key", k));
        });
    }
// END Controls //

// Popup stack //
    var _stack = [];
    var BASE_Z = 300;

    function topPop() {
        return _stack.length ? _stack[_stack.length - 1] : null;
    }

    function dismiss(pop, result) {
        var i = _stack.indexOf(pop);
        if (i === -1) return;
        _stack.splice(i, 1);
        pop.overlay.classList.remove("open");
        setTimeout(function() { pop.overlay.remove(); }, 200);
        if (pop.onClose) pop.onClose(result);
    }

    function cancel(pop) {
        dismiss(pop, pop.onCancel ? pop.onCancel() : undefined);
    }

    function open(opts) {
        injectStyles();
        opts = opts || {};
        var overlay = el("div", "ms-pop-overlay" + (opts.tone ? " tone-" + opts.tone : ""));
        overlay.setAttribute("role", opts.tone === "danger" ? "alertdialog" : "dialog");
        overlay.setAttribute("aria-modal", "true");
        overlay.style.zIndex = String(BASE_Z + _stack.length * 10);
        var card = el("div", "ms-pop-card");
        if (opts.width) card.style.width = opts.width + "px";
        overlay.appendChild(card);

        var titleEl = el("div", "ms-pop-title");
        var titleText = el("span", null, opts.title || "");
        if (opts.tone === "danger") titleEl.innerHTML = WARN_SVG;
        titleEl.appendChild(titleText);
        card.appendChild(titleEl);
        var subEl = el("div", "ms-pop-sub", opts.sub || "");
        subEl.style.display = opts.sub ? "" : "none";
        card.appendChild(subEl);
        var body = el("div");
        card.appendChild(body);
        var actions = el("div", "ms-pop-actions");

        var pop = {
            overlay:   overlay,
            onClose:   opts.onClose,
            onCancel:  opts.onCancel,
            onConfirm: opts.onConfirm,
        };
        var api = {
            el:      card,
            actions: actions,
            close:   function(result) { dismiss(pop, result); },
            toggle:  toggle,
            seg:     seg,
            button:  button,
            select:  select,
            range:   range,
            text:    function(paragraphs) { return api.add(text(paragraphs)); },
            setTitle: function(t) { titleText.textContent = t || ""; },
            setSub: function(text) {
                subEl.textContent = text || "";
                subEl.style.display = text ? "" : "none";
            },
            isOpen: function() { return _stack.indexOf(pop) !== -1; },
            add: function(node) {
                body.appendChild(node);
                return node;
            },
            row: function(label, hint, control) {
                var r = el("div", "ms-pop-row");
                var l = el("div", "ms-pop-label", label);
                if (hint) l.appendChild(el("div", "ms-pop-hint", hint));
                r.appendChild(l);
                if (control) r.appendChild(control);
                body.appendChild(r);
                return r;
            },
            action: function(node) {
                actions.appendChild(node);
                return node;
            },
            spacer: function() {
                actions.appendChild(el("span", "ms-pop-spacer"));
            },
        };
        pop.api = api;
        if (opts.build) opts.build(api);
        if (!opts.noDone && !actions.children.length) {
            api.spacer();
            api.action(button("Done", function() { api.close(); }));
        }
        if (actions.children.length) card.appendChild(actions);

        overlay.addEventListener("click", function(e) {
            if (e.target === overlay) {
                sound("back");
                cancel(pop);
            }
        });
        document.body.appendChild(overlay);
        _stack.push(pop);
        requestAnimationFrame(function() { overlay.classList.add("open"); });
        if (!opts.silent) sound("interact");
        return api;
    }

    document.addEventListener("keydown", function(e) {
        var pop = topPop();
        if (!pop) return;
        if (e.key === "Escape") {
            e.preventDefault();
            e.stopPropagation();
            sound("back");
            cancel(pop);
        } else if (e.key === "Enter" && pop.onConfirm) {
            e.preventDefault();
            e.stopPropagation();
            sound("interact");
            pop.onConfirm();
        }
    }, true);
// END Popup stack //

// Dialog //
    function dialog(opts) {
        opts = opts || {};
        var input = null;
        var keysBox = null;
        var btnConfirm = null;
        var btnCancel = null;
        var api = null;
        function result(confirmed) {
            return { confirmed: !!confirmed, value: input ? input.value : "" };
        }
        var done = new Promise(function(resolve) {
            api = open({
                title:     opts.title,
                sub:       opts.msg,
                width:     300,
                silent:    true,
                noDone:    true,
                onClose:   function(r) { resolve(r || result(false)); },
                onCancel:  function() { return result(false); },
                onConfirm: function() { api.close(result(true)); },
                build: function(p) {
                    keysBox = p.add(el("div", "ms-pop-keys"));
                    keysBox.style.display = "none";
                    if (opts.input) {
                        input = p.add(el("input", "ms-pop-input"));
                        input.type = "text";
                        input.value = opts.defaultVal || "";
                        input.setAttribute("autocomplete", "off");
                        input.setAttribute("spellcheck", "false");
                        setTimeout(function() { input.focus(); }, 100);
                    }
                    p.actions.classList.add("fill");
                    btnCancel = p.action(button(opts.cancelLabel || "Cancel", function() {
                        p.close(result(false));
                    }, "back"));
                    btnConfirm = p.action(button(opts.confirmLabel || "OK", function() {
                        p.close(result(true));
                    }, "primary"));
                },
            });
        });
        api.result = done;
        api.setKeys = function(keys) {
            keysBox.style.display = "flex";
            renderKeys(keysBox, keys);
        };
        api.setConfirmLabel = function(t) { btnConfirm.textContent = t; };
        api.setCancelLabel = function(t) { btnCancel.textContent = t; };
        api.showConfirm = function(on) { btnConfirm.style.display = on ? "" : "none"; };
        api.showCancel = function(on) { btnCancel.style.display = on ? "" : "none"; };
        api.finish = function(confirmed) { api.close(result(confirmed)); };
        return api;
    }
// END Dialog //

    window.msPopup = {
        open:   open,
        dialog: dialog,
        isOpen: function() { return _stack.length > 0; },
        topEl:  function() { var p = topPop(); return p ? p.overlay : null; },
        cancelTop: function() {
            var p = topPop();
            if (p) cancel(p);
        },
    };
})();
