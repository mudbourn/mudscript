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
    var TOPBAR_REGION = '#header, .macro-toolbar';
    var OVERLAY_SEL = '.fn-picker-overlay.open';
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

        function step(delta) {
            var list = gpInTopbar ? topbarItems() : focusables();
            if (!list.length) { setFocus(null); return; }
            var idx = gpFocusEl ? list.indexOf(gpFocusEl) : -1;
            if (idx === -1) {
                var remembered = gpLastFocus[panelKey()];
                if (remembered && list.indexOf(remembered) !== -1) { setFocus(remembered); return; }
                setFocus(delta > 0 ? list[0] : list[list.length - 1]); return;
            }
            var next = idx + delta;
            if (next < 0) next = 0;
            if (next >= list.length) next = list.length - 1;
            setFocus(list[next]);
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

        function scrollBy(delta) {
            var sc = scope();
            if (!sc) return;
            var el = sc.querySelector('[class$="-scroll"], #scroll, .data-scroll') || sc;
            var guard = 0;
            while (el && guard < 6) {
                if (el.scrollHeight > el.clientHeight + 2) break;
                el = el.parentElement;
                guard++;
            }
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

        window.gpNavInit = function() { gpInTopbar = false; setFocus(null); };

        window.gpNav = function(cmd, arg) {
            switch (cmd) {
                case 'panelPrev': if (cfg.switchPanel) cfg.switchPanel(-1); break;
                case 'panelNext': if (cfg.switchPanel) cfg.switchPanel(1); break;
                case 'tabPrev': switchTab(-1); break;
                case 'tabNext': switchTab(1); break;
                case 'itemUp': case 'itemLeft': step(-1); break;
                case 'itemDown': case 'itemRight': step(1); break;
                case 'activate':
                    // The click's own handler plays the interaction sound; don't
                    // stack a second one on top of it.
                    if (gpFocusEl) {
                        if (gpFocusEl.matches && gpFocusEl.matches('.entry, .step')) {
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
                        // Dismiss the side menu via its own close control so its
                        // teardown (and Back sound) runs exactly as a click would.
                        var closeBtn = ov.querySelector('.fn-picker-overlay-close');
                        if (closeBtn) closeBtn.click();
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
                        cfg.closeRoot();
                    }
                    break;
                case 'toggleRail': if (cfg.toggleRail) cfg.toggleRail(); break;
                case 'focusTopbar':
                    var titems = topbarItems();
                    if (titems.length) { gpInTopbar = true; setFocus(titems[0]); }
                    break;
                case 'popOut': if (cfg.switchWindow) cfg.switchWindow(); break;
                case 'scroll': scrollBy(arg || 0); break;
            }
        };
    }

    window.installGpNav = installGpNav;
})();
