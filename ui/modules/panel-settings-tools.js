(function() {
    "use strict";
            const P = window.msSettings;
            const { S, showCtxMenu, sendToHost, playSlot, showAlert, h, toggle, seg, section, row, btnRow, actionBtn, divider } = P;

            function renderToolsPanel() {
                const scroll = document.getElementById("tools-scroll");
                if (!scroll) return;
                syncToolsFilterBtn();
                const active = window._toolsFilter !== "all";
                if (window.shellPost) window.shellPost("macros", "listTools", {});
                const scrollTop = scroll.scrollTop;
                scroll.innerHTML = "";

                for (const menu of S.userMenus || []) {
                    if (menu.plugin) continue;
                    if (active && !toolOriginMatches(menu.origin)) continue;
                    const title = menu.icon
                        ? menu.icon + " " + menu.title
                        : menu.title;
                    scroll.appendChild(
                        section("user_" + menu.id, title, (body) =>
                            P.buildUserSection(body, menu),
                        ),
                    );
                }

                if (!active
                    || filterByOrigin(S.userSettings).some(P.isDefaultSection)) {
                    scroll.appendChild(
                        section("settings", "Settings", P.buildSettings,
                            "Defined by your macro pack"),
                    );
                }
                if (!active || filterByOrigin(S.userFunctions).length) {
                    scroll.appendChild(
                        section("functions", "Functions", P.buildFunctions,
                            "Function tools your macros can call"),
                    );
                }
                if (!active || filterByOrigin(S.userVariables).length) {
                    scroll.appendChild(
                        section("variables", "Variables", P.buildVariables,
                            "Shared helper variables"),
                    );
                }

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
                        if (active && window._toolsFilter !== "user" && !items.length)
                            continue;
                        scroll.appendChild(
                            P.userSectionGroup(meta, items));
                    } else {
                        if (!items.length) continue;
                        const disp = P.packSectionDisplay(id);
                        scroll.appendChild(
                            section(id, disp.title, (body) => {
                                P.renderItemsCollapsed(body, items);
                            }, disp.desc));
                    }
                }

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
                        section("builder", "Setting Builder", P.buildSettingBuilder,
                            "Compose a new setting and preview it live"),
                    );
                    bscroll.appendChild(
                        section("arrange", "Arrange", P.buildArrange,
                            "Drag to position dividers, labels and settings"),
                    );
                }
                if (bscroll) {
                    const asec = bscroll.querySelector(
                        '[data-section="arrange"] .section-body');
                    if (asec) {
                        asec.innerHTML = "";
                        P.buildArrange(asec);
                    }
                }

                renderToolFunctionsTab();
                renderToolVariablesTab();
            }
            window.renderToolsPanel = renderToolsPanel;

            const TOOL_FILTER_ORDER = ["all", "user", "pack"];
            const TOOL_FILTER_LABEL = {
                all: "All", user: "Visual", pack: "Hand",
            };
            window._toolsFilter = window._toolsFilter || "all";
            function toolOriginMatches(origin) {
                if (window._toolsFilter === "all") return true;
                return (origin || "pack") === window._toolsFilter;
            }
            function filterByOrigin(arr) {
                return (arr || []).filter((x) => x && !x.plugin && toolOriginMatches(x.origin));
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

            function showToolsFilterMenu(x, y) {
                showCtxMenu(x, y, TOOL_FILTER_ORDER.map((key) => ({
                    icon: window._toolsFilter === key ? "check" : "",
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

        // Function Tab //
            let _fnCanvas = null;
            let _fnEditor = null;
            let _fnHotkeysBound = false;

            function bindFunctionHotkeys() {
                if (_fnHotkeysBound) return;
                _fnHotkeysBound = true;
                document.addEventListener("keydown", function(e) {
                    if (!_fnCanvas) return;
                    const host = _fnCanvas._root;
                    if (!host || host.offsetParent === null) return;
                    const t = e.target;
                    if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
                    const mod = msMod(e);
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
                const coroToggle = toggle(false, () => {});
                coroToggle.tabIndex = 0;
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
                        className: "input-sm macros-add-step",
                        placeholder: "+ Add step...",
                        action: true,
                        searchable: true,
                        searchPlaceholder: "Search modules...",
                        options: buildStepOptions(),
                        value: undefined,
                        onChange: (v) => {
                            if (!v || !_fnCanvas) return;
                            const def = buildStepDef(v);
                            if (!def) return;
                            const sid = _fnCanvas.addTool(def);
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
                    setCoro(fnDef.coroutine !== false);
                    if (_fnCanvas) _fnCanvas.load(fnDef.steps || []);
                    switchToolsTab("functions");
                };
            }

            function buildStepOptions() {
                const reg = (window.fnPicker && window.fnPicker.registry) || [];
                const skip = { "if": 1, "for": 1, "while": 1, "repeat": 1 };
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
                let fns = (window.msMacroFunctions || []).filter((fn) => !fn.plugin);
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
                    const isPack = fn.source === "pack";
                    const isPlugin = fn.source === "plugin";
                    const callOnly = isPack || isPlugin;
                    const r = h("div", { cls: "row row-sub" });
                    const lbl = h("div", { cls: "row-label" }, fn.name || fn.id);
                    if (isPack) lbl.appendChild(h("small", {}, "from pack - call by id '" + fn.id + "'"));
                    else if (isPlugin) lbl.appendChild(h("small", {}, "from plugin - call by id '" + fn.id + "'"));
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
        // END Function Tab //

        // Variable Tab //
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
                        "Insert appends a {name} token into the Default field above. "
                        + "it resolves to the variable's value when the macro runs"));
                } else {
                    const listBody = document.getElementById("tool-var-list-body");
                    if (listBody) fillVariableList(listBody);
                }
            }
            window.renderToolVariablesTab = renderToolVariablesTab;

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
                    const token = "{" + v.name + "}";
                    const ins = actionBtn("Insert", "", () => {
                        const el = _varDefaultInput;
                        if (!el || !el.isConnected) {
                            showAlert("Open the Default field above first.");
                            return;
                        }
                        let start = el.selectionStart, end = el.selectionEnd;
                        if (typeof start !== "number" || document.activeElement !== el) {
                            start = el.value.length; end = start;
                        }
                        el.value = el.value.slice(0, start) + token + el.value.slice(end);
                        const caret = start + token.length;
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
        // END Variable Tab //

        // Tools Tabs //
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
        // END Tools Tabs //

            Object.assign(window.msSettings, {
                renderToolsPanel,
                filterByOrigin,
                switchToolsTab,
            });
    })();
