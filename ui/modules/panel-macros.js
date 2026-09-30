(function() {
    "use strict";

    var _svgCache = window.msSvgCache;
    var _fetchSVG = window.msFetchSVG;
    var enumDefault = window.msMacroRegistry.enumDefault;

    var _currentMacroId = null;
    var _currentMacroDef = null;
    var _macroDirty = false;
    var _canvas = null;
    var _mtabs = null;

    var slot = document.getElementById("slot-macros");
    if (!slot) return;

    var existingPicker = slot.querySelector(".fn-picker");

    var layout = document.createElement("div");
    layout.className = "macros-layout";

    var toolbar = document.createElement("div");
    toolbar.className = "macro-toolbar";

    var macroLabel = document.createElement("span");
    macroLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-right:4px";
    macroLabel.textContent = "Macro";
    toolbar.appendChild(macroLabel);

// Custom dropdown rather than <select> //
    var macroSelect = (function() {
        var root = document.createElement("div");
        root.className = "macro-select";
        root.tabIndex = 0;

        var label = document.createElement("span");
        label.className = "macro-select-label";
        root.appendChild(label);

        var arrow = document.createElement("span");
        arrow.className = "macro-select-arrow";
        arrow.innerHTML = (typeof window.icon === "function" && window.ICONS
            && window.ICONS.chevdown)
            ? window.icon("chevdown")
            : "";
        root.appendChild(arrow);

        var menu = document.createElement("div");
        menu.className = "macro-select-menu";
        root.appendChild(menu);

        var _opts = [];
        var _value = "";
        var PLACEHOLDER = "Select";

        function labelFor(v) {
            for (var i = 0; i < _opts.length; i++) {
                if (_opts[i].value === v) return _opts[i].label;
            }
            return "";
        }
        function close() { root.classList.remove("open"); }
        function render() {
            var lbl = _value ? labelFor(_value) : "";
            label.textContent = lbl || PLACEHOLDER;
            menu.innerHTML = "";
            var choices = _opts.filter(function(o) { return o.value !== ""; });
            if (choices.length === 0) {
                var none = document.createElement("div");
                none.className = "macro-select-item macro-select-empty";
                none.textContent = "None";
                menu.appendChild(none);
                return;
            }
            choices.forEach(function(o) {
                var item = document.createElement("div");
                item.className = "macro-select-item" + (o.value === _value ? " active" : "");
                item.textContent = o.label;
                item.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                item.addEventListener("click", function(e) {
                    e.stopPropagation();
                    if (window.playSlot) playSlot("interact");
                    close();
                    if (o.value === _value) return;
                    _value = o.value;
                    render();
                    root.dispatchEvent(new Event("change"));
                });
                menu.appendChild(item);
            });
        }

        root.setOptions = function(list) { _opts = list; render(); };
        Object.defineProperty(root, "value", {
            get: function() { return _value; },
            set: function(v) { _value = v == null ? "" : String(v); render(); },
        });

        root.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        root.addEventListener("click", function(e) {
            e.stopPropagation();
            if (!root.classList.contains("open")) {
                if (window.playSlot) playSlot("interact");
                _gpIndex = -1;
                menu.querySelectorAll(".gp-hi").forEach(function(it) { it.classList.remove("gp-hi"); });
            }
            root.classList.toggle("open");
        });
        root.addEventListener("keydown", function(e) {
            if (e.key === "Escape") close();
        });
        document.addEventListener("click", close);

        var _gpIndex = -1;
        function gpItems() {
            return Array.prototype.slice.call(
                menu.querySelectorAll(".macro-select-item:not(.macro-select-empty)"));
        }
        function gpHighlight(i) {
            var items = gpItems();
            if (!items.length) { _gpIndex = -1; return; }
            _gpIndex = ((i % items.length) + items.length) % items.length;
            items.forEach(function(it, idx) { it.classList.toggle("gp-hi", idx === _gpIndex); });
            items[_gpIndex].scrollIntoView({ block: "nearest" });
        }
        root.gpIsOpen = function() { return root.classList.contains("open"); };
        root.gpMove = function(dir) {
            var items = gpItems();
            if (!items.length) return;
            var start = _gpIndex;
            if (start < 0) start = items.findIndex(function(it) { return it.classList.contains("active"); });
            gpHighlight(start < 0 ? 0 : start + dir);
            if (window.playSlot) playSlot("hover");
        };
        root.gpPick = function() {
            var items = gpItems();
            var it = items[_gpIndex];
            if (!it) it = items.filter(function(x) { return x.classList.contains("active"); })[0] || items[0];
            if (it) it.click();
        };
        root.gpClose = function() { _gpIndex = -1; close(); };

        root.setOptions([]);
        return root;
    })();
    toolbar.appendChild(macroSelect);

    var nameInput = document.createElement("input");
    nameInput.className = "macro-name-input";
    nameInput.type = "text";
    nameInput.placeholder = "Macro name";
    nameInput.setAttribute("spellcheck", "false");
    nameInput.setAttribute("autocomplete", "off");
    nameInput.setAttribute("autocorrect", "off");
    nameInput.setAttribute("autocapitalize", "off");
    nameInput.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    nameInput.addEventListener("focus", function() {
        if (window.playSlot) playSlot("interact");
    });
    toolbar.appendChild(nameInput);

    var bindLabel = document.createElement("span");
    bindLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    bindLabel.textContent = "Bind";
    toolbar.appendChild(bindLabel);

    var bindBtn = document.createElement("button");
    bindBtn.className = "bind-pill unset";
    bindBtn.textContent = "UNSET";
    bindBtn.title = "Click to capture a bind for this macro";
    toolbar.appendChild(bindBtn);

    var _currentMacroClass = "main";
    var _currentMacroCooldown = null;
    var _currentMacroShared = "";

    var classLabel = document.createElement("span");
    classLabel.style.cssText = "font-family:inherit;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    classLabel.textContent = "Class";
    toolbar.appendChild(classLabel);
// END Custom dropdown rather than <select> //

// Two //
    var classSeg = document.createElement("span");
    classSeg.className = "fn-bind-switch macro-class-seg";
    function buildClassOpt(value, text) {
        var b = document.createElement("button");
        b.className = "fn-bind-opt" + (_currentMacroClass === value ? " on" : "");
        b.setAttribute("data-class", value);
        b.textContent = text;
        b.title = value === "main"
            ? "Main macro, grouped under VISUAL - MAIN"
            : "Optional macro, grouped under VISUAL - OPTIONAL";
        b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        b.addEventListener("click", function() {
            if (_currentMacroClass === value) return;
            if (window.playSlot) playSlot("interact");
            setMacroClass(value);
            _macroDirty = true;
            updateSaveBtnState();
        });
        return b;
    }
    classSeg.appendChild(buildClassOpt("main", "Main"));
    classSeg.appendChild(buildClassOpt("optional", "Optional"));
    toolbar.appendChild(classSeg);

    function setMacroClass(value) {
        _currentMacroClass = (value === "optional") ? "optional" : "main";
        var opts = classSeg.querySelectorAll(".fn-bind-opt");
        opts.forEach(function(o) {
            o.classList.toggle("on", o.getAttribute("data-class") === _currentMacroClass);
        });
    }
    function classFromGroup(group) {
        return (typeof group === "string" && /optional/i.test(group)) ? "optional" : "main";
    }

    var actions = document.createElement("div");
    actions.className = "macro-toolbar-actions";

    var newBtn = document.createElement("button");
    newBtn.className = "macro-toolbar-btn";
    newBtn.textContent = "New";
    actions.appendChild(newBtn);

    var saveBtn = document.createElement("button");
    saveBtn.className = "macro-toolbar-btn primary";
    saveBtn.textContent = "Save";
    actions.appendChild(saveBtn);
// END Two //

// Secondary actions live under an overflow menu so the toolbar never clips them //
    var overflowWrap = document.createElement("div");
    overflowWrap.className = "macro-overflow";
    var overflowBtn = document.createElement("button");
    overflowBtn.className = "macro-toolbar-btn macro-overflow-btn";
    overflowBtn.textContent = "⋯";
    overflowBtn.title = "More actions";
    var overflowMenu = document.createElement("div");
    overflowMenu.className = "macro-overflow-menu";
    overflowWrap.appendChild(overflowBtn);
    overflowWrap.appendChild(overflowMenu);

    function closeOverflow() { overflowWrap.classList.remove("open"); }
    overflowBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    overflowBtn.addEventListener("click", function(e) {
        e.stopPropagation();
        if (!overflowWrap.classList.contains("open") && window.playSlot) playSlot("interact");
        overflowWrap.classList.toggle("open");
    });
    overflowMenu.addEventListener("click", function() { closeOverflow(); });
    document.addEventListener("click", closeOverflow);
// END Secondary actions live under an overflow menu so the toolbar never clips them //

// Every overflow item is icon + label so the menu reads as one consistent list //
    function menuLabel(name, text) {
        return (window.icon ? window.icon(name) : "") + '<span>' + text + '</span>';
    }

    var flowCooldownRow = document.createElement("div");
    flowCooldownRow.className = "macro-flow-row";
    var cooldownLbl = document.createElement("label");
    cooldownLbl.textContent = "Cooldown (ms)";
    var cooldownInput = document.createElement("input");
    cooldownInput.className = "macro-flow-input";
    cooldownInput.type = "number";
    cooldownInput.min = "0";
    cooldownInput.step = "50";
    cooldownInput.placeholder = "1000";
    cooldownInput.title = "Milliseconds the macro stays locked after it fires. Re-triggers within this window are ignored. Blank uses the default of 1000.";
    cooldownInput.setAttribute("spellcheck", "false");
    cooldownInput.addEventListener("input", function() {
        var raw = cooldownInput.value.trim();
        _currentMacroCooldown = raw === "" ? null : Math.max(0, parseInt(raw, 10) || 0);
        _macroDirty = true;
        updateSaveBtnState();
    });
    flowCooldownRow.appendChild(cooldownLbl);
    flowCooldownRow.appendChild(cooldownInput);

    var flowGroupRow = document.createElement("div");
    flowGroupRow.className = "macro-flow-row";
    var sharedLbl = document.createElement("label");
    sharedLbl.textContent = "Group";
    var sharedInput = document.createElement("input");
    sharedInput.className = "macro-flow-input";
    sharedInput.type = "text";
    sharedInput.placeholder = "solo";
    sharedInput.title = "Macros sharing a group name never run at the same time. Blank keeps this macro isolated to itself.";
    sharedInput.setAttribute("spellcheck", "false");
    sharedInput.setAttribute("autocomplete", "off");
    sharedInput.addEventListener("input", function() {
        var clean = sharedInput.value.replace(/[^A-Za-z0-9_ -]/g, "");
        if (clean !== sharedInput.value) sharedInput.value = clean;
        _currentMacroShared = clean.trim();
        _macroDirty = true;
        updateSaveBtnState();
    });
    flowGroupRow.appendChild(sharedLbl);
    flowGroupRow.appendChild(sharedInput);

    [flowCooldownRow, flowGroupRow].forEach(function(row) {
        row.addEventListener("click", function(e) { e.stopPropagation(); });
    });

    var flowDivider = document.createElement("div");
    flowDivider.className = "macro-overflow-divider";

    overflowMenu.appendChild(flowCooldownRow);
    overflowMenu.appendChild(flowGroupRow);
    overflowMenu.appendChild(flowDivider);

    var testBtn = document.createElement("button");
    testBtn.className = "macro-toolbar-btn";
    testBtn.innerHTML = menuLabel("play", "Test");
    testBtn.title = "Test Run current macro";
    overflowMenu.appendChild(testBtn);

    var recordRow = document.createElement("div");
    recordRow.className = "macro-record-row";
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = menuLabel("record", "Record");
    recordBtn.title = "Record user actions into modules";
    recordRow.appendChild(recordBtn);

    var recSettingsBtn = document.createElement("button");
    recSettingsBtn.className = "macro-toolbar-btn macro-record-settings-btn";
    recSettingsBtn.textContent = "⋯";
    recSettingsBtn.title = "Recording settings";
    recSettingsBtn.setAttribute("aria-label", "Recording settings");
    recordRow.appendChild(recSettingsBtn);

    overflowMenu.appendChild(recordRow);

    var delMacroBtn = document.createElement("button");
    delMacroBtn.className = "macro-toolbar-btn danger";
    delMacroBtn.innerHTML = menuLabel("trash", "Delete");
    delMacroBtn.title = "Delete macro";
    overflowMenu.appendChild(delMacroBtn);

    var editFileBtn = document.createElement("button");
    editFileBtn.className = "macro-toolbar-btn";
    editFileBtn.innerHTML = menuLabel("edit", "Edit File");
    editFileBtn.title = "Open ms_macros.lua in your editor";
    overflowMenu.appendChild(editFileBtn);

    var editorBtn = document.createElement("button");
    editorBtn.className = "macro-toolbar-btn";
    editorBtn.innerHTML = menuLabel("settings", "Change Editor");
    editorBtn.title = "Pick which app opens ms_macros.lua";
    overflowMenu.appendChild(editorBtn);

    actions.appendChild(overflowWrap);
    toolbar.appendChild(actions);

    if (window.msMotion) toolbar._glide = msMotion.glideOnWrap(toolbar);

    var mainArea = document.createElement("div");
    mainArea.className = "macros-main";

    var toolArea = document.createElement("div");
    toolArea.className = "macros-tool-area";
    var canvasContainer = document.createElement("div");
    canvasContainer.className = "macros-canvas-scroll";
    canvasContainer.style.cssText = "flex:1;overflow-y:auto;overflow-x:hidden;position:relative";
    toolArea.appendChild(canvasContainer);

    mainArea.appendChild(toolArea);

    var addToolBtn = document.createElement("button");
    addToolBtn.className = "macros-add-tool-btn";
    addToolBtn.innerHTML = (_svgCache["add"] || "+") + " Add Module";
    toolArea.appendChild(addToolBtn);

    var testToast = document.createElement("div");
    testToast.className = "macro-test-toast";
    toolArea.appendChild(testToast);
// END Every overflow item is icon + label so the menu reads as one consistent list //

// Fn //
    var overlay = document.createElement("div");
    overlay.className = "fn-picker-overlay";

    var overlayHeader = document.createElement("div");
    overlayHeader.className = "fn-picker-overlay-header";
    var overlayTitle = document.createElement("span");
    overlayTitle.className = "fn-picker-overlay-title";
    overlayTitle.textContent = "Add Module";
    overlayHeader.appendChild(overlayTitle);
    var overlayClose = document.createElement("div");
    overlayClose.className = "fn-picker-overlay-close";
    overlayClose.innerHTML = (_svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>');
    overlayClose.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    overlayClose.addEventListener("click", function() {
        if (window.playSlot) playSlot("back");
        closeFnOverlay();
    });
    overlayHeader.appendChild(overlayClose);
    overlay.appendChild(overlayHeader);

    if (existingPicker) {
        existingPicker.style.width = "100%";
        existingPicker.style.height = "100%";
        existingPicker.style.flex = "1";
        overlay.appendChild(existingPicker);
    }
    mainArea.appendChild(overlay);

    var mtabs = document.createElement("div");
    mtabs.className = "mtabs";

    var builderSection = document.createElement("div");
    builderSection.className = "mtab-section";
    builderSection.setAttribute("data-msec", "builder");

    var bindsSection = document.createElement("div");
    bindsSection.className = "mtab-section active";
    bindsSection.setAttribute("data-msec", "binds");

    var bindsScroll = document.createElement("div");
    bindsScroll.className = "binds-scroll";
    bindsSection.appendChild(bindsScroll);

    var bindList = document.createElement("div");
    bindsScroll.appendChild(bindList);
// END Fn //

// Pack Info //
    var _metaLoaded  = false;
    var _metaDirty   = false;
    var _metaOwned   = false;

    function metaField(labelText, placeholder) {
        var wrap = document.createElement("label");
        wrap.className = "meta-field";
        var lb = document.createElement("span");
        lb.className = "meta-field-label";
        lb.textContent = labelText;
        var inp = document.createElement("input");
        inp.type = "text";
        inp.className = "meta-input";
        inp.placeholder = placeholder || "";
        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
        inp.addEventListener("input", function() {
            if (_metaLoaded) { _metaDirty = true; updateMetaSaveBtn(); }
        });
        wrap.appendChild(lb);
        wrap.appendChild(inp);
        return { wrap: wrap, input: inp };
    }
// END Pack Info //

// Pack Info //
    var _kit = window.msUI;
    var _metaName    = metaField("Name",    "My Macros");
    var _metaVersion = metaField("Version", "1.0.0");
    var _metaAuthor  = metaField("Author",  "You");
    var _metaWebsite = metaField("Website", "https://...");

    var metaSaveBtn = _kit.actionBtn("Save Pack Info", "", function() {
        if (!_metaDirty) return;
        if (window.shellPost) {
            shellPost("macros", "setMeta", {
                name:    _metaName.input.value.trim(),
                version: _metaVersion.input.value.trim(),
                author:  _metaAuthor.input.value.trim(),
                website: _metaWebsite.input.value.trim(),
            });
        }
        _metaDirty = false;
        updateMetaSaveBtn();
    });
    var metaSaveRow = _kit.btnRow(metaSaveBtn);

    var metaCard = _kit.section("macro-meta", "Pack Info", function(body) {
        var form = _kit.h("div", { cls: "meta-form" });
        form.appendChild(_metaName.wrap);
        form.appendChild(_metaVersion.wrap);
        form.appendChild(_metaAuthor.wrap);
        form.appendChild(_metaWebsite.wrap);
        form.appendChild(metaSaveRow);
        body.appendChild(form);
    }, "Credits baked into your visual macros (ms.macroMeta)");
    var metaDesc = metaCard.querySelector(".section-desc");
    bindsScroll.insertBefore(metaCard, bindList);

    var _macroLib = [];
    var packList;
// END Pack Info //

// Per //
    function macroMenuItems(e) {
        var items = [];
        if (!e.active) items.push({
            icon: "", label: "Activate this macro pack",
            action: function() { window.msLibraryClient.activate("macro", e.slug, e.name); },
        });
        items.push({
            icon: "", label: "Export this macro pack...",
            action: function() {
                if (window.sendToHost) window.sendToHost({
                    action: "exportPackage", type: "macro", slug: e.slug, name: e.name,
                });
            },
        });
        items.push({
            icon: "", label: "Rename...",
            action: async function() {
                var r = await window.openModal(
                    "Rename macro pack",
                    "New name for \"" + e.name + "\".",
                    "Rename", "Cancel", true, e.name);
                var v = (r.value || "").trim();
                if (r.confirmed && v) window.msLibraryClient.rename("macro", e.slug, v);
            },
        });
        items.push({
            icon: "", label: "Remove from library", danger: true,
            action: async function() {
                var r = await window.openModal(
                    "Delete " + e.name + "?",
                    "Removes it from your library. Macros already applied stay in place.",
                    "Delete", "Cancel");
                if (r.confirmed) window.msLibraryClient.remove("macro", e.slug);
            },
        });
        return items;
    }

    var packCreateBtn = _kit.actionBtn("Create New macro pack", "", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        var r = await window.openModal(
            "Create New macro pack",
            "Name a fresh macro pack.",
            "Next", "Cancel", true, "");
        var v = (r.value || "").trim();
        if (!r.confirmed || !v) return;
        var s = await window.openModal(
            "Create \"" + v + "\"",
            "Start it from your current macros, or blank?",
            "Seed from current", "Start blank");
        window.msLibraryClient.createEmpty("macro", v, s.confirmed);
    });
    var packSaveBtn = _kit.actionBtn("Save current macros...", "", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        var r = await window.openModal(
            "Save current macros",
            "Name this macro pack so you can hotswap back to it later.",
            "Save", "Cancel", true, "");
        if (r.confirmed) window.msLibraryClient.capture("macro", (r.value || "").trim());
    });

    var packImportBtn = _kit.actionBtn("Import macro pack...", "", function() {
        if (window.sendToHost) window.sendToHost({ action: "importPackage" });
    });
    var packExportBtn = _kit.actionBtn("Export current macros...", "", function() {
        if (window.sendToHost) window.sendToHost({ action: "exportPackage", type: "macro" });
    });

    var packCard = _kit.section("installed-macro", "Installed Macro Packs", function(body) {
        packList = _kit.h("div", { id: "library-list-macro", cls: "library-list" });
        body.appendChild(packList);
    }, "Hotswap a saved macro set");
    var packClearBtn = _kit.actionBtn("Clear Saved macro packs", "danger", async function() {
        if (!window.openModal || !window.msLibraryClient) return;
        var r = await window.openModal(
            "Clear Saved macro packs",
            "Delete all saved macro packs except the active one?"
            + "\n\nThis cannot be undone.",
            "Delete All", "Cancel");
        if (r.confirmed) window.msLibraryClient.clear("macro");
    });
    var packManageCard = _kit.section("manage-macro", "Manage", function(body) {
        body.appendChild(_kit.btnRow(packCreateBtn, packSaveBtn));
        body.appendChild(_kit.btnRow(packImportBtn, packExportBtn));
        body.appendChild(_kit.btnRow(packClearBtn));
    }, "Creating, saving and moving macro packs");
// END Per //

// Managers sit at the bottom //
    bindsScroll.appendChild(packCard);
    bindsScroll.appendChild(packManageCard);

    function fillMacroLib() {
        var kit = window.msUI;
        packList.innerHTML = "";
        if (!kit) return;

        if (!_macroLib.length) {
            packList.appendChild(kit.h("div", { cls: "theme-note" },
                "Nothing here yet. Install a macro pack from Browse, or save "
                + "your current one below."));
            return;
        }

        for (var i = 0; i < _macroLib.length; i++) {
            (function(e) {
                var meta = [e.origin, e.version].filter(Boolean).join(" - ");
                var r = kit.h("div", { cls: "row",
                    onmouseenter: function() { if (window.playSlot) playSlot("hover"); } });
                var lbl = kit.h("div", { cls: "row-label" }, e.name);
                if (meta) lbl.appendChild(kit.h("small", {}, meta));
                r.appendChild(lbl);
                if (e.active) r.appendChild(kit.h("span", { cls: "pill success" }, "Active"));

                var menuBtn = kit.h("button", {
                    cls: "row-menu-btn", title: "macro pack actions",
                    onmouseenter: function() { if (window.playSlot) playSlot("hover"); },
                }, "⋯");
                var openMenu = function(x, y) {
                    if (window.playSlot) playSlot("interact");
                    kit.showCtxMenu(x, y, macroMenuItems(e), e.name);
                };
                menuBtn.addEventListener("click", function(ev) {
                    ev.preventDefault(); ev.stopPropagation();
                    var rect = menuBtn.getBoundingClientRect();
                    openMenu(rect.right, rect.bottom);
                });
                r.appendChild(menuBtn);

                if (!e.active) r.addEventListener("click", function() {
                    window.msLibraryClient.activate("macro", e.slug, e.name);
                });
                r.addEventListener("contextmenu", function(ev) {
                    ev.preventDefault(); ev.stopImmediatePropagation();
                    openMenu(ev.clientX, ev.clientY);
                });
                packList.appendChild(r);
            })(_macroLib[i]);
        }
    }

    if (window.msLibraryClient) {
        window.msLibraryClient.on("macro", function(entries) {
            _macroLib = entries || [];
            fillMacroLib();
        });
        window.msLibraryClient.request("macro");
    }

    function updateMetaSaveBtn() {
        var on = _metaDirty && !_metaOwned;
        metaSaveBtn.disabled = !on;
        metaSaveBtn.style.opacity = on ? "1" : "0.5";
    }
    updateMetaSaveBtn();

    function refreshMeta() {
        if (window.shellPost) shellPost("macros", "getMeta", {});
    }

    function setMeta(meta) {
        meta = meta || {};
        _metaLoaded = false;
        _metaName.input.value    = meta.name    || "";
        _metaVersion.input.value = meta.version || "";
        _metaAuthor.input.value  = meta.author  || "";
        _metaWebsite.input.value = meta.website || "";
        _metaLoaded = true;
        _metaDirty  = false;

        _metaOwned = meta.owned === true;
        [_metaName, _metaVersion, _metaAuthor, _metaWebsite].forEach(function(f) {
            f.input.readOnly = _metaOwned;
            f.input.classList.toggle("meta-input-locked", _metaOwned);
        });
        metaDesc.textContent = _metaOwned
            ? "Sourced from your handwritten ms_macros.lua (read-only)"
            : "Credits baked into your visual macros (ms.macroMeta)";
        metaSaveRow.style.display = _metaOwned ? "none" : "";
        updateMetaSaveBtn();
    }

    ["builder", "binds"].forEach(function(id) {
        var b = document.createElement("button");
        b.className = "mtab" + (id === "binds" ? " active" : "");
        b.setAttribute("data-mtab", id);
        b.textContent = id === "builder" ? "Builder" : "Manager";
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function() {
            if (_mtabs) _mtabs.switch(id);
        });
        mtabs.appendChild(b);
    });

    builderSection.appendChild(toolbar);
    builderSection.appendChild(mainArea);
    layout.appendChild(mtabs);
    layout.appendChild(builderSection);
    layout.appendChild(bindsSection);
    slot.appendChild(layout);
