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

            // -- Constants --
            const BTN_NAMES = {
                0: "Left",
                1: "Right",
                2: "Middle",
                3: "Btn4",
                4: "Btn5",
            };

            function btnName(n) { return BTN_NAMES[n] ?? "M" + n; }

            // -- Entry builder --
            function mkSpan(cls, text) {
                const s = document.createElement("span");
                s.className = cls;
                s.textContent = text;
                return s;
            }

            function mkIcon(cls, name) {
                const s = document.createElement("span");
                s.className = cls;
                s.innerHTML = icon(name, "icon-inline");
                return s;
            }

            function buildRow(entry) {
                const row = document.createElement("div");
                const t = entry.type;

                if (t === "mousemove") {
                    row.className = "entry move-entry";
                    row.append(
                        mkSpan("ts", "[" + (entry.ts || "") + "]"),
                        mkSpan("arrow arrow-move", "->"),
                        mkSpan("move-name", entry.x + ", " + entry.y),
                    );
                    row.onmouseenter = function() { lp.playSlot("hover"); };
                    row.onclick = lp._handleEntryClick;
                    return row;
                }

                row.className = "entry";
                row.appendChild(mkSpan("ts", "[" + (entry.ts || "") + "]"));

                if (t === "key") {
                    row.append(
                        mkSpan("badge badge-key", "key"),
                        mkIcon(
                            "arrow " +
                                (entry.down ? "arrow-key" : "arrow-key-up"),
                            entry.down ? "arrow-down" : "arrow-up",
                        ),
                        mkSpan("key-name", entry.key || ""),
                        mkSpan("dim", " (" + (entry.keyCode ?? "?") + ")"),
                    );
                } else if (t === "mouse") {
                    row.append(
                        mkSpan("badge badge-mouse", "mouse"),
                        mkIcon(
                            "arrow " +
                                (entry.down ? "arrow-mouse" : "arrow-up"),
                            entry.down ? "arrow-down" : "arrow-up",
                        ),
                        mkSpan("mouse-name", btnName(entry.button)),
                        mkSpan("dim", " (" + entry.button + ")"),
                        mkSpan("dim", "  " + entry.x + ", " + entry.y),
                    );
                } else if (t === "scroll") {
                    row.append(
                        mkSpan("badge badge-scroll", "scroll"),
                        mkIcon(
                            "arrow arrow-scroll",
                            entry.direction === "up" ? "arrow-up" : "arrow-down",
                        ),
                        mkSpan(
                            "scroll-name",
                            entry.direction +
                                (entry.amount > 1 ? " x" + entry.amount : ""),
                        ),
                    );
                }

                row.onmouseenter = function() { lp.playSlot("hover"); };
                row.onclick = lp._handleEntryClick;
                return row;
            }

            // -- Route entries to the correct log --
            function appendEntry(entry) {
                if (lp.isPaused()) return;
                if (entry.type === "key" && entry.down)
                    flagKey(entry.key || "?");
                if (entry.type === "mouse" && entry.down)
                    flagMouse(btnName(entry.button) + " (" + entry.button + ")");

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
            }

            // -- Active keys pills --
            function updateActiveKeys(keys) {
                const row = document.getElementById("keys-pills");
                row.innerHTML = "";
                if (!keys || keys.length === 0) {
                    const p = document.createElement("span");
                    p.className = "pill pill-empty";
                    p.textContent = ",";
                    row.appendChild(p);
                    return;
                }
                keys.forEach((entry) => {
                    const p = document.createElement("span");
                    p.className = "pill pill-key";
                    if (typeof entry === "object" && entry !== null) {
                        p.textContent = entry.name + " (" + entry.code + ")";
                    } else {
                        p.textContent = entry;
                    }
                    row.appendChild(p);
                });
            }

            // -- Mouse state (position + active buttons) --
            function updateMouseState(state) {
                const mx = _panel ? _panel.querySelector("#mx-display") : document.getElementById("mx-display");
                const my = _panel ? _panel.querySelector("#my-display") : document.getElementById("my-display");
                if (state.x != null && mx) mx.textContent = state.x;
                if (state.y != null && my) my.textContent = state.y;
                const row = _panel ? _panel.querySelector("#mouse-pills") : document.getElementById("mouse-pills");
                if (!row) return;
                row.innerHTML = "";
                const btns = Array.isArray(state.buttons)
                    ? state.buttons
                    : Object.values(state.buttons || {});
                if (
                    !btns ||
                    (Array.isArray(btns)
                        ? btns.length === 0
                        : Object.keys(btns).length === 0)
                ) {
                    const emp = document.createElement("span");
                    emp.className = "pill pill-key pill-empty";
                    emp.textContent = "\u2014";
                    row.appendChild(emp);
                    return;
                }
                btns.forEach((b) => {
                    const p = document.createElement("span");
                    p.className = "pill pill-mouse";
                    p.textContent = btnName(b) + " (" + b + ")";
                    row.appendChild(p);
                });
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

            function flagKey(name) {
                _lastKeyTime = Date.now();
                document.getElementById("flag-key-name").textContent =
                    name || ",";
                _updateFlagStyles();
            }

            function flagMouse(name) {
                _lastMouseTime = Date.now();
                document.getElementById("flag-mouse-name").textContent =
                    name || ",";
                _updateFlagStyles();
            }

            function _updateFlagStyles() {
                const kRecent = _lastKeyTime >= _lastMouseTime;
                document
                    .getElementById("flag-key-pill")
                    .classList.toggle(
                        "flag-recent",
                        kRecent && _lastKeyTime > 0,
                    );
                document
                    .getElementById("flag-mouse-pill")
                    .classList.toggle(
                        "flag-recent",
                        !kRecent && _lastMouseTime > 0,
                    );
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
