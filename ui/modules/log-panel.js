(function() {
    "use strict";

// Theme //
function hexToRgb(hex) {
    hex = hex.replace(/^#/, "");
    if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
    const n = parseInt(hex, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

// Global UI zoom. WebKit's CSS `zoom` scales all content (fonts, padding,
// controls, canvas) in one property, so the shell and every popout share this
// one applier — same seam as applyTheme. Called from the pushed state and from
// the Lua-side zoom broadcast (ms.dev:rezoom / ms.shell.applyZoom).
function applyZoom(z) {
    var v = parseFloat(z);
    if (!isFinite(v) || v <= 0) v = 1;
    v = Math.max(0.5, Math.min(2.0, v));
    document.documentElement.style.zoom = String(v);
}
if (typeof window !== "undefined") window.applyZoom = applyZoom;

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
        if (c) r.setProperty("--text2", `rgba(${c.r},${c.g},${c.b},0.85)`);
    }
    if (t.text && !t.text3) {
        const c = hexToRgb(t.text);
        if (c) r.setProperty("--text3", `rgba(${c.r},${c.g},${c.b},0.55)`);
    }
    if (t.accent && t.hover && !t.border) {
        const a = hexToRgb(t.accent);
        const h = hexToRgb(t.hover);
        if (a && h) {
            const mr = Math.round(a.r * 0.5 + h.r * 0.5);
            const mg = Math.round(a.g * 0.5 + h.g * 0.5);
            const mb = Math.round(a.b * 0.5 + h.b * 0.5);
            r.setProperty("--border", `rgba(${mr},${mg},${mb},0.55)`);
            r.setProperty("--border-dim", `rgba(${mr},${mg},${mb},0.18)`);
        }
    }
    if (t.accent && !t.accentGlow) {
        const a = hexToRgb(t.accent);
        if (a) r.setProperty("--accent-glow", `rgba(${a.r},${a.g},${a.b},0.4)`);
    }
    if (t.accent && !t.accentGlowFaint) {
        const a = hexToRgb(t.accent);
        if (a) r.setProperty("--accent-glow-faint", `rgba(${a.r},${a.g},${a.b},0.12)`);
    }
    if (t.danger && !t.dangerGlow) {
        const d = hexToRgb(t.danger);
        if (d) r.setProperty("--danger-glow", `rgba(${d.r},${d.g},${d.b},0.6)`);
    }
    if (t.danger && !t.dangerBorder) {
        const d = hexToRgb(t.danger);
        if (d) r.setProperty("--danger-border", `rgba(${d.r},${d.g},${d.b},0.3)`);
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
        document.body.style.fontFamily = `"${t.font}", Almendra, Palatino, Georgia, serif`;
    }
}

// Default copy text extractor //
function defaultExtractCopyText(el) {
    const ts = el.querySelector(".ts")?.textContent || "";
    const badge = (el.querySelector(".badge")?.textContent || "").toUpperCase();
    // Try .msg first, then .tool-msg, then gather all text content as fallback
    let msg = el.querySelector(".msg")?.textContent || "";
    if (!msg) msg = el.querySelector(".tool-msg")?.textContent || "";
    if (!msg) {
        // Fallback: gather non-ts, non-badge text from child spans
        const parts = [];
        el.querySelectorAll(".key-name, .mouse-name, .scroll-name, .arrow, .dim, .input").forEach(s => {
            const t = s.textContent?.trim();
            if (t) parts.push(t);
        });
        msg = parts.join(" ");
    }
    const repeat = el.querySelector(".repeat-badge")?.textContent || "";
    const prefix = badge ? `${ts} [${badge}]` : ts;
    const suffix = repeat ? ` ${repeat}` : '';
    return msg ? `${prefix} ${msg}${suffix}` : `${prefix}${suffix}`;
}

// Time helpers //
function pad2(n) { return String(n).padStart(2, "0"); }

function nowTs() {
    const d = new Date();
    return (
        pad2(d.getHours()) + ":" +
        pad2(d.getMinutes()) + ":" +
        pad2(d.getSeconds())
    );
}

// Scroll primitives //
function _isNearBottom(logEl, thresh) {
    if (!logEl) return false;
    return (
        logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight <=
        thresh
    );
}

function _trimLog(logEl, max) {
    while (logEl.childElementCount > max) {
        logEl.removeChild(logEl.firstElementChild);
    }
}

// Factory //
/**
 * @param {Object} config
 * @param {string} config.channel        - WebKit message handler name
 * @param {function} config.buildRow     - (entry) => HTMLElement
 * @param {string} [config.entrySelector="#log .entry, #log .step"]
 * @param {function} [config.extractCopyText] - (el) => string
 * @param {string} [config.clearAction="clearLog"] - global fn name for Clear
 * @param {number} [config.maxEntries=300]
 * @param {number} [config.scrollThresh=48]
 * @returns {Object} controller with methods to expose as globals
 */
function createLogPanel(config) {
    const {
        channel,
        buildRow,
        container = null,
        entrySelector = "#log .entry, #log .step",
        extractCopyText = defaultExtractCopyText,
        clearAction = "clearLog",
        maxEntries = 300,
        scrollThresh = 48,
    } = config;

    // Scoped DOM queries, container.querySelector finds the right #log
    // even when multiple panels share the same id="log"
    const _root = container || document;
    function _byId(id) { return _root.querySelector('#' + id); }
    function _queryAll(sel) { return _root.querySelectorAll(sel); }

    // Host bridge //
    function sendToHost(msg) {
        const s = typeof msg === "string" ? msg : JSON.stringify(msg);
        if (window.shellPost) {
            // Running inside the Macro Lab shell, route through msShell channel
            const data = typeof msg === "string" ? JSON.parse(msg) : msg;
            window.shellPost(channel, data.action || "unknown", data);
        } else {
            try {
                window.webkit.messageHandlers[channel].postMessage(s);
            } catch (e) {}
        }
    }

    function playSlot(slot) {
        if (slot === "hover" && !document.hasFocus()) return;
        sendToHost({ action: "playSlot", slot });
    }

    // Pause state //
    let _paused = false;
    function togglePause() {
        _paused = !_paused;
        const btn = _byId("pause-btn");
        if (btn) btn.textContent = _paused ? "Resume" : "Pause";
    }

    // Selection state //
    const _selected = new Set();
    let _lastClicked = null;

    function _getEntries() {
        return Array.from(_queryAll(entrySelector));
    }

    function _updateSelectionVisuals() {
        for (const el of _getEntries()) {
            el.classList.toggle("selected", _selected.has(el));
        }
    }

    function _handleEntryClick(e) {
        const row = e.currentTarget;
        const entries = _getEntries();
        const idx = entries.indexOf(row);
        if (idx === -1) return;
        playSlot("interact");

        if (e.shiftKey && _lastClicked !== null) {
            const lo = Math.min(_lastClicked, idx);
            const hi = Math.max(_lastClicked, idx);
            for (let i = lo; i <= hi; i++) _selected.add(entries[i]);
        } else if (e.metaKey || e.ctrlKey) {
            if (_selected.has(row)) _selected.delete(row);
            else _selected.add(row);
        } else {
            if (_selected.has(row) && _selected.size === 1) {
                _selected.delete(row);
            } else {
                _selected.clear();
                _selected.add(row);
            }
        }
        _lastClicked = idx;
        _updateSelectionVisuals();
    }

    function _copySelected() {
        if (_selected.size === 0) return;
        const lines = [];
        for (const el of _getEntries()) {
            if (_selected.has(el)) {
                lines.push(extractCopyText(el));
            }
        }
        const text = lines.join("\n");
        // Try native clipboard first, fall back to host
        try {
            navigator.clipboard.writeText(text).catch(() => {
                if (typeof shellDispatch === "function") {
                    shellDispatch("_shell", "clipboard", { text });
                }
            });
        } catch (_) {
            if (typeof shellDispatch === "function") {
                shellDispatch("_shell", "clipboard", { text });
            }
        }
        playSlot("update");
    }

    function _selectAll() {
        _selected.clear();
        for (const el of _getEntries()) _selected.add(el);
        _updateSelectionVisuals();
    }

    // Context menu //
    function closeCtxMenu() {
        const el = _byId("ctx-menu");
        if (el) el.classList.remove("open");
    }

    function showCtxMenu(x, y, items) {
        const el = _byId("ctx-menu");
        if (!el) return;
        el.innerHTML = "";
        for (const item of items) {
            if (item === "divider") {
                const d = document.createElement("div");
                d.className = "ctx-divider";
                el.appendChild(d);
                continue;
            }
            const row = document.createElement("div");
            row.className = "ctx-item";
            row.textContent = item.label;
            row.addEventListener("mouseenter", () => playSlot("hover"));
            row.addEventListener("click", (e) => {
                e.stopPropagation();
                playSlot("interact");
                closeCtxMenu();
                item.action();
            });
            el.appendChild(row);
        }
        // Keep the menu fully visible: clamp horizontally, flip up when there's
        // more room above, and cap the height so a tall menu scrolls internally
        // rather than spilling past the window border and getting clipped.
        el.classList.add("open");
        el.style.maxHeight = "";
        const MARGIN = 6;
        // The menu is position:fixed inside the zoomed root, so its left/top and
        // offsetWidth/scrollHeight are in zoomed CSS px, while the incoming x/y
        // (clientX/Y) and innerWidth/Height come back in physical px. Fold the
        // pointer and viewport into the same zoomed space or the menu lands
        // off-cursor once the UI is scaled.
        const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
        x /= zoom; y /= zoom;
        const vw = window.innerWidth / zoom, vh = window.innerHeight / zoom;
        const mw = el.offsetWidth || 140;
        const naturalH = el.scrollHeight;
        const left = Math.max(MARGIN, Math.min(x, vw - mw - MARGIN));
        const spaceBelow = vh - y - MARGIN, spaceAbove = y - MARGIN;
        let top, maxH;
        if (naturalH <= spaceBelow)      { top = y;            maxH = spaceBelow; }
        else if (naturalH <= spaceAbove) { top = y - naturalH; maxH = spaceAbove; }
        else if (spaceBelow >= spaceAbove) { top = y;          maxH = spaceBelow; }
        else                             { top = MARGIN;        maxH = spaceAbove; }
        top = Math.max(MARGIN, top);
        el.style.left = left + "px";
        el.style.top = top + "px";
        el.style.maxHeight = maxH + "px";
    }

    // Suppress native context menu, show custom menu
    document.addEventListener("contextmenu", (e) => {
        // Only handle when this panel is visible
        if (container && container.style.display === "none") return;
        if (container && getComputedStyle(container).display === "none") return;
        e.preventDefault();
        const row = e.target.closest(".entry, .step");
        const items = [];
        if (row && !_selected.has(row)) {
            _selected.clear();
            _selected.add(row);
            _updateSelectionVisuals();
        }
        if (_selected.size > 0) {
            items.push({ label: "Copy", action: _copySelected });
            items.push("divider");
        }
        items.push({ label: "Select All", action: _selectAll });
        items.push({
            label: "Clear",
            action: () => {
                if (typeof window[clearAction] === "function") window[clearAction]();
            },
        });
        showCtxMenu(e.clientX, e.clientY, items);
    });

    document.addEventListener("click", () => closeCtxMenu());

    // Keyboard shortcuts //
    document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") closeCtxMenu();
        // Only handle shortcuts when this panel is visible
        if (container && container.style.display === "none") return;
        if (container && getComputedStyle(container).display === "none") return;
        const inInput = e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA";
        if ((e.metaKey || e.ctrlKey) && e.key === "a" && !inInput) {
            e.preventDefault();
            _selectAll();
        }
        if ((e.metaKey || e.ctrlKey) && e.key === "c" && !inInput && _selected.size > 0) {
            e.preventDefault();
            _copySelected();
        }
    });

    // Window drag (title header + rail top strip) //
    // A webview reports pointer coords relative to its own (moving) window, so any
    // JS-side delta feeds back and flings the panel off-screen. We only tell Lua
    // when the drag starts/ends; it tracks the real OS mouse position itself.
    (function () {
        document.addEventListener("mousedown", (e) => {
            if (e.button !== 0) return;
            if (!e.target.closest("#header, #rail-drag")) return;
            if (e.target.closest(".header-btns")) return;
            sendToHost({ action: "dragStart" });
            // While dragging, the window slides under a near-stationary cursor, which
            // would otherwise sweep hover across every rail item (their transitions
            // leave a trail of half-highlighted rows). Suppress pointer interaction
            // for the duration so nothing spuriously highlights.
            document.body.classList.add("dragging");
            const onUp = () => {
                document.body.classList.remove("dragging");
                sendToHost({ action: "moveEnd" });
                window.removeEventListener("mouseup", onUp);
            };
            window.addEventListener("mouseup", onUp);
        });
    })();

    // Resize grab zones //
    (function () {
        document.querySelectorAll(".resize-zone").forEach(function(zone) {
            zone.addEventListener("mousedown", function(e) {
                if (e.button !== 0) return;
                var edge = zone.dataset.edge;
                if (!edge) return;
                window.__msResizing = true;
                sendToHost({ action: "resizeStart", edge: edge });
                document.body.classList.add("resizing");
                var onUp = function() {
                    window.__msResizing = false;
                    document.body.classList.remove("resizing");
                    window.removeEventListener("mouseup", onUp);
                };
                window.addEventListener("mouseup", onUp);
            });
        });
    })();

    // Minimum size //
    // The floor is enforced entirely in the Lua resize math (_resizeEdgeMath),
    // which clamps smoothly as you drag an edge. The old JS approach watched the
    // resize event and asked Lua to grow the window back to a minimum, holding
    // x/y fixed, which snapped a small window back to a "default" size and
    // shimmied it sideways on a west-edge resize. Removed: one source of truth.

    // Default appendEntry / loadHistory (single #log) //
    let _lastEntry = null;
    const _pendingHolds = {}; // label+key -> { row, ts }

    function _entryBadge(entry) {
        if (entry.type === 'step') {
            const msg = entry.msg || '';
            if (/\] wait /.test(msg)) return 'wait';
            if (/\] sound /.test(msg)) return 'sound';
            if (/\] cam\.move/.test(msg)) return 'cam';
            if (/\] [↓↑] |\] type /.test(msg)) return 'keys';
            if (/\] Mouse /.test(msg)) return 'mouse';
            if (/\] scroll /.test(msg)) return 'scroll';
            if (/\] copy/.test(msg)) return 'copy';
            return 'other';
        }
        return entry.type || 'unknown';
    }

    function _entryLabel(entry) {
        const m = (entry.msg || '').match(/^\[([^\]]+)\]\s/);
        return m ? m[1] : (entry.label || entry.type || '_default');
    }

    function _isKeyDown(entry) {
        return (entry.msg || '').includes('] ↓ ');
    }

    function _isKeyUp(entry) {
        return (entry.msg || '').includes('] ↑ ');
    }

    function _holdKey(entry) {
        // Extract key name from "[label] ↓ W" -> "W"
        const m = (entry.msg || '').match(/\] [↓↑]\s+(.+)$/);
        return m ? m[1] : null;
    }

    function appendEntry(entry) {
        if (_paused) return;
        const log = _byId("log");
        if (!log) return;
        const atBottom = _isNearBottom(log, scrollThresh);
        const label = _entryLabel(entry);

        // Key hold tracking: ↓ stores pending, ↑ replaces with hold entry
        if (_isKeyDown(entry)) {
            const keyName = _holdKey(entry);
            if (keyName) {
                const holdId = label + ':' + keyName;
                const row = buildRow(entry);
                row.dataset.holdId = holdId;
                _pendingHolds[holdId] = { row, ts: entry.ts };
                log.appendChild(row);
                // Update _lastEntry so this doesn't also get consecutive-collapsed
                _lastEntry = { cat: _entryBadge(entry), row, count: 1 };
                _trimLog(log, maxEntries);
                if (atBottom) log.scrollTop = log.scrollHeight;
                return;
            }
        }

        if (_isKeyUp(entry)) {
            const keyName = _holdKey(entry);
            if (keyName) {
                const holdId = label + ':' + keyName;
                const pending = _pendingHolds[holdId];
                if (pending && pending.row && pending.row.parentNode) {
                    // Replace the ↓ row with a hold row
                    const holdRow = document.createElement('div');
                    holdRow.className = 'step';
                    holdRow.dataset.cat = 'keys';
                    const ts = document.createElement('span');
                    ts.className = 'ts';
                    ts.textContent = '[' + (entry.ts || '') + ']';
                    const msg = document.createElement('span');
                    msg.className = 'tool-msg';
                    msg.textContent = '[' + label + '] hold ' + keyName;
                    holdRow.append(ts, msg);
                    holdRow.onmouseenter = function() { lp.playSlot('hover'); };
                    holdRow.onclick = lp._handleEntryClick;
                    pending.row.replaceWith(holdRow);
                    delete _pendingHolds[holdId];
                    // Clear dedup state so next entry starts fresh
                    _lastEntry = null;
                    _trimLog(log, maxEntries);
                    if (atBottom) log.scrollTop = log.scrollHeight;
                    return;
                }
            }
        }

        const row = buildRow(entry);
        log.appendChild(row);

        _trimLog(log, maxEntries);
        if (atBottom) log.scrollTop = log.scrollHeight;
    }

    function loadHistory(entries) {
        const log = _byId("log");
        if (!log) return;
        log.innerHTML = "";
        _lastEntry = null;
        for (const k in _pendingHolds) delete _pendingHolds[k];
        const capped =
            entries && entries.length > maxEntries
                ? entries.slice(-maxEntries)
                : entries || [];
        const frag = document.createDocumentFragment();
        capped.forEach((e) => frag.appendChild(buildRow(e)));
        log.appendChild(frag);
        log.scrollTop = log.scrollHeight;
    }

    // Actions //
    function clearLog() {
        const log = _byId("log");
        if (log) log.innerHTML = "";
        sendToHost({ action: "clear" });
    }

    function closePanel() {
        sendToHost({ action: "close" });
    }

    // Controller //
    return {
        sendToHost,
        playSlot,
        togglePause,
        appendEntry,
        loadHistory,
        clearLog,
        closePanel,
        getSelected: () => _selected,
        isPaused: () => _paused,
        applyTheme,
        hexToRgb,
        pad2,
        nowTs,
        // Primitives for panels that override appendEntry/loadHistory
        isNearBottom: (logEl) => _isNearBottom(logEl, scrollThresh),
        trimLog: (logEl) => _trimLog(logEl, maxEntries),
        buildRow,
        maxEntries,
        _handleEntryClick,
        _updateSelectionVisuals,
    };
}


    window.createLogPanel = createLogPanel;

    })();