// END Managers sit at the bottom //

// Shared tab model //
    _mtabs = window.createTabs && window.createTabs({
        root: layout,
        tabSelector: ".mtab",
        sectionSelector: ".mtab-section",
        tabKey: function(el) { return el.getAttribute("data-mtab"); },
        sectionKey: function(el) { return el.getAttribute("data-msec"); },
        onSame: function() { if (window.playSlot) playSlot("back"); },
        onSwitch: function(tab) {
            if (window.playSlot) playSlot("interact");
            if (tab === "binds") {
                refreshBindList();
                refreshMeta();
                if (window.msLibraryClient) window.msLibraryClient.request("macro");
            } else if (tab === "builder" && _canvas) {
                requestAnimationFrame(function() {
                    requestAnimationFrame(function() { _canvas._updateParamMarquee(); });
                });
            }
        },
    });
// END Shared tab model //

// Tool Canvas instance //
    _canvas = new ToolCanvas(canvasContainer, {
        onChange: function(steps) {
            _macroDirty = true;
            updateSaveBtnState();
        },
        onSelect: function(sid, step) {
            if (!_toolEditor) return;
            if (_toolEditor._open && (!sid || _toolEditor._toolSid !== sid)) {
                _toolEditor.close();
            }
        },
        onContext: function(sid) {
            if (!_toolEditor || !sid) return;
            if (_toolEditor._open && _toolEditor._toolSid === sid) {
                _toolEditor.close();
            } else {
                _toolEditor.open(sid);
            }
        }
    });
