(function() {
    "use strict";
            const P = window.msSettings;
            const { S, showCtxMenu, sendToHost, playSlot, showAlert, openModal, h, toggle, seg, section, row, btnRow, actionBtn, divider, groupLabel } = P;

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
                const decimals = (String(step || 1).split(".")[1] || "").length;
                slider.addEventListener("input", () => {
                    numInput.value = parseFloat(slider.value).toFixed(decimals);
                });
                slider.addEventListener("change", () =>
                    onChange(parseFloat(slider.value)),
                );
                numInput.addEventListener("change", () => {
                    const raw = parseFloat(numInput.value);
                    const v = Math.max(min, Math.min(max, isNaN(raw) ? min : raw));
                    numInput.value = v;
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
        // END Sections //

        // Accessibility //
            function buildAccessibility(body) {
                const hidden = S.hiddenFeatures || {};
                const hasTrackpad = !hidden.trackpad;
                const hasSocd = !hidden.socd;
                const hasGamepad = !hidden.gamepad;

                (function () {
                    const z = S.uiZoom || 1.0;
                    const pct = Math.round(z * 100) + "%";
                    const zoomCtl = h("div", {});
                    zoomCtl.style.cssText =
                        "display:flex;align-items:center;gap:8px;";
                    const send = (data) =>
                        sendToHost(Object.assign({ action: "setUiZoom" }, data));
                    const minus = actionBtn("-", "", () =>
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
                            "Scale the whole interface, shell and popouts. "
                                + "Rebindable hotkeys live under Accessibility Hotkeys below",
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

                body.appendChild(
                    row(
                        "Windows Mode",
                        S.windowsHost
                            ? "Always on when running on Windows"
                            : "Use Windows key conventions: Ctrl for copy and paste, "
                                + "and Alt shown in shortcut hints instead of the Mac option symbol",
                        toggle(S.windowsMode ?? false, (e) =>
                            sendToHost({
                                action: "setWindowsMode",
                                value: e.target.checked,
                            }),
                        ),
                        S.windowsHost ? "disabled" : "",
                    ),
                );
                body.appendChild(divider());

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
                                "No controller detected. Pair one over "
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

                        body.appendChild(divider());

                        const mapBtn = actionBtn("Open controller map", "", () => {
                            const gtype =
                                (ctrls[0] && ctrls[0].type) ||
                                window.__gpType ||
                                "xbox";
                            if (window.openGamepadMap) {
                                window.openGamepadMap(gtype);
                                playSlot("interact");
                            }
                        });
                        body.appendChild(
                            row(
                                "Shell navigation",
                                "While the shell is open, steer it like a console UI.",
                                mapBtn,
                                "row-sub",
                            ),
                        );
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

                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Accessibility Hotkeys",
                        "Rebind Octane, zoom, and other system shortcuts in Macros > Binds",
                        actionBtn("Open Binds", "", () => {
                            if (window.showPanel) window.showPanel("macros");
                            setTimeout(() => {
                                if (window.macroLab && window.macroLab.focusSystemBinds) {
                                    window.macroLab.focusSystemBinds();
                                }
                            }, 60);
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

            function isDefaultSection(item) {
                const s = item && item.section;
                return !s || s === "settings";
            }
        // END Accessibility //

        // Settings Group //
            function emptyState(body, title, hint) {
                body.appendChild(groupLabel(title));
                const r = h("div", { cls: "row" });
                const lbl = h("div", { cls: "row-label" });
                lbl.appendChild(h("small", {}, hint));
                r.appendChild(lbl);
                body.appendChild(r);
            }

            function buildSettings(body) {
                const items = P.filterByOrigin(S.userSettings || [])
                    .filter(isDefaultSection);
                if (items.length > 0) {
                    for (const item of items) {
                        renderUserItem(body, item);
                    }
                } else {
                    emptyState(body, "No settings defined.",
                        "Use ms.settings.define() in ms_macros.lua, or add one in the Setting tab.");
                }
            }

            function buildFunctions(body) {
                const items = P.filterByOrigin(S.userFunctions || []);
                if (!items.length) {
                    emptyState(body, "No functions defined.",
                        "Make one in the Function tab. Any macro can call it, and you can run it from here.");
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
                const items = P.filterByOrigin(S.userVariables || []);
                if (!items.length) {
                    emptyState(body, "No variables defined.",
                        "Add one in the Variable tab, or with ms.vars.define() in ms_macros.lua. Every macro shares its value, and you can change it from here.");
                    return;
                }
                for (const v of items) {
                    body.appendChild(row(v.label || v.name, v.hint || null, varControl(v)));
                }
            }
        // END Settings Group //

        // Pack Menus //
            function buildUserSection(body, menu) {
                for (const item of menu.items || []) {
                    renderUserItem(body, item);
                }
            }

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
                if (lastWasDivider && body.childElementCount > start) {
                    const last = body.lastElementChild;
                    if (last && last.classList.contains("divider")) last.remove();
                }
                return rendered;
            }

            function packSectionDisplay(id) {
                if (id === "calibration")
                    return { title: "Calibration", desc: "Tune the pack to your setup" };
                const title = id.replace(/^user_/, "").replace(/[_-]+/g, " ")
                    .replace(/\b\w/g, (c) => c.toUpperCase());
                return { title: title || id, desc: null };
            }

            function userSectionGroup(meta, items) {
                const title = (meta.icon && window.ICONS && window.ICONS[meta.icon])
                    ? h("span", {}, window.iconNode(meta.icon, "icon-inline"), " " + (meta.title || ""))
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
        // END Pack Menus //

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
                    section("developer", "Developer", (b) => P.buildDeveloper(b),
                        "Editing, logs, updates, and integrity"),
                );
                scroll.appendChild(
                    section("help", "Help", (b) => P.buildHelp(b), "Version and documentation"),
                );

                scroll.scrollTop = scrollTop;
            }
        // END Render //

        // Profiles Panel //
            function renderProfilesPanel() {
                const el = document.getElementById("profiles-scroll");
                if (!el) return;
                el.innerHTML = "";
                P.buildProfiles(el);
                const note = h("div", {
                    style: "padding:16px 14px 8px;font-size:11px;color:var(--text3);opacity:0.6;font-style:italic;",
                }, "More profile features coming soon.");
                el.appendChild(note);
            }
            window.renderProfilesPanel = renderProfilesPanel;
        // END Profiles Panel //

        // Theme //
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
                document.documentElement.style.setProperty("--font", `"${font}", Arial, Helvetica, sans-serif`);
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
                if (t.accentGlow) r.setProperty("--accent-glow", t.accentGlow);
                if (t.accentGlowFaint) r.setProperty("--accent-glow-faint", t.accentGlowFaint);
                if (t.dangerGlow) r.setProperty("--danger-glow", t.dangerGlow);
                if (t.dangerBorder) r.setProperty("--danger-border", t.dangerBorder);

                if (t.radius !== undefined) {
                    r.setProperty("--radius", t.radius + "px");
                    r.setProperty(
                        "--radius-s",
                        Math.max(0, t.radius - 1) + "px",
                    );
                    var wr = (t.windowRadius !== undefined) ? t.windowRadius : t.radius;
                    r.setProperty("--ms-window-radius", wr + "px");
                }
                applyFont(t.font, t.fontURL);
            }

            const receiveState = (window.msEditGuard || ((_, f) => f))("#scroll, #tools-scroll", applyState);

            function applyState(state) {
                for (const k of Object.keys(S)) delete S[k];
                Object.assign(S, state);
                applyTheme(S.theme);
                if (typeof applyZoom === "function" && S.uiZoom !== undefined) {
                    applyZoom(S.uiZoom);
                }
                const verEl = document.getElementById("rail-version");
                if (verEl && S.msVersion) verEl.textContent = "v" + S.msVersion;
                render();
                P.renderToolsPanel();
                renderProfilesPanel();
                if (window.updateMacrosToggleBtn) {
                    window.updateMacrosToggleBtn(S.macrosEnabled ?? false);
                }
                if (window.renderThemePanel) window.renderThemePanel(state);
                if (window.renderPluginsPanel) window.renderPluginsPanel(state);
            }
        // END Theme //

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
        // END Init //

        // Shell Integration //
            if (window.registerPanel) {
                window.registerPanel("settings", function(action, body) {
                    if (action === "state" && body) {
                        receiveState(body);
                    } else if (action === "theme" && body) {
                        applyTheme(body);
                    }
                });
            }

            window.sendToHost = sendToHost;
            window.playSlot = playSlot;
            window.closePanel = function() { sendToHost({ action: 'close' }); };
        // END Shell Integration //

            Object.assign(window.msSettings, {
                buildSlider,
                renderUserItem,
                isDefaultSection,
                buildSettings,
                buildFunctions,
                buildVariables,
                buildUserSection,
                renderItemsCollapsed,
                packSectionDisplay,
                userSectionGroup,
            });
    })();
