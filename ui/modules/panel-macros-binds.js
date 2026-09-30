(function() {
    "use strict";

    window.msMacroBinds = function(ctx) {
        var M = ctx.M;

        var macroSelect = ctx.macroSelect;

        var nameInput = ctx.nameInput;

        var setMacroClass = ctx.setMacroClass;

        var classFromGroup = ctx.classFromGroup;

        var saveBtn = ctx.saveBtn;

        var cooldownInput = ctx.cooldownInput;

        var sharedInput = ctx.sharedInput;

        var bindOptsBtn = ctx.bindOptsBtn;

        var bindList = ctx.bindList;

        var _history = ctx._history;

        var refreshMacroList = ctx.refreshMacroList;

        var refreshBindList = ctx.refreshBindList;

        var showTestToast = ctx.showTestToast;

        // Themed delete confirmation //
            function confirmDelete(name) {
                var msg = 'Delete "' + name + '"? This cannot be undone.';
                if (typeof window.openModal === "function") {
                    return window.openModal("Delete macro", msg, "Delete", "Cancel")
                        .then(function(r) { return !!(r && r.confirmed); });
                }
                // lint-allow native-dialog
                var ok = (typeof window.confirm !== "function") || window.confirm(msg);
                return Promise.resolve(ok);
            }

            function bindPill(text, onClick, title, onMenu) {
                var b = document.createElement("button");
                b.className = "bind-pill" + (text ? "" : " unset");
                b.textContent = text || "Unset";
                if (title) b.title = title;
                b.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                b.addEventListener("click", function(e) {
                    e.stopPropagation();
                    if (window.playSlot) playSlot("interact");
                    onClick();
                });
                if (onMenu) b.addEventListener("contextmenu", function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    onMenu();
                });
                return b;
            }
        // END Themed delete confirmation //

        // Bind list //
            function openBindMenu(m, isSub, mode) {
                window.msBindMenu.open(m, isSub, mode, {
                    list:          function() { return M.bindList; },
                    confirmDelete: confirmDelete,
                    onDelete:      function(id) {
                        M.bindList = M.bindList.filter(function(x) { return x.id !== id; });
                        renderBindList();
                    },
                });
            }

            function bindRow(m, isSub) {
                var r = document.createElement("div");
                r.className = "bind-row" + (isSub ? " bind-row-sub" : "");
                r.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });

                var lbl = document.createElement("div");
                lbl.className = "bind-label";
                lbl.textContent = m.label || m.id;
                r.appendChild(lbl);

                var acts = document.createElement("div");
                acts.className = "bind-acts";

                var mode = { full: false };
                acts.appendChild(bindPill(m.bind, function() {
                    if (isSub && !mode.full) {
                        shellPost("macros", "startModRebind", {
                            action: "startModRebind",
                            id:     m.id,
                        });
                    } else {
                        shellPost("macros", "startRebind", {
                            action:     "startRebind",
                            id:         m.id,
                            systemBind: m.systemBind || false,
                        });
                    }
                }, isSub
                    ? "Click to rebind - capture mode is set in the options menu"
                    : "Click to rebind", function() { openBindMenu(m, isSub, mode); }));

                var moreBtn = document.createElement("button");
                moreBtn.className = "bind-act bind-more";
                moreBtn.innerHTML = window.icon ? window.icon("ellipsis") : "...";
                moreBtn.title = "Bind options";
                moreBtn.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                moreBtn.addEventListener("click", function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    openBindMenu(m, isSub, mode);
                });
                acts.appendChild(moreBtn);

                r.appendChild(acts);
                return r;
            }

            function renderBindList() {
                bindList.innerHTML = "";

                if (!M.bindList.length) {
                    var empty = document.createElement("div");
                    empty.className = "binds-empty";
                    empty.textContent = "No macros registered.";
                    bindList.appendChild(empty);
                    return;
                }

                var order = [];
                var groups = {};
                M.bindList.forEach(function(m) {
                    var g = m.group || "ungrouped";
                    if (!groups[g]) { groups[g] = []; order.push(g); }
                    groups[g].push(m);
                });

                order.forEach(function(g) {
                    var rows = [];
                    groups[g].forEach(function(m) {
                        rows.push(bindRow(m, false));
                        (m.subs || []).forEach(function(sub) {
                            rows.push(bindRow(sub, true));
                        });
                    });
                    var sec = bindSection(
                        titleCaseGroup(g),
                        g === "system" ? "Always live, these cannot be disabled" : null,
                        rows,
                    );
                    sec.setAttribute("data-bind-group", g);
                    bindList.appendChild(sec);
                });
            }

            function focusSystemBinds() {
                if (M.mtabs) M.mtabs.switch("binds");
                refreshBindList();
                setTimeout(function() {
                    var sec = bindList.querySelector('[data-bind-group="system"]');
                    if (sec && sec.scrollIntoView) sec.scrollIntoView({ block: "start" });
                }, 90);
            }

            function titleCaseGroup(g) {
                return String(g).replace(/[A-Za-z]+/g, function(w) {
                    return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
                });
            }
        // END Bind list //

        // Same markup as msUI.section //
            function bindSection(title, desc, rows) {
                var wrap = document.createElement("div");
                wrap.className = "section";
                var head = document.createElement("div");
                head.className = "section-head";
                var t = document.createElement("span");
                t.className = "section-title";
                t.textContent = title;
                head.appendChild(t);
                if (desc) {
                    var d = document.createElement("span");
                    d.className = "section-desc";
                    d.textContent = desc;
                    head.appendChild(d);
                }
                var body = document.createElement("div");
                body.className = "section-body";
                rows.forEach(function(r) { body.appendChild(r); });
                wrap.appendChild(head);
                wrap.appendChild(body);
                return wrap;
            }

            function setBindList(list) {
                M.bindList = Array.isArray(list) ? list : [];
                renderBindList();
                if (window.msBindMenu) window.msBindMenu.refresh(M.bindList);
            }

            function setMacroList(ids) {
                var opts = [];
                for (var i = 0; i < ids.length; i++) {
                    opts.push({ value: ids[i], label: ids[i] });
                }
                macroSelect.setOptions(opts);

                if (M.currentMacroId) {
                    macroSelect.value = M.currentMacroId;
                }
            }

            function loadMacro(macroId) {
                if (!macroId) {
                    M.currentMacroId = null;
                    M.currentMacroDef = null;
                    M.canvas.load([]);
                    nameInput.value = "";
                    setMacroClass("main");
                    M.currentMacroCooldown = null;
                    cooldownInput.value = "";
                    M.currentMacroShared = "";
                    sharedInput.value = "";
                    M.macroDirty = false;
                    updateSaveBtnState();
                    if (_history) _history.reset();
                    return;
                }
                if (window.shellPost) {
                    shellPost("macros", "getMacro", { id: macroId });
                }
            }

            function setMacroDef(def) {
                M.currentMacroId = def.id;
                M.currentMacroDef = def;
                nameInput.value = def.name || def.id || "";
                M.canvas.load(def.steps || []);
                setMacroClass(classFromGroup(def.group));
                M.currentMacroCooldown = def.cooldown != null ? def.cooldown : null;
                cooldownInput.value = M.currentMacroCooldown != null ? String(M.currentMacroCooldown) : "";
                M.currentMacroShared = def.shared || "";
                sharedInput.value = M.currentMacroShared;
                M.macroDirty = false;
                updateSaveBtnState();
                if (_history) _history.reset();
                macroSelect.value = def.id;
            }
        // END Same markup as msUI.section //

        // Bind options and saving //
            function openCurrentBindMenu() {
                var found = null;
                M.bindList.forEach(function(top) {
                    if (top.id === M.currentMacroId) found = { m: top, sub: false };
                    (top.subs || []).forEach(function(s) {
                        if (s.id === M.currentMacroId) found = { m: s, sub: true };
                    });
                });
                if (!found) {
                    showTestToast("Save the macro before binding it", "error");
                    return;
                }
                openBindMenu(found.m, found.sub, { full: false });
            }

            bindOptsBtn.addEventListener("click", openCurrentBindMenu);

            function saveMacro() {
                if (!M.currentMacroId) {
                    var name = nameInput.value.trim();
                    if (!name) {
                        nameInput.focus();
                        return;
                    }
                    M.currentMacroId = name.replace(/[^a-zA-Z0-9_]/g, "_");
                }

                var name = nameInput.value.trim() || M.currentMacroId;
                var def = {
                    id: M.currentMacroId,
                    name: name,
                    author: "User",
                    group: "visual - " + M.currentMacroClass,
                    steps: M.canvas.serialize()
                };
                if (M.currentMacroDef && M.currentMacroDef.bind) {
                    def.bind = M.currentMacroDef.bind;
                }
                if (M.currentMacroCooldown != null) {
                    def.cooldown = M.currentMacroCooldown;
                }
                if (M.currentMacroShared) {
                    def.shared = M.currentMacroShared;
                }
                M.currentMacroDef = def;

                if (window.shellPost) {
                    shellPost("macros", "saveMacro", { id: M.currentMacroId, def: def });
                }
                updateSaveBtnState();
            }

            function deleteMacro() {
                if (!M.currentMacroId) return;
                if (window.shellPost) {
                    shellPost("macros", "deleteMacro", { id: M.currentMacroId });
                }
                M.currentMacroId = null;
                M.currentMacroDef = null;
                M.canvas.load([]);
                nameInput.value = "";
                setMacroClass("main");
                M.currentMacroCooldown = null;
                cooldownInput.value = "";
                M.currentMacroShared = "";
                sharedInput.value = "";
                M.macroDirty = false;
                updateSaveBtnState();
                if (_history) _history.reset();
                refreshMacroList();
            }

            function updateSaveBtnState() {
                saveBtn.style.opacity = M.macroDirty ? "1" : "0.5";
                if (M.macroDirty && _history) _history.record();
            }
        // END Bind options and saving //

        return {
            focusSystemBinds: focusSystemBinds,
            setBindList: setBindList,
            setMacroList: setMacroList,
            loadMacro: loadMacro,
            setMacroDef: setMacroDef,
            saveMacro: saveMacro,
            deleteMacro: deleteMacro,
            updateSaveBtnState: updateSaveBtnState,
        };
    };
})();