// END Tool Canvas instance //

// Picker //
    (function() {
        var FN_MIME     = "application/x-ms-fn";
        var TOOL_MIME   = "application/x-ms-tool";
        var CALLFN_MIME = "application/x-ms-callfn";
        function hasType(e, mime) {
            var types = e.dataTransfer && e.dataTransfer.types;
            if (!types) return false;
            return Array.prototype.indexOf.call(types, mime) !== -1;
        }
        function hasFn(e)   { return hasType(e, FN_MIME) || hasType(e, TOOL_MIME) || hasType(e, CALLFN_MIME); }
        function buildCallFnDef(id) {
            if (!id) return null;
            return { action: "call_fn", params: { name: id } };
        }
        function buildToolDef(key) {
            var tools = window.msMacroTools || [];
            for (var i = 0; i < tools.length; i++) {
                if (tools[i].key === key) {
                    return (window.fnPicker && window.fnPicker.settingDef)
                        ? window.fnPicker.settingDef(tools[i])
                        : { action: "setting", params: { key: tools[i].key, label: tools[i].label || tools[i].key, type: tools[i].type } };
                }
            }
            return null;
        }
        function buildDefaultDef(fnId) {
            var reg = window.fnPicker && window.fnPicker.registry;
            if (!reg) return null;
            var fn = null;
            for (var i = 0; i < reg.length; i++) {
                if (reg[i].id === fnId) { fn = reg[i]; break; }
            }
            if (!fn) return null;
            var params = {};
            (fn.params || []).forEach(function(p) {
                if (p.type === "mods") params[p.name] = [];
                else if (p.type === "number") params[p.name] = p.default != null ? p.default : 0;
                else if (p.type === "enum") params[p.name] = enumDefault(p);
                else params[p.name] = "";
            });
            return { action: fn.name, params: params };
        }
        _canvas.defFor = buildDefaultDef;
        function beforeSidAt(clientY) {
            var root = _canvas._root;
            var blocks = root.children;
            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i];
                if (!b.getAttribute) continue;
                var sid = b.getAttribute("data-sid");
                if (!sid) continue;
                var r = b.getBoundingClientRect();
                if (clientY < r.top + r.height / 2) return sid;
            }
            return null;
        }
        canvasContainer.addEventListener("dragenter", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
        }, true);
        canvasContainer.addEventListener("dragover", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            e.dataTransfer.dropEffect = "copy";
            _canvas._root.classList.add("fn-drop-target");
        }, true);
        canvasContainer.addEventListener("dragleave", function(e) {
            if (!hasFn(e)) return;
            if (e.target === canvasContainer || !canvasContainer.contains(e.relatedTarget)) {
                _canvas._root.classList.remove("fn-drop-target");
            }
        }, true);
        canvasContainer.addEventListener("drop", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            _canvas._root.classList.remove("fn-drop-target");
            var def = null;
            if (hasType(e, TOOL_MIME)) {
                def = buildToolDef(e.dataTransfer.getData(TOOL_MIME));
            } else if (hasType(e, CALLFN_MIME)) {
                def = buildCallFnDef(e.dataTransfer.getData(CALLFN_MIME));
            } else {
                def = buildDefaultDef(e.dataTransfer.getData(FN_MIME));
            }
            if (!def) return;
            _canvas.insertDefAt(def, beforeSidAt(e.clientY));
            _macroDirty = true;
            updateSaveBtnState();
            if (window.playSlot) playSlot("interact");
            closeFnOverlay();
        }, true);
    })();
