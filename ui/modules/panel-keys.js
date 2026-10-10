(function() {
    "use strict";
// -- Panel container --
            const _panel = document.querySelector('.panel-keys');

// -- Create LogPanel (selection, context menu, keyboard, drag, theme) --
            const lp = createLogPanel({
                channel: "keys",
                buildRow, // defined below
                container: _panel,
                entrySelector: ".log .entry, .log .step",
                maxEntries: 500,
                scrollThresh: 48,
                extractCopyText(el) {
                    const ts = el.querySelector(".ts")?.textContent || "";
                    const badge = (el.querySelector(".badge")?.textContent || "").toUpperCase();
                    const arrow = el.querySelector(".arrow")?.textContent || "";
                    const name = el.querySelector(".key-name, .mouse-name, .scroll-name, .move-name")?.textContent || "";
                    const dim = el.querySelector(".dim")?.textContent || "";
                    const parts = [ts, `[${badge}]`];
                    if (arrow) parts.push(arrow);
                    if (name) parts.push(name);
                    if (dim) parts.push(dim.trim());
                    return parts.join(" ");
                },
            });

            // -- Expose globals for inline handlers --
            window._panelPauseFns['keys'] = lp.togglePause;
            window.playSlot    = lp.playSlot;
            window._panelClearFns['keys'] = clearLog;
            window.closePanel  = lp.closePanel;
            window.switchTab   = switchTab;
            window.onCoordModeChange = onCoordModeChange;
            window.keysApplyTheme = lp.applyTheme;

            // -- Entry builder --
            function buildRow(entry) {
                const row = devfmt.inputRow(entry);

                row.onmouseenter = function() { lp.playSlot("hover"); };
                row.onclick = lp._handleEntryClick;

                return row;
            }

            // -- Route entries to the correct log --
            function appendEntry(entry) {
                if (lp.isPaused()) return;
                if (entry.type === "key" && entry.down)
                    flagKey(entry);
                if (entry.type === "mouse" && entry.down)
                    flagMouse(entry);

                const t = entry.type;
                const isMouseSide =
                    t === "mouse" || t === "scroll" || t === "mousemove";
                const log = _panel ? _panel.querySelector(
                    isMouseSide ? "#mouse-log" : "#keys-log"
                ) : document.getElementById(
                    isMouseSide ? "mouse-log" : "keys-log"
                );
                if (!log) return;
                const atBottom = lp.isNearBottom(log);
                log.appendChild(buildRow(entry));
                lp.trimLog(log);
                if (atBottom) log.scrollTop = log.scrollHeight;
            }

            function loadHistory(entries) {
                const kl = _panel ? _panel.querySelector("#keys-log") : document.getElementById("keys-log");
                const ml = _panel ? _panel.querySelector("#mouse-log") : document.getElementById("mouse-log");
                if (!kl || !ml) return;
                kl.innerHTML = ml.innerHTML = "";
                const capped =
                    entries && entries.length > lp.maxEntries
                        ? entries.slice(-lp.maxEntries)
                        : entries || [];
                const kf = document.createDocumentFragment();
                const mf = document.createDocumentFragment();
                capped.forEach((e) => {
                    const isMouseSide =
                        e.type === "mouse" ||
                        e.type === "scroll" ||
                        e.type === "mousemove";
                    (isMouseSide ? mf : kf).appendChild(buildRow(e));
                });
                kl.appendChild(kf);
                ml.appendChild(mf);
                kl.scrollTop = kl.scrollHeight;
                ml.scrollTop = ml.scrollHeight;

                const last = devfmt.lastInput(capped);

                if (last.key) flagKey(last.key);
                if (last.mouse) flagMouse(last.mouse);
            }

            // -- Active keys pills --
            function updateActiveKeys(keys) {
                devfmt.renderPills(
                    document.getElementById("keys-pills"),
                    "key",
                    devfmt.keyPills(keys),
                );
            }

            // -- Mouse state (position + active buttons) --
            function updateMouseState(state) {
                const mx = _panel ? _panel.querySelector("#mx-display") : document.getElementById("mx-display");
                const my = _panel ? _panel.querySelector("#my-display") : document.getElementById("my-display");

                if (state.x != null && mx) mx.textContent = state.x;
                if (state.y != null && my) my.textContent = state.y;

                if (state.buttons === undefined) return;

                devfmt.renderPills(
                    _panel ? _panel.querySelector("#mouse-pills") : document.getElementById("mouse-pills"),
                    "mouse",
                    devfmt.buttonPills(state.buttons),
                );
            }

            function updateMousePos(pos) {
                const mx = _panel ? _panel.querySelector("#mx-display") : document.getElementById("mx-display");
                const my = _panel ? _panel.querySelector("#my-display") : document.getElementById("my-display");
                if (pos.x != null && mx) mx.textContent = pos.x;
                if (pos.y != null && my) my.textContent = pos.y;
            }

            // -- Flag row --
            let _lastKeyTime = 0,
                _lastMouseTime = 0;

            function flagKey(entry) {
                _lastKeyTime = Date.now();
                devfmt.renderFlag(
                    document.getElementById("flag-key-pill"),
                    "Key",
                    devfmt.key(entry.key, entry.keyCode),
                    null,
                    false,
                );
                _updateFlagStyles();
            }

            function flagMouse(entry) {
                _lastMouseTime = Date.now();
                devfmt.renderFlag(
                    document.getElementById("flag-mouse-pill"),
                    "Mouse",
                    devfmt.button(entry.button),
                    null,
                    false,
                );
                _updateFlagStyles();
            }

            function _updateFlagStyles() {
                const kRecent = _lastKeyTime >= _lastMouseTime;
                const kp = document.getElementById("flag-key-pill");
                const mp = document.getElementById("flag-mouse-pill");

                if (kp) kp.classList.toggle("flag-recent", kRecent && _lastKeyTime > 0);
                if (mp) mp.classList.toggle("flag-recent", !kRecent && _lastMouseTime > 0);
            }

            // -- Tab switching --
            // At load, not lazily: the styles must be up whether or not anyone
            // ever clicks a tab. The shell no longer carries its own copy.
            injectTabStyles();

            // Scoped to this panel, the shell hosts every panel's markup at
            // once, so an unscoped ".tab" would reach into its neighbours.
            let _ktabs = null;
            function _tabs() {
                if (!_ktabs) {
                    _ktabs = createTabs({
                        root: document.querySelector(".panel-keys") || document,
                        onSame: () => playSlot("back"),
                        onSwitch(tab) {
                            playSlot("interact");
                            // Scroll the newly-visible log to the bottom
                            const log = document.getElementById(tab + "-log");
                            if (log) log.scrollTop = log.scrollHeight;
                        },
                    });
                }
                return _ktabs;
            }

            function switchTab(tab) { _tabs().switch(tab); }

            // -- Button actions --
            function clearLog() {
                document.getElementById("keys-log").innerHTML = "";
                document.getElementById("mouse-log").innerHTML = "";
                lp.sendToHost({ action: "clear" });
            }

            function coordLabels() {
                return {
                    screen: 'Screen', window: 'Window TL', windowTR: 'Window TR',
                    windowBL: 'Window BL', windowBR: 'Window BR',
                    windowCenter: 'Window Center',
                    screenCenter: 'Screen center',
                };
            }

            function onCoordModeChange(mode) {
                lp.sendToHost({ action: "setCoordMode", mode: mode });
                var items = document.querySelectorAll('.coord-dd-item');
                var labels = coordLabels();
                items.forEach(function(el) {
                    el.classList.toggle('active', el.dataset.value === mode);
                });
                var btn = document.getElementById('coord-dd-btn');
                if (btn) {
                    btn.textContent = (labels[mode] || mode) + ' ';
                    btn.insertAdjacentHTML('beforeend', icon('chevdown', 'icon-inline'));
                }
            }

            // -- Expose for Lua evaluateJavaScript --
            window.updateActiveKeys = updateActiveKeys;
            window.updateMouseState = updateMouseState;
            window.updateMousePos   = updateMousePos;

            // -- Init --
            document.addEventListener("DOMContentLoaded", () => {
                if (typeof registerPanel === "function") {
                    registerPanel("keys", function(action, body) {
                        if (action === "appendEntry" && body) appendEntry(body);
                        else if (action === "loadHistory" && body) loadHistory(body);
                        else if (action === "updateActiveKeys" && body) updateActiveKeys(body);
                        else if (action === "updateMouseState" && body) updateMouseState(body);
                    });
                }
                if (window.shellPost) {
                    var p = document.getElementById("panel");
                    if (p) { p.style.borderRadius = "0"; p.style.clipPath = "none"; }
                }
                lp.sendToHost({ action: "ready" });
            });
    })();
