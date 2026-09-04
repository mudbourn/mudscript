(function() {
"use strict";

    // Shared gamepad navigation layer. The Lua nav handler evaluates
    // gpNav(cmd, arg) / gpNavInit() into whichever window currently holds
    // controller focus (the shell or a popout), so both documents install this
    // and differ only in the small config seam below.
    //
    // config:
    //   scope()        -> the content root element to navigate (or null)
    //   panelKey()     -> string key for per-panel focus memory
    //   sound(slot)    -> play a UI sound slot
    //   closeRoot()    -> Back with nothing focused: close/dismiss this window
    //   switchPanel(d) -> optional: move between sibling panels (shell rail)
    //   toggleRail()   -> optional: collapse/expand the shell rail
    //   switchWindow() -> optional: the pop-out / window-switch action

    var FOCUSABLE = 'button, a[href], input, select, textarea, [tabindex]:not([tabindex="-1"]), .row, .entry, .step, .tool-block, .fn-entry, .fn-cat-head';
    var TOPBAR_REGION = '#header';
    var OVERLAY_SEL = '.fn-picker-overlay.open, .macro-overflow.open';
    var TAB_SEL = '.tab, .mtab, .otab, .ttab, .wtab';

    function ensureFocusStyle() {
        if (document.getElementById('gp-nav-css')) return;
        var s = document.createElement('style');
        s.id = 'gp-nav-css';
        s.textContent = '.gp-focus { outline: 2px solid var(--text) !important;'
            + ' outline-offset: -2px; border-radius: var(--radius-s, 4px);'
            + ' box-shadow: inset 0 0 0 4px color-mix(in srgb, var(--bg) 70%, transparent) !important; }'
            // A slider fills its row, so ring the thumb (the grabbable dot) rather
            // than the full-width track bar.
            + 'input[type="range"].gp-focus { outline: none !important; box-shadow: none !important; }'
            + 'input[type="range"].gp-focus::-webkit-slider-thumb {'
            + ' box-shadow: 0 0 0 2px var(--text),'
            + ' 0 0 0 5px color-mix(in srgb, var(--bg) 70%, transparent) !important; }'
            + 'input[type="range"].gp-focus::-moz-range-thumb {'
            + ' box-shadow: 0 0 0 2px var(--text),'
            + ' 0 0 0 5px color-mix(in srgb, var(--bg) 70%, transparent) !important; }'
            + '.toggle.gp-focus { outline: none !important; border-radius: 10px;'
            + ' box-shadow: 0 0 0 2px var(--text),'
            + ' 0 0 0 5px color-mix(in srgb, var(--bg) 70%, transparent) !important; }'
            + '.gp-grabbing { outline: 2px dashed var(--accent) !important;'
            + ' opacity: 0.85; }';
        (document.head || document.documentElement).appendChild(s);
    }

    function installGpNav(cfg) {
        ensureFocusStyle();
        var gpFocusEl = null;
        var gpLastFocus = {};
        var gpInTopbar = false;
        var gpGrab = null;
        var gpXTapTimer = null;

        function panelKey() { return cfg.panelKey ? cfg.panelKey() : 'panel'; }
        function sound(slot) {
            if (cfg.sound) cfg.sound(slot);
            else if (window.playSlot) window.playSlot(slot);
        }

        function setFocus(el) {
            if (gpFocusEl === el) return;
            if (gpFocusEl) gpFocusEl.classList.remove('gp-focus');
            gpFocusEl = el || null;
            if (gpFocusEl) {
                if (!gpInTopbar) gpLastFocus[panelKey()] = gpFocusEl;
                gpFocusEl.classList.add('gp-focus');
                scrollFocusIntoView(gpFocusEl);
                sound('hover');
            }
        }

        function scope() { return cfg.scope ? cfg.scope() : document.body; }

        function scrollFocusIntoView(el) {
            var sc = null, a = el.parentElement;
            while (a) { if (canScroll(a)) { sc = a; break; } a = a.parentElement; }
            if (!sc) { try { el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {} return; }
            var pad = 8;
            for (var i = 0; i < 24; i++) {
                var er = el.getBoundingClientRect();
                var cr = sc.getBoundingClientRect();
                var delta = 0;
                if (er.top < cr.top + pad) delta = er.top - (cr.top + pad);
                else if (er.bottom > cr.bottom - pad) delta = er.bottom - (cr.bottom - pad);
                if (Math.abs(delta) < 1) break;
                var before = sc.scrollTop;
                sc.scrollTop += delta;
                if (Math.abs(sc.scrollTop - before) < 0.5) break;
            }
        }

        function isVisible(el) {
            if (!el || el.disabled) return false;
            var r = el.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) return false;
            if (el.offsetParent === null && getComputedStyle(el).position !== 'fixed') return false;
            // A closed side menu is only slid off-screen (transform), not
            // display:none, so its controls still measure as visible. Treat
            // anything inside a not-open overlay as unreachable.
            if (el.closest && el.closest('.fn-picker-overlay:not(.open)')) return false;
            return true;
        }

        function isTopbarEl(el) {
            if (el.matches && el.matches(TAB_SEL)) return true;
            var sc = scope();
            if (!sc) return false;
            var regions = sc.querySelectorAll(TOPBAR_REGION);
            for (var i = 0; i < regions.length; i++) {
                if (regions[i].contains(el)) return true;
            }
            return false;
        }

        function dedupeWrappers(all) {
            // A .row wrapper and the control inside it both match FOCUSABLE, but
            // only the inner control is actionable. Drop any element that merely
            // contains another matched element so each stop maps to one target.
            return all.filter(function(el) {
                for (var i = 0; i < all.length; i++) {
                    if (all[i] !== el && el.contains(all[i])) return false;
                }
                return true;
            });
        }

        // The confirm/prompt modal is a fixed overlay parented to <body>, outside
        // any panel scope, so find it at the document root and treat it as the
        // active overlay while it is open — that scopes navigation to its own
        // buttons and input.
        function modalOverlay() {
            var md = document.getElementById('modal-overlay');
            return (md && md.classList.contains('open')) ? md : null;
        }

        function mapOverlay() {
            var mp = document.querySelector('.gp-map-overlay.open');
            return mp || null;
        }

        function activeOverlay() {
            var mp = mapOverlay();
            if (mp) return mp;
            var md = modalOverlay();
            if (md) return md;
            var sc = scope();
            return sc ? sc.querySelector(OVERLAY_SEL) : null;
        }

        function focusables() {
            var overlay = activeOverlay();
            var sc = overlay || scope();
            if (!sc) return [];
            var all = Array.prototype.slice.call(sc.querySelectorAll(FOCUSABLE)).filter(isVisible);
            if (!overlay) all = all.filter(function(el) { return !isTopbarEl(el); });
            return dedupeWrappers(all);
        }

        function topbarItems() {
            var sc = scope();
            if (!sc) return [];
            var all = Array.prototype.slice.call(sc.querySelectorAll(FOCUSABLE))
                .filter(isVisible).filter(isTopbarEl);
            return dedupeWrappers(all);
        }

        function centerOf(el) {
            var r = el.getBoundingClientRect();
            return { cx: r.left + r.width / 2, cy: r.top + r.height / 2, top: r.top, left: r.left };
        }

        // First landing spot when nothing is focused yet: the remembered item,
        // else the top-left-most control (reading order start).
        function pickInitial(list) {
            var remembered = gpLastFocus[panelKey()];
            if (remembered && list.indexOf(remembered) !== -1) return remembered;
            if (inLogPanel()) {
                // A log panel with a text entry (the console) lands on that field
                // so the user can type straight away. Focus alone does not raise
                // the on-screen keyboard — that waits for A — so the field is
                // highlighted, not opened.
                var tf = window.MSOsk && window.MSOsk.isTextField;
                if (tf) {
                    for (var t = 0; t < list.length; t++) {
                        if (window.MSOsk.isTextField(list[t])) return list[t];
                    }
                }
                // Otherwise land on the freshest row at the bottom, since logs read
                // newest-last, rather than scrolling up to the oldest.
                for (var j = list.length - 1; j >= 0; j--) {
                    if (list[j].matches && list[j].matches('.entry, .step')) return list[j];
                }
            }
            var best = list[0], b = centerOf(best);
            for (var i = 1; i < list.length; i++) {
                var c = centerOf(list[i]);
                if (c.top < b.top - 4 || (Math.abs(c.top - b.top) <= 4 && c.left < b.left)) {
                    best = list[i]; b = c;
                }
            }
            return best;
        }

        // Spatial move: from the focused element, pick the nearest focusable in
        // the pressed direction. A target whose cross-axis extent overlaps the
        // current element (i.e. it shares the row for a horizontal move, or the
        // column for a vertical one) always wins over a merely-nearby diagonal
        // one — so pressing Right from the console input lands on the Run button
        // beside it, not the log line sitting just above. Only when nothing lines
        // up does it fall back to the weighted-diagonal score, which still allows
        // a fall-through (e.g. Down from a toolbar reaching the content below).
        function reanchor() {
            if (!gpFocusEl || document.contains(gpFocusEl)) return;
            var sid = gpFocusEl.getAttribute && gpFocusEl.getAttribute('data-sid');
            if (!sid) return;
            var sc = activeOverlay() || scope();
            var fresh = sc && sc.querySelector('.tool-block[data-sid="' + sid + '"]');
            if (!fresh) return;
            gpFocusEl.classList.remove('gp-focus');
            gpFocusEl = fresh;
            fresh.classList.add('gp-focus');
            if (!gpInTopbar) gpLastFocus[panelKey()] = fresh;
        }

        function move(dir) {
            var list = gpInTopbar ? topbarItems() : focusables();
            if (!list.length) { setFocus(null); return; }
            if (!gpFocusEl || list.indexOf(gpFocusEl) === -1) { setFocus(pickInitial(list)); return; }
            var cur = centerOf(gpFocusEl);
            var cr = gpFocusEl.getBoundingClientRect();
            var horizontal = (dir === 'left' || dir === 'right');
            var best = null, bestScore = Infinity;
            var lined = null, linedDist = Infinity;
            for (var i = 0; i < list.length; i++) {
                if (list[i] === gpFocusEl) continue;
                var t = centerOf(list[i]);
                var dx = t.cx - cur.cx, dy = t.cy - cur.cy, score = null;
                if (dir === 'right' && dx > 1) score = dx + Math.abs(dy) * 2;
                else if (dir === 'left' && dx < -1) score = -dx + Math.abs(dy) * 2;
                else if (dir === 'down' && dy > 1) score = dy + Math.abs(dx) * 2;
                else if (dir === 'up' && dy < -1) score = -dy + Math.abs(dx) * 2;
                if (score === null) continue;
                if (score < bestScore) { bestScore = score; best = list[i]; }
                var tr = list[i].getBoundingClientRect();
                var overlap = horizontal
                    ? (tr.bottom > cr.top && tr.top < cr.bottom)
                    : (tr.right > cr.left && tr.left < cr.right);
                var primary = horizontal ? Math.abs(dx) : Math.abs(dy);
                if (overlap && primary < linedDist) { linedDist = primary; lined = list[i]; }
            }
            var pick = lined || best;
            if (pick) setFocus(pick);
        }

        function tabStrip() {
            var sc = scope();
            if (!sc) return [];
            return Array.prototype.slice.call(sc.querySelectorAll(TAB_SEL)).filter(isVisible);
        }

        function switchTab(delta) {
            var tabs = tabStrip();
            if (!tabs.length) return;
            var cur = -1;
            for (var i = 0; i < tabs.length; i++) {
                if (tabs[i].classList.contains('active')) { cur = i; break; }
            }
            var ni = cur === -1 ? 0 : cur + delta;
            if (ni < 0) ni = tabs.length - 1;
            if (ni >= tabs.length) ni = 0;
            // The tab's own onSwitch handler plays the interaction sound.
            tabs[ni].click();
            gpInTopbar = false;
            setFocus(null);
        }

        function canScroll(el) {
            if (!el || el.scrollHeight <= el.clientHeight + 2) return false;
            var oy = getComputedStyle(el).overflowY;
            return oy === 'auto' || oy === 'scroll';
        }

        function scrollTarget(sc) {
            // Scroll the container the focused item lives in, so a two-pane view
            // (e.g. the keyboard/mouse logs) scrolls the pane you are actually in.
            if (gpFocusEl) {
                var a = gpFocusEl.parentElement;
                while (a && a !== sc.parentElement) {
                    if (canScroll(a)) return a;
                    a = a.parentElement;
                }
            }
            // Otherwise the tallest scrollable region within scope (log views,
            // bind lists, the picker's entry column, generic *-scroll wrappers).
            var cands = sc.querySelectorAll(
                '#log, .log, [class$="-scroll"], [class*="scroll"], .fn-picker-entries, .fn-picker-detail, [class*="log"], .gp-map-body');
            var best = null, bestH = 0;
            for (var i = 0; i < cands.length; i++) {
                if (canScroll(cands[i]) && cands[i].clientHeight > bestH) {
                    bestH = cands[i].clientHeight; best = cands[i];
                }
            }
            if (best) return best;
            return canScroll(sc) ? sc : null;
        }

        function scrollBy(delta) {
            var sc = activeOverlay() || scope();
            if (!sc) return;
            var el = scrollTarget(sc);
            if (el) el.scrollTop += delta;
        }

        function inLogPanel() {
            var sc = scope();
            return !!(sc && sc.querySelector('.entry, .step'));
        }

        // Reuse the log panels' own document-level ctrl+c / ctrl+a handlers,
        // which are already scoped to the visible panel, so the controller drives
        // the exact same copy / select-all path the keyboard does.
        function synthCtrlKey(k) {
            document.dispatchEvent(new KeyboardEvent('keydown', { key: k, ctrlKey: true, bubbles: true }));
        }

        // Only the top-bar toggle announces; panel switches stay quiet. Window
        // switches are announced host-side.
        function announce(msg) { if (cfg.announce) cfg.announce(msg); }

        window.gpNavInit = function() {
            gpInTopbar = false; gpGrab = null;
            if (gpXTapTimer) { clearTimeout(gpXTapTimer); gpXTapTimer = null; }
            setFocus(null);
        };

        // Let an overlay (e.g. the controller map) hand the controller a fresh
        // focus target so the highlight lands inside it the moment it opens,
        // rather than stranding it on the button that launched the overlay.
        window.gpSetFocus = function(el) { setFocus(el || null); };

        function osk() { return window.MSOsk && window.MSOsk.isOpen() ? window.MSOsk : null; }

        // An open custom dropdown (ui-select) owns the controller the same way the
        // keyboard does: its root stays in the panel while the menu portals to
        // <body>, so find it in scope and drive it through its gp* API.
        function openSelect() {
            var sc = activeOverlay() || scope();
            if (!sc) return null;
            var el = sc.querySelector('.macro-select.open');
            return (el && el.gpIsOpen && el.gpIsOpen()) ? el : null;
        }

        // A focus stop is often the .row wrapper, not the control inside it — a
        // .toggle switch hides its checkbox at 0x0 so only the row is reachable,
        // and clicking the row does nothing. Forward the press to the real
        // control: the switch (its label click flips the checkbox and fires its
        // change handler + sound) or a lone button standing in for the row.
        function activate(el) {
            if (!el) return;
            var ctrl = null;
            if (el.matches && el.matches('.toggle, button, a[href]')) ctrl = el;
            else if (el.querySelector) ctrl = el.querySelector('.toggle, button, a[href]');
            (ctrl || el).click();
        }

        // Left/Right nudge a focused slider by one step, the way the arrow keys
        // would for a keyboard user — range inputs otherwise swallow the stop but
        // can't be driven, so the controller could never change a slider. Returns
        // true when it handled the press, false to let it fall back to a move.
        function adjustRange(dir) {
            var el = gpFocusEl;
            if (!el || !el.matches || !el.matches('input[type="range"]')) return false;
            var step = parseFloat(el.step) || 1;
            var min = el.min !== '' ? parseFloat(el.min) : 0;
            var max = el.max !== '' ? parseFloat(el.max) : 100;
            var next = Math.max(min, Math.min(max, (parseFloat(el.value) || 0) + dir * step));
            if (next === (parseFloat(el.value) || 0)) return true;
            el.value = next;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            sound('hover');
            return true;
        }

        function toolBlock(el) {
            return el && el.matches && el.matches('.tool-block[data-sid]') ? el : null;
        }
        function macroAddBtn() {
            var sc = scope();
            var b = sc && sc.querySelector('.macros-add-tool-btn');
            return (b && isVisible(b)) ? b : null;
        }
        function macroAddSelect() {
            var sc = scope();
            var s = sc && sc.querySelector('.macro-select.macros-add-step');
            return (s && isVisible(s)) ? s : null;
        }
        function toolCanvas() {
            var sc = scope();
            return sc ? sc.querySelector('.tool-canvas') : null;
        }

        function xSingle() {
            if (toolBlock(gpFocusEl)) {
                gpFocusEl.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true }));
            } else if (inLogPanel()) {
                synthCtrlKey('a');
            }
        }
        function xDouble() {
            var canvas = toolCanvas();
            if (canvas && canvas.gpDuplicateSelection) {
                var blk = toolBlock(gpFocusEl);
                if (blk && !blk.classList.contains('selected')) ctrlClick(blk);
                var sid = canvas.gpDuplicateSelection();
                if (sid) {
                    sound('interact');
                    var fresh = canvas.querySelector('.tool-block[data-sid="' + sid + '"]');
                    if (fresh) setFocus(fresh);
                    return;
                }
            }
            if (inLogPanel()) synthCtrlKey('a');
        }

        function ctrlClick(el) {
            el.dispatchEvent(new MouseEvent('click', { bubbles: true, ctrlKey: true }));
        }

        function startGrab() {
            var el = toolBlock(gpFocusEl);
            if (!el) return;
            var root = el.closest('.tool-canvas');
            if (!root || !root.gpReorderSelection) return;
            if (!el.classList.contains('selected')) ctrlClick(el);
            gpGrab = { root: root, sid: el.getAttribute('data-sid') };
            el.classList.add('gp-grabbing');
            sound('interact');
        }
        function grabMove(dir) {
            if (!gpGrab) return;
            if (!gpGrab.root.gpReorderSelection(dir)) return;
            var el = gpGrab.root.querySelector('.tool-block[data-sid="' + gpGrab.sid + '"]');
            setFocus(el);
            if (el) el.classList.add('gp-grabbing');
        }
        function endGrab() {
            if (!gpGrab) return;
            if (gpFocusEl) gpFocusEl.classList.remove('gp-grabbing');
            gpGrab = null;
            sound('back');
        }

        // Hold X on a module: delete the selection, first selecting the focused
        // block if the user hasn't explicitly selected anything yet, so a plain
        // "walk here, hold X" removes what the cursor sits on.
        function deleteSelection() {
            var canvas = toolCanvas();
            if (!canvas || !canvas.gpDeleteSelection) return;
            var blk = toolBlock(gpFocusEl);
            if (blk && !blk.classList.contains('selected')) ctrlClick(blk);
            if (canvas.gpDeleteSelection()) {
                sound('back');
                setFocus(null);
            }
        }

        function doActivate() {
            if (!gpFocusEl) return;
            if (window.MSOsk && window.MSOsk.isTextField(gpFocusEl)) {
                window.MSOsk.open(gpFocusEl);
            } else if (toolBlock(gpFocusEl) || (gpFocusEl.matches && gpFocusEl.matches('.entry, .step'))) {
                ctrlClick(gpFocusEl);
            } else if (gpFocusEl.matches && gpFocusEl.matches('.fn-cat-head')) {
                // Expanding a category rebuilds the whole entry list, so the
                // focused head is replaced; re-focus the head at the same
                // position rather than falling back to the search box at the top.
                var sc0 = activeOverlay() || scope();
                var heads0 = sc0 ? Array.prototype.slice.call(sc0.querySelectorAll('.fn-cat-head')) : [];
                var hidx = heads0.indexOf(gpFocusEl);
                activate(gpFocusEl);
                var sc1 = activeOverlay() || scope();
                var heads1 = sc1 ? sc1.querySelectorAll('.fn-cat-head') : [];
                if (hidx >= 0 && heads1[hidx]) setFocus(heads1[hidx]);
            } else {
                activate(gpFocusEl);
            }
        }

        window.gpNav = function(cmd, arg, arg2) {
            // While the on-screen keyboard is up it owns the controller: the
            // stick/dpad picks a key, A presses it, B dismisses it.
            var kb = osk();
            if (kb) {
                switch (cmd) {
                    case 'itemUp': kb.move('up'); return;
                    case 'itemDown': kb.move('down'); return;
                    case 'itemLeft': kb.move('left'); return;
                    case 'itemRight': kb.move('right'); return;
                    case 'activate': case 'grabDrop': kb.press(); return;
                    case 'grab': return;
                    case 'back': kb.close(); return;
                    case 'copy': kb.space(); return;        // Y = space
                    case 'selectAll': kb.backspace(); return; // X = backspace
                    case 'panelPrev': kb.caretLeft(); return;  // LB = caret left
                    case 'panelNext': kb.caretRight(); return; // RB = caret right
                    case 'tabPrev': kb.symbols(); return;      // LT = symbol layer
                    case 'tabNext': kb.shift(); return;        // RT = shift
                    case 'toggleRail': kb.close(); return;    // Start/Menu = Done
                    case 'rstick': if (kb.nudge) kb.nudge(arg || 0, arg2 || 0); return;
                    default: return;
                }
            }
            // While a dropdown is open the stick/dpad walks its items, A picks the
            // highlighted one, B dismisses — everything else is held so presses
            // don't leak to the panel behind the open menu.
            var sel = openSelect();
            if (sel) {
                switch (cmd) {
                    case 'itemUp': case 'itemLeft': sel.gpMove(-1); return;
                    case 'itemDown': case 'itemRight': sel.gpMove(1); return;
                    case 'activate': case 'grabDrop': sel.gpPick(); return;
                    case 'grab': return;
                    case 'back': case 'toggleRail': sel.gpClose(); return;
                    default: return;
                }
            }
            var mapOv = mapOverlay();
            if (mapOv) {
                switch (cmd) {
                    case 'tabPrev': if (mapOv.gpTab) mapOv.gpTab(-1); return;
                    case 'tabNext': if (mapOv.gpTab) mapOv.gpTab(1); return;
                    case 'back': case 'toggleRail':
                        if (window.closeGamepadMap) window.closeGamepadMap();
                        sound('back');
                        gpInTopbar = false;
                        setFocus(null);
                        return;
                    default: break;
                }
            }
            if (gpGrab) {
                switch (cmd) {
                    case 'itemUp': case 'itemLeft': grabMove(-1); return;
                    case 'itemDown': case 'itemRight': grabMove(1); return;
                    case 'grabDrop': case 'back': endGrab(); return;
                    default: return;
                }
            }
            reanchor();
            switch (cmd) {
                case 'panelPrev': if (cfg.switchPanel) cfg.switchPanel(-1); break;
                case 'panelNext': if (cfg.switchPanel) cfg.switchPanel(1); break;
                case 'tabPrev': switchTab(-1); break;
                case 'tabNext': switchTab(1); break;
                case 'itemUp': move('up'); break;
                case 'itemDown': move('down'); break;
                case 'itemLeft': if (!adjustRange(-1)) move('left'); break;
                case 'itemRight': if (!adjustRange(1)) move('right'); break;
                case 'activate': doActivate(); break;
                case 'grab': startGrab(); break;
                case 'grabDrop': doActivate(); break;
                case 'deleteSel': deleteSelection(); break;
                case 'copy':
                    var addBtn = macroAddBtn();
                    var addSel = macroAddSelect();
                    if (addBtn) activate(addBtn);
                    else if (addSel) { if (!addSel.gpIsOpen()) addSel.click(); }
                    else if (inLogPanel()) synthCtrlKey('c');
                    break;
                case 'selectAll':
                    if (gpXTapTimer) {
                        clearTimeout(gpXTapTimer);
                        gpXTapTimer = null;
                        xDouble();
                    } else {
                        gpXTapTimer = setTimeout(function() {
                            gpXTapTimer = null;
                            xSingle();
                        }, 300);
                    }
                    break;
                case 'back':
                    var ov = activeOverlay();
                    if (ov && ov.id === 'modal-overlay') {
                        // Back cancels the modal through its own close path so the
                        // pending promise resolves (a bare .open drop would strand
                        // the caller waiting on it).
                        sound('back');
                        if (window.closeModal) window.closeModal(false);
                        gpInTopbar = false;
                        setFocus(null);
                    } else if (ov) {
                        // Dismiss via the overlay's own close control so its
                        // teardown (and Back sound) runs exactly as a click would.
                        // Menus that just slide off on an .open class have no such
                        // control, so drop the class and play Back ourselves.
                        var closeBtn = ov.querySelector('.fn-picker-overlay-close');
                        if (closeBtn) { closeBtn.click(); }
                        else { ov.classList.remove('open'); sound('back'); }
                        gpInTopbar = false;
                        setFocus(null);
                    } else if (gpInTopbar) {
                        // Leaving the top bar drops back into the content and
                        // restores the last content position.
                        gpInTopbar = false;
                        sound('back');
                        var list = focusables();
                        var back = gpLastFocus[panelKey()];
                        setFocus(back && list.indexOf(back) !== -1 ? back : null);
                    } else if (gpFocusEl) {
                        sound('back');
                        setFocus(null);
                    } else if (cfg.closeRoot) {
                        // Match the mouse close control, which plays Back before it
                        // dismisses / re-docks the window.
                        sound('back');
                        cfg.closeRoot();
                    }
                    break;
                case 'toggleRail': if (cfg.toggleRail) cfg.toggleRail(); break;
                case 'focusTopbar':
                    // Toggle between the top bar and the panel content: pressing
                    // it again drops back to where you were in the content.
                    if (gpInTopbar) {
                        gpInTopbar = false;
                        sound('back');
                        var backList = focusables();
                        var backTo = gpLastFocus[panelKey()];
                        setFocus(backTo && backList.indexOf(backTo) !== -1 ? backTo : null);
                        announce('Switched to panel');
                    } else {
                        var titems = topbarItems();
                        if (titems.length) { sound('interact'); gpInTopbar = true; setFocus(titems[0]); announce('Switched to topbar'); }
                    }
                    break;
                case 'popOut': if (cfg.switchWindow) cfg.switchWindow(); break;
                case 'rstick': scrollBy(-(arg2 || 0) * 0.42); break;
            }
        };
    }

    window.installGpNav = installGpNav;
})();