// END Picker //

// Tool keyboard shortcuts //
    document.addEventListener("keydown", function(e) {
        if (!builderSection.classList.contains("active")) return;
        var t = e.target;
        if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
        var mod = e.metaKey || e.ctrlKey;
        var hk = _history && window.msHistoryKey(e);
        if (hk) {
            e.preventDefault();
            if (_history[hk]() && window.playSlot) playSlot("interact");
            return;
        }
        if (mod && (e.key === "a" || e.key === "A")) {
            e.preventDefault();
            _canvas.selectAll();
            return;
        }
        if (mod && (e.key === "v" || e.key === "V")) {
            e.preventDefault();
            if (!(e.shiftKey && _canvas.pasteInside())) _canvas.pasteAfter();
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (e.key === "Escape" && _canvas.hasSelection()) {
            e.preventDefault();
            _canvas.clearSelection();
            return;
        }
        if (!_canvas.hasSelection()) return;
        if (mod && (e.key === "c" || e.key === "C")) {
            e.preventDefault();
            _canvas.copySelected();
        } else if (mod && (e.key === "x" || e.key === "X")) {
            e.preventDefault();
            _canvas.cutSelected();
            _macroDirty = true;
            updateSaveBtnState();
        } else if (mod && (e.key === "d" || e.key === "g")) {
            e.preventDefault();
            if (e.key === "d") _canvas.duplicateSelected();
            else _canvas.openWrapMenu();
        } else if (e.key === "Delete" || e.key === "Backspace") {
            e.preventDefault();
            _canvas.removeSelected();
            _macroDirty = true;
            updateSaveBtnState();
        }
    });

    var _history = window.createHistory && window.createHistory({
        limit: 256,
        capture: function() {
            return {
                steps: _canvas.serialize(),
                cls: _currentMacroClass,
                cooldown: _currentMacroCooldown,
                shared: _currentMacroShared,
            };
        },
        restore: function(snap) {
            if (_toolEditor && _toolEditor._open) _toolEditor.close();
            _canvas.load(snap.steps);
            setMacroClass(snap.cls);
            _currentMacroCooldown = snap.cooldown;
            cooldownInput.value = snap.cooldown != null ? String(snap.cooldown) : "";
            _currentMacroShared = snap.shared;
            sharedInput.value = snap.shared;
            _macroDirty = true;
            updateSaveBtnState();
        },
    });
    if (_history) {
        _history.reset();
        var histBtns = window.msHistoryButtons(_history, "macro-toolbar-btn");
        overflowMenu.insertBefore(histBtns.redo, testBtn);
        overflowMenu.insertBefore(histBtns.undo, histBtns.redo);
    }

    var _toolEditor = null;
    if (window.ToolEditor) {
        _toolEditor = new ToolEditor({ canvas: _canvas });
    } else {
        console.warn("[macros] ToolEditor not loaded, inline editing disabled");
    }

    _fetchSVG("add").then(function(svg) {
        if (svg) addToolBtn.innerHTML = svg + " Add Module";
    });
    _fetchSVG("close").then(function(svg) {
        if (svg) overlayClose.innerHTML = svg;
    });
// END Tool keyboard shortcuts //

// Fn //
    overlay.inert = true;
    function openFnOverlay() {
        overlay.classList.add("open");
        overlay.inert = false;
        refreshToolList();
    }
    function closeFnOverlay() {
        overlay.classList.remove("open");
        overlay.inert = true;
    }
    addToolBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    addToolBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        openFnOverlay();
    });

    function refreshToolList() {
        if (window.shellPost) shellPost("macros", "listTools", {});
    }

    function refreshMacroList() {
        if (window.shellPost) {
            shellPost("macros", "listMacros", {});
        }
    }

    var _bindList = [];

    function refreshBindList() {
        if (window.shellPost) shellPost("macros", "listBinds", {});
    }
