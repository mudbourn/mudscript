(function() {
    "use strict";
        // State //
            let S = {};
            let _modalResolve = null;
            let _toastTimer = null;
            let _ctxTarget = null;
        // END State //

        // Context Menu //
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
                        ico.innerHTML = window.icon ? window.icon(item.icon) : "";
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
        // END Context Menu //

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
        // END Bridge //

        // Window Drag //
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
        // END Window Drag //

        // Sound //
            const _lastSlot = {};
            let _lastNonHoverAt = 0;
            function playSlot(slot) {
                if (_dragging) return;
                if (slot === "hover" && !document.hasFocus()) return;
                const now = Date.now();
                if (slot === "hover" && now - _lastNonHoverAt < 250) return;
                if (slot !== "hover") _lastNonHoverAt = now;
                if (now - (_lastSlot[slot] || 0) < 50) return;
                _lastSlot[slot] = now;
                sendToHost({ action: "playSlot", slot });
            }
        // END Sound //

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
        // END Toast //

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
        // END Modal //

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
        // END Shutdown //

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
        // END Helpers //

            window.msSettings = {
                S,
                showCtxMenu,
                sendToHost,
                playSlot,
                showAlert,
                openModal,
                h,
                toggle,
                seg,
                section,
                row,
                btnRow,
                actionBtn,
                divider,
                groupLabel,
            };
    })();
