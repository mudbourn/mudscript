(function() {
    "use strict";
            const P = window.msSettings;
            const { S, sendToHost, playSlot, showAlert, openModal, h, toggle, seg, row, btnRow, actionBtn, divider, groupLabel } = P;

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

                let editKey = (preset && preset.editKey) || null;
                if (preset && preset.item) seedDraftFrom(draft, preset.item);

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

                const typeSeg = () => seg(typeLabels, draft.type, (v) => {
                    draft.type = v;
                    renderDynamic();
                    updatePreview();
                });
                let typeCtl = typeSeg();
                body.appendChild(row("Type", "What kind of control to add", typeCtl));

                body.appendChild(divider());
                const dyn = h("div", { cls: "setting-builder-dyn" });
                body.appendChild(dyn);

                body.appendChild(divider());
                body.appendChild(groupLabel("Preview"));
                const preview = h("div", { cls: "setting-builder-preview" });
                body.appendChild(preview);

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
                                label: P.packSectionDisplay(s).title,
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
                                        updatePreview();
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

                const undoHistory = window.createHistory && window.createHistory({
                    limit: 64,
                    capture: () => ({ draft: draft, editKey: editKey }),
                    restore: (snap) => {
                        Object.assign(draft, snap.draft);
                        editKey = snap.editKey;
                        primaryBtn.textContent = editKey ? "Update Setting" : "Add Setting";
                        const next = typeSeg();
                        typeCtl.replaceWith(next);
                        typeCtl = next;
                        syncIdentityInputs();
                        renderDynamic();
                        updatePreview();
                    },
                });
                const onHistoryKey = (e) => {
                    if (!body.isConnected) {
                        document.removeEventListener("keydown", onHistoryKey);
                        return;
                    }
                    const hk = body.getClientRects().length && window.msHistoryKey(e);
                    if (!hk) return;
                    e.preventDefault();
                    if (undoHistory[hk]()) playSlot("interact");
                };
                if (undoHistory) document.addEventListener("keydown", onHistoryKey);

                function updatePreview() {
                    if (undoHistory) undoHistory.record();
                    preview.innerHTML = "";
                    const def = buildDef();
                    try {
                        P.renderUserItem(preview, def);
                    } catch (e) {
                        preview.appendChild(
                            groupLabel("Preview unavailable."),
                        );
                    }
                }

                renderDynamic();
                updatePreview();
                if (undoHistory) undoHistory.reset();
            }

            const _dragSvg = '<svg class="icon" viewBox="0 0 24 24" fill="none" '
                + 'xmlns="http://www.w3.org/2000/svg"><path d="M9 6h.01M9 12h.01'
                + 'M9 18h.01M15 6h.01M15 12h.01M15 18h.01" stroke="currentColor" '
                + 'stroke-width="2.5" stroke-linecap="round" '
                + 'stroke-linejoin="round"/></svg>';

            function arrangeRowLabel(it) {
                if (it.type === "divider") return "Divider";
                if (it.type === "groupLabel")
                    return "'" + (it.label || "") + "' label";
                const name = it.label || it.key || "(setting)";
                return name + "  -  " + it.type;
            }

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

                const list = h("div", { cls: "arrange-list" });
                let lastSection = "";
                for (const it of authored) {
                    const sec = it.section || "settings";
                    if (sec !== lastSection) {
                        lastSection = sec;
                        const title = sec === "settings"
                            ? "Settings"
                            : (P.packSectionDisplay(sec).title || sec);
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

            window._loadSettingIntoBuilder = (item) => {
                if (!item || !item.key) return;
                const bscroll = document.getElementById("tools-builder-scroll");
                if (!bscroll) return;
                const bodyEl = bscroll.querySelector(
                    '[data-section="builder"] .section-body');
                if (!bodyEl) return;
                bodyEl.innerHTML = "";
                buildSettingBuilder(bodyEl, { editKey: item.key, item: item });
                P.switchToolsTab("builder");
            };


            Object.assign(window.msSettings, {
                buildSettingBuilder,
                buildArrange,
            });
    })();