// END Fn //

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

    function bindPill(text, onClick, title) {
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
        return b;
    }
// END Themed delete confirmation //

// Candidate macros this one can be tethered to //
    function linkTargets(m) {
        var exclude = {};
        exclude[m.id] = true;
        (function walk(node) {
            (node.subs || []).forEach(function(s) { exclude[s.id] = true; walk(s); });
        })(m);
        var out = [];
        _bindList.forEach(function(top) {
            function consider(x) {
                if (exclude[x.id]) return;
                if (x.group === "system" || x.systemBind) return;
                out.push({ value: x.id, label: x.label || x.id, group: top.label || top.id });
            }
            consider(top);
            (top.subs || []).forEach(consider);
        });
        return out;
    }


    function linkMenuItems(m) {
        return linkTargets(m).map(function(o) {
            return {
                icon:  "",
                label: (m.parent === o.value ? "✓ " : "") + o.label,
                action: function() {
                    shellPost("macros", "bindToMacro", {
                        action:   "bindToMacro",
                        id:       m.id,
                        targetId: o.value,
                    });
                },
            };
        });
    }
// END Candidate macros this one can be tethered to //

// Opens the per //
    function openBindMenu(m, isSub, mode, x, y) {
        var kit = window.msUI;
        if (!kit || typeof kit.showCtxMenu !== "function") return;
        var items = [];

        if (m.group !== "system" && !m.systemBind) {
            items.push({
                icon:  "",
                label: m.enabled ? "Disable macro" : "Enable macro",
                action: function() {
                    shellPost("macros", "setMacroEnabled", {
                        action: "setMacroEnabled",
                        id:     m.id,
                        value:  !m.enabled,
                    });
                    if (window.playSlot) playSlot(m.enabled ? "toggleOff" : "toggleOn");
                },
            });
        }

        if (isSub) {
            items.push({
                icon:  "",
                label: "Re-attach to parent",
                action: function() {
                    shellPost("macros", "clearModifier", {
                        action: "clearModifier",
                        id:     m.id,
                    });
                },
            });
        } else {
            items.push({
                icon:  "",
                label: "Reset to default bind",
                action: function() {
                    shellPost("macros", "resetBind", {
                        action:     "resetBind",
                        id:         m.id,
                        systemBind: m.systemBind || false,
                    });
                },
            });
        }

        if (isSub) {
            items.push({
                icon:  "",
                label: mode.full ? "Switch to modifier only" : "Switch to full trigger",
                action: function() { mode.full = !mode.full; },
            });
        }

        if (m.group !== "system" && !m.systemBind
            && (m.bindType === "key" || m.bindType === "combo")) {
            items.push({
                icon:  "",
                label: (m.ignoreMods ? "✓ " : "") + "Ignore extra modifiers",
                action: function() {
                    shellPost("macros", "setBindIgnoreMods", {
                        action: "setBindIgnoreMods",
                        id:     m.id,
                        value:  !m.ignoreMods,
                    });
                },
            });
        }

        if (m.group !== "system" && !m.systemBind) {
            var targets = linkMenuItems(m);
            if (targets.length) {
                items.push({
                    icon:  "",
                    label: (m.parent ? "Change linked macro..." : "Link to another macro..."),
                    action: function() { kit.showCtxMenu(x, y, targets, m.label || m.id); },
                });
            }
        }

        if (m.group !== "system" && !m.systemBind) {
            items.push({
                icon:  "",
                label: "Delete macro",
                danger: true,
                action: function() {
                    confirmDelete(m.label || m.id).then(function(ok) {
                        if (!ok) return;
                        if (window.playSlot) playSlot("back");
                        shellPost("macros", "deleteMacro", { id: m.id });
                        _bindList = _bindList.filter(function(x) { return x.id !== m.id; });
                        renderBindList();
                    });
                },
            });
        }

        if (!items.length) return;
        if (window.playSlot) playSlot("interact");
        kit.showCtxMenu(x, y, items, m.label || m.id);
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
            ? "Click to rebind - capture mode is set in the ⋯ menu"
            : "Click to rebind"));

        var moreBtn = document.createElement("button");
        moreBtn.className = "bind-act bind-more";
        moreBtn.textContent = "⋯";
        moreBtn.title = "Bind options";
        moreBtn.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        moreBtn.addEventListener("click", function(e) {
            e.preventDefault();
            e.stopPropagation();
            var rect = moreBtn.getBoundingClientRect();
            openBindMenu(m, isSub, mode, rect.right, rect.bottom);
        });
        acts.appendChild(moreBtn);

        r.appendChild(acts);
        return r;
    }

    function renderBindList() {
        bindList.innerHTML = "";

        if (!_bindList.length) {
            var empty = document.createElement("div");
            empty.className = "binds-empty";
            empty.textContent = "No macros registered.";
            bindList.appendChild(empty);
            return;
        }

        var order = [];
        var groups = {};
        _bindList.forEach(function(m) {
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
        if (_mtabs) _mtabs.switch("binds");
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
// END Opens the per //

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
        _bindList = Array.isArray(list) ? list : [];
        renderBindList();
        updateBindBtn();
    }

    function setMacroList(ids) {
        var opts = [];
        for (var i = 0; i < ids.length; i++) {
            opts.push({ value: ids[i], label: ids[i] });
        }
        macroSelect.setOptions(opts);

        if (_currentMacroId) {
            macroSelect.value = _currentMacroId;
        }
    }

    function loadMacro(macroId) {
        if (!macroId) {
            _currentMacroId = null;
            _currentMacroDef = null;
            _canvas.load([]);
            nameInput.value = "";
            setMacroClass("main");
            _currentMacroCooldown = null;
            cooldownInput.value = "";
            _currentMacroShared = "";
            sharedInput.value = "";
            _macroDirty = false;
            updateSaveBtnState();
            if (_history) _history.reset();
            updateBindBtn();
            return;
        }
        if (window.shellPost) {
            shellPost("macros", "getMacro", { id: macroId });
        }
    }

    function setMacroDef(def) {
        _currentMacroId = def.id;
        _currentMacroDef = def;
        nameInput.value = def.name || def.id || "";
        _canvas.load(def.steps || []);
        setMacroClass(classFromGroup(def.group));
        _currentMacroCooldown = def.cooldown != null ? def.cooldown : null;
        cooldownInput.value = _currentMacroCooldown != null ? String(_currentMacroCooldown) : "";
        _currentMacroShared = def.shared || "";
        sharedInput.value = _currentMacroShared;
        _macroDirty = false;
        updateSaveBtnState();
        if (_history) _history.reset();
        macroSelect.value = def.id;
        updateBindBtn();
    }
// END Same markup as msUI.section //

// Show the macro's effective bind //
    function updateBindBtn() {
        var text = "";
        for (var i = 0; i < _bindList.length; i++) {
            if (_bindList[i].id === _currentMacroId) { text = _bindList[i].bind || ""; break; }
        }
        if (!text && _currentMacroDef && _currentMacroDef.bind) {
            var b = _currentMacroDef.bind;
            if (b.type === "mouse") text = "Mouse " + b.button;
            else if (b.type === "mods") text = (b.mods || []).join("+");
            else if (b.key) text = (b.mods || []).concat([b.key]).join("+");
        }
        bindBtn.textContent = text || "Unset";
        bindBtn.className = "bind-pill" + (text ? "" : " unset");
    }

    bindBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    bindBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (!_currentMacroId || _macroDirty) {
            showTestToast("Save the macro before binding it", "error");
            return;
        }
        shellPost("macros", "startRebind", {
            action: "startRebind",
            id:     _currentMacroId,
        });
    });

    function saveMacro() {
        if (!_currentMacroId) {
            var name = nameInput.value.trim();
            if (!name) {
                nameInput.focus();
                return;
            }
            _currentMacroId = name.replace(/[^a-zA-Z0-9_]/g, "_");
        }

        var name = nameInput.value.trim() || _currentMacroId;
        var def = {
            id: _currentMacroId,
            name: name,
            author: "User",
            group: "visual - " + _currentMacroClass,
            steps: _canvas.serialize()
        };
        if (_currentMacroDef && _currentMacroDef.bind) {
            def.bind = _currentMacroDef.bind;
        }
        if (_currentMacroCooldown != null) {
            def.cooldown = _currentMacroCooldown;
        }
        if (_currentMacroShared) {
            def.shared = _currentMacroShared;
        }
        _currentMacroDef = def;

        if (window.shellPost) {
            shellPost("macros", "saveMacro", { id: _currentMacroId, def: def });
        }
        updateSaveBtnState();
    }

    function deleteMacro() {
        if (!_currentMacroId) return;
        if (window.shellPost) {
            shellPost("macros", "deleteMacro", { id: _currentMacroId });
        }
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        setMacroClass("main");
        _currentMacroCooldown = null;
        cooldownInput.value = "";
        _currentMacroShared = "";
        sharedInput.value = "";
        _macroDirty = false;
        updateSaveBtnState();
        if (_history) _history.reset();
        refreshMacroList();
    }

    function updateSaveBtnState() {
        saveBtn.style.opacity = _macroDirty ? "1" : "0.5";
        if (_macroDirty && _history) _history.record();
    }
