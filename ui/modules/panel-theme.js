(function() {
    "use strict";



    // State //
    let S = {};
    let _pending = {};
    let _openSoundPicker = null;
    let _tabs = null;

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }
    function sendToHost(msg) { if (window.sendToHost) window.sendToHost(msg); }

    const COLOR_KEYS = [
        { key: "bg",       label: "Background",    hint: "Panel backdrop" },
        { key: "surface",  label: "Surface",       hint: "Headers, rails, cards" },
        { key: "surface2", label: "Surface (alt)", hint: "Raised and inset areas" },
        { key: "hover",    label: "Hover",         hint: "Row and button hover" },
        { key: "accent",   label: "Accent",        hint: "Active tabs, focus, links" },
        { key: "accentHi", label: "Accent (hi)",   hint: "Accent hover state" },
        { key: "text",     label: "Text",          hint: "Dimmer text is derived from this" },
        { key: "success",  label: "Success",       hint: "Macros on, healthy status" },
        { key: "warning",  label: "Warning",       hint: "Cautions" },
        { key: "danger",   label: "Danger",        hint: "Errors, destructive actions" },
        { key: "dangerBg", label: "Danger (bg)",   hint: "Backdrop behind danger text" },
    ];

    // Advanced overrides. These are normally *derived* from the colours above
    // (see applyTheme in log-panel.js). Leaving a field blank keeps the derived
    // value; setting one overrides it — the same keys the theme file exposes.
    const ADVANCED_KEYS = [
        { key: "text2",          label: "Text (secondary)", hint: "Labels, sublabels" },
        { key: "text3",          label: "Text (muted)",     hint: "Hints, placeholders" },
        { key: "border",         label: "Border",           hint: "Panel and control edges" },
        { key: "borderDim",      label: "Border (dim)",     hint: "Faint separators" },
        { key: "accentGlow",     label: "Accent glow",      hint: "Focus/active glow" },
        { key: "accentGlowFaint",label: "Accent glow (faint)", hint: "Subtle accent wash" },
        { key: "dangerGlow",     label: "Danger glow",      hint: "Destructive emphasis" },
        { key: "dangerBorder",   label: "Danger border",    hint: "Destructive edges" },
        { key: "key",            label: "Key indicator",    hint: "Keyboard key colour" },
        { key: "mouse",          label: "Mouse indicator",  hint: "Mouse button colour" },
        { key: "scroll",         label: "Scrollbar",        hint: "Scrollbar thumb" },
    ];

    // Live preview //
    function previewTheme() {
        const t = Object.assign({}, S.theme || {}, _pending);
        if (window._shellApplyTheme) window._shellApplyTheme(t);
        else if (window.settingsApplyTheme) window.settingsApplyTheme(t);
    }

    // Committing //
    const SETTLE_MS = 350;
    let _commitTimers = {};
    let _editingUntil = 0;
    let _rerenderTimer = null;

    function touchEditing() { _editingUntil = Date.now() + SETTLE_MS * 2; }

    function commit(key, value) {
        _pending[key] = value;
        previewTheme();
        touchEditing();
        clearTimeout(_commitTimers[key]);
        _commitTimers[key] = setTimeout(() => {
            delete _commitTimers[key];
            sendToHost({ action: "setThemeKey", key: key, value: value });
        }, SETTLE_MS);
    }

    function editing() {
        return Date.now() < _editingUntil || Object.keys(_commitTimers).length > 0;
    }

    function isHex(s) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s); }

    function longHex(s) {
        if (!isHex(s)) return null;
        const b = s.slice(1);
        return b.length === 3 ? "#" + b[0]+b[0]+b[1]+b[1]+b[2]+b[2] : "#" + b.toLowerCase();
    }

    // Colour field //
    function colorField(key, current) {
        const { h } = ui();
        const wrap = h("div", { cls: "color-field" });

        const swatch = h("input", { type: "color", cls: "color-swatch" });
        const hex    = h("input", { type: "text", cls: "color-hex", spellcheck: "false", maxlength: "7", placeholder: "auto" });

        const long = longHex(current) || "#000000";
        swatch.value = long;
        hex.value    = current || "";

        swatch.addEventListener("input", () => {
            hex.value = swatch.value;
            _pending[key] = swatch.value;
            previewTheme();
            touchEditing();
        });
        swatch.addEventListener("change", () => commit(key, swatch.value));

        hex.addEventListener("change", () => {
            const v = hex.value.trim();
            if (v === "") { swatch.value = "#000000"; commit(key, ""); return; }
            const l = longHex(v);
            if (!l) { hex.value = current || ""; playSlot("back"); return; }
            swatch.value = l;
            commit(key, v);
        });

        wrap.appendChild(swatch);
        wrap.appendChild(hex);
        return wrap;
    }

    // Sections //
    function sec(root, id, title, desc, buildFn) {
        root.appendChild(ui().section(id, title, buildFn, desc));
    }

    // Installed library //
    const LIB_STATE = { theme: [], sound: [] };
    const LIB_NOUN  = { theme: "theme", sound: "sound pack" };

    // Per-entry actions, mirroring the profiles panel's profileMenuItems so
    // a pack row and a profile row offer the same shape of ⋯ menu.
    function libMenuItems(kind, e) {
        const items = [];
        if (!e.active) items.push({
            icon: "", label: "Activate this " + LIB_NOUN[kind],
            action: () => window.msLibraryClient.activate(kind, e.slug, e.name),
        });
        items.push({
            icon: "", label: "Export this " + LIB_NOUN[kind] + "...",
            action: () => sendToHost({
                action: "exportPackage", type: kind, slug: e.slug, name: e.name,
            }),
        });
        items.push({
            icon: "", label: "Rename...",
            action: async () => {
                const r = await window.openModal(
                    "Rename " + LIB_NOUN[kind],
                    "New name for \"" + e.name + "\".",
                    "Rename", "Cancel", true, e.name);
                const v = (r.value || "").trim();
                if (r.confirmed && v) window.msLibraryClient.rename(kind, e.slug, v);
            },
        });
        items.push({
            icon: "", label: "Remove from library", danger: true,
            action: async () => {
                const r = await window.openModal(
                    "Delete " + e.name + "?",
                    "Removes it from your library. Anything already applied stays in place.",
                    "Delete", "Cancel");
                if (r.confirmed) window.msLibraryClient.remove(kind, e.slug);
            },
        });
        return items;
    }

    function fillLibList(kind, wrap) {
        const { h, showCtxMenu } = ui();
        wrap.innerHTML = "";

        const entries = LIB_STATE[kind] || [];
        if (!entries.length) {
            wrap.appendChild(h("div", { cls: "theme-note" },
                "Nothing here yet. Install a " + LIB_NOUN[kind] + " from Browse, "
                + "or save your current one below."));
            return;
        }

        for (const e of entries) {
            const meta = [e.origin, e.version].filter(Boolean).join(" · ");
            const r = h("div", { cls: "row", onmouseenter: () => playSlot("hover") });
            const lbl = h("div", { cls: "row-label" }, e.name);
            if (meta) lbl.appendChild(h("small", {}, meta));
            r.appendChild(lbl);
            if (e.active) r.appendChild(h("span", { cls: "pill success" }, "Active"));

            const menuBtn = h("button", {
                cls: "row-menu-btn",
                title: LIB_NOUN[kind] + " actions",
                onmouseenter: () => playSlot("hover"),
            }, "⋯");
            const openMenu = (x, y) => {
                playSlot("interact");
                showCtxMenu(x, y, libMenuItems(kind, e), e.name);
            };
            menuBtn.addEventListener("click", (ev) => {
                ev.preventDefault(); ev.stopPropagation();
                const rect = menuBtn.getBoundingClientRect();
                openMenu(rect.right, rect.bottom);
            });
            r.appendChild(menuBtn);

            // Click the row to activate (unless it is already live), matching
            // the profiles panel's click-to-switch affordance.
            if (!e.active) r.addEventListener("click", () =>
                window.msLibraryClient.activate(kind, e.slug, e.name));
            r.addEventListener("contextmenu", (ev) => {
                ev.preventDefault(); ev.stopImmediatePropagation();
                openMenu(ev.clientX, ev.clientY);
            });
            wrap.appendChild(r);
        }
    }

    function repaintLib(kind) {
        const wrap = document.getElementById("library-list-" + kind);
        if (wrap) fillLibList(kind, wrap);
    }

    // Two sub-sections mirroring the profiles panel: Installed (the hotswap
    // list) and Manage — create/save plus import/export, since moving a pack
    // between machines is just another way of managing it.
    function librarySection(root, kind, title, desc, captureLabel) {
        const { h, btnRow, actionBtn } = ui();
        const noun = LIB_NOUN[kind];

        sec(root, "installed-" + kind, title, desc, (body) => {
            const list = h("div", { id: "library-list-" + kind, cls: "library-list" });
            fillLibList(kind, list);
            body.appendChild(list);
        });

        sec(root, "manage-" + kind, "Manage",
            "Creating, saving and moving " + noun + "s", (body) => {
            body.appendChild(btnRow(
                actionBtn("Create New " + noun, "", async () => {
                    // Name the entry, then choose seed-or-blank — the pack
                    // mirror of Create New Profile.
                    const r = await window.openModal(
                        "Create New " + noun,
                        "Name a fresh " + noun + ".",
                        "Next", "Cancel", true, "");
                    const v = (r.value || "").trim();
                    if (!r.confirmed || !v) return;
                    const s = await window.openModal(
                        "Create \"" + v + "\"",
                        "Start it from your current " + noun + ", or blank?",
                        "Seed from current", "Start blank");
                    window.msLibraryClient.createEmpty(kind, v, s.confirmed);
                }),
                actionBtn(captureLabel, "", async () => {
                    const r = await window.openModal(
                        "Save current " + noun,
                        "Name it so you can hotswap back to it later.",
                        "Save", "Cancel", true, "");
                    if (r.confirmed) {
                        window.msLibraryClient.capture(kind, (r.value || "").trim());
                    }
                }),
            ));
            // Import routes by the package's manifest; Export here is scoped to
            // the live slice of this kind (per-pack export lives in the ⋯ menu).
            body.appendChild(btnRow(
                actionBtn("Import " + noun + "...", "", () =>
                    sendToHost({ action: "importPackage" })),
                actionBtn("Export current " + noun + "...", "", () =>
                    sendToHost({ action: "exportPackage", type: kind })),
            ));
            // Clear every stored entry except the active one, mirroring the
            // profiles panel. Always rendered (the manage section is not
            // repainted per push); the host clears only non-active entries.
            body.appendChild(btnRow(
                actionBtn("Clear Saved " + noun + "s", "danger", async () => {
                    const r = await window.openModal(
                        "Clear Saved " + noun + "s",
                        "Delete all saved " + noun + "s except the active one?"
                        + "\n\nThis cannot be undone.",
                        "Delete All", "Cancel");
                    if (r.confirmed) window.msLibraryClient.clear(kind);
                }),
            ));
        });

        if (window.msLibraryClient) window.msLibraryClient.request(kind);
    }

    if (window.msLibraryClient) {
        window.msLibraryClient.on("theme", (entries) => {
            LIB_STATE.theme = entries;
            repaintLib("theme");
        });

        window.msLibraryClient.on("sound", (entries) => {
            LIB_STATE.sound = entries;
            repaintLib("sound");
        });
    }

    // Theme tab //
    function buildTheme(root) {
        const { h, row, toggle, btnRow, actionBtn } = ui();
        const theme = Object.assign({}, S.theme || {}, _pending);
        const set   = S.themeSet || {};

        const customTheme = S.customThemeEnabled !== false;
        sec(root, "custom", "Theme", "Whether this pack's look is used at all", (body) => {
            body.appendChild(
                row(
                    "Custom theme",
                    "Off reverts every colour, the font and the sound set to stock",
                    toggle(customTheme, (e) =>
                        sendToHost({ action: "setCustomTheme", value: e.target.checked }),
                        true,
                    ),
                ),
            );
            if (!customTheme) {
                body.appendChild(h("div", { cls: "theme-note" },
                    "Turn custom theme on to edit colours."));
            }
        });

        if (!customTheme) return;

        sec(root, "colours", "Colours", "Everything dimmer is derived from these", (body) => {
            for (const c of COLOR_KEYS) {
                const value = theme[c.key] || "";
                body.appendChild(
                    row(
                        c.label,
                        set[c.key] ? c.hint : c.hint + " · default",
                        colorField(c.key, value),
                        "",
                        [{
                            icon: "",
                            label: "Reset to default",
                            action: () => { delete _pending[c.key]; commit(c.key, ""); },
                        }],
                    ),
                );
            }
        });

        // Advanced / derived colour overrides //
        sec(root, "colours-adv", "Derived colours",
            "Normally computed from the colours above — set to override, blank to derive",
            (body) => {
                for (const c of ADVANCED_KEYS) {
                    const value = theme[c.key] || "";
                    body.appendChild(
                        row(
                            c.label,
                            set[c.key] ? c.hint : c.hint + " · derived",
                            colorField(c.key, value),
                            "",
                            [{
                                icon: "",
                                label: "Reset to derived",
                                action: () => { delete _pending[c.key]; commit(c.key, ""); },
                            }],
                        ),
                    );
                }
            });

        // Radius //
        sec(root, "shape", "Shape", "Corner rounding across every panel", (body) => {
            const radius = theme.radius ?? 8;
            const radWrap = h("div", { cls: "row slider-row", onmouseenter: () => playSlot("hover") });
            const radTop  = h("div", { cls: "slider-top" });
            radTop.appendChild(h("div", { cls: "row-label" }, "Corner radius"));
            const radNum = h("input", { type: "number", min: "0", max: "40", step: "1" });
            radNum.value = radius;
            const radVal = h("div", { cls: "slider-val" });
            radVal.appendChild(radNum);
            radTop.appendChild(radVal);
            radWrap.appendChild(radTop);

            const radSlider = h("input", { type: "range", min: "0", max: "40", step: "1" });
            radSlider.value = radius;
            radSlider.addEventListener("input", () => {
                radNum.value = radSlider.value;
                _pending.radius = parseInt(radSlider.value, 10);
                previewTheme();
                touchEditing();
            });
            radSlider.addEventListener("change", () =>
                commit("radius", parseInt(radSlider.value, 10)));
            radNum.addEventListener("change", () => {
                const v = Math.max(0, Math.min(40, parseInt(radNum.value, 10) || 0));
                radNum.value = v;
                radSlider.value = v;
                commit("radius", v);
            });
            radWrap.appendChild(radSlider);
            body.appendChild(radWrap);
        });

        // Font //
        sec(root, "type", "Type", "The face the whole shell is set in", (body) => {
            const fonts   = S.themeFonts || [];
            const current = S.themeFontValue || "";

            const options = [];
            if (!fonts.some((f) => f.value === current) && current) {
                options.push({ value: current, label: current + " (from file)" });
            }
            for (const f of fonts) {
                options.push({ value: f.value, label: f.label });
            }

            const select = createSelect({
                options: options,
                value: current,
                className: "theme-select",
                onChange: (v) =>
                    sendToHost({ action: "setThemeKey", key: "font", value: v }),
            });
            select.addEventListener("mouseenter", () => playSlot("hover"));
            body.appendChild(
                row("Font", "Files in ui/fonts/ travel with a theme package", select),
            );
        });

        // Escape hatches //
        sec(root, "themefile", "Theme File", "Editing ms_theme.json by hand", (body) => {
            body.appendChild(
                btnRow(
                    actionBtn("Edit Theme File...", "", () =>
                        sendToHost({ action: "editTheme" })),
                    actionBtn("Reset Theme", "danger", () =>
                        sendToHost({ action: "resetTheme" })),
                ),
            );
            body.appendChild(h("div", { cls: "theme-note" },
                "Overrides the editor doesn't offer, text2, border, the glow "
                + "colours, can be hand-written into ms_theme.json and win over "
                + "the values derived here."));
        });

        librarySection(root, "theme", "Installed Themes",
            "Hotswap a saved look", "Save current theme...");
    }

    // Sound picker //
    const themeLocked = () => S.customThemeEnabled === false;
    const LOCK_HINT = "Turn custom theme on to change sounds";

    function soundPicker(slotId, assigned, soundNames, scrollEl) {
        const { h } = ui();
        const display = assigned || "off";
        const locked = themeLocked();
        const wrap = h("div", { cls: "sound-picker-wrap" });
        const btn = h(
            "div",
            {
                cls: "sound-picker-btn" + (locked ? " locked" : ""),
                title: locked ? LOCK_HINT : "",
                onmouseenter: () => { if (!locked) playSlot("hover"); },
            },
            display,
            h("span", { cls: "arrow" }, "▾"),
        );
        const list = h("div", { cls: "sound-list" });
        list._detach = () => detach();

        let _filter = "all";
        function categoryOf(name) {
            if (name.startsWith("d_")) return "default";
            if (name.startsWith("m_")) return "macro";
            if (name.startsWith("a_")) return "active";
            return "other";
        }

        function detach() {
            if (list._scrollHandler && scrollEl) {
                scrollEl.removeEventListener("scroll", list._scrollHandler);
                list._scrollHandler = null;
            }
        }

        const filterBar = h("div", { cls: "sound-filter-bar" });
        const filters = [
            { key: "all", label: "All" },
            { key: "default", label: "Default" },
            { key: "active", label: "Active" },
            { key: "macro", label: "Macro" },
        ];
        function rebuildList() {
            while (list.children.length > 1) list.removeChild(list.lastChild);
            const opts = [
                { name: "None", value: "" },
                ...soundNames
                    .filter(n => _filter === "all" || categoryOf(n) === _filter)
                    .map(n => ({ name: n, value: n })),
            ];
            for (const opt of opts) {
                const isSelected = opt.value === (assigned || "");
                const item = h(
                    "div",
                    { cls: "sound-opt" + (isSelected ? " selected" : "") },
                    h("span", { cls: "check" }, isSelected ? "✓" : ""),
                    opt.name,
                );
                item.addEventListener("mouseenter", () => playSlot("hover"));
                item.addEventListener("click", () => {
                    sendToHost({ action: "setSoundAssign", slot: slotId, name: opt.value });
                    detach();
                    list.classList.remove("open");
                    _openSoundPicker = null;
                });
                list.appendChild(item);
            }
        }
        for (const f of filters) {
            const fBtn = h("button", {
                cls: "seg-btn sound-filter-btn" + (_filter === f.key ? " active" : ""),
                onmouseenter: () => playSlot("hover"),
                onclick: (e) => {
                    e.stopPropagation();
                    playSlot("interact");
                    _filter = f.key;
                    for (const child of filterBar.children) child.classList.remove("active");
                    fBtn.classList.add("active");
                    rebuildList();
                },
            }, f.label);
            filterBar.appendChild(fBtn);
        }
        list.appendChild(filterBar);
        rebuildList();

        btn.addEventListener("click", (e) => {
            e.stopPropagation();
            if (locked) return;
            playSlot("interact");
            if (_openSoundPicker && _openSoundPicker !== list)
                _openSoundPicker.classList.remove("open");
            const open = !list.classList.contains("open");
            list.classList.toggle("open", open);
            if (open) {
                const positionList = () => {
                    const rect = btn.getBoundingClientRect();
                    const MARGIN = 6;
                    const vw = window.innerWidth, vh = window.innerHeight;
                    const w = list.offsetWidth || 140;
                    const spaceBelow = vh - rect.bottom - MARGIN;
                    const spaceAbove = rect.top - MARGIN;
                    list.style.maxHeight =
                        Math.min(200, Math.max(spaceBelow, spaceAbove)) + "px";
                    const menuH = list.offsetHeight;
                    let top;
                    if (menuH <= spaceBelow)           top = rect.bottom + 4;
                    else if (menuH <= spaceAbove)      top = rect.top - menuH - 4;
                    else if (spaceBelow >= spaceAbove) top = rect.bottom + 4;
                    else                               top = rect.top - menuH - 4;
                    top = Math.max(MARGIN, Math.min(top, vh - menuH - MARGIN));
                    list.style.top = top + "px";
                    list.style.left =
                        Math.max(MARGIN, Math.min(rect.right - w, vw - w - MARGIN)) + "px";
                };
                positionList();
                if (scrollEl) {
                    list._scrollHandler = positionList;
                    scrollEl.addEventListener("scroll", list._scrollHandler);
                }
            } else {
                detach();
            }
            _openSoundPicker = open ? list : null;
        });

        wrap.appendChild(btn);
        wrap.appendChild(list);
        return wrap;
    }

    document.addEventListener("click", () => {
        if (_openSoundPicker) {
            if (_openSoundPicker._detach) _openSoundPicker._detach();
            _openSoundPicker.classList.remove("open");
            _openSoundPicker = null;
        }
    });

    // Sound tab //
    const slotsIn = (group) => (S.soundSlots || []).filter((s) => s.group === group);

    function defaultAssignsFor(slots) {
        const out = {};
        for (const s of slots) if (s.d) out[s.id] = s.d;
        return out;
    }

    function entryFor(name) {
        if (!name) return null;
        const entries = S.soundEntries || [];
        for (const e of entries) if (e.name === name) return e;
        return null;
    }

    function removable(name) {
        const e = entryFor(name);
        return !!(e && e.removable);
    }

    function removeBtn(name, onRemoved) {
        const { h } = ui();
        const can = removable(name) && !themeLocked();
        const b = h("button", {
            cls: "slot-btn slot-btn-danger",
            title: themeLocked() ? LOCK_HINT
                 : can ? "Remove “" + name + "”"
                       : (name ? "Default sounds cannot be removed"
                               : "Nothing assigned to remove"),
            onmouseenter: () => { if (can) playSlot("hover"); },
            onclick: (e) => {
                e.stopPropagation();
                if (!can) return;
                sendToHost({ action: "removeSound", name: name });
                if (onRemoved) onRemoved();
            },
        });
        b.disabled = !can;
        const svg = typeof window.icon === "function" ? window.icon("close") : "";
        if (svg && svg.indexOf("<path") !== -1) b.innerHTML = svg;
        else b.textContent = "✕";
        return b;
    }

    function slotButtons(slotId, label) {
        const { h } = ui();
        const wrap = h("div", { cls: "slot-btns" });
        const mk = (iconName, glyph, title, action, locked) => {
            const b = h("button", {
                cls: "slot-btn",
                title: locked ? LOCK_HINT : title,
                onmouseenter: () => { if (!locked) playSlot("hover"); },
                onclick: (e) => { e.stopPropagation(); if (locked) return; action(); },
            });
            b.disabled = !!locked;
            const svg = typeof window.icon === "function" ? window.icon(iconName) : "";
            if (svg && svg.indexOf("<path") !== -1) b.innerHTML = svg;
            else b.textContent = glyph;
            return b;
        };
        wrap.appendChild(mk("play", "▶", "Preview",
            () => sendToHost({ action: "playSlot", slot: slotId })));
        wrap.appendChild(mk("download", "⤓", "Import a file for this slot",
            () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label }),
            themeLocked()));
        wrap.appendChild(removeBtn((S.soundAssign || {})[slotId] || ""));
        return wrap;
    }

    function slotRow(slotId, label, names, scrollEl) {
        const { h, row } = ui();
        const assigned = (S.soundAssign || {})[slotId] || "";
        const ctl = h("div", { cls: "slot-ctl" });
        ctl.appendChild(soundPicker(slotId, assigned, names, scrollEl));
        ctl.appendChild(slotButtons(slotId, label));
        return row(label, null, ctl, "", [
            { icon: "", label: "Play",
              action: () => sendToHost({ action: "playSlot", slot: slotId }) },
            ...(themeLocked() ? [] : [
                { icon: "", label: "Import",
                  action: () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label }) },
                ...(assigned ? [{
                    icon: "", label: "Clear",
                    action: () => sendToHost({ action: "setSoundAssign", slot: slotId, name: "" }),
                }] : []),
            ]),
        ]);
    }

    function buildSound(root, scrollEl) {
        const { h, row, toggle, seg, divider, groupLabel, btnRow, actionBtn, showCtxMenu } = ui();

        sec(root, "output", "Output", "Whether the shell makes sound, and how loud", (body) => {
            body.appendChild(
                row(
                    "Sound Effects",
                    null,
                    toggle(S.soundEnabled ?? true, (e) =>
                        sendToHost({ action: "setSoundEnabled", value: e.target.checked })),
                    "",
                    [{ icon: "", label: "Reset to default",
                       action: () => sendToHost({ action: "resetSetting", key: "soundEnabled" }) }],
                ),
            );

            // Volume //
            const volWrap = h("div", { cls: "row slider-row", onmouseenter: () => playSlot("hover") });
            volWrap.addEventListener("contextmenu", (e) => {
                e.preventDefault();
                e.stopImmediatePropagation();
                playSlot("interact");
                showCtxMenu(e.clientX, e.clientY, [{
                    icon: "", label: "Reset to 100",
                    action: () => sendToHost({ action: "resetSetting", key: "soundVolume" }),
                }], "Volume");
            });
            const volTop = h("div", { cls: "slider-top" });
            volTop.appendChild(h("div", { cls: "row-label" }, "Volume"));
            const volNum = h("input", { type: "number", min: "0", max: "100", step: "1" });
            volNum.value = S.soundVolume ?? 100;
            const volDiv = h("div", { cls: "slider-val" });
            volDiv.appendChild(volNum);
            volTop.appendChild(volDiv);
            volWrap.appendChild(volTop);
            const volSlider = h("input", { type: "range", min: "0", max: "100", step: "1" });
            volSlider.value = S.soundVolume ?? 100;
            volSlider.addEventListener("input", () => { volNum.value = volSlider.value; });
            volSlider.addEventListener("change", () =>
                sendToHost({ action: "setSoundVolume", value: parseInt(volSlider.value, 10) }));
            volNum.addEventListener("change", () => {
                const v = Math.max(0, Math.min(100, parseInt(volNum.value, 10) || 0));
                volSlider.value = v;
                sendToHost({ action: "setSoundVolume", value: v });
            });
            volWrap.appendChild(volSlider);
            body.appendChild(volWrap);
        });

        // Presets //
        const presets   = S.soundPresets || [];
        const ALL_SLOTS = S.soundSlots || [];
        const presetSlotIds = ALL_SLOTS.filter(s => s.d || s.a).map(s => s.id);

        const defaultAssigns = defaultAssignsFor(ALL_SLOTS);

        const sa = S.soundAssign || {};
        let activePreset = null;
        let isDefault = presetSlotIds.length > 0;
        for (const sid of presetSlotIds) {
            if ((sa[sid] || "") !== (defaultAssigns[sid] || "")) { isDefault = false; break; }
        }
        if (isDefault) activePreset = "default";
        if (!activePreset) {
            for (const p of presets) {
                const pSlots = Object.keys(p.assigns || {});
                if (pSlots.length === 0) continue;
                let match = true;
                for (const sid of pSlots) {
                    if ((p.assigns[sid] || null) !== (sa[sid] || null)) { match = false; break; }
                }
                if (match) { activePreset = String(p.num); break; }
            }
        }

        const soundLocked = themeLocked();
        const shown = soundLocked ? "default" : activePreset;

        const segBtn = (key, labelText, action) => {
            const b = h("button", {
                cls: "seg-btn" + (shown === key ? " active" : ""),
                title: soundLocked ? LOCK_HINT : "",
                onmouseenter: () => { if (!soundLocked) playSlot("hover"); },
                onclick: () => { if (soundLocked) return; action(); },
            }, labelText);
            b.disabled = soundLocked;
            return b;
        };

        sec(root, "presets", "Presets", "A whole slot map in one click", (body) => {
            const presetWrap = h("div", { cls: "seg" + (soundLocked ? " locked" : "") });
            presetWrap.appendChild(segBtn(null, "Custom", () =>
                sendToHost({ action: "clearSoundPreset", slots: presetSlotIds })));
            presetWrap.appendChild(segBtn("default", "Default", () =>
                sendToHost({ action: "setSoundPreset", assigns: defaultAssigns, preset: "default" })));
            for (const p of presets) {
                presetWrap.appendChild(segBtn(String(p.num), String(p.num), () =>
                    sendToHost({ action: "setSoundPreset", assigns: p.assigns, preset: String(p.num) })));
            }
            body.appendChild(row(
                "Preset",
                soundLocked
                    ? "Fixed at Default while custom theme is off"
                    : "Select a numbered sound set, or Custom for individual control",
                presetWrap,
            ));
        });

        // Slots //
        const names = S.soundNames || [];

        const loadSlots = slotsIn("load");
        if (loadSlots.length > 0) {
            sec(root, "loadslots", "Startup", "Played while mudscript starts up", (body) => {
                for (const slot of loadSlots) {
                    body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
                }
            });
        }

        sec(root, "eventslots", "Event Slots", "One sound per shell interaction", (body) => {
            for (const slot of slotsIn("event")) {
                body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
            }
        });


        const userSlots = S.userSoundSlots || [];
        if (userSlots.length > 0) {
            sec(root, "packslots", "Pack Slots", "Declared by your macro pack", (body) => {
                for (const slot of userSlots) {
                    body.appendChild(slotRow(slot.key, slot.label, names, scrollEl));
                }
            });
        }

        // Sound library //
        const entries = S.soundEntries || [];
        const byKind = (k) => entries.filter((e) => e.kind === k);

        const soundEntryRow = (e) => {
            const ctl = h("div", { cls: "slot-ctl" });
            const selected = e.imported ? null : e.role;
            if (e.role === "default") {
                ctl.appendChild(h("span", { cls: "snd-entry-kind" }, e.kind));
            } else {
                ctl.appendChild(seg(
                    [{ value: "active", label: "Active" },
                     { value: "macro",  label: "Macro"  }],
                    selected,
                    (v) => {
                        if (v === selected) return;
                        sendToHost({ action: "setSoundKind", name: e.name, kind: v });
                    },
                ));
            }
            const btns = h("div", { cls: "slot-btns" });
            const play = h("button", {
                cls: "slot-btn",
                title: "Preview “" + e.name + "”",
                onmouseenter: () => playSlot("hover"),
                onclick: (ev) => {
                    ev.stopPropagation();
                    sendToHost({ action: "previewSound", name: e.name });
                },
            });
            const psvg = typeof window.icon === "function" ? window.icon("play") : "";
            if (psvg && psvg.indexOf("<path") !== -1) play.innerHTML = psvg;
            else play.textContent = "▶";
            btns.appendChild(play);
            btns.appendChild(removeBtn(e.name));
            ctl.appendChild(btns);
            return row(e.name, null, ctl, "", [
                { icon: "", label: "Play",
                  action: () => sendToHost({ action: "previewSound", name: e.name }) },
                ...(e.removable ? [{
                    icon: "", label: "Remove",
                    action: () => sendToHost({ action: "removeSound", name: e.name }),
                }] : []),
            ]);
        };

        sec(root, "library", "Sound Library",
            "The files themselves, whether or not a slot uses them", (body) => {
            const activeEntries = byKind("active");
            body.appendChild(groupLabel("Active"));
            if (activeEntries.length === 0) {
                body.appendChild(h("div", { cls: "theme-note" },
                    "Sounds in sounds/active/ appear here. These are the ones the "
                    + "slots above can be assigned to."));
            } else {
                for (const e of activeEntries) body.appendChild(soundEntryRow(e));
            }

            const macroEntries = byKind("macro");
            body.appendChild(divider());
            body.appendChild(groupLabel("Macro"));
            if (macroEntries.length === 0) {
                body.appendChild(h("div", { cls: "theme-note" },
                    "Sounds in sounds/macro/ appear here, one row each. Macros play "
                    + "them by name with ms.sound(\"m_Name\"), they have no slot, "
                    + "because a macro chooses its own sound at the call."));
            } else {
                for (const e of macroEntries) body.appendChild(soundEntryRow(e));
            }

            const importedEntries = byKind("imported");
            if (importedEntries.length > 0) {
                body.appendChild(divider());
                body.appendChild(groupLabel("Imported"));
                for (const e of importedEntries) body.appendChild(soundEntryRow(e));
            }

            body.appendChild(divider());
            body.appendChild(
                btnRow(actionBtn("Import Sound Files...", "", () =>
                    sendToHost({ action: "importSounds" }))),
            );
        });

        sec(root, "bundling", "Sharing", "What travels with a theme package", (body) => {
            body.appendChild(row(
                "Bundle Sounds With Theme",
                "Include your sounds and their slot assignments in theme exports",
                toggle(S.bundleSoundsWithTheme ?? true, (e) =>
                    sendToHost({ action: "setBundleSoundsWithTheme", value: e.target.checked })),
                "",
                [{ icon: "", label: "Reset to default",
                   action: () => sendToHost({ action: "setBundleSoundsWithTheme", value: true }) }],
            ));
        });

        librarySection(root, "sound", "Installed Sound Packs",
            "Hotswap a saved set", "Save current sounds...");
    }

    // Share tab //
    // Tabs //
    function tabs() {
        if (_tabs) return _tabs;
        const panel = document.querySelector(".panel-theme");
        if (!panel || !window.createTabs) return null;
        _tabs = window.createTabs({
            root: panel,
            tabSelector: ".ttab",
            sectionSelector: ".ttab-section",
            tabKey: (el) => el.dataset.ttab,
            sectionKey: (el) => el.dataset.tsection,
            onSame: () => playSlot("back"),
            onSwitch: () => playSlot("interact"),
        });
        return _tabs;
    }

    function switchThemeTab(tab) {
        const t = tabs();
        if (t) t.switch(tab);
    }
    window.switchThemeTab = switchThemeTab;

    // Render //
    function renderInto(id, buildFn) {
        const el = document.getElementById(id);
        if (!el) return;
        const scrollTop = el.scrollTop;
        el.innerHTML = "";
        buildFn(el, el);
        el.scrollTop = scrollTop;
    }

    function renderThemePanel(state) {
        if (state) S = state;
        if (!ui()) return;

        renderInto("sound-scroll", buildSound);

        if (editing()) {
            clearTimeout(_rerenderTimer);
            _rerenderTimer = setTimeout(() => renderThemePanel(), SETTLE_MS);
            return;
        }
        _pending = {};
        renderInto("theme-scroll", buildTheme);
        const t = tabs();
        if (t) t.refresh();
    }
    window.renderThemePanel = renderThemePanel;

    })();
