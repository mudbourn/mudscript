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

    var FOCUSABLE = 'button, a[href], input, select, textarea, [tabindex]:not([tabindex="-1"]), .row, .entry, .step, .fn-entry, .fn-cat-head';
    var TOPBAR_REGION = '#header';
    var OVERLAY_SEL = '.fn-picker-overlay.open, .macro-overflow.open';
    var TAB_SEL = '.tab, .mtab, .otab, .ttab, .wtab';

    function ensureFocusStyle() {
        if (document.getElementById('gp-nav-css')) return;
        var s = document.createElement('style');
        s.id = 'gp-nav-css';
        s.textContent = '.gp-focus { outline: 2px solid var(--accent-hi) !important;'
            + ' outline-offset: -2px; border-radius: var(--radius-s, 4px); }';
        (document.head || document.documentElement).appendChild(s);
    }

    function installGpNav(cfg) {
        ensureFocusStyle();
        var gpFocusEl = null;
        var gpLastFocus = {};
        var gpInTopbar = false;

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
                try { gpFocusEl.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) {}
                sound('hover');
            }
        }

        function scope() { return cfg.scope ? cfg.scope() : document.body; }

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

        function activeOverlay() {
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
        // the pressed direction. Off-axis distance is weighted so travelling
        // along a row/column stays coherent, while still allowing a diagonal
        // fall-through (e.g. Down from a toolbar reaches the content below it).
        function move(dir) {
            var list = gpInTopbar ? topbarItems() : focusables();
            if (!list.length) { setFocus(null); return; }
            if (!gpFocusEl || list.indexOf(gpFocusEl) === -1) { setFocus(pickInitial(list)); return; }
            var cur = centerOf(gpFocusEl);
            var best = null, bestScore = Infinity;
            for (var i = 0; i < list.length; i++) {
                if (list[i] === gpFocusEl) continue;
                var t = centerOf(list[i]);
                var dx = t.cx - cur.cx, dy = t.cy - cur.cy, score = null;
                if (dir === 'right' && dx > 1) score = dx + Math.abs(dy) * 2;
                else if (dir === 'left' && dx < -1) score = -dx + Math.abs(dy) * 2;
                else if (dir === 'down' && dy > 1) score = dy + Math.abs(dx) * 2;
                else if (dir === 'up' && dy < -1) score = -dy + Math.abs(dx) * 2;
                if (score !== null && score < bestScore) { bestScore = score; best = list[i]; }
            }
            if (best) setFocus(best);
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
                '#log, .log, [class$="-scroll"], [class*="scroll"], .fn-picker-entries, .fn-picker-detail, [class*="log"]');
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

        window.gpNavInit = function() { gpInTopbar = false; setFocus(null); };

        function osk() { return window.MSOsk && window.MSOsk.isOpen() ? window.MSOsk : null; }

        window.gpNav = function(cmd, arg) {
            // While the on-screen keyboard is up it owns the controller: the
            // stick/dpad picks a key, A presses it, B dismisses it.
            var kb = osk();
            if (kb) {
                switch (cmd) {
                    case 'itemUp': kb.move('up'); return;
                    case 'itemDown': kb.move('down'); return;
                    case 'itemLeft': kb.move('left'); return;
                    case 'itemRight': kb.move('right'); return;
                    case 'activate': kb.press(); return;
                    case 'back': kb.close(); return;
                    case 'copy': kb.space(); return;        // Y = space
                    case 'selectAll': kb.backspace(); return; // X = backspace
                    case 'toggleRail': kb.close(); return;    // Start/Menu = Done
                    default: return;
                }
            }
            switch (cmd) {
                case 'panelPrev': if (cfg.switchPanel) cfg.switchPanel(-1); break;
                case 'panelNext': if (cfg.switchPanel) cfg.switchPanel(1); break;
                case 'tabPrev': switchTab(-1); break;
                case 'tabNext': switchTab(1); break;
                case 'itemUp': move('up'); break;
                case 'itemDown': move('down'); break;
                case 'itemLeft': move('left'); break;
                case 'itemRight': move('right'); break;
                case 'activate':
                    // The click's own handler plays the interaction sound; don't
                    // stack a second one on top of it.
                    if (gpFocusEl) {
                        if (window.MSOsk && window.MSOsk.isTextField(gpFocusEl)) {
                            // Text fields raise the on-screen keyboard instead of
                            // a bare click, so no physical keyboard is needed.
                            window.MSOsk.open(gpFocusEl);
                        } else if (gpFocusEl.matches && gpFocusEl.matches('.entry, .step')) {
                            // Log rows: A toggles the row into a multi-selection,
                            // the same as a ctrl+click from the mouse.
                            gpFocusEl.dispatchEvent(new MouseEvent('click', { bubbles: true, ctrlKey: true }));
                        } else {
                            gpFocusEl.click();
                        }
                    }
                    break;
                case 'copy': if (inLogPanel()) synthCtrlKey('c'); break;
                case 'selectAll': if (inLogPanel()) synthCtrlKey('a'); break;
                case 'back':
                    var ov = activeOverlay();
                    if (ov) {
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
                case 'scroll': scrollBy(arg || 0); break;
            }
        };
    }

    window.installGpNav = installGpNav;
})();