// END Show the macro's effective bind //

// Wire toolbar buttons //
    newBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    newBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        nameInput.focus();
        setMacroClass("main");
        _currentMacroCooldown = null;
        cooldownInput.value = "";
        _currentMacroShared = "";
        sharedInput.value = "";
        _macroDirty = false;
        updateSaveBtnState();
        if (_history) _history.reset();
        macroSelect.value = "";
        updateBindBtn();
    });

    saveBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    saveBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        saveMacro();
    });

    editFileBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editFileBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) shellPost("macros", "editMacros", { action: "editMacros" });
    });

    editorBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editorBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) shellPost("macros", "chooseMacroEditor", { action: "chooseMacroEditor" });
    });
// END Wire toolbar buttons //

// Test Run //
    var _testRunning = false;
    var _testToastTimer = null;

    function showTestToast(msg, type, iconName) {
        if (iconName && window.icon) {
            testToast.innerHTML = window.icon(iconName);
            testToast.appendChild(document.createTextNode(" " + msg));
        } else {
            testToast.textContent = msg;
        }
        testToast.className = "macro-test-toast show"
            + (type === "error" ? " error-toast" : "")
            + (type === "success" ? " success-toast" : "");
        if (_testToastTimer) clearTimeout(_testToastTimer);
        _testToastTimer = setTimeout(function() {
            testToast.className = "macro-test-toast";
            _testToastTimer = null;
        }, type === "error" ? 5000 : 2500);
    }

    function _resetTestBtn() {
        testBtn.className = "macro-toolbar-btn";
        testBtn.innerHTML = menuLabel("play", "Test");
        testBtn.disabled = false;
        _testRunning = false;
    }

    testBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    testBtn.addEventListener("click", function() {
        if (_testRunning) return;
        var steps = _canvas.serialize();
        if (!steps || steps.length === 0) {
            if (window.playSlot) playSlot("back");
            showTestToast("No steps to run", "error");
            return;
        }
        if (window.playSlot) playSlot("interact");

        var macroId = _currentMacroId || ("_test_" + Date.now().toString(36));
        var macroDef = {
            id: macroId,
            name: nameInput.value.trim() || macroId,
            steps: steps,
        };

        _testRunning = true;
        testBtn.className = "macro-toolbar-btn running";
        testBtn.innerHTML = menuLabel("timer", "Running\u2026");
        testBtn.disabled = true;

        if (window.shellPost) {
            shellPost("macros", "testRun", macroDef);
        }

        setTimeout(function() {
            if (_testRunning) {
                _resetTestBtn();
                showTestToast("Test run timed out", "error");
            }
        }, 30000);
    });

    var _isRecording = false;
