(function() {
    "use strict";
// State //
            let S = {};
            let _modalResolve = null;
            let _toastTimer = null;
            let _ctxTarget = null;

            // Context menu //
            function closeCtxMenu() {
                const el = document.getElementById("ctx-menu-settings");
                if (el) el.classList.remove("open");
                _ctxTarget = null;
            }

            function showCtxMenu(x, y, items, title) {
                const el = document.getElementById("ctx-menu-settings");
                if (!el) return;
                el.innerHTML = "";
                if (title) {
                    const hdr = document.createElement("div");
                    hdr.className = "ctx-header";
                    hdr.textContent = title;
                    el.appendChild(hdr);
                }
                for (const item of items) {
                    if (item === "divider") {
                        const d = document.createElement("div");
                        d.className = "ctx-divider";
                        el.appendChild(d);
                        continue;
                    }
                    const row = document.createElement("div");
                    row.className = "ctx-item" + (item.danger ? " danger" : "");
                    if (item.icon) {
                        const ico = document.createElement("span");
                        ico.className = "ctx-icon";
                        ico.textContent = item.icon;
                        row.appendChild(ico);
                    }
                    const lbl = document.createElement("span");
                    lbl.textContent = item.label;
                    row.appendChild(lbl);
                    row.addEventListener("mouseenter", () => playSlot("hover"));
                    row.addEventListener("click", (e) => {
                        e.stopPropagation();
                        playSlot("interact");
                        closeCtxMenu();
                        item.action();
                    });
                    el.appendChild(row);
                }

                el.classList.add("open");
                el.style.maxHeight = "";
                const MARGIN = 6;
                // The menu is position:fixed inside the zoomed root, so its left/top
                // and offsetWidth/scrollHeight are in zoomed CSS px, while clientX/Y
                // and innerWidth/Height come back in physical px. Fold the pointer and
                // viewport into the same zoomed space or the menu lands off-cursor.
                const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
                x /= zoom; y /= zoom;
                const vw = window.innerWidth / zoom, vh = window.innerHeight / zoom;
                const mw = el.offsetWidth || 160;
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

            document.addEventListener("click", () => closeCtxMenu());
            const _settingsPanel = document.querySelector('.panel-settings');
            document.addEventListener("contextmenu", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                e.preventDefault();
                closeCtxMenu();
            });
            document.addEventListener("keydown", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                if (e.key === "Escape") closeCtxMenu();
            });

            // Bridge //
            function sendToHost(msg) {
                const s = typeof msg === "string" ? msg : JSON.stringify(msg);
                if (window.shellPost) {
                    const data = typeof msg === "string" ? JSON.parse(msg) : msg;
                    window.shellPost("settings", data.action || "unknown", data);
                } else if (window.chrome?.webview) {
                    window.chrome.webview.postMessage(s);
                } else {
                    window.webkit.messageHandlers.ms.postMessage(s);
                }
            }

            // Shell integration //
            if (window.registerPanel) {
                window.registerPanel("settings", function(action, body) {
                    if (action === "state" && body) {
                        receiveState(body);
                    } else if (action === "theme" && body) {
                        applyTheme(body);
                    }
                });
            }

            // Window drag //
            let _dragging = false;
            (function () {
                let _drag = null;
                document
                    .getElementById("header")
                    .addEventListener("mousedown", (e) => {
                        if (
                            e.target.closest(
                                ".header-btns, button, input, select",
                            )
                        )
                            return;
                        _drag = { ox: e.screenX, oy: e.screenY };
                        _dragging = true;
                        const onMove = (ev) => {
                            if (!_drag) return;
                            sendToHost({
                                action: "moveWindow",
                                dx: ev.screenX - _drag.ox,
                                dy: ev.screenY - _drag.oy,
                            });
                            _drag.ox = ev.screenX;
                            _drag.oy = ev.screenY;
                        };
                        const onUp = () => {
                            _drag = null;
                            _dragging = false;
                            window.removeEventListener("mousemove", onMove);
                            window.removeEventListener("mouseup", onUp);
                        };
                        window.addEventListener("mousemove", onMove);
                        window.addEventListener("mouseup", onUp);
                    });
            })();

            // Sound //
            const _lastSlot = {};
            let _lastNonHoverAt = 0;
            function playSlot(slot) {
                if (_dragging) return;
                if (slot === "hover" && !document.hasFocus()) return;
                const now = Date.now();
                // A "hover" firing right after a click is the synthetic mouseenter
                // a re-render throws when a fresh button lands under the stationary
                // cursor (e.g. Browse's Refresh rebuilds its own toolbar). A real
                // hover needs pointer movement, which can't happen this fast at the
                // same spot -- so swallow hover briefly after any deliberate slot.
                if (slot === "hover" && now - _lastNonHoverAt < 250) return;
                if (slot !== "hover") _lastNonHoverAt = now;
                if (now - (_lastSlot[slot] || 0) < 50) return;
                _lastSlot[slot] = now;
                sendToHost({ action: "playSlot", slot });
            }

            // Toast //
            function showAlert(msg, duration) {
                const el = document.getElementById("toast");
                el.textContent = msg;
                el.classList.add("visible");
                clearTimeout(_toastTimer);
                _toastTimer = setTimeout(
                    () => el.classList.remove("visible"),
                    duration || 3000,
                );
            }

            function hideToast() {
                const el = document.getElementById("toast");
                el.classList.remove("visible");
                clearTimeout(_toastTimer);
                _toastTimer = null;
            }

            // Modal //
            function openModal(
                title,
                msg,
                confirmLabel = "OK",
                cancelLabel = "Cancel",
                withInput = false,
                defaultVal = "",
            ) {
                return new Promise((resolve) => {
                    _modalResolve = resolve;
                    document.getElementById("modal-title").textContent = title;
                    document.getElementById("modal-msg").textContent = msg;
                    const inp = document.getElementById("modal-input");
                    if (withInput) {
                        inp.classList.add("show");
                        inp.value = defaultVal;
                        setTimeout(() => inp.focus(), 100);
                    } else {
                        inp.classList.remove("show");
                    }
                    document.getElementById("modal-confirm").style.display = "";
                    document.getElementById("modal-cancel").style.display = "";
                    const keysBox = document.getElementById("modal-keys");
                    keysBox.innerHTML = "";
                    keysBox.style.display = "none";
                    document.getElementById("modal-confirm").textContent =
                        confirmLabel;
                    document.getElementById("modal-cancel").textContent =
                        cancelLabel;
                    const ov = document.getElementById("modal-overlay");
                    ov.inert = false;
                    ov.classList.add("open");
                });
            }
            function closeModal(confirmed) {
                const val = document.getElementById("modal-input").value;
                const ov = document.getElementById("modal-overlay");
                ov.classList.remove("open");
                ov.inert = true;
                if (_modalResolve) {
                    _modalResolve({ confirmed, value: val });
                    _modalResolve = null;
                }
            }
            window.openModal = openModal;
            window.closeModal = closeModal;

            function openLuaModal(d) {
                openModal(
                    d.title || "",
                    d.msg || "",
                    d.confirm || "OK",
                    d.cancel || "Cancel",
                    !!d.hasInput,
                    d.inputDefault || "",
                ).then((r) => {
                    sendToHost({
                        action: "modalResult",
                        confirmed: r.confirmed,
                        value: r.value || "",
                    });
                });
            }
            window.openLuaModal = openLuaModal;

            function updateLuaModal(d) {
                if (d.title !== undefined)
                    document.getElementById("modal-title").textContent = d.title;
                if (d.msg !== undefined)
                    document.getElementById("modal-msg").textContent = d.msg;
                if (d.confirm !== undefined)
                    document.getElementById("modal-confirm").textContent =
                        d.confirm;
                if (d.cancel !== undefined)
                    document.getElementById("modal-cancel").textContent =
                        d.cancel;
                if (d.showConfirm !== undefined)
                    document.getElementById("modal-confirm").style.display =
                        d.showConfirm ? "" : "none";
                if (d.showCancel !== undefined)
                    document.getElementById("modal-cancel").style.display =
                        d.showCancel ? "" : "none";
                if (d.keys !== undefined) {
                    const box = document.getElementById("modal-keys");
                    box.innerHTML = "";
                    box.style.display = "flex";
                    const arr = Array.isArray(d.keys) ? d.keys : [];
                    if (arr.length === 0) {
                        const ph = document.createElement("kbd");
                        ph.className = "modal-key placeholder";
                        ph.textContent = "...";
                        box.appendChild(ph);
                    } else {
                        arr.forEach((k, i) => {
                            if (i > 0) {
                                const plus = document.createElement("span");
                                plus.className = "modal-key-plus";
                                plus.textContent = "+";
                                box.appendChild(plus);
                            }
                            const cap = document.createElement("kbd");
                            cap.className = "modal-key";
                            cap.textContent = k;
                            box.appendChild(cap);
                        });
                    }
                }
            }
            window.updateLuaModal = updateLuaModal;

            document
                .getElementById("modal-overlay")
                .addEventListener("click", (e) => {
                    if (e.target === e.currentTarget) closeModal(false);
                });
            document.addEventListener("keydown", (e) => {
                const overlay = document.getElementById("modal-overlay");
                if (!overlay || !overlay.classList.contains("open")) return;
                if (e.key === "Enter") {
                    // Don't double-fire if focus is on the input (its own handler runs).
                    if (document.activeElement === document.getElementById("modal-input")) return;
                    e.preventDefault();
                    playSlot("interact");
                    closeModal(true);
                }
                if (e.key === "Escape") {
                    e.preventDefault();
                    playSlot("back");
                    closeModal(false);
                }
            });
            document
                .getElementById("modal-input")
                .addEventListener("keydown", (e) => {
                    if (e.key === "Enter") {
                        playSlot("interact");
                        closeModal(true);
                    }
                    if (e.key === "Escape") {
                        playSlot("back");
                        closeModal(false);
                    }
                });

            // Shutdown //
            let _shuttingDown = false;

            async function requestShutdown() {
                if (_shuttingDown) return;
                playSlot("interact");
                const r = await openModal(
                    "Quit mudscript",
                    "Stop all macros and quit mudscript?\n\nThis quits Hammerspoon, mudscript runs inside it, so there is no way to leave one without the other.",
                    "Quit",
                );
                if (!r.confirmed) return;
                beginShutdown();
            }
            window.requestShutdown = requestShutdown;

            function beginShutdown() {
                _shuttingDown = true;
                sendToHost({ action: "shutdown" });
            }

            // Helpers //
            function h(tag, attrs = {}, ...children) {
                const el = document.createElement(tag);
                for (const [k, v] of Object.entries(attrs)) {
                    if (k === "cls") el.className = v;
                    else if (k.startsWith("on"))
                        el.addEventListener(k.slice(2), v);
                    else el.setAttribute(k, v);
                }
                for (const c of children) {
                    if (c == null) continue;
                    el.appendChild(
                        typeof c === "string" ? document.createTextNode(c) : c,
                    );
                }
                return el;
            }

            function toggle(checked, onchange, silent) {
                const label = h(
                    "label",
                    { cls: "toggle", onmouseenter: () => playSlot("hover") },
                    h("input", {
                        type: "checkbox",
                        onchange: (e) => {
                            const on = e.target.checked;
                            try { if (onchange) onchange(e); }
                            finally { if (!silent) playSlot(on ? "toggleOn" : "toggleOff"); }
                        },
                    }),
                    h("div", { cls: "toggle-track" }),
                    h("div", { cls: "toggle-thumb" }),
                );
                label.querySelector("input").checked = checked;
                return label;
            }

            function seg(options, active, onselect) {
                const wrap = h("div", { cls: "seg" });
                for (const o of options) {
                    const btn = h(
                        "button",
                        {
                            cls:
                                "seg-btn" +
                                (o.value === active ? " active" : ""),
                            onmouseenter: () => playSlot("hover"),
                            onclick: () => {
                                playSlot("interact");
                                for (const b of wrap.children)
                                    b.classList.remove("active");
                                btn.classList.add("active");
                                onselect(o.value);
                            },
                        },
                        o.label,
                    );
                    wrap.appendChild(btn);
                }
                return wrap;
            }

            function section(id, title, buildFn, desc) {
                const head = h(
                    "div",
                    { cls: "section-head" },
                    h("span", { cls: "section-title" }, title),
                    desc ? h("span", { cls: "section-desc" }, desc) : null,
                );
                const body = h("div", { cls: "section-body" });
                buildFn(body);
                const wrap = h("div", { cls: "section" });
                wrap.setAttribute("data-section", id);
                wrap.appendChild(head);
                wrap.appendChild(body);
                return wrap;
            }

            function row(
                label,
                sublabel,
                control,
                extra = "",
                ctxItems = null,
            ) {
                const r = h("div", {
                    cls: "row " + extra,
                    onmouseenter: () => playSlot("hover"),
                });
                const lbl = h("div", { cls: "row-label" }, label);
                if (sublabel) lbl.appendChild(h("small", {}, sublabel));
                r.appendChild(lbl);
                if (control) r.appendChild(control);
                r.addEventListener("contextmenu", (e) => {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    if (ctxItems && ctxItems.length > 0) {
                        playSlot("interact");
                        showCtxMenu(e.clientX, e.clientY, ctxItems, label);
                    }
                });
                return r;
            }

            function btnRow(...buttons) {
                const wrap = h("div", { cls: "btn-row" });
                for (const b of buttons) wrap.appendChild(b);
                return wrap;
            }

            function actionBtn(label, cls, action) {
                return h(
                    "button",
                    {
                        cls: "btn-action " + (cls || ""),
                        onmouseenter: () => playSlot("hover"),
                        onclick: () => {
                            playSlot("interact");
                            action();
                        },
                    },
                    label,
                );
            }

            function divider() {
                return h("div", { cls: "divider" });
            }
            function groupLabel(txt) {
                return h("div", { cls: "group-label" }, txt);
            }

            window.msUI = {
                h, toggle, seg, section, row, btnRow, actionBtn, divider,
                groupLabel, showCtxMenu,
            };

            // Sections //


            function buildSlider(
                label,
                hint,
                min,
                max,
                step,
                unit,
                val,
                onChange,
                ctxItems,
            ) {
                const wrap = h("div", {
                    cls: "row slider-row",
                    onmouseenter: () => playSlot("hover"),
                });
                if (ctxItems && ctxItems.length) {
                    wrap.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(e.clientX, e.clientY, ctxItems, label);
                    });
                }
                const top = h("div", { cls: "slider-top" });
                const lbl = h("div", { cls: "row-label" }, label);
                if (hint) lbl.appendChild(h("small", {}, hint));
                top.appendChild(lbl);
                const numInput = h("input", {
                    type: "number",
                    step: String(step || 1),
                    min: String(min),
                    max: String(max),
                });
                numInput.value = val;
                const valDiv = h("div", { cls: "slider-val" });
                valDiv.appendChild(numInput);
                if (unit) {
                    const uSpan = document.createElement("span");
                    uSpan.textContent = unit;
                    uSpan.style.cssText =
                        "font-size:11px;opacity:0.55;margin-left:3px;";
                    valDiv.appendChild(uSpan);
                }
                top.appendChild(valDiv);
                wrap.appendChild(top);
                const slider = h("input", {
                    type: "range",
                    min: String(min),
                    max: String(max),
                    step: String(step || 1),
                });
                slider.value = val;
                const decimals = step && step < 1 ? 2 : 0;
                slider.addEventListener("input", () => {
                    numInput.value = parseFloat(slider.value).toFixed(decimals);
                });
                slider.addEventListener("change", () =>
                    onChange(parseFloat(slider.value)),
                );
                numInput.addEventListener("change", () => {
                    const v = Math.max(
                        min,
                        Math.min(max, parseFloat(numInput.value) || min),
                    );
                    slider.value = v;
                    onChange(v);
                });
                wrap.appendChild(slider);
                return wrap;
            }

            function buildRuntime(body) {
                body.appendChild(
                    row(
                        "Macros",
                        "Master switch for the macro engine",
                        // Silent: setMacros -> _doNotify plays the bind-state
                        // slot (enabled/disabled) itself. Without silent, the
                        // toggle's own toggleOn/toggleOff would fire on top of
                        // that, doubling the sound on every flip.
                        toggle(S.macrosEnabled ?? false, (e) =>
                            sendToHost({
                                action: "setMacros",
                                value: e.target.checked ? 1 : 0,
                            }),
                            true,
                        ),
                    ),
                );

                body.appendChild(divider());
                body.appendChild(groupLabel("Reload"));
                body.appendChild(
                    h("div", { cls: "group-hint" },
                        "Pick what a reload rebuilds. Anything left off keeps "
                        + "its current state."),
                );

                const qr = S.qrOptions || {};
                const targets = [
                    ["macros", "Macro pack"],
                    ["theme", "Appearance (theme & sounds)"],
                    ["settings", "Settings file"],
                    ["ui", "Shell windows"],
                ];
                for (const [key, label] of targets) {
                    body.appendChild(
                        row(
                            label,
                            null,
                            toggle(qr[key] !== false, (e) =>
                                sendToHost({
                                    action: "setQROption",
                                    key: key,
                                    value: e.target.checked,
                                }),
                            ),
                            "row-sub row-compact",
                        ),
                    );
                }

                body.appendChild(
                    btnRow(
                        actionBtn("Reload Selected", "accent", () => {
                            const q = S.qrOptions || {};
                            const acts = {
                                macros: "reloadMacros",
                                theme: "reloadTheme",
                                settings: "reloadSettings",
                                ui: "reloadUI",
                            };
                            let sent = false;
                            for (const [key, action] of Object.entries(acts)) {
                                if (q[key] !== false) {
                                    sendToHost({ action: action });
                                    sent = true;
                                }
                            }
                            if (!sent) showAlert("Nothing selected to reload.");
                        }),
                        actionBtn("Reload All", "", async () => {
                            const r = await openModal(
                                "Reload All",
                                "Restart Hammerspoon and reload mudscript from disk?",
                                "Reload",
                            );
                            if (r.confirmed) sendToHost({ action: "reloadAll" });
                        }),
                    ),
                );
            }

            // buildAccessibility, input and motion settings //
            function buildAccessibility(body) {
                const hidden = S.hiddenFeatures || {};
                const hasTrackpad = !hidden.trackpad;
                const hasSocd = !hidden.socd;
                const hasGamepad = !hidden.gamepad;

                // Display zoom — scales the whole UI (shell + popouts) for
                // large or small displays. Also driven by Cmd +/- / Cmd 0.
                (function () {
                    const z = S.uiZoom || 1.0;
                    const pct = Math.round(z * 100) + "%";
                    const zoomCtl = h("div", {});
                    zoomCtl.style.cssText =
                        "display:flex;align-items:center;gap:8px;";
                    const send = (data) =>
                        sendToHost(Object.assign({ action: "setUiZoom" }, data));
                    const minus = actionBtn("−", "", () =>
                        send({ delta: -0.1 }));
                    const plus = actionBtn("+", "", () =>
                        send({ delta: 0.1 }));
                    const pctEl = h("span", {}, pct);
                    pctEl.style.cssText =
                        "min-width:42px;text-align:center;font-size:12px;"
                        + "color:var(--text2);font-variant-numeric:tabular-nums;";
                    minus.disabled = z <= 0.5;
                    plus.disabled = z >= 2.0;
                    zoomCtl.appendChild(minus);
                    zoomCtl.appendChild(pctEl);
                    zoomCtl.appendChild(plus);
                    body.appendChild(
                        row(
                            "Display Zoom",
                            "Scale the whole interface — shell and popouts "
                                + "(Cmd +/−, Cmd 0 to reset)",
                            zoomCtl,
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to 100%",
                                    action: () => send({ reset: true }),
                                },
                            ],
                        ),
                    );
                    body.appendChild(divider());
                })();

                if (hasTrackpad) {
                    body.appendChild(
                        row(
                            "Trackpad / Pen Mode",
                            null,
                            toggle(S.trackpadMode ?? false, (e) =>
                                sendToHost({
                                    action: "setTrackpadMode",
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to default",
                                    action: () =>
                                        sendToHost({
                                            action: "resetSetting",
                                            key: "trackpadMode",
                                        }),
                                },
                            ],
                        ),
                    );
                }

                // SOCD
                if (hasSocd) {
                    if (hasTrackpad) body.appendChild(divider());
                    body.appendChild(
                        row(
                            "SOCD Cleaning",
                            null,
                            toggle(S.socdEnabled ?? false, (e) =>
                                sendToHost({
                                    action: "setSocdEnabled",
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to default",
                                    action: () =>
                                        sendToHost({
                                            action: "resetSetting",
                                            key: "socdEnabled",
                                        }),
                                },
                            ],
                        ),
                    );
                    if (S.socdEnabled) {
                        body.appendChild(
                            row(
                                "SOCD Mode",
                                null,
                                seg(
                                    [
                                        {
                                            label: "Last Wins",
                                            value: "lastWins",
                                        },
                                        { label: "Neutral", value: "neutral" },
                                        {
                                            label: "First Wins",
                                            value: "firstWins",
                                        },
                                    ],
                                    S.socdMode ?? "lastWins",
                                    (v) =>
                                        sendToHost({
                                            action: "setSocdMode",
                                            value: v,
                                        }),
                                ),
                                "row-sub",
                                [
                                    {
                                        icon: "",
                                        label: "Reset to default",
                                        action: () =>
                                            sendToHost({
                                                action: "resetSetting",
                                                key: "socdMode",
                                            }),
                                    },
                                ],
                            ),
                        );
                    }
                }

                // Controller / Gamepad — enable toggle, live detection status,
                // and the macros currently bound to controller buttons.
                if (hasGamepad) {
                    if (hasTrackpad || hasSocd) body.appendChild(divider());
                    const gpOn = S.gamepadEnabled === true;
                    body.appendChild(
                        row(
                            "Controller / Gamepad Input",
                            "Let macros be triggered by controller buttons. "
                                + "Pair your controller over Bluetooth, then use "
                                + "a macro's Bind button and press a button",
                            toggle(gpOn, (e) =>
                                sendToHost({
                                    action: "setGamepadEnabled",
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to default",
                                    action: () =>
                                        sendToHost({
                                            action: "resetSetting",
                                            key: "gamepadEnabled",
                                        }),
                                },
                            ],
                        ),
                    );

                    if (gpOn) {
                        // Live detection status.
                        const TYPE_NAMES = {
                            ds4: "PlayStation",
                            xbox: "Xbox",
                            switch: "Nintendo Switch Pro",
                            generic: "Controller",
                        };
                        const ctrls = S.gamepadControllers || [];
                        let statusText;
                        if (ctrls.length === 0) {
                            statusText =
                                "No controller detected — pair one over "
                                + "Bluetooth, then it will appear here.";
                        } else {
                            statusText =
                                "Detected: "
                                + ctrls
                                    .map(
                                        (c) =>
                                            TYPE_NAMES[c.type] || "Controller",
                                    )
                                    .join(", ");
                        }
                        const statusRow = row(
                            "Status",
                            statusText,
                            null,
                            "row-sub",
                        );
                        statusRow
                            .querySelector(".row-label")
                            .classList.add(
                                ctrls.length ? "gp-status-ok" : "gp-status-none",
                            );
                        body.appendChild(statusRow);

                        // Macros currently bound to a controller button.
                        const binds = S.gamepadBinds || [];
                        if (binds.length === 0) {
                            body.appendChild(
                                row(
                                    "Bound macros",
                                    "None",
                                    null,
                                    "row-sub",
                                ),
                            );
                        } else {
                            binds.forEach((b) => {
                                const controls = btnRow(
                                    h(
                                        "span",
                                        { cls: "gp-bind-pill" },
                                        "Pad " + (b.pad || "?"),
                                    ),
                                    actionBtn("Rebind", "", () =>
                                        sendToHost({
                                            action: "startRebind",
                                            id: b.id,
                                            systemBind: b.systemBind === true,
                                        }),
                                    ),
                                    actionBtn("Unbind", "danger", () =>
                                        sendToHost({
                                            action: "resetBind",
                                            id: b.id,
                                            systemBind: b.systemBind === true,
                                        }),
                                    ),
                                );
                                body.appendChild(
                                    row(
                                        b.label,
                                        null,
                                        controls,
                                        "row-sub gp-bind-row",
                                    ),
                                );
                            });
                        }
                    }
                }

                if (hasTrackpad || hasSocd || hasGamepad) body.appendChild(divider());
                const octane = S.octaneMode === true;
                body.appendChild(
                    row(
                        "Octane Mode",
                        "Low-overhead mode: disables logging, animations, pollers, and sounds while macros run as normal",
                        toggle(octane, (e) => {
                            sendToHost({
                                action: "setOctaneMode",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );

                const octaneMute = S.octaneMuteSounds === true;
                body.appendChild(
                    row(
                        "Octane: mute sounds",
                        "Silence all UI sounds when Octane Mode is active",
                        toggle(octaneMute, (e) => {
                            sendToHost({
                                action: "setOctaneMuteSounds",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );
            }

            function userCtxItems(item) {
                const out = [];
                if (item.default !== undefined) {
                    out.push({
                        icon: "",
                        label: "Reset to default",
                        action: () =>
                            sendToHost({ action: "resetUserSetting", key: item.key }),
                    });
                }
                if (item.authored && item.key) {
                    out.push({
                        icon: "",
                        label: "Edit tool",
                        action: () => {
                            if (window._loadSettingIntoBuilder)
                                window._loadSettingIntoBuilder(item);
                        },
                    });
                    out.push({
                        icon: "",
                        label: "Delete tool",
                        danger: true,
                        action: async () => {
                            const res = await openModal(
                                "Delete Tool",
                                `Delete "${item.label || item.key}"?\n\nThis removes the setting from your pack. This cannot be undone.`,
                                "Delete",
                            );
                            if (res.confirmed)
                                sendToHost({
                                    action: "removeUserSetting",
                                    key: item.key,
                                });
                        },
                    });
                } else if (item.authored && item.uid) {
                    // Keyless authored items (divider / label): no Edit, but they
                    // can be deleted by their stable uid.
                    out.push({
                        icon: "",
                        label: "Delete " + (item.type === "divider"
                            ? "divider" : "label"),
                        danger: true,
                        action: async () => {
                            const res = await openModal(
                                "Delete Item",
                                "Remove this " + (item.type === "divider"
                                    ? "divider" : "label")
                                    + " from your pack? This cannot be undone.",
                                "Delete",
                            );
                            if (res.confirmed)
                                sendToHost({
                                    action: "removeUserSettingByUid",
                                    uid: item.uid,
                                });
                        },
                    });
                }
                return out.length ? out : null;
            }

            function renderUserItem(body, item) {
                if (item.type === "divider") {
                    body.appendChild(divider());
                } else if (item.type === "groupLabel") {
                    body.appendChild(groupLabel(item.label || ""));
                } else if (item.type === "toggle") {
                    const ctxItems = userCtxItems(item);
                    body.appendChild(
                        row(
                            item.label || item.key,
                            item.hint || null,
                            toggle(item.value ?? false, (e) =>
                                sendToHost({
                                    action: "userSettingChange",
                                    key: item.key,
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            ctxItems,
                        ),
                    );
                } else if (item.type === "slider") {
                    const ctxItems = userCtxItems(item);
                    body.appendChild(
                        buildSlider(
                            item.label || item.key,
                            item.hint || null,
                            item.min ?? 0,
                            item.max ?? 100,
                            item.step ?? 1,
                            item.unit || null,
                            item.value ?? item.default ?? 0,
                            (v) =>
                                sendToHost({
                                    action: "userSettingChange",
                                    key: item.key,
                                    value: v,
                                }),
                            ctxItems,
                        ),
                    );
                } else if (item.type === "seg") {
                    const ctxItems = userCtxItems(item);
                    body.appendChild(
                        row(
                            item.label || item.key,
                            item.hint || null,
                            seg(
                                item.options || [],
                                item.value ?? item.default,
                                (v) =>
                                    sendToHost({
                                        action: "userSettingChange",
                                        key: item.key,
                                        value: v,
                                    }),
                            ),
                            "",
                            ctxItems,
                        ),
                    );
                } else if (item.type === "action") {
                    const btn = actionBtn(
                        item.btnLabel || "Run",
                        item.danger ? "danger" : "",
                        () =>
                            sendToHost({
                                action: "userSettingAction",
                                key: item.key,
                            }),
                    );
                    if (item.label) {
                        body.appendChild(
                            row(item.label, item.hint || null, btn, "",
                                userCtxItems(item)),
                        );
                    } else {
                        body.appendChild(btnRow(btn));
                    }
                } else if (item.type === "group") {
                    const det = document.createElement("details");
                    det.className = "user-group";
                    det.open = item.open !== false;
                    const sum = document.createElement("summary");
                    sum.className = "user-group-summary";
                    const arrow = document.createElement("span");
                    arrow.className = "user-group-arrow";
                    arrow.textContent = "\u25b8";
                    sum.appendChild(arrow);
                    sum.appendChild(
                        document.createTextNode(
                            "\u00a0" + (item.label || "Group"),
                        ),
                    );
                    det.appendChild(sum);
                    for (const child of item.items || []) {
                        renderUserItem(det, child);
                    }
                    body.appendChild(det);
                }
            }

            function buildDefaults(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Save as Default", "", async () => {
                            const r = await openModal(
                                "Save as Default",
                                "Save current settings as the new default?\nThe existing default will be archived.",
                                "Save",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "saveDefault" });
                        }),
                        actionBtn("Reset to Default", "danger", async () => {
                            const r = await openModal(
                                "Reset to Default",
                                "Reset all settings to the saved default?\nCurrent settings will be overwritten.",
                                "Reset",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "resetToDefault" });
                        }),
                    ),
                );
            }

            // A setting belongs to the default Settings group when it names no
            // section (or names "settings"); anything else groups by section.
            function isDefaultSection(item) {
                const s = item && item.section;
                return !s || s === "settings";
            }

            // buildSettings, the default Settings group //
            function buildSettings(body) {
                const items = filterByOrigin(S.userSettings || [])
                    .filter(isDefaultSection);
                if (items.length > 0) {
                    for (const item of items) {
                        renderUserItem(body, item);
                    }
                } else {
                    body.appendChild(groupLabel("No settings defined."));
                    const r = h("div", { cls: "row" });
                    const lbl = h("div", { cls: "row-label" });
                    lbl.appendChild(
                        h(
                            "small",
                            {},
                            "Use ms.settings.define() in ms_macros.lua, or build settings with the builder.",
                        ),
                    );
                    r.appendChild(lbl);
                    body.appendChild(r);
                }
            }

            // Function tools — each callable from here or from a macro.
            function buildFunctions(body) {
                const items = filterByOrigin(S.userFunctions || []);
                if (!items.length) {
                    body.appendChild(groupLabel("No functions defined."));
                    return;
                }
                for (const fn of items) {
                    const label = fn.icon
                        ? fn.icon + " " + (fn.label || fn.id)
                        : (fn.label || fn.id);
                    body.appendChild(
                        row(label, fn.info || null,
                            actionBtn("Run", "", () =>
                                sendToHost({ action: "runFunction", id: fn.id })),
                        ),
                    );
                }
            }

            // Shared helper variables, each editable by its declared type.
            function varControl(v) {
                const type = v.type || "string";
                const cur = (v.value !== undefined && v.value !== null)
                    ? v.value : v.default;
                const send = (val) =>
                    sendToHost({ action: "setHelperVarValue", name: v.name, value: val });
                if (type === "boolean") {
                    return toggle(cur === true || cur === "true",
                        (e) => send(e.target.checked));
                }
                const inp = h("input", {
                    type: type === "number" ? "number" : "text",
                    cls: "input-sm",
                    value: (cur !== undefined && cur !== null) ? String(cur) : "",
                });
                inp.addEventListener("change", () =>
                    send(type === "number" ? Number(inp.value) : inp.value));
                inp.addEventListener("keydown", (e) => e.stopPropagation());
                return inp;
            }

            function buildVariables(body) {
                const items = filterByOrigin(S.userVariables || []);
                if (!items.length) {
                    body.appendChild(groupLabel("No variables defined."));
                    return;
                }
                for (const v of items) {
                    body.appendChild(row(v.label || v.name, v.hint || null, varControl(v)));
                }
            }

            // buildUserSection, a pack ms.menu.define() menu (its own item list) //
            function buildUserSection(body, menu) {
                for (const item of menu.items || []) {
                    renderUserItem(body, item);
                }
            }

            // Render a list of user items, dropping leading/trailing dividers and
            // merging consecutive ones so a section never shows an empty cell.
            function renderItemsCollapsed(body, items) {
                let lastWasDivider = true;
                let rendered = 0;
                const start = body.childElementCount;
                for (const item of items) {
                    if (item.type === "divider") {
                        if (lastWasDivider) continue;
                        lastWasDivider = true;
                        renderUserItem(body, item);
                        continue;
                    }
                    lastWasDivider = false;
                    rendered++;
                    renderUserItem(body, item);
                }
                // Trailing divider, if any, is the last child added here.
                if (lastWasDivider && body.childElementCount > start) {
                    const last = body.lastElementChild;
                    if (last && last.classList.contains("divider")) last.remove();
                }
                return rendered;
            }

            // Display title/desc for a section id that has no user metadata (pack
            // sections such as "calibration", or any section= a pack chose).
            function packSectionDisplay(id) {
                if (id === "calibration")
                    return { title: "Calibration", desc: "Tune the pack to your setup" };
                const title = id.replace(/^user_/, "").replace(/[_-]+/g, " ")
                    .replace(/\b\w/g, (c) => c.toUpperCase());
                return { title: title || id, desc: null };
            }

            // A user-created section: a plain heading (title + optional hint)
            // whose name and hint are edited by right-clicking it, plus its
            // settings (divider-collapsed). Right-click editing keeps this
            // distinct from pack/handwritten sections, which have no edit menu.
            function userSectionGroup(meta, items) {
                const title = meta.icon
                    ? meta.icon + " " + (meta.title || "")
                    : (meta.title || "");
                const wrap = section(meta.id, title, (body) => {
                    const n = renderItemsCollapsed(body, items);
                    if (!n) {
                        body.appendChild(groupLabel("Empty section."));
                        const r = h("div", { cls: "row" });
                        const lbl = h("div", { cls: "row-label" });
                        lbl.appendChild(h("small", {},
                            "Add a setting with the Setting builder and pick this "
                            + "section as its destination."));
                        r.appendChild(lbl);
                        body.appendChild(r);
                    }
                }, meta.hint || null);

                // Right-click the heading to rename, edit the hint, or remove.
                const editName = async () => {
                    const res = await openModal(
                        "Rename Section", "Name for this section.",
                        "Save", "Cancel", true, meta.title || "");
                    const v = (res.value || "").trim();
                    if (res.confirmed && v)
                        sendToHost({ action: "updateUserMenu", id: meta.id, title: v });
                };
                const editHint = async () => {
                    const res = await openModal(
                        "Edit Hint", "Short hint shown under the section name "
                        + "(leave blank for none).",
                        "Save", "Cancel", true, meta.hint || "");
                    if (res.confirmed)
                        sendToHost({
                            action: "updateUserMenu", id: meta.id,
                            hint: (res.value || "").trim(),
                        });
                };
                const remove = async () => {
                    const res = await openModal(
                        "Remove Section",
                        `Remove "${meta.title}"?\n\nAny settings inside it move `
                        + `back to the Settings group; nothing is deleted.`,
                        "Remove",
                    );
                    if (res.confirmed)
                        sendToHost({ action: "removeUserMenu", id: meta.id });
                };
                const head = wrap.querySelector(".section-head");
                if (head) {
                    head.style.cursor = "context-menu";
                    head.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(e.clientX, e.clientY, [
                            { label: "Edit name...", action: editName },
                            { label: "Edit hint...", action: editHint },
                            "divider",
                            { label: "Remove section", danger: true, action: remove },
                        ], meta.title || "Section");
                    });
                }
                return wrap;
            }

            function buildProfiles(root) {
                const current = S.currentProfile || "";
                const profiles = S.profiles || [];
                const hasOthers = profiles.some((n) => n !== current);

                root.appendChild(section("profiles-list", "Profiles",
                    (body) => buildProfileList(body, current, profiles),
                    current ? "Active: " + current : "None active"));

                root.appendChild(section("profiles-manage", "Manage",
                    (body) => buildProfileManage(body, current, profiles, hasOthers),
                    "Creating, saving, moving and clearing profiles"));
            }

            function profileMenuItems(name, isCurrent) {
                const items = [];
                items.push({
                    icon: "",
                    label: "Rename...",
                    action: async () => {
                        const r = await openModal(
                            "Rename Profile",
                            `New name for "${name}".`,
                            "Rename",
                            "Cancel",
                            true,
                            name,
                        );
                        const v = (r.value || "").trim();
                        if (r.confirmed && v)
                            sendToHost({ action: "renameProfile", name, newName: v });
                    },
                });
                if (!isCurrent) {
                    items.push({
                        icon: "",
                        label: "Switch to this profile",
                        action: async () => {
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        },
                    });
                }
                items.push({
                    icon: "",
                    label: "Export this profile...",
                    action: () =>
                        sendToHost(
                            isCurrent
                                ? { action: "exportPackage", type: "profile" }
                                : { action: "exportPackage", type: "profile", profileName: name },
                        ),
                });
                if (!isCurrent) {
                    items.push("divider");
                    items.push({
                        icon: "",
                        label: "Delete profile",
                        danger: true,
                        action: async () => {
                            const res = await openModal(
                                "Delete Profile",
                                `Delete "${name}"?\n\nThis cannot be undone.`,
                                "Delete",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "deleteProfile", name });
                        },
                    });
                }
                return items;
            }

            function buildProfileList(body, current, profiles) {
                const otherProfiles = profiles.filter((n) => n !== current);
                if (otherProfiles.length === 0 && !current) {
                    body.appendChild(
                        h(
                            "div",
                            { cls: "row disabled" },
                            h(
                                "div",
                                { cls: "row-label" },
                                "No saved profiles yet.",
                            ),
                        ),
                    );
                }

                for (const name of profiles) {
                    const isCurrent = name === current;
                    const r = h("div", {
                        cls: "row",
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, name));
                    if (isCurrent)
                        r.appendChild(
                            h("span", { cls: "pill success" }, "Active"),
                        );

                    const menuBtn = h(
                        "button",
                        {
                            cls: "row-menu-btn",
                            title: "Profile actions",
                            onmouseenter: () => playSlot("hover"),
                        },
                        "⋯",
                    );
                    menuBtn.addEventListener("click", (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        playSlot("interact");
                        const rect = menuBtn.getBoundingClientRect();
                        showCtxMenu(
                            rect.right,
                            rect.bottom,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    r.appendChild(menuBtn);

                    if (!isCurrent)
                        r.addEventListener("click", async () => {
                            playSlot("interact");
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        });

                    r.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(
                            e.clientX,
                            e.clientY,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    body.appendChild(r);
                }
            }

            function buildProfileManage(body, current, profiles, hasOthers) {
                const nameExists = current && profiles.some((n) => n === current);
                body.appendChild(
                    btnRow(
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action",
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: async () => {
                                        playSlot("interact");
                                        const r = await openModal(
                                            "Create New Profile",
                                            "Start it from your current macros, theme, settings, and sounds — or blank?",
                                            "Seed from current",
                                            "Start blank",
                                        );
                                        sendToHost({
                                            action: "createNewProfile",
                                            seed: r.confirmed,
                                        });
                                    },
                                },
                                "Create New Profile",
                            );
                            return b;
                        })(),
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action" + (!nameExists ? " disabled" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        if (!nameExists) return;
                                        playSlot("interact");
                                        sendToHost({ action: "saveCurrentProfile" });
                                    },
                                },
                                "Save Current Profile",
                            );
                            return b;
                        })(),
                    ),
                );
                // Moving a profile between machines is just another way of
                // managing it, so import/export live here rather than in a
                // separate section (matching the theme/sound/macro panels).
                body.appendChild(
                    btnRow(
                        actionBtn("Import Profile", "", () =>
                            sendToHost({ action: "importPackage" }),
                        ),
                        actionBtn("Export Profile", "", () =>
                            sendToHost({ action: "exportPackage", type: "profile" }),
                        ),
                    ),
                );
                if (hasOthers) {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Clear Saved Profiles",
                                "danger",
                                async () => {
                                    const res = await openModal(
                                        "Clear Saved Profiles",
                                        "Delete all saved profiles except the active one?\n\nThis cannot be undone.",
                                        "Delete All",
                                    );
                                    if (res.confirmed)
                                        sendToHost({ action: "clearProfiles" });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildDeveloper(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Open Log Folder", "", () =>
                            sendToHost({ action: "openDevLogs" }),
                        ),
                    ),
                );

                body.appendChild(divider());

                body.appendChild(
                    buildSlider(
                        "Log archive limit",
                        "Max archived log files kept per category in backups/",
                        0,
                        50,
                        1,
                        null,
                        S.devArchiveLimit ?? 15,
                        (v) =>
                            sendToHost({
                                action: "setDevArchiveLimit",
                                value: v,
                            }),
                        [
                            {
                                icon: "",
                                label: "Reset to default",
                                action: () =>
                                    sendToHost({
                                        action: "setDevArchiveLimit",
                                        value: 15,
                                    }),
                            },
                        ],
                    ),
                );

                const chan = S.updateChannel || "stable";
                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Update Channel",
                        chan === "testing"
                            ? "Checks GitHub Actions for latest testing build"
                            : "Checks MANIFEST.json for stable releases",
                        h(
                            "button",
                            {
                                cls: "btn-macro " + (chan === "testing" ? "btn-enable" : ""),
                                onmouseenter: () => playSlot("hover"),
                                onclick: () => {
                                    const next = chan === "testing" ? "stable" : "testing";
                                    sendToHost({
                                        action: "setUpdateChannel",
                                        value: next,
                                    });
                                },
                            },
                            chan === "testing" ? "Testing" : "Stable",
                        ),
                    ),
                );

                body.appendChild(divider());

                if (chan === "testing") {
                    const src = S.testingSource || "release";
                    body.appendChild(
                        row(
                            "Testing Source",
                            src === "artifact"
                                ? "Downloads from GitHub Actions artifacts (zip only)"
                                : "Downloads from GitHub Releases (signed manifests)",
                            h(
                                "button",
                                {
                                    cls: "btn-macro " + (src === "artifact" ? "btn-enable" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        const next = src === "artifact" ? "release" : "artifact";
                                        sendToHost({
                                            action: "setTestingSource",
                                            value: next,
                                        });
                                    },
                                },
                                src === "artifact" ? "Artifacts" : "Releases",
                            ),
                        ),
                    );

                    if (src === "artifact") {
                        const token = S.githubToken || "";
                        body.appendChild(
                            row(
                                "GitHub Token",
                                token ? "••••••••" + token.slice(-4) : "Required for artifact downloads",
                                h("input", {
                                    type: "password",
                                    cls: "input-sm",
                                    placeholder: "ghp_...",
                                    value: token,
                                    onchange: (e) => {
                                        sendToHost({
                                            action: "setGithubToken",
                                            value: e.target.value,
                                        });
                                    },
                                }),
                            ),
                        );
                    }
                }

                body.appendChild(divider());

                const status = S.integrityStatus || "uninitialized";
                const hash = S.integrityHash
                    ? S.integrityHash.slice(0, 16) + "..."
                    : ",";
                const trusted = status === "trusted";

                let statusPill;
                if (status === "trusted")
                    statusPill = h(
                        "span",
                        { cls: "pill success", style: "font-weight:600" },
                        "Trusted",
                    );
                else if (status === "mismatch")
                    statusPill = h(
                        "span",
                        { cls: "pill danger", style: "font-weight:600" },
                        "⚠ Mismatch",
                    );
                else statusPill = h("span", { cls: "pill", style: "font-weight:600" }, "Not set");
                body.appendChild(row("System Integrity", hash, statusPill));

                const trustRow = h("div", {
                    cls: "row" + (trusted ? " disabled" : ""),
                    onmouseenter: () => {
                        if (!trusted) playSlot("hover");
                    },
                });
                trustRow.appendChild(
                    h(
                        "div",
                        { cls: "row-label" },
                        trusted
                            ? "Trust Current Version"
                            : "Trust Current Version...",
                    ),
                );
                if (!trusted) {
                    trustRow.addEventListener("click", async () => {
                        playSlot("interact");
                        const prompt =
                            status === "uninitialized"
                                ? `Seal this ms_core.lua as the trusted baseline?\nHash: ${hash}`
                                : `Hash mismatch, trust the CURRENT (possibly modified) version?\nHash: ${hash}`;
                        const r = await openModal(
                            "Trust Current Version",
                            prompt,
                            "Trust",
                        );
                        if (r.confirmed)
                            sendToHost({ action: "trustCurrentVersion" });
                    });
                }
                body.appendChild(trustRow);

                body.appendChild(
                    btnRow(
                        actionBtn("Check Integrity", "", () =>
                            sendToHost({ action: "checkIntegrity" }),
                        ),
                    ),
                );

                if (status !== "uninitialized") {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Delete Trusted Hash",
                                "danger",
                                async () => {
                                    const r = await openModal(
                                        "Delete Trusted Hash",
                                        "This removes integrity protection entirely.\n\n" +
                                            "From this point on mudscript will load ANY version of its code " +
                                            "without warning, including maliciously modified files.\n\n" +
                                            "You are on your own. Proceed only if you know what you are doing.",
                                        "Delete, I understand the risk",
                                    );
                                    if (r.confirmed)
                                        sendToHost({
                                            action: "deleteTrustedHash",
                                        });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildHelp(body) {
                const meta = S.macroMeta || {};
                const ver = S.msVersion || "dev";
                body.appendChild(
                    h(
                        "div",
                        { cls: "group-label" },
                        "mudscript HS Utilities \u2013 Version: ",
                        h("span", { style: "text-transform: none" }, ver),
                    ),
                );

                const aboutBtn = actionBtn("About", "", () => {
                    sendToHost({
                        action: "alert",
                        msg: "mudscript Utility Library\nBy: mudbourn \u2014 mudbourn.info",
                        duration: 5,
                    });
                    if (meta.name) {
                        const line2 =
                            meta.name +
                            (meta.author ? `\nBy: ${meta.author}` : "") +
                            (meta.website ? `\n${meta.website}` : "");
                        sendToHost({
                            action: "alert",
                            msg: line2,
                            duration: 5,
                            noSound: true,
                        });
                    }
                });

                const docBtn = actionBtn("Documentation", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: (S.docsURL || "") + "?platform=mac",
                    }),
                );
                docBtn.style.flex = "1";

                const githubBtn = actionBtn("GitHub", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: "https://github.com/mudbourn/mudscript",
                    }),
                );
                githubBtn.style.flex = "1";

                if (S.updateManifestURL || S.updateChannel === "testing") {
                    const _chan = S.updateChannel || "stable";
                    const updateBtn = actionBtn(
                        "Check for Update",
                        "",
                        async () => {
                            const r = await openModal(
                                "Check for Update",
                                "Channel: " + _chan + "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                                "Update",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "checkForUpdate" });
                        },
                    );
                    body.appendChild(btnRow(aboutBtn, updateBtn));
                } else {
                    body.appendChild(btnRow(aboutBtn));
                }
                body.appendChild(btnRow(docBtn, githubBtn));

                // Launch update alerts toggle — the same setting as the menubar
                // Help item, surfaced here so the update alert's "turn these off
                // under Help" points at something the user can actually see.
                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Update Alerts on Launch",
                        "Notify about app, plugin, and content updates at startup",
                        toggle(!(S.updateAlertsDisabled ?? false), (e) =>
                            sendToHost({
                                action: "setUpdateAlerts",
                                value: e.target.checked,
                            }),
                        ),
                    ),
                );
            }

            // Render //
            function render() {
                const scroll = document.getElementById("scroll");
                const scrollTop = scroll.scrollTop;
                scroll.innerHTML = "";

                scroll.appendChild(
                    section("runtime", "Runtime", buildRuntime,
                        "Macro engine and what a reload touches"),
                );
                scroll.appendChild(
                    section("accessibility", "Accessibility", buildAccessibility,
                        "Input handling and performance"),
                );
                scroll.appendChild(
                    section("defaults", "Defaults", buildDefaults,
                        "Save or restore every setting at once"),
                );
                scroll.appendChild(
                    section("developer", "Developer", buildDeveloper,
                        "Editing, logs, updates, and integrity"),
                );
                scroll.appendChild(
                    section("help", "Help", buildHelp, "Version and documentation"),
                );

                scroll.scrollTop = scrollTop;
            }

            // `preset` (optional) puts the builder in edit mode: { editKey, item }
            // seeds the draft from an existing authored setting so Save updates it
            // in place instead of adding a new one.
            function buildSettingBuilder(body, preset) {
                const draft = {
                    type: "toggle",
                    key: "",
                    label: "",
                    hint: "",
                    default: false,
                    min: 0,
                    max: 100,
                    step: 1,
                    unit: "",
                    options: [
                        { label: "One", value: "one" },
                        { label: "Two", value: "two" },
                    ],
                    btnLabel: "Run",
                    danger: false,
                    target: "settings",
                };

                // Non-null while editing an existing setting; carries the ORIGINAL
                // key so the host can locate the def even if the key is renamed.
                let editKey = (preset && preset.editKey) || null;
                if (preset && preset.item) seedDraftFrom(draft, preset.item);

                // Map a serialized authored-setting item back onto the draft.
                function seedDraftFrom(dr, item) {
                    dr.type   = item.type || "toggle";
                    dr.key    = item.key || "";
                    dr.label  = item.label || "";
                    dr.hint   = item.hint || "";
                    dr.target = item.section || "settings";
                    if (item.type === "toggle") {
                        dr.default = (item.default === true) || (item.value === true);
                    } else if (item.type === "slider") {
                        dr.min  = item.min  != null ? item.min  : 0;
                        dr.max  = item.max  != null ? item.max  : 100;
                        dr.step = item.step != null ? item.step : 1;
                        dr.unit = item.unit || "";
                        dr.default = item.default != null ? item.default : dr.min;
                    } else if (item.type === "seg") {
                        dr.options = (item.options || []).map(
                            (o) => ({ label: o.label, value: o.value }));
                        if (!dr.options.length)
                            dr.options = [{ label: "", value: "" }];
                    } else if (item.type === "action") {
                        dr.btnLabel = item.btnLabel || "Run";
                        dr.danger   = item.danger === true;
                    }
                }

                const typeLabels = [
                    { label: "Toggle", value: "toggle" },
                    { label: "Slider", value: "slider" },
                    { label: "Segmented", value: "seg" },
                    { label: "Action", value: "action" },
                    { label: "Label", value: "groupLabel" },
                    { label: "Divider", value: "divider" },
                ];
                const keyed = (t) =>
                    t !== "divider" && t !== "groupLabel";
                const identityInputs = {};
                const textField = (labelText, sub, key, placeholder) => {
                    const input = h("input", {
                        type: "text",
                        cls: "input-sm",
                        placeholder: placeholder || "",
                        value: draft[key] || "",
                        oninput: (e) => {
                            draft[key] = e.target.value;
                            updatePreview();
                        },
                    });
                    identityInputs[key] = input;
                    return row(labelText, sub, input);
                };
                const syncIdentityInputs = () => {
                    for (const k in identityInputs)
                        identityInputs[k].value = draft[k] || "";
                };

                const numField = (labelText, key, step) =>
                    row(
                        labelText,
                        null,
                        h("input", {
                            type: "number",
                            cls: "input-sm",
                            step: String(step || 1),
                            value: String(draft[key]),
                            oninput: (e) => {
                                const v = parseFloat(e.target.value);
                                draft[key] = isNaN(v) ? 0 : v;
                                updatePreview();
                            },
                        }),
                        "row-sub row-compact",
                    );

                // Stable containers //
                body.appendChild(
                    row(
                        "Type",
                        "What kind of control to add",
                        seg(typeLabels, draft.type, (v) => {
                            draft.type = v;
                            renderDynamic();
                            updatePreview();
                        }),
                    ),
                );

                body.appendChild(divider());
                const dyn = h("div", { cls: "setting-builder-dyn" });
                body.appendChild(dyn);

                // Preview //
                body.appendChild(divider());
                body.appendChild(groupLabel("Preview"));
                const preview = h("div", { cls: "setting-builder-preview" });
                body.appendChild(preview);

                // Add / Update / Reset //
                // Return the builder to add-mode (identity cleared, edit target
                // dropped). Called after a save and by the Reset button.
                const clearIdentity = () => {
                    editKey = null;
                    primaryBtn.textContent = "Add Setting";
                    draft.key = "";
                    draft.label = "";
                    draft.hint = "";
                    syncIdentityInputs();
                    renderDynamic();
                    updatePreview();
                };
                const primaryBtn = actionBtn(
                    editKey ? "Update Setting" : "Add Setting", "accent", () => {
                        const def = buildDef();
                        const err = validate(def);
                        if (err) {
                            showAlert(err);
                            return;
                        }
                        if (editKey) {
                            sendToHost({
                                action: "updateUserSetting", key: editKey, def: def });
                        } else {
                            sendToHost({ action: "addUserSetting", def: def });
                        }
                        clearIdentity();
                    });
                body.appendChild(
                    btnRow(primaryBtn, actionBtn("Reset", "", clearIdentity)),
                );

                // Builders //
                function buildDef() {
                    const d = { type: draft.type, target: draft.target };
                    if (keyed(draft.type)) {
                        d.key = draft.key.trim();
                        d.hint = draft.hint.trim() || undefined;
                    }
                    if (draft.type === "groupLabel") {
                        d.label = draft.label.trim();
                    } else if (draft.type !== "divider") {
                        d.label = draft.label.trim();
                    }
                    if (draft.type === "toggle") {
                        d.default = draft.default;
                        d.value = draft.default;
                    } else if (draft.type === "slider") {
                        d.min = draft.min;
                        d.max = draft.max;
                        d.step = draft.step;
                        d.unit = draft.unit.trim() || undefined;
                        d.default = draft.default || draft.min;
                        d.value = d.default;
                    } else if (draft.type === "seg") {
                        d.options = draft.options.filter(
                            (o) => o.label.trim() !== "",
                        );
                        d.default =
                            d.options.length > 0 ? d.options[0].value : undefined;
                        d.value = d.default;
                    } else if (draft.type === "action") {
                        d.btnLabel = draft.btnLabel.trim() || "Run";
                        d.danger = draft.danger;
                    }
                    return d;
                }

                function validate(def) {
                    if (keyed(def.type) && !def.key)
                        return "A key is required for this setting type.";
                    if (def.type === "groupLabel" && !def.label)
                        return "A label is required.";
                    if (def.type === "seg" && (!def.options || !def.options.length))
                        return "Add at least one option.";
                    return null;
                }

                // Type-specific fields //
                function renderDynamic() {
                    dyn.innerHTML = "";
                    const t = draft.type;

                    if (keyed(t)) {
                        dyn.appendChild(
                            textField(
                                "Key",
                                "Unique id used to read the value",
                                "key",
                                "mySetting",
                            ),
                        );
                    }
                    if (t !== "divider") {
                        dyn.appendChild(
                            textField("Label", null, "label", "My Setting"),
                        );
                    }
                    if (keyed(t)) {
                        dyn.appendChild(
                            textField("Hint", "Optional one-line help", "hint", ""),
                        );
                    }

                    if (t === "toggle") {
                        dyn.appendChild(
                            row(
                                "Default",
                                "State when reset",
                                toggle(draft.default, (e) => {
                                    draft.default = e.target.checked;
                                    updatePreview();
                                }),
                                "row-sub",
                            ),
                        );
                    } else if (t === "slider") {
                        dyn.appendChild(numField("Min", "min", draft.step));
                        dyn.appendChild(numField("Max", "max", draft.step));
                        dyn.appendChild(numField("Step", "step", 0.1));
                        dyn.appendChild(numField("Default", "default", draft.step));
                        dyn.appendChild(
                            textField("Unit", "Optional suffix, e.g. px", "unit", ""),
                        );
                    } else if (t === "seg") {
                        dyn.appendChild(groupLabel("Options"));
                        renderOptions(dyn);
                    } else if (t === "action") {
                        dyn.appendChild(
                            textField(
                                "Button text",
                                null,
                                "btnLabel",
                                "Run",
                            ),
                        );
                        dyn.appendChild(
                            row(
                                "Destructive",
                                "Style the button as a danger action",
                                toggle(draft.danger, (e) => {
                                    draft.danger = e.target.checked;
                                    updatePreview();
                                }),
                                "row-sub",
                            ),
                        );
                    }

                    if (keyed(t) || t === "groupLabel" || t === "divider") {
                        dyn.appendChild(divider());
                        // Every known section is a valid destination: the default
                        // Settings group, user-created sections, and any section a
                        // pack already uses (calibration and the like).
                        const destOpts = [{ label: "Settings", value: "settings" }];
                        const seen = { settings: true };
                        for (const m of S.userSections || []) {
                            if (seen[m.id]) continue;
                            seen[m.id] = true;
                            destOpts.push({ label: m.title, value: m.id });
                        }
                        for (const it of S.userSettings || []) {
                            const s = it.section;
                            if (!s || seen[s]) continue;
                            seen[s] = true;
                            destOpts.push({
                                label: packSectionDisplay(s).title,
                                value: s,
                            });
                        }
                        dyn.appendChild(
                            row(
                                "Destination",
                                "Which Tools section it lands in",
                                seg(
                                    destOpts,
                                    draft.target,
                                    (v) => {
                                        draft.target = v;
                                    },
                                ),
                                "row-sub",
                            ),
                        );
                    }
                }

                function renderOptions(host) {
                    const list = h("div", { cls: "setting-builder-opts" });
                    draft.options.forEach((opt, i) => {
                        const rowEl = h("div", { cls: "sb-opt-row" });
                        rowEl.appendChild(
                            h("input", {
                                type: "text",
                                cls: "input-sm",
                                placeholder: "Label",
                                value: opt.label,
                                oninput: (e) => {
                                    opt.label = e.target.value;
                                    updatePreview();
                                },
                            }),
                        );
                        rowEl.appendChild(
                            h("input", {
                                type: "text",
                                cls: "input-sm",
                                placeholder: "value",
                                value: opt.value,
                                oninput: (e) => {
                                    opt.value = e.target.value;
                                    updatePreview();
                                },
                            }),
                        );
                        const rm = actionBtn("✕", "", () => {
                            draft.options.splice(i, 1);
                            host.innerHTML = "";
                            renderOptions(host);
                            updatePreview();
                        });
                        rm.classList.add("sb-opt-rm");
                        rowEl.appendChild(rm);
                        list.appendChild(rowEl);
                    });
                    host.appendChild(list);
                    host.appendChild(
                        btnRow(
                            actionBtn("Add Option", "", () => {
                                draft.options.push({ label: "", value: "" });
                                host.innerHTML = "";
                                renderOptions(host);
                                updatePreview();
                            }),
                        ),
                    );
                }

                function updatePreview() {
                    preview.innerHTML = "";
                    const def = buildDef();
                    try {
                        renderUserItem(preview, def);
                    } catch (e) {
                        preview.appendChild(
                            groupLabel("Preview unavailable."),
                        );
                    }
                }

                renderDynamic();
                updatePreview();
            }

            // Arrange list — every authored item, grouped by section, each row
            // draggable so dividers, labels and settings can be positioned. This
            // is what makes the visual builder competitive with hand-editing:
            // add drops an item at the end, then it is dragged into place here.
            // Reordering is constrained to a section (a row only reorders among
            // its own section's siblings); the whole authored order is sent to
            // the host on drop.
            const _dragSvg = '<svg class="icon" viewBox="0 0 24 24" fill="none" '
                + 'xmlns="http://www.w3.org/2000/svg"><path d="M9 6h.01M9 12h.01'
                + 'M9 18h.01M15 6h.01M15 12h.01M15 18h.01" stroke="currentColor" '
                + 'stroke-width="2.5" stroke-linecap="round" '
                + 'stroke-linejoin="round"/></svg>';

            function arrangeRowLabel(it) {
                if (it.type === "divider") return "— Divider —";
                if (it.type === "groupLabel")
                    return "“" + (it.label || "") + "” label";
                const name = it.label || it.key || "(setting)";
                return name + "  ·  " + it.type;
            }

            // Read the current DOM order of a section group and push it to the
            // host as the new authored order (all groups concatenated).
            function commitArrangeOrder(listEl) {
                const order = [];
                listEl.querySelectorAll(".arrange-row[data-uid]")
                    .forEach((r) => order.push(r.getAttribute("data-uid")));
                sendToHost({ action: "reorderUserSettings", order: order });
            }

            function buildArrange(body) {
                const authored = (S.userSettings || []).filter((it) => it.uid);
                if (!authored.length) {
                    body.appendChild(groupLabel(
                        "Nothing to arrange yet. Add a setting, divider or "
                        + "label above, then drag it into place here."));
                    return;
                }

                // One flat, ordered list; section changes print a heading so the
                // user sees the grouping, but rows carry data-section so a drag
                // never crosses a boundary.
                const list = h("div", { cls: "arrange-list" });
                let lastSection = "";
                for (const it of authored) {
                    const sec = it.section || "settings";
                    if (sec !== lastSection) {
                        lastSection = sec;
                        const title = sec === "settings"
                            ? "Settings"
                            : (packSectionDisplay(sec).title || sec);
                        list.appendChild(
                            h("div", { cls: "arrange-head" }, title));
                    }
                    list.appendChild(arrangeRow(it, sec, list));
                }
                body.appendChild(list);
                body.appendChild(h("div", { cls: "arrange-hint" },
                    "Drag the handle to reorder within a section. Use a "
                    + "setting's Destination to move it to another section."));
            }

            function arrangeRow(it, sec, listEl) {
                const rowEl = h("div", { cls: "arrange-row" });
                rowEl.setAttribute("data-uid", it.uid);
                rowEl.setAttribute("data-section", sec);
                if (it.type === "divider") rowEl.classList.add("is-divider");
                if (it.type === "groupLabel") rowEl.classList.add("is-label");

                const handle = h("div", { cls: "arrange-handle" });
                handle.innerHTML = _dragSvg;
                handle.title = "Drag to reorder";
                rowEl.appendChild(handle);

                rowEl.appendChild(
                    h("div", { cls: "arrange-label" }, arrangeRowLabel(it)));

                if (it.key) {
                    const edit = actionBtn("Edit", "", () => {
                        if (window._loadSettingIntoBuilder)
                            window._loadSettingIntoBuilder(it);
                    });
                    edit.classList.add("arrange-btn");
                    rowEl.appendChild(edit);
                }

                const del = actionBtn("✕", "", async () => {
                    const what = it.type === "divider" ? "divider"
                        : it.type === "groupLabel" ? "label"
                        : ("\"" + (it.label || it.key) + "\"");
                    const res = await openModal("Delete Item",
                        "Remove this " + what
                        + " from your pack? This cannot be undone.", "Delete");
                    if (!res.confirmed) return;
                    if (it.key)
                        sendToHost({ action: "removeUserSetting", key: it.key });
                    else
                        sendToHost({
                            action: "removeUserSettingByUid", uid: it.uid });
                });
                del.classList.add("arrange-btn", "arrange-del");
                rowEl.appendChild(del);

                wireArrangeDrag(handle, rowEl, listEl);
                return rowEl;
            }

            // Pointer-based reorder (HTML5 DnD drops are swallowed in this
            // WKWebView — see the macro builder note). Mirrors that pattern but
            // flat: a row only reorders among siblings sharing its data-section.
            function wireArrangeDrag(handle, rowEl, listEl) {
                handle.addEventListener("mousedown", (down) => {
                    if (down.button !== 0) return;
                    down.preventDefault();
                    const sec = rowEl.getAttribute("data-section");
                    const startY = down.clientY;
                    let started = false, ghost = null, offY = 0;
                    const scroller = listEl.closest(".tsec-scroll") || listEl;

                    const peers = () => Array.prototype.filter.call(
                        listEl.querySelectorAll(".arrange-row"),
                        (r) => r.getAttribute("data-section") === sec
                            && r !== rowEl);

                    const begin = () => {
                        started = true;
                        rowEl.classList.add("dragging");
                        ghost = rowEl.cloneNode(true);
                        ghost.classList.add("arrange-ghost");
                        ghost.style.width = rowEl.offsetWidth + "px";
                        const r = rowEl.getBoundingClientRect();
                        offY = startY - r.top;
                        document.body.appendChild(ghost);
                        moveGhost(down.clientX, startY);
                        if (window.playSlot) playSlot("interact");
                    };
                    const moveGhost = (x, y) => {
                        if (ghost) {
                            ghost.style.left = (x - 12) + "px";
                            ghost.style.top = (y - offY) + "px";
                        }
                    };
                    const clearMarks = () => {
                        listEl.querySelectorAll(
                            ".arrange-row.drop-above,.arrange-row.drop-below")
                            .forEach((r) => r.classList.remove(
                                "drop-above", "drop-below"));
                    };
                    // Place rowEl relative to the nearest peer under the pointer.
                    const place = (y) => {
                        clearMarks();
                        let best = null, bestPos = "below", bestDist = Infinity;
                        peers().forEach((r) => {
                            const rc = r.getBoundingClientRect();
                            const mid = rc.top + rc.height / 2;
                            const d = Math.abs(y - mid);
                            if (d < bestDist) {
                                bestDist = d; best = r;
                                bestPos = y < mid ? "above" : "below";
                            }
                        });
                        if (!best) return;
                        best.classList.add(
                            bestPos === "above" ? "drop-above" : "drop-below");
                        if (bestPos === "above")
                            best.parentNode.insertBefore(rowEl, best);
                        else
                            best.parentNode.insertBefore(rowEl, best.nextSibling);
                    };
                    const autoscroll = (y) => {
                        if (!scroller) return;
                        const r = scroller.getBoundingClientRect(), M = 28;
                        if (y < r.top + M) scroller.scrollTop -= 10;
                        else if (y > r.bottom - M) scroller.scrollTop += 10;
                    };
                    const onMove = (e) => {
                        if (!started) {
                            if (Math.abs(e.clientY - startY) < 4) return;
                            begin();
                        }
                        e.preventDefault();
                        moveGhost(e.clientX, e.clientY);
                        autoscroll(e.clientY);
                        place(e.clientY);
                    };
                    const cleanup = () => {
                        document.removeEventListener("mousemove", onMove, true);
                        document.removeEventListener("mouseup", onUp, true);
                        document.removeEventListener("keydown", onKey, true);
                        if (ghost) ghost.remove();
                        ghost = null;
                        rowEl.classList.remove("dragging");
                        clearMarks();
                    };
                    const onUp = (e) => {
                        if (started) {
                            e.preventDefault(); e.stopPropagation();
                            commitArrangeOrder(listEl);
                        }
                        cleanup();
                    };
                    const onKey = (e) => {
                        if (e.key === "Escape") cleanup();
                    };
                    document.addEventListener("mousemove", onMove, true);
                    document.addEventListener("mouseup", onUp, true);
                    document.addEventListener("keydown", onKey, true);
                });
            }

            // Load an existing authored setting into the Setting Builder (edit
            // mode) and reveal the builder tab. Called by each setting's "Edit
            // tool" context item; rebuilds the builder body from scratch so the
            // Type control and every field reflect the loaded def.
            window._loadSettingIntoBuilder = (item) => {
                if (!item || !item.key) return;
                const bscroll = document.getElementById("tools-builder-scroll");
                if (!bscroll) return;
                const bodyEl = bscroll.querySelector(
                    '[data-section="builder"] .section-body');
                if (!bodyEl) return;
                bodyEl.innerHTML = "";
                buildSettingBuilder(bodyEl, { editKey: item.key, item: item });
                switchToolsTab("builder");
            };

            function renderToolsPanel() {
                const scroll = document.getElementById("tools-scroll");
                if (!scroll) return;
                // Keep the origin-filter header button in step with the flag,
                // which outlives a panel rebuild.
                syncToolsFilterBtn();
                const active = window._toolsFilter !== "all";
                // Populate window.msMacroTools so the Function/Setting builders'
                // Value->Tool dropdowns have data. It is otherwise filled only when
                // the macro builder calls refreshToolList(), so opening Tools
                // without ever opening the macro builder left those dropdowns empty.
                if (window.shellPost) window.shellPost("macros", "listTools", {});
                const scrollTop = scroll.scrollTop;
                scroll.innerHTML = "";

                // Pack menus authored with ms.menu.define() (they carry their own
                // item lists) render first, unchanged.
                for (const menu of S.userMenus || []) {
                    if (active && !toolOriginMatches(menu.origin)) continue;
                    const title = menu.icon
                        ? menu.icon + " " + menu.title
                        : menu.title;
                    scroll.appendChild(
                        section("user_" + menu.id, title, (body) =>
                            buildUserSection(body, menu),
                        ),
                    );
                }

                // Default Settings group: settings that name no section.
                if (!active
                    || filterByOrigin(S.userSettings).some(isDefaultSection)) {
                    scroll.appendChild(
                        section("settings", "Settings", buildSettings,
                            "Defined by your macro pack"),
                    );
                }
                if (!active || filterByOrigin(S.userFunctions).length) {
                    scroll.appendChild(
                        section("functions", "Functions", buildFunctions,
                            "Function tools your macros can call"),
                    );
                }
                if (!active || filterByOrigin(S.userVariables).length) {
                    scroll.appendChild(
                        section("variables", "Variables", buildVariables,
                            "Shared helper variables"),
                    );
                }

                // Named sections, driven by the settings' `section` field. User
                // metadata (userSections) lists ones made in the UI; any other
                // referenced section id is a pack section. User-created first,
                // then pack sections in first-seen order.
                const userMeta = {};
                const order = [];
                for (const m of S.userSections || []) {
                    userMeta[m.id] = m;
                    order.push(m.id);
                }
                for (const it of S.userSettings || []) {
                    const s = it.section;
                    if (s && s !== "settings" && order.indexOf(s) === -1)
                        order.push(s);
                }

                for (const id of order) {
                    const meta = userMeta[id];
                    const items = filterByOrigin(S.userSettings || [])
                        .filter((it) => it.section === id);
                    if (meta) {
                        // User-created section: always shown (even empty) unless a
                        // non-user origin filter is active.
                        if (active && window._toolsFilter !== "user" && !items.length)
                            continue;
                        scroll.appendChild(
                            userSectionGroup(meta, items));
                    } else {
                        if (!items.length) continue;
                        const disp = packSectionDisplay(id);
                        scroll.appendChild(
                            section(id, disp.title, (body) => {
                                renderItemsCollapsed(body, items);
                            }, disp.desc));
                    }
                }

                // At the very bottom: create your own section. Only one custom
                // section is allowed, so this creator is hidden once any section
                // exists — whether made here or defined in the handwritten file
                // (a setting tagged section= in ms_macros.lua). `order` holds
                // every custom section id, so an empty `order` means none yet.
                if ((!active || window._toolsFilter === "user") && !order.length) {
                    scroll.appendChild(
                        section("new-section", "New Section", (body) => {
                            const inp = h("input", {
                                type: "text",
                                cls: "input-sm",
                                placeholder: "Section name",
                            });
                            inp.addEventListener("keydown", (e) => {
                                e.stopPropagation();
                                if (e.key === "Enter") add();
                            });
                            const add = () => {
                                const t = inp.value.trim();
                                sendToHost({
                                    action: "addUserMenu",
                                    title: t || "New Section",
                                });
                                inp.value = "";
                            };
                            body.appendChild(
                                row("Name", "Title for the new section", inp));
                            body.appendChild(btnRow(
                                actionBtn("Add Section", "accent", add)));
                        }, "Add your own section to this panel"),
                    );
                }

                scroll.scrollTop = scrollTop;

                const bscroll = document.getElementById("tools-builder-scroll");
                if (bscroll && !bscroll.firstChild) {
                    bscroll.appendChild(
                        section("builder", "Setting Builder", buildSettingBuilder,
                            "Compose a new setting and preview it live"),
                    );
                    // The Arrange list rebuilds on every refresh (see below), so
                    // its body is emptied and refilled — the section shell here is
                    // created once, alongside the builder.
                    bscroll.appendChild(
                        section("arrange", "Arrange", buildArrange,
                            "Drag to position dividers, labels and settings"),
                    );
                }
                // Keep the Arrange list in step with the current authored items
                // (a new add, delete or reorder changes them) without disturbing
                // the builder's in-progress draft above it.
                if (bscroll) {
                    const asec = bscroll.querySelector(
                        '[data-section="arrange"] .section-body');
                    if (asec) {
                        asec.innerHTML = "";
                        buildArrange(asec);
                    }
                }

                renderToolFunctionsTab();
                renderToolVariablesTab();
            }
            window.renderToolsPanel = renderToolsPanel;

            // Header origin filter: cycles All -> Visual -> Hand -> Plugin. Each
            // tool carries an `origin`: "user" = the visual builder (ms_authored
            // .json), "pack" = the handwritten ms_macros.lua, "plugin" = a loaded
            // plugin. The non-"all" states show only that origin. Read by the
            // Tuning-tab builders and the Function tab list. Origin keys stay
            // "user"/"pack" in the data model; only their labels changed.
            const TOOL_FILTER_ORDER = ["all", "user", "pack", "plugin"];
            const TOOL_FILTER_LABEL = {
                all: "All", user: "Visual", pack: "Hand", plugin: "Plugin",
            };
            window._toolsFilter = window._toolsFilter || "all";
            function toolOriginMatches(origin) {
                if (window._toolsFilter === "all") return true;
                return (origin || "pack") === window._toolsFilter;
            }
            function filterByOrigin(arr) {
                return (arr || []).filter((x) => toolOriginMatches(x && x.origin));
            }
            function syncToolsFilterBtn() {
                const btn = document.getElementById("toolsFilterToggle");
                if (!btn) return;
                btn.textContent = TOOL_FILTER_LABEL[window._toolsFilter] || "All";
                btn.classList.toggle("active", window._toolsFilter !== "all");
            }
            function setToolsFilter(key) {
                if (TOOL_FILTER_ORDER.indexOf(key) === -1) return;
                window._toolsFilter = key;
                syncToolsFilterBtn();
                renderToolsPanel();
            }
            function cycleToolsFilter() {
                const i = TOOL_FILTER_ORDER.indexOf(window._toolsFilter);
                setToolsFilter(
                    TOOL_FILTER_ORDER[(i + 1) % TOOL_FILTER_ORDER.length]);
            }
            window.cycleToolsFilter = cycleToolsFilter;

            // Right-clicking the header button opens a menu to jump straight to
            // any origin, instead of cycling through them one left-click at a time.
            function showToolsFilterMenu(x, y) {
                showCtxMenu(x, y, TOOL_FILTER_ORDER.map((key) => ({
                    icon: window._toolsFilter === key ? "✓" : "",
                    label: TOOL_FILTER_LABEL[key] || key,
                    action: () => setToolsFilter(key),
                })), "Filter by origin");
            }
            window.showToolsFilterMenu = showToolsFilterMenu;

            function sendToTools(action, data) {
                if (window.shellPost) {
                    window.shellPost("tools", action,
                        Object.assign({ action: action }, data || {}));
                }
            }

            function buildStepDef(fnId) {
                const reg = window.fnPicker && window.fnPicker.registry;
                if (!reg) return null;
                let fn = null;
                for (let i = 0; i < reg.length; i++) {
                    if (reg[i].id === fnId) { fn = reg[i]; break; }
                }
                if (!fn) return null;
                const params = {};
                (fn.params || []).forEach((p) => {
                    if (p.type === "mods") params[p.name] = [];
                    else if (p.type === "number") params[p.name] = 0;
                    else params[p.name] = "";
                });
                return { action: fn.name, params: params };
            }

            // Function tab (reuses the macro step canvas) //
            let _fnCanvas = null;
            let _fnEditor = null;
            let _fnHotkeysBound = false;

            // Copy/cut/paste/select-all/delete for the function canvas — the same
            // ToolCanvas clipboard the macro builder drives, gated on the function
            // canvas being on-screen (its otab section active and the panel open).
            function bindFunctionHotkeys() {
                if (_fnHotkeysBound) return;
                _fnHotkeysBound = true;
                document.addEventListener("keydown", function(e) {
                    if (!_fnCanvas) return;
                    const host = _fnCanvas._root;
                    if (!host || host.offsetParent === null) return;   // not visible
                    const t = e.target;
                    if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
                    const mod = e.metaKey || e.ctrlKey;
                    if (mod && (e.key === "a" || e.key === "A")) {
                        e.preventDefault(); _fnCanvas.selectAll(); return;
                    }
                    if (mod && (e.key === "v" || e.key === "V")) {
                        e.preventDefault(); _fnCanvas.pasteAfter(); return;
                    }
                    if (e.key === "Escape" && _fnCanvas.hasSelection()) {
                        e.preventDefault(); _fnCanvas.clearSelection(); return;
                    }
                    if (!_fnCanvas.hasSelection()) return;
                    if (mod && (e.key === "c" || e.key === "C")) {
                        e.preventDefault(); _fnCanvas.copySelected();
                    } else if (mod && (e.key === "x" || e.key === "X")) {
                        e.preventDefault(); _fnCanvas.cutSelected();
                    } else if (e.key === "Delete" || e.key === "Backspace") {
                        e.preventDefault(); _fnCanvas.removeSelected();
                    }
                });
            }
            let _fnEditingId = null;

            function renderToolFunctionsTab() {
                const scroll = document.getElementById("tools-functions-scroll");
                if (!scroll) return;
                if (!scroll.firstChild) {
                    scroll.appendChild(section("fn-editor", "Function", buildFunctionEditor,
                        "A reusable block of steps any macro can call"));
                    scroll.appendChild(section("fn-list", "Your functions", buildFunctionList,
                        "Authored function tools"));
                } else {
                    const listBody = document.getElementById("tool-fn-list-body");
                    if (listBody) fillFunctionList(listBody);
                }
            }
            window.renderToolFunctionsTab = renderToolFunctionsTab;

            function buildFunctionEditor(body) {
                const nameInput = h("input", {
                    type: "text", cls: "input-sm", placeholder: "My Function",
                });
                // Coroutine toggle sits beside the name: on = run async in its
                // own coroutine; off = run inline in the caller's.
                const coroToggle = toggle(false, () => {});
                const nameControls = h("div", {});
                nameControls.style.cssText =
                    "display:flex;align-items:center;gap:8px;flex:2;min-width:0;";
                nameInput.style.flex = "1";
                const coroLabel = h("span", {});
                coroLabel.style.cssText =
                    "display:flex;align-items:center;gap:6px;white-space:nowrap;"
                    + "font-size:12px;color:var(--text2);";
                coroLabel.appendChild(document.createTextNode("Coroutine"));
                coroLabel.appendChild(coroToggle);
                nameControls.appendChild(nameInput);
                nameControls.appendChild(coroLabel);
                const setCoro = (on) => {
                    const cb = coroToggle.querySelector("input");
                    if (cb) cb.checked = !!on;
                };
                const getCoro = () => {
                    const cb = coroToggle.querySelector("input");
                    return !!(cb && cb.checked);
                };
                body.appendChild(row("Name",
                    "Shown in the Call function block", nameControls));
                body.appendChild(divider());

                const canvasHost = h("div", { cls: "tool-fn-canvas" });
                canvasHost.style.cssText =
                    "min-height:120px;border:1px solid var(--border-dim);"
                    + "border-radius:var(--radius);padding:4px;margin:4px 0;";
                body.appendChild(canvasHost);

                if (typeof window.ToolCanvas === "function") {
                    _fnCanvas = new window.ToolCanvas(canvasHost, {
                        onChange: function() {},
                        onContext: function(sid) {
                            if (!_fnEditor || !sid) return;
                            if (_fnEditor._open && _fnEditor._toolSid === sid) _fnEditor.close();
                            else _fnEditor.open(sid);
                        },
                    });
                    if (typeof window.ToolEditor === "function") {
                        _fnEditor = new window.ToolEditor({ canvas: _fnCanvas });
                    }
                    bindFunctionHotkeys();
                } else {
                    canvasHost.textContent = "Step canvas unavailable.";
                }

                const mkSelect = window.createSelect || (typeof createSelect === "function" ? createSelect : null);
                if (mkSelect) {
                    const addSel = mkSelect({
                        className: "input-sm",
                        placeholder: "+ Add step…",
                        action: true,
                        searchable: true,
                        searchPlaceholder: "Search modules…",
                        options: buildStepOptions(),
                        value: undefined,
                        onChange: (v) => {
                            if (!v || !_fnCanvas) return;
                            const def = buildStepDef(v);
                            if (!def) return;
                            const sid = _fnCanvas.addTool(def);
                            // Open the parameter editor on the step we just added so
                            // its params can be set inline, rather than making the
                            // user right-click to find it.
                            if (sid && _fnEditor) _fnEditor.open(sid);
                        },
                    });
                    body.appendChild(row("Step", "Pick a module to add it, then set its parameters",
                        addSel, "row-sub"));
                }

                body.appendChild(btnRow(
                    actionBtn("Save Function", "accent", () => {
                        const nm = (nameInput.value || "").trim();
                        if (!nm) { showAlert("A name is required."); return; }
                        const id = _fnEditingId || slugToId(nm);
                        if (!id) { showAlert("Name must contain a letter."); return; }
                        const steps = _fnCanvas ? _fnCanvas.serialize() : [];
                        sendToTools("saveFunction", {
                            id: id,
                            def: { name: nm, steps: steps, coroutine: getCoro() },
                        });
                    }),
                    actionBtn("Clear", "", () => {
                        _fnEditingId = null;
                        nameInput.value = "";
                        setCoro(false);
                        if (_fnCanvas) _fnCanvas.load([]);
                    }),
                ));

                window._loadFunctionIntoEditor = (fnDef) => {
                    _fnEditingId = fnDef.id || null;
                    nameInput.value = fnDef.name || fnDef.id || "";
                    // Legacy defs (no flag) were wrapped as coroutines, so default
                    // on unless the stored flag is explicitly false.
                    setCoro(fnDef.coroutine !== false);
                    if (_fnCanvas) _fnCanvas.load(fnDef.steps || []);
                    switchToolsTab("functions");
                };
            }

            function buildStepOptions() {
                const reg = (window.fnPicker && window.fnPicker.registry) || [];
                const skip = { "if": 1, "for": 1, "while": 1, "repeat": 1 };
                // Carry the module's category through as a group header, and keep
                // categories contiguous (in first-seen registry order) so the
                // shared select can render one header per section.
                const order = [];
                const byCat = {};
                reg.filter((f) => !skip[f.id]).forEach((f) => {
                    const cat = f.category || "other";
                    if (!byCat[cat]) { byCat[cat] = []; order.push(cat); }
                    byCat[cat].push({ value: f.id, label: f.name, group: cat });
                });
                const out = [];
                order.forEach((cat) => { byCat[cat].forEach((o) => out.push(o)); });
                return out;
            }

            function buildFunctionList(body) {
                const listBody = h("div", { id: "tool-fn-list-body" });
                body.appendChild(listBody);
                fillFunctionList(listBody);
            }

            function fillFunctionList(host) {
                host.innerHTML = "";
                let fns = window.msMacroFunctions || [];
                // Apply the header origin filter. A function tool's `source`
                // ("pack"/"plugin", else builder) maps onto the same origins the
                // rest of the panel uses.
                if (window._toolsFilter && window._toolsFilter !== "all") {
                    fns = fns.filter((fn) => {
                        const origin = fn.source === "pack" ? "pack"
                            : fn.source === "plugin" ? "plugin" : "user";
                        return origin === window._toolsFilter;
                    });
                }
                if (fns.length === 0) {
                    host.appendChild(h("div", {
                        cls: "row-sub",
                        style: "padding:8px 14px;color:var(--text3);font-style:italic;",
                    }, (window._toolsFilter && window._toolsFilter !== "all")
                        ? "No " + (TOOL_FILTER_LABEL[window._toolsFilter]
                            || window._toolsFilter) + " function tools."
                        : "No function tools yet."));
                    return;
                }
                fns.forEach((fn) => {
                    // Pack macros and plugin-defined tools are both reference-only
                    // callables: no builder Edit/Delete (the compiler doesn't own
                    // them), just a "Call in macro" action.
                    const isPack = fn.source === "pack";
                    const isPlugin = fn.source === "plugin";
                    const callOnly = isPack || isPlugin;
                    const r = h("div", { cls: "row row-sub" });
                    const lbl = h("div", { cls: "row-label" }, fn.name || fn.id);
                    if (isPack) lbl.appendChild(h("small", {}, "from pack · call by id “" + fn.id + "”"));
                    else if (isPlugin) lbl.appendChild(h("small", {}, "from plugin · call by id “" + fn.id + "”"));
                    r.appendChild(lbl);
                    const controls = h("div", { style: "display:flex;gap:6px" });
                    if (callOnly) {
                        controls.appendChild(actionBtn("Call in macro", "", () => {
                            if (window.macroLab && window.macroLab.addTool) {
                                window.macroLab.addTool({
                                    action: "call_fn",
                                    params: { name: fn.id },
                                });
                            } else {
                                showAlert("Open a macro in the Macros panel first.");
                            }
                        }));
                    } else {
                        controls.appendChild(actionBtn("Edit", "", () => {
                            sendToTools("getFunction", { id: fn.id });
                        }));
                        controls.appendChild(actionBtn("Delete", "danger", () => {
                            sendToTools("deleteFunction", { id: fn.id });
                        }));
                    }
                    r.appendChild(controls);
                    host.appendChild(r);
                });
            }

            // Variable tab (declare disk-persistent helper vars) //
            // Reference to the builder's Default input so each variable's Insert
            // button can append a {name} token straight into it (same window, no
            // cross-webview focus tracking needed).
            let _varDefaultInput = null;
            function renderToolVariablesTab() {
                const scroll = document.getElementById("tools-variables-scroll");
                if (!scroll) return;
                if (!scroll.firstChild) {
                    scroll.appendChild(section("var-builder", "Helper Variable",
                        buildVariableBuilder,
                        "A shared value macros can read and write, saved to disk"));
                    scroll.appendChild(section("var-list", "Your variables",
                        buildVariableList,
                        "Insert appends a {name} token into the Default field above — "
                        + "it resolves to the variable's value when the macro runs"));
                } else {
                    const listBody = document.getElementById("tool-var-list-body");
                    if (listBody) fillVariableList(listBody);
                }
            }
            window.renderToolVariablesTab = renderToolVariablesTab;

            // `preset` (optional) puts the builder in edit mode, seeding the draft
            // from an existing helper var so Save updates it (re-declaring by the
            // same name overwrites in place; a rename drops the old declaration).
            function buildVariableBuilder(body, preset) {
                const draft = preset
                    ? { name: preset.name || "",
                        type: preset.type || "number",
                        default: (preset.default != null ? String(preset.default) : ""),
                        hint: preset.hint || "" }
                    : { name: "", type: "number", default: "", hint: "" };
                let editName = (preset && preset.name) || null;
                const nameInput = h("input", {
                    type: "text", cls: "input-sm", placeholder: "myCounter",
                    value: draft.name,
                    oninput: (e) => { draft.name = e.target.value; },
                });
                body.appendChild(row("Name", "Identifier macros use to read it",
                    nameInput));
                // Placeholder tracks the chosen type so the Default hint matches
                // what's expected (0 / text / true) instead of always showing 0.
                const DEF_PLACEHOLDER = { number: "0", string: "text", boolean: "true" };
                body.appendChild(row("Type", "How the value is stored",
                    seg([
                        { label: "Number", value: "number" },
                        { label: "Text", value: "string" },
                        { label: "True/False", value: "boolean" },
                    ], draft.type, (v) => {
                        draft.type = v;
                        defInput.placeholder = DEF_PLACEHOLDER[v] || "";
                    })));
                const defInput = h("input", {
                    type: "text", cls: "input-sm", placeholder: DEF_PLACEHOLDER[draft.type],
                    value: draft.default,
                    oninput: (e) => { draft.default = e.target.value; },
                });
                _varDefaultInput = defInput;
                body.appendChild(row("Default", "Starting value", defInput, "row-sub"));
                const hintInput = h("input", {
                    type: "text", cls: "input-sm", placeholder: "",
                    value: draft.hint,
                    oninput: (e) => { draft.hint = e.target.value; },
                });
                body.appendChild(row("Hint", "Optional one-line help", hintInput, "row-sub"));

                const saveVarBtn = actionBtn(
                    editName ? "Update Variable" : "Save Variable", "accent", () => {
                        const nm = (draft.name || "").trim();
                        if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(nm)) {
                            showAlert("Name must be a valid identifier.");
                            return;
                        }
                        let dv = draft.default;
                        if (draft.type === "number") dv = parseFloat(dv) || 0;
                        else if (draft.type === "boolean") dv = (dv === "true" || dv === "1" || dv === "yes");
                        // A rename leaves the old declaration behind, so drop it.
                        if (editName && editName !== nm) {
                            sendToTools("deleteHelperVar", { name: editName });
                        }
                        sendToTools("saveHelperVar", {
                            def: { name: nm, type: draft.type, default: dv,
                                   hint: (draft.hint || "").trim() },
                        });
                        editName = null;
                        saveVarBtn.textContent = "Save Variable";
                        draft.name = ""; draft.default = ""; draft.hint = "";
                        nameInput.value = ""; defInput.value = ""; hintInput.value = "";
                    });
                body.appendChild(btnRow(saveVarBtn));
            }

            // Load an existing helper var into the Variable builder (edit mode)
            // and reveal the Variable tab. Rebuilds the builder body so the Type
            // control and every field reflect the loaded declaration.
            window._loadVariableIntoBuilder = (v) => {
                if (!v || !v.name) return;
                const vscroll = document.getElementById("tools-variables-scroll");
                if (!vscroll) return;
                const bodyEl = vscroll.querySelector(
                    '[data-section="var-builder"] .section-body');
                if (!bodyEl) return;
                bodyEl.innerHTML = "";
                buildVariableBuilder(bodyEl, {
                    name: v.name, type: v.type || "number",
                    default: (v.default != null ? v.default : v.value),
                    hint: v.hint || "",
                });
                switchToolsTab("variables");
            };

            function buildVariableList(body) {
                const listBody = h("div", { id: "tool-var-list-body" });
                body.appendChild(listBody);
                fillVariableList(listBody);
            }

            function fillVariableList(host) {
                host.innerHTML = "";
                // Read the authoritative helper-var list from S.userVariables --
                // the same source the Tuning tab uses, delivered to this popout
                // via receiveState(). window.msMacroTools is only populated by the
                // macro builder in the MAIN shell webview, so in this (Tools popout)
                // window it is never filled -- reading it here left this list
                // permanently empty even when variables existed.
                const vars = (S && Array.isArray(S.userVariables)) ? S.userVariables : [];
                if (vars.length === 0) {
                    host.appendChild(h("div", {
                        cls: "row-sub",
                        style: "padding:8px 14px;color:var(--text3);font-style:italic;",
                    }, "No helper variables yet."));
                    return;
                }
                vars.forEach((v) => {
                    const r = h("div", { cls: "row row-sub" });
                    const val = (v.value !== undefined && v.value !== null)
                        ? String(v.value) : "";
                    r.appendChild(h("div", { cls: "row-label" },
                        (v.label || v.name) + "  =  " + val));
                    // Insert the {name} interpolation token into the last-focused
                    // Value field; if none is focused, copy it so it can be pasted.
                    const token = "{" + v.name + "}";
                    const ins = actionBtn("Insert", "", () => {
                        const el = _varDefaultInput;
                        if (!el || !el.isConnected) {
                            showAlert("Open the Default field above first.");
                            return;
                        }
                        // Insert at the caret when the Default field is focused,
                        // otherwise append to the end.
                        let start = el.selectionStart, end = el.selectionEnd;
                        if (typeof start !== "number" || document.activeElement !== el) {
                            start = el.value.length; end = start;
                        }
                        el.value = el.value.slice(0, start) + token + el.value.slice(end);
                        const caret = start + token.length;
                        // Fire input so the draft.default binding stays in sync.
                        el.dispatchEvent(new Event("input", { bubbles: true }));
                        el.focus();
                        try { el.setSelectionRange(caret, caret); } catch (e) {}
                    });
                    ins.title = "Append " + token + " to the Default field";
                    r.appendChild(ins);
                    const edit = actionBtn("Edit", "", () => {
                        if (window._loadVariableIntoBuilder)
                            window._loadVariableIntoBuilder(v);
                    });
                    r.appendChild(edit);
                    const del = actionBtn("Delete", "danger", () => {
                        sendToTools("deleteHelperVar", { name: v.name });
                    });
                    r.appendChild(del);
                    host.appendChild(r);
                });
            }

            function slugToId(name) {
                let s = String(name).replace(/[^A-Za-z0-9_]/g, "");
                if (!s) return "";
                if (/^[0-9]/.test(s)) s = "fn" + s;
                return s;
            }

            if (window.registerPanel) {
                window.registerPanel("tools", function(action, body) {
                    if (action === "functionSaved") {
                        if (body && body.error) { showAlert(body.error); return; }
                        _fnEditingId = null;
                        renderToolFunctionsTab();
                    } else if (action === "helperVarSaved") {
                        if (body && body.error) { showAlert(body.error); return; }
                        renderToolVariablesTab();
                    } else if (action === "functionDef" && body && body.id) {
                        if (window._loadFunctionIntoEditor)
                            window._loadFunctionIntoEditor(body);
                    }
                });
            }

            // Tools tab strip //
            let _otabs = null;
            function toolsTabs() {
                if (_otabs) return _otabs;
                const panel = document.querySelector(".panel-tools");
                if (!panel || !window.createTabs) return null;
                _otabs = window.createTabs({
                    root: panel,
                    tabSelector: ".otab",
                    sectionSelector: ".otab-section",
                    tabKey: (el) => el.dataset.otab,
                    sectionKey: (el) => el.dataset.osection,
                    onSame: () => playSlot("back"),
                    onSwitch: () => playSlot("interact"),
                });
                return _otabs;
            }

            function switchToolsTab(tab) {
                const t = toolsTabs();
                if (t) t.switch(tab);
            }
            window.switchToolsTab = switchToolsTab;

            // Profiles panel (rendered into #profiles-scroll) //
            function renderProfilesPanel() {
                const el = document.getElementById("profiles-scroll");
                if (!el) return;
                el.innerHTML = "";
                buildProfiles(el);
                const note = h("div", {
                    style: "padding:16px 14px 8px;font-size:11px;color:var(--text3);opacity:0.6;font-style:italic;",
                }, "More profile features coming soon.");
                el.appendChild(note);
            }
            window.renderProfilesPanel = renderProfilesPanel;

            // Theme application //
            window.settingsApplyTheme = settingsApplyTheme;

            function applyFont(font, fontURL) {
                if (!font) return;
                if (fontURL) {
                    let el = document.getElementById("_ms-custom-font");
                    if (!el) {
                        el = document.createElement("style");
                        el.id = "_ms-custom-font";
                        document.head.appendChild(el);
                    }
                    el.textContent = `@font-face { font-family: "${font}"; src: url("${fontURL}"); }`;
                }
                document.body.style.fontFamily = `"${font}", Almendra, Palatino, Georgia, serif`;
            }

            function hexToRgb(hex) {
                hex = hex.replace(/^#/, "");
                if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
                const n = parseInt(hex, 16);
                return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
            }

            function settingsApplyTheme(t) {
                if (!t) return;
                const r = document.documentElement.style;
                // Base colors //
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

                // Derived: text2/text3 from text //
                if (t.text && !t.text2) {
                    const c = hexToRgb(t.text);
                    if (c) r.setProperty("--text2", `rgba(${c.r},${c.g},${c.b},0.85)`);
                }
                if (t.text && !t.text3) {
                    const c = hexToRgb(t.text);
                    if (c) r.setProperty("--text3", `rgba(${c.r},${c.g},${c.b},0.55)`);
                }

                // Derived: border from accent + hover mix //
                if (t.accent && t.hover && !t.border) {
                    const a = hexToRgb(t.accent);
                    const h = hexToRgb(t.hover);
                    if (a && h) {
                        const mr = Math.round(a.r * 0.5 + h.r * 0.5);
                        const mg = Math.round(a.g * 0.5 + h.g * 0.5);
                        const mb = Math.round(a.b * 0.5 + h.b * 0.5);
                        r.setProperty("--border", `rgba(${mr},${mg},${mb},0.55)`);
                    }
                }

                // Derived: accent glow //
                if (t.accent && !t.accentGlow) {
                    const a = hexToRgb(t.accent);
                    if (a) r.setProperty("--accent-glow", `rgba(${a.r},${a.g},${a.b},0.4)`);
                }
                if (t.accent && !t.accentGlowFaint) {
                    const a = hexToRgb(t.accent);
                    if (a) r.setProperty("--accent-glow-faint", `rgba(${a.r},${a.g},${a.b},0.12)`);
                }

                // Derived: danger glow/border //
                if (t.danger && !t.dangerGlow) {
                    const d = hexToRgb(t.danger);
                    if (d) r.setProperty("--danger-glow", `rgba(${d.r},${d.g},${d.b},0.6)`);
                }
                if (t.danger && !t.dangerBorder) {
                    const d = hexToRgb(t.danger);
                    if (d) r.setProperty("--danger-border", `rgba(${d.r},${d.g},${d.b},0.3)`);
                }

                // Explicit overrides always win //
                if (t.text2) r.setProperty("--text2", t.text2);
                if (t.text3) r.setProperty("--text3", t.text3);
                if (t.border) r.setProperty("--border", t.border);
                if (t.accentGlow) r.setProperty("--accent-glow", t.accentGlow);
                if (t.accentGlowFaint) r.setProperty("--accent-glow-faint", t.accentGlowFaint);
                if (t.dangerGlow) r.setProperty("--danger-glow", t.dangerGlow);
                if (t.dangerBorder) r.setProperty("--danger-border", t.dangerBorder);

                // Radius, font //
                if (t.radius !== undefined) {
                    r.setProperty("--radius", t.radius + "px");
                    r.setProperty(
                        "--radius-s",
                        Math.max(0, t.radius - 1) + "px",
                    );
                }
                applyFont(t.font, t.fontURL);
            }

            // receiveState //
            function receiveState(state) {
                S = state;
                applyTheme(S.theme);
                if (typeof applyZoom === "function" && S.uiZoom !== undefined) {
                    applyZoom(S.uiZoom);
                }
                const verEl = document.getElementById("rail-version");
                if (verEl && S.msVersion) verEl.textContent = "v" + S.msVersion;
                render();
                renderToolsPanel();
                renderProfilesPanel();
                // Keep the Macro Lab header's engine toggle in step with the real
                // bind validity, however it was changed (hotkey, Settings switch,
                // target focus/blur).
                if (window.updateMacrosToggleBtn) {
                    window.updateMacrosToggleBtn(S.macrosEnabled ?? false);
                }
                if (window.renderThemePanel) window.renderThemePanel(state);
                if (window.renderPluginsPanel) window.renderPluginsPanel(state);
            }

            // Init //
            document.addEventListener("DOMContentLoaded", () => {
                if (window.shellPost) {
                    var p = document.getElementById("panel");
                    if (p) {
                        p.style.borderRadius = "0";
                        p.style.clipPath = "none";
                    }
                }
                (function() {
                })();
                sendToHost({ action: "ready" });
            });

            window.sendToHost = sendToHost;
            window.playSlot = playSlot;
            window.closePanel = function() { sendToHost({ action: 'close' }); };
    })();