// END Test Run //

// Recording options //
    var _REC_OPTS_KEY = "ms.macroRecordOpts";
    var _recOptDefaults = {
        recordDelays:       true,
        pressMode:          "type",
        recordDrags:        true,
        dragGranularity:    5,
        recordMouseMoves:   false,
        moveGranularity:    5,
        recordMouseButtons: true,
        recordWindowMove:   false,
        recordWindowResize: false,
        waitThreshold:      50
    };
    var _recOpts = (function() {
        var o = {};
        for (var k in _recOptDefaults) o[k] = _recOptDefaults[k];
        try {
            var saved = JSON.parse(localStorage.getItem(_REC_OPTS_KEY) || "{}");
            for (var k2 in saved) if (k2 in o) o[k2] = saved[k2];
            if (o.pressMode === "press") o.pressMode = "pressRelease";
        } catch (e) {}
        return o;
    })();
    function _saveRecOpts() {
        try { localStorage.setItem(_REC_OPTS_KEY, JSON.stringify(_recOpts)); }
        catch (e) {}
    }

    function _setRecordingState(on) {
        _isRecording = on;
        if (on) {
            recordBtn.className = "macro-toolbar-btn recording";
            recordBtn.innerHTML = menuLabel("stop", "Stop");
            recordBtn.title = "Stop recording";
            showTestToast("Recording, perform actions, then click Stop\u2026", null, "record");
        } else {
            recordBtn.className = "macro-toolbar-btn";
            recordBtn.innerHTML = menuLabel("record", "Record");
            recordBtn.title = "Record user actions into tools";
        }
    }

    recordBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recordBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (!_isRecording) {
            if (window.shellPost) {
                shellPost("macros", "startRecording", {
                    waitThreshold: _recOpts.waitThreshold,
                    options: _recOpts
                });
            }
            _setRecordingState(true);
        } else {
            if (window.shellPost) {
                shellPost("macros", "stopRecording", {});
            }
            _setRecordingState(false);
            showTestToast("Recording stopped", "success");
        }
    });
// END Recording options //

// Recording settings menu //
    var _recModal = null;

    function _buildRecModal() {
        var overlayEl = document.createElement("div");
        overlayEl.className = "rec-settings-overlay";
        overlayEl.style.cssText =
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;" +
            "align-items:center;justify-content:center;z-index:320;opacity:0;" +
            "pointer-events:none;transition:opacity 0.2s;";

        var card = document.createElement("div");
        card.style.cssText =
            "background:var(--surface);border-top:2px solid var(--accent);" +
            "border-radius:var(--radius);padding:18px 20px;width:340px;" +
            "max-height:82vh;overflow-y:auto;box-shadow:0 16px 48px rgba(0,0,0,0.7)," +
            "0 0 0 1px var(--border);transform:scale(0.96);transition:transform 0.2s;";
        overlayEl.appendChild(card);

        var title = document.createElement("div");
        title.style.cssText = "font-size:14px;font-weight:700;margin-bottom:2px;";
        title.textContent = "Recording Settings";
        card.appendChild(title);

        var sub = document.createElement("div");
        sub.style.cssText = "font-size:11px;color:var(--text2);margin-bottom:14px;line-height:1.5;";
        sub.textContent = "Choose what a recording captures. Applied to the next recording you start.";
        card.appendChild(sub);

        function row(label, hint, control) {
            var r = document.createElement("div");
            r.style.cssText =
                "display:flex;align-items:center;justify-content:space-between;" +
                "gap:12px;padding:9px 0;border-bottom:1px solid var(--border-dim,var(--border));";
            var lwrap = document.createElement("div");
            lwrap.style.cssText = "min-width:0;flex:1;";
            var l = document.createElement("div");
            l.style.cssText = "font-size:12px;color:var(--text);";
            l.textContent = label;
            lwrap.appendChild(l);
            if (hint) {
                var h = document.createElement("div");
                h.style.cssText = "font-size:10px;color:var(--text3);margin-top:2px;line-height:1.4;";
                h.textContent = hint;
                lwrap.appendChild(h);
            }
            r.appendChild(lwrap);
            r.appendChild(control);
            card.appendChild(r);
            return r;
        }

        function toggle(key) {
            var wrap = document.createElement("label");
            wrap.className = "toggle";
            var input = document.createElement("input");
            input.type = "checkbox";
            input.checked = !!_recOpts[key];
            var track = document.createElement("span"); track.className = "toggle-track";
            var thumb = document.createElement("span"); thumb.className = "toggle-thumb";
            wrap.appendChild(input); wrap.appendChild(track); wrap.appendChild(thumb);
            input.addEventListener("change", function() {
                _recOpts[key] = input.checked;
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            return wrap;
        }

        function slider(key, min, max) {
            var wrap = document.createElement("div");
            wrap.style.cssText = "display:flex;align-items:center;gap:10px;";
            var input = document.createElement("input");
            input.type = "range";
            input.min = String(min); input.max = String(max); input.step = "1";
            input.value = String(_recOpts[key] != null ? _recOpts[key] : min);
            input.style.cssText = "flex:1;min-width:110px;accent-color:var(--accent);";
            var val = document.createElement("span");
            val.style.cssText = "font-size:12px;color:var(--text2);min-width:20px;text-align:right;font-variant-numeric:tabular-nums;";
            val.textContent = input.value;
            input.addEventListener("input", function() {
                val.textContent = input.value;
            });
            input.addEventListener("change", function() {
                _recOpts[key] = parseInt(input.value, 10);
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            wrap.appendChild(input);
            wrap.appendChild(val);
            return wrap;
        }

        function seg(key, opts) {
            var s = document.createElement("div");
            s.className = "seg";
            opts.forEach(function(o) {
                var b = document.createElement("button");
                b.className = "seg-btn" + (_recOpts[key] === o.value ? " active" : "");
                b.textContent = o.label;
                b.title = o.hint || "";
                b.addEventListener("click", function() {
                    _recOpts[key] = o.value;
                    _saveRecOpts();
                    if (window.playSlot) playSlot("interact");
                    Array.prototype.forEach.call(s.children, function(c) {
                        c.classList.remove("active");
                    });
                    b.classList.add("active");
                });
                b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
                s.appendChild(b);
            });
            return s;
        }

        row("Record delays", "Insert wait modules for idle gaps between actions.", toggle("recordDelays"));
        row("Key presses", "How keystrokes are captured.",
            seg("pressMode", [
                { value: "type",         label: "Type",    hint: "Full press+release keystroke (ms.type)" },
                { value: "pressRelease", label: "Press",   hint: "Separate press and release with real hold timing" }
            ]));
        row("Record mouse buttons", "Capture left/right/middle clicks.", toggle("recordMouseButtons"));
        row("Record mouse drags", "Capture press-move-release as a drag gesture.", toggle("recordDrags"));
        row("Drag fidelity", "How closely a recorded drag follows your real path. Lower is coarser; higher tracks curves near 1:1. The whole gesture stays one module either way.", slider("dragGranularity", 1, 10));
        row("Record mouse movement", "Capture free cursor motion (no button held) as moveMouse steps.", toggle("recordMouseMoves"));
        row("Movement fidelity", "How closely recorded movement follows your real path. Lower is coarser, higher tracks curves near 1:1.", slider("moveGranularity", 1, 10));
        row("Record window moves", "Capture moving the focused window.", toggle("recordWindowMove"));
        var lastRow =
        row("Record window resizes", "Capture resizing the focused window.", toggle("recordWindowResize"));
        lastRow.style.borderBottom = "none";

        var btns = document.createElement("div");
        btns.className = "modal-btns";
        btns.style.cssText = "display:flex;gap:8px;margin-top:16px;";
        var resetBtn = document.createElement("button");
        resetBtn.textContent = "Reset";
        resetBtn.style.cssText = "flex:0 0 auto;padding:8px 12px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--surface2);color:var(--text2);";
        var doneBtn = document.createElement("button");
        doneBtn.className = "primary";
        doneBtn.textContent = "Done";
        doneBtn.style.cssText = "flex:1;padding:8px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--accent);color:var(--bg);";
        btns.appendChild(resetBtn);
        btns.appendChild(doneBtn);
        card.appendChild(btns);

        function close() {
            overlayEl.style.opacity = "0";
            overlayEl.style.pointerEvents = "none";
            card.style.transform = "scale(0.96)";
        }
        resetBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        resetBtn.addEventListener("click", function() {
            for (var k in _recOptDefaults) _recOpts[k] = _recOptDefaults[k];
            _saveRecOpts();
            if (window.playSlot) playSlot("back");
            _recModal = null;
            card.remove(); overlayEl.remove();
            _openRecModal();
        });
        doneBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        doneBtn.addEventListener("click", function() { if (window.playSlot) playSlot("interact"); close(); });
        overlayEl.addEventListener("click", function(e) {
            if (e.target === overlayEl) { if (window.playSlot) playSlot("back"); close(); }
        });

        document.body.appendChild(overlayEl);
        _recModal = { overlay: overlayEl, card: card };
        return _recModal;
    }

    function _openRecModal() {
        var m = _recModal || _buildRecModal();
        m.overlay.getBoundingClientRect();
        m.overlay.style.opacity = "1";
        m.overlay.style.pointerEvents = "all";
        m.card.style.transform = "scale(1)";
    }

    recSettingsBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recSettingsBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        _openRecModal();
    });

    delMacroBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    delMacroBtn.addEventListener("click", function() {
        if (_currentMacroId) {
            if (window.playSlot) playSlot("back");
            deleteMacro();
        }
    });

    macroSelect.addEventListener("change", function() {
        var id = macroSelect.value;
        loadMacro(id);
    });

    nameInput.addEventListener("keydown", function(e) { e.stopPropagation(); });
    nameInput.addEventListener("input", function() {
        _macroDirty = true;
        updateSaveBtnState();
    });
// END Recording settings menu //

// Panel handler //
    var _libSelfHealed = false;
    window.registerPanel("macros", function(action, body) {
        if (!_libSelfHealed && window.msLibraryClient) {
            _libSelfHealed = true;
            window.msLibraryClient.request("macro");
        }
        if (window.fnPicker && window.fnPicker.handler) {
            window.fnPicker.handler(action, body);
        }
        if (action === "addTool" && body) {
            _canvas.addTool(body);
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (action === "macroList" && Array.isArray(body)) {
            setMacroList(body);
            return;
        }
        if (action === "macroDef" && body) {
            setMacroDef(body);
            return;
        }
        if (action === "macroSaved") {
            _macroDirty = false;
            updateSaveBtnState();
            refreshMacroList();
            refreshBindList();
            return;
        }
        if (action === "saveError") {
            _macroDirty = true;
            updateSaveBtnState();
            refreshMacroList();
            refreshBindList();
            showTestToast("\u2717 Save failed to compile: "
                + ((body && body.err) || "Unknown error"), "error");
            return;
        }
        if (action === "bindList" && Array.isArray(body)) {
            setBindList(body);
            return;
        }
        if (action === "packMeta" && body) {
            setMeta(body);
            return;
        }
        if (action === "setToolList" && Array.isArray(body)) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(body);
            }
            return;
        }
        if (action === "testRunResult" && body) {
            _resetTestBtn();
            if (body.ok) {
                testBtn.className = "macro-toolbar-btn success";
                showTestToast("\u2713 Macro ran successfully", "success");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 2500);
            } else {
                testBtn.className = "macro-toolbar-btn error";
                showTestToast("\u2717 " + (body.err || "Unknown error"), "error");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 5000);
            }
            return;
        }
        if (action === "recordStep" && body) {
            _canvas.addTool({ action: body.action, params: body.params });
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
    });
// END Panel handler //

// External API //
    window.macroLab = {
        canvas: _canvas,
        editor: _toolEditor,
        loadMacro: loadMacro,
        saveMacro: saveMacro,
        refreshList: refreshMacroList,
        setMacroList: setMacroList,
        setMacroDef: setMacroDef,
        setBindList: setBindList,
        refreshBinds: refreshBindList,
        focusSystemBinds: focusSystemBinds,
        setMeta: setMeta,
        refreshMeta: refreshMeta,
        addTool: function(def) { _canvas.addTool(def); closeFnOverlay(); },
        setToolList: function(list) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(list);
            }
            if (typeof window.renderToolVariablesTab === "function") {
                window.renderToolVariablesTab();
            }
        },
        setFunctionList: function(list) {
            window.msMacroFunctions = Array.isArray(list) ? list : [];
            if (window.fnPicker && window.fnPicker.setFunctionList) {
                window.fnPicker.setFunctionList(window.msMacroFunctions);
            }
            if (typeof window.renderToolFunctionsTab === "function") {
                window.renderToolFunctionsTab();
            }
        },
        createTool: function(def) {
            if (!window.shellPost) return;
            shellPost("macros", "addUserSetting", { action: "addUserSetting", def: def });
            setTimeout(refreshToolList, 250);
        },
        deleteTool: function(key) {
            if (!window.shellPost) return;
            shellPost("macros", "removeUserSetting", { action: "removeUserSetting", key: key });
            setTimeout(refreshToolList, 250);
        },
        testRun: function() { testBtn.click(); },
        startRecording: function() { if (!_isRecording) recordBtn.click(); },
        stopRecording: function() { if (_isRecording) recordBtn.click(); },
        isRecording: function() { return _isRecording; },
    };

    window.closePanel = function() {
        if (window.shellPost) shellPost("macros", "close", {});
    };

    window._macrosEnabled = window._macrosEnabled || false;
    window.updateMacrosToggleBtn = function(enabled) {
        window._macrosEnabled = !!enabled;
        var btn = document.getElementById("macrosEnabledToggle");
        if (!btn) return;
        btn.classList.toggle("active", !!enabled);
        btn.textContent = enabled ? "On" : "Off";
    };
    window.toggleMacrosEnabled = function() {
        if (window.shellPost) {
            shellPost("settings", "setMacros", {
                action: "setMacros",
                value: window._macrosEnabled ? 0 : 1,
            });
        }
    };

    updateSaveBtnState();
    refreshMacroList();
    refreshBindList();
    refreshMeta();
// END External API //

// Header drag //
    (function() {
        let _drag = null;
        const panel = document.querySelector(".panel-macros");
        if (!panel) return;
        const header = panel.querySelector("#header");
        if (!header) return;
        header.style.cursor = "-webkit-grab";
        header.addEventListener("mousedown", (e) => {
            if (e.button !== 0) return;
            if (e.target.closest(".header-btns")) return;
            _drag = { ox: e.screenX, oy: e.screenY };
            const onMove = (ev) => {
                if (!_drag) return;
                if (window.shellPost) {
                    shellPost("macros", "move", {
                        dx: ev.screenX - _drag.ox,
                        dy: ev.screenY - _drag.oy,
                    });
                }
                _drag.ox = ev.screenX;
                _drag.oy = ev.screenY;
            };
            const onUp = () => {
                _drag = null;
                window.removeEventListener("mousemove", onMove);
                window.removeEventListener("mouseup", onUp);
            };
            window.addEventListener("mousemove", onMove);
            window.addEventListener("mouseup", onUp);
        });
    })();
// END Header drag //
})();
