(function() {
    "use strict";

    var M = {};

    var _svgCache = window.msSvgCache;
    var _fetchSVG = window.msFetchSVG;
    var enumDefault = window.msMacroRegistry.enumDefault;

    M.currentMacroId = null;
    M.currentMacroDef = null;
    M.macroDirty = false;
    M.canvas = null;
    M.mtabs = null;

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
    window.msTextHints(nameInput);
    nameInput.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    nameInput.addEventListener("focus", function() {
        if (window.playSlot) playSlot("interact");
    });
    toolbar.appendChild(nameInput);

    var idChip = document.createElement("button");
    idChip.type = "button";
    idChip.className = "macro-id-chip";
    idChip.title = "Macro id, used by ms.bindstate(\"id\"). Click to copy.";

    var idText = document.createElement("span");
    idChip.appendChild(idText);

    idChip.appendChild(window.iconNode("copy", "icon-inline"));

    toolbar.appendChild(idChip);

    idChip.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });

    idChip.addEventListener("click", function() {
        var id = M.currentMacroId;

        if (!id) return;

        var viaHost = function() {
            if (typeof shellDispatch === "function") shellDispatch("_shell", "clipboard", { text: id });
        };

        try {
            navigator.clipboard.writeText(id).catch(viaHost);
        } catch (_) {
            viaHost();
        }

        if (window.playSlot) playSlot("update");
    });

    var _currentMacroId = M.currentMacroId || null;

    Object.defineProperty(M, "currentMacroId", {
        get: function() { return _currentMacroId; },
        set: function(v) {
            _currentMacroId = v;
            idText.textContent = v || "";
            idChip.style.display = v ? "" : "none";
        },
    });

    M.currentMacroId = _currentMacroId;

    var histSlot = document.createElement("div");
    histSlot.className = "macro-hist-slot";
    histSlot.style.cssText = "display:flex;gap:4px;margin-left:8px";
    toolbar.appendChild(histSlot);

    M.currentMacroClass = "main";
    M.currentMacroCooldown = null;
    M.currentMacroShared = "";

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
        b.className = "fn-bind-opt" + (M.currentMacroClass === value ? " on" : "");
        b.setAttribute("data-class", value);
        b.textContent = text;
        b.title = value === "main"
            ? "Main macro, grouped under VISUAL - MAIN"
            : "Optional macro, grouped under VISUAL - OPTIONAL";
        b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        b.addEventListener("click", function() {
            if (M.currentMacroClass === value) return;
            if (window.playSlot) playSlot("interact");
            setMacroClass(value);
            M.macroDirty = true;
            updateSaveBtnState();
        });
        return b;
    }
    classSeg.appendChild(buildClassOpt("main", "Main"));
    classSeg.appendChild(buildClassOpt("optional", "Optional"));
    toolbar.appendChild(classSeg);

    function setMacroClass(value) {
        M.currentMacroClass = (value === "optional") ? "optional" : "main";
        var opts = classSeg.querySelectorAll(".fn-bind-opt");
        opts.forEach(function(o) {
            o.classList.toggle("on", o.getAttribute("data-class") === M.currentMacroClass);
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
    overflowBtn.innerHTML = window.icon ? window.icon("ellipsis") : "...";
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
    function iconOnly(name) {
        return window.icon ? window.icon(name) : "";
    }

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
    window.msTextHints(cooldownInput);
    cooldownInput.addEventListener("input", function() {
        var raw = cooldownInput.value.trim();
        M.currentMacroCooldown = raw === "" ? null : Math.max(0, parseInt(raw, 10) || 0);
        M.macroDirty = true;
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
    window.msTextHints(sharedInput);
    sharedInput.addEventListener("input", function() {
        var clean = sharedInput.value.replace(/[^A-Za-z0-9_ -]/g, "");
        if (clean !== sharedInput.value) sharedInput.value = clean;
        M.currentMacroShared = clean.trim();
        M.macroDirty = true;
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

    var bindOptsBtn = document.createElement("button");
    bindOptsBtn.className = "macro-toolbar-btn";
    bindOptsBtn.innerHTML = menuLabel("keyboard", "Bind Options");
    bindOptsBtn.title = "Rebind, toggle, and link this macro";
    overflowMenu.appendChild(bindOptsBtn);

    var testBtn = document.createElement("button");
    testBtn.className = "macro-toolbar-btn macro-icon-btn";
    testBtn.innerHTML = iconOnly("play");
    testBtn.title = "Hide mudscript, run the macro, then come back";

    var recordRow = document.createElement("div");
    recordRow.className = "macro-record-row";
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = menuLabel("record", "Record");
    recordBtn.title = "Record user actions into modules";
    recordRow.appendChild(recordBtn);

    var recSettingsBtn = document.createElement("button");
    recSettingsBtn.className = "macro-toolbar-btn macro-record-settings-btn";
    recSettingsBtn.innerHTML = window.icon ? window.icon("ellipsis") : "...";
    recSettingsBtn.title = "Recording settings";
    recSettingsBtn.setAttribute("aria-label", "Recording settings");
    recordRow.appendChild(recSettingsBtn);

    overflowMenu.appendChild(recordRow);

    var collapseAllBtn = document.createElement("button");
    collapseAllBtn.className = "macro-toolbar-btn";
    collapseAllBtn.innerHTML = menuLabel("chevup", "Collapse All");
    collapseAllBtn.title = msKeyLabel("Collapse every container (Cmd+[)");
    overflowMenu.appendChild(collapseAllBtn);

    var expandAllBtn = document.createElement("button");
    expandAllBtn.className = "macro-toolbar-btn";
    expandAllBtn.innerHTML = menuLabel("chevdown", "Expand All");
    expandAllBtn.title = msKeyLabel("Expand every container (Cmd+])");
    overflowMenu.appendChild(expandAllBtn);

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
    addToolBtn.innerHTML = (_svgCache["plus"] || "+") + " Add Module";
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
    M.metaLoaded  = false;
    M.metaDirty   = false;
    M.metaOwned   = false;

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
            if (M.metaLoaded) { M.metaDirty = true; updateMetaSaveBtn(); }
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
        if (!M.metaDirty) return;
        if (window.shellPost) {
            shellPost("macros", "setMeta", {
                name:    _metaName.input.value.trim(),
                version: _metaVersion.input.value.trim(),
                author:  _metaAuthor.input.value.trim(),
                website: _metaWebsite.input.value.trim(),
            });
        }
        M.metaDirty = false;
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

    var targetSelect = window.createSelect({
        className: "input-sm",
        minWidth: 180,
        searchable: true,
        searchPlaceholder: "Search apps",
        options: [{ value: "", label: "None" }],
        value: "",
        onChange: function(v) {
            if (window.shellPost) shellPost("macros", "setTargetApp", { name: v || null });
        },
    });
    var targetRow = _kit.row("Target App", "Binds only fire while this app is focused", targetSelect);
    var targetCard = _kit.section("macro-target", "Target App", function(body) {
        body.appendChild(targetRow);
    }, "The app your macros drive");
    var targetDesc = targetCard.querySelector(".section-desc");
    bindsScroll.insertBefore(targetCard, bindList);

    M.macroLib = [];
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

        if (!M.macroLib.length) {
            packList.appendChild(kit.h("div", { cls: "theme-note" },
                "Nothing here yet. Install a macro pack from Browse, or save "
                + "your current one below."));
            return;
        }

        for (var i = 0; i < M.macroLib.length; i++) {
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
                }, iconNode("ellipsis"));
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
            })(M.macroLib[i]);
        }
    }

    if (window.msLibraryClient) {
        window.msLibraryClient.on("macro", function(entries) {
            M.macroLib = entries || [];
            fillMacroLib();
        });
        window.msLibraryClient.request("macro");
    }

    function updateMetaSaveBtn() {
        var on = M.metaDirty && !M.metaOwned;
        metaSaveBtn.disabled = !on;
        metaSaveBtn.style.opacity = on ? "1" : "0.5";
    }
    updateMetaSaveBtn();

    function refreshMeta() {
        if (window.shellPost) {
            shellPost("macros", "getMeta", {});
            shellPost("macros", "getTargetApp", {});
        }
    }

    function setTargetApp(state) {
        state = state || {};
        var opts = [{ value: "", label: "None" }];
        (state.options || []).forEach(function(n) { opts.push({ value: n, label: n }); });
        targetSelect.setOptions(opts);
        targetSelect.value = state.current || "";
        var declared = !!state.declared;
        targetSelect.classList.toggle("meta-input-locked", declared);
        targetSelect.style.pointerEvents = declared ? "none" : "";
        targetDesc.textContent = declared
            ? "Declared in your handwritten ms_macros.lua (read-only)"
            : "The app your macros drive";
    }

    function setMeta(meta) {
        meta = meta || {};
        M.metaLoaded = false;
        _metaName.input.value    = meta.name    || "";
        _metaVersion.input.value = meta.version || "";
        _metaAuthor.input.value  = meta.author  || "";
        _metaWebsite.input.value = meta.website || "";
        M.metaLoaded = true;
        M.metaDirty  = false;

        M.metaOwned = meta.owned === true;
        var locked = meta.locked || {};
        var anyLocked = false;
        [
            [_metaName, "name"],
            [_metaVersion, "version"],
            [_metaAuthor, "author"],
            [_metaWebsite, "website"],
        ].forEach(function(pair) {
            var isLocked = locked[pair[1]] === true;
            if (isLocked) anyLocked = true;
            pair[0].input.readOnly = isLocked;
            pair[0].input.classList.toggle("meta-input-locked", isLocked);
            pair[0].input.title = isLocked ? "Set in your handwritten ms_macros.lua" : "";
        });
        if (M.metaOwned)
            metaDesc.textContent = "Sourced from your handwritten ms_macros.lua (read-only)";
        else if (anyLocked)
            metaDesc.textContent = "Greyed fields come from your handwritten ms_macros.lua";
        else
            metaDesc.textContent = "Credits baked into your visual macros (ms.macroMeta)";
        metaSaveRow.style.display = M.metaOwned ? "none" : "";
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
            if (M.mtabs) M.mtabs.switch(id);
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
    M.mtabs = window.createTabs && window.createTabs({
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
            } else if (tab === "builder" && M.canvas) {
                requestAnimationFrame(function() {
                    requestAnimationFrame(function() { M.canvas._updateParamMarquee(); });
                });
            }
        },
    });
// END Shared tab model //

// Tool Canvas instance //
    M.canvas = new ToolCanvas(canvasContainer, {
        onChange: function(steps) {
            M.macroDirty = true;
            updateSaveBtnState();
        },
        onSelect: function(sid, step) {
            if (!M.toolEditor) return;
            if (M.toolEditor._open && (!sid || M.toolEditor._toolSid !== sid)) {
                M.toolEditor.close();
            }
        },
        onContext: function(sid) {
            if (!M.toolEditor || !sid) return;
            if (M.toolEditor._open && M.toolEditor._toolSid === sid) {
                M.toolEditor.close();
            } else {
                M.toolEditor.open(sid);
            }
        }
    });
    window.addEventListener("ms:padtype", function() { M.canvas._render(); });
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
        M.canvas.defFor = buildDefaultDef;
        function beforeSidAt(clientY) {
            var root = M.canvas._root;
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
            M.canvas._root.classList.add("fn-drop-target");
        }, true);
        canvasContainer.addEventListener("dragleave", function(e) {
            if (!hasFn(e)) return;
            if (e.target === canvasContainer || !canvasContainer.contains(e.relatedTarget)) {
                M.canvas._root.classList.remove("fn-drop-target");
            }
        }, true);
        canvasContainer.addEventListener("drop", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            M.canvas._root.classList.remove("fn-drop-target");
            var def = null;
            if (hasType(e, TOOL_MIME)) {
                def = buildToolDef(e.dataTransfer.getData(TOOL_MIME));
            } else if (hasType(e, CALLFN_MIME)) {
                def = buildCallFnDef(e.dataTransfer.getData(CALLFN_MIME));
            } else {
                def = buildDefaultDef(e.dataTransfer.getData(FN_MIME));
            }
            if (!def) return;
            M.canvas.insertDefAt(def, beforeSidAt(e.clientY));
            M.macroDirty = true;
            updateSaveBtnState();
            if (window.playSlot) playSlot("interact");
            closeFnOverlay();
        }, true);
    })();
// END Picker //

// Tool keyboard shortcuts //
    function pasteNow(inside) {
        if (!(inside && M.canvas.pasteInside())) M.canvas.pasteAfter();
        M.macroDirty = true;
        updateSaveBtnState();
    }

    function syncClipboard() {
        if (window.shellPost) shellPost("macros", "readClipboard", {});
    }

    canvasContainer.addEventListener("mousedown", syncClipboard, true);

    canvasContainer.addEventListener("contextmenu", syncClipboard, true);

    document.addEventListener("keydown", function(e) {
        if (!builderSection.classList.contains("active")) return;
        var mod = msMod(e);
        if (mod && !e.shiftKey && (e.key === "s" || e.key === "S")) {
            e.preventDefault();
            if (M.macroDirty && window.playSlot) playSlot("interact");
            saveMacro();
            return;
        }
        if (mod && !e.shiftKey && (e.key === "n" || e.key === "N")) {
            e.preventDefault();
            newBtn.click();
            return;
        }
        if (mod && !e.shiftKey && (e.key === "f" || e.key === "F")) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            var wasOpen = overlay.classList.contains("open");
            openFnOverlay();
            if (!window.fnPicker || !window.fnPicker.focusSearch) return;
            if (wasOpen) {
                window.fnPicker.focusSearch();
                return;
            }
            var focused = false;
            var focusOnce = function() {
                if (focused) return;
                focused = true;
                overlay.removeEventListener("transitionend", focusOnce);
                window.fnPicker.focusSearch();
            };
            overlay.addEventListener("transitionend", focusOnce);
            setTimeout(focusOnce, 300);
            return;
        }
        var t = e.target;
        if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
        var hk = _history && window.msHistoryKey(e);
        if (hk) {
            e.preventDefault();
            if (_history[hk]() && window.playSlot) playSlot("interact");
            return;
        }
        if (mod && (e.key === "a" || e.key === "A")) {
            e.preventDefault();
            M.canvas.selectAll();
            return;
        }
        if (mod && (e.key === "v" || e.key === "V")) {
            e.preventDefault();
            if (window.shellPost) {
                shellPost("macros", "readClipboard", {
                    inside: e.shiftKey,
                    paste: true,
                });
            } else {
                pasteNow(e.shiftKey);
            }
            return;
        }
        if (mod && !e.shiftKey && (e.key === "[" || e.key === "]")) {
            e.preventDefault();
            if (M.canvas.setAllCollapsed(e.key === "[") && window.playSlot) playSlot("interact");
            return;
        }
        if (e.key === "Escape" && M.canvas.hasSelection()) {
            e.preventDefault();
            M.canvas.clearSelection();
            return;
        }
        if (!M.canvas.hasSelection()) return;
        if (mod && (e.key === "c" || e.key === "C")) {
            e.preventDefault();
            M.canvas.copySelected();
        } else if (mod && (e.key === "x" || e.key === "X")) {
            e.preventDefault();
            M.canvas.cutSelected();
            M.macroDirty = true;
            updateSaveBtnState();
        } else if (mod && e.shiftKey && (e.key === "g" || e.key === "G")) {
            e.preventDefault();
            if (M.canvas.unwrapSelected() && window.playSlot) playSlot("interact");
        } else if (mod && (e.key === "d" || e.key === "g")) {
            e.preventDefault();
            if (e.key === "d") M.canvas.duplicateSelected();
            else M.canvas.openWrapMenu();
        } else if (e.altKey && !mod && (e.key === "ArrowUp" || e.key === "ArrowDown")) {
            e.preventDefault();
            if (M.canvas.stepSelection(e.key === "ArrowUp" ? -1 : 1) && window.playSlot) playSlot("interact");
        } else if (e.key === "Delete" || e.key === "Backspace") {
            e.preventDefault();
            M.canvas.removeSelected();
            M.macroDirty = true;
            updateSaveBtnState();
        }
    });

    var _history = window.createHistory && window.createHistory({
        limit: 256,
        capture: function() {
            return {
                steps: M.canvas.serialize(),
                cls: M.currentMacroClass,
                cooldown: M.currentMacroCooldown,
                shared: M.currentMacroShared,
            };
        },
        restore: function(snap) {
            if (M.toolEditor && M.toolEditor._open) M.toolEditor.close();
            M.canvas.load(snap.steps);
            setMacroClass(snap.cls);
            M.currentMacroCooldown = snap.cooldown;
            cooldownInput.value = snap.cooldown != null ? String(snap.cooldown) : "";
            M.currentMacroShared = snap.shared;
            sharedInput.value = snap.shared;
            M.macroDirty = true;
            updateSaveBtnState();
        },
    });
    if (_history) {
        _history.reset();
        var histBtns = window.msHistoryButtons(_history, "macro-toolbar-btn");
        [histBtns.undo, histBtns.redo].forEach(function(b) {
            var label = b.querySelector("span");
            if (label) label.remove();
            b.classList.add("macro-icon-btn");
            histSlot.appendChild(b);
        });
    }
    histSlot.appendChild(testBtn);

    M.toolEditor = null;
    if (window.ToolEditor) {
        M.toolEditor = new ToolEditor({ canvas: M.canvas });
    } else {
        console.warn("[macros] ToolEditor not loaded, inline editing disabled");
    }

    _fetchSVG("plus").then(function(svg) {
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

    M.bindList = [];

    function refreshBindList() {
        if (window.shellPost) shellPost("macros", "listBinds", {});
    }
// END Fn //

// Bind list and saving //
    var _binds = window.msMacroBinds({
        M: M,
        macroSelect: macroSelect,
        nameInput: nameInput,
        setMacroClass: setMacroClass,
        classFromGroup: classFromGroup,
        saveBtn: saveBtn,
        cooldownInput: cooldownInput,
        sharedInput: sharedInput,
        bindOptsBtn: bindOptsBtn,
        bindList: bindList,
        _history: _history,
        refreshMacroList: refreshMacroList,
        refreshBindList: refreshBindList,
        showTestToast: function() { return showTestToast.apply(null, arguments); },
    });

    var focusSystemBinds = _binds.focusSystemBinds;

    var setBindList = _binds.setBindList;

    var setMacroList = _binds.setMacroList;

    var loadMacro = _binds.loadMacro;

    var setMacroDef = _binds.setMacroDef;

    var saveMacro = _binds.saveMacro;

    var deleteMacro = _binds.deleteMacro;

    var updateSaveBtnState = _binds.updateSaveBtnState;
// END Bind list and saving //

// Wire toolbar buttons //
    newBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    newBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (M.macroDirty && M.currentMacroId) saveMacro();
        var taken = M.macroIds || [];
        var n = 1;
        while (taken.indexOf("New_Macro_" + n) !== -1) n++;
        M.currentMacroId = "New_Macro_" + n;
        M.currentMacroDef = null;
        M.canvas.load([]);
        nameInput.value = "New Macro " + n;
        nameInput.focus();
        nameInput.select();
        setMacroClass("main");
        M.currentMacroCooldown = null;
        cooldownInput.value = "";
        M.currentMacroShared = "";
        sharedInput.value = "";
        if (_history) _history.reset();
        M.macroIds = taken.concat([M.currentMacroId]);
        M.macroDirty = true;
        saveMacro();
    });

    saveBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    saveBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        saveMacro();
    });

    [collapseAllBtn, expandAllBtn].forEach(function(b) {
        b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        b.addEventListener("click", function() {
            if (window.playSlot) playSlot("interact");
            M.canvas.setAllCollapsed(b === collapseAllBtn);
        });
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

// Test Run and Recording //
    var _record = window.msMacroRecord({
        M: M,
        nameInput: nameInput,
        iconOnly: iconOnly,
        menuLabel: menuLabel,
        testBtn: testBtn,
        recordBtn: recordBtn,
        recSettingsBtn: recSettingsBtn,
        testToast: testToast,
    });

    var showTestToast = _record.showTestToast;

    var _resetTestBtn = _record._resetTestBtn;

    var _setRecordingState = _record._setRecordingState;
// END Test Run and Recording //

// Delete, select and rename wiring //
    delMacroBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    delMacroBtn.addEventListener("click", function() {
        if (M.currentMacroId) {
            if (window.playSlot) playSlot("back");
            deleteMacro();
        }
    });

    macroSelect.addEventListener("change", function() {
        var id = macroSelect.value;
        loadMacro(id);
    });

    nameInput.addEventListener("keydown", function(e) {
        var mod = msMod(e);
        if (mod && !e.shiftKey && /^[sfn]$/i.test(e.key)) return;
        e.stopPropagation();
    });
    nameInput.addEventListener("input", function() {
        M.macroDirty = true;
        updateSaveBtnState();
    });
// END Delete, select and rename wiring //

// Panel handler //
    M.libSelfHealed = false;
    window.registerPanel("macros", function(action, body) {
        if (!M.libSelfHealed && window.msLibraryClient) {
            M.libSelfHealed = true;
            window.msLibraryClient.request("macro");
        }
        if (window.fnPicker && window.fnPicker.handler) {
            window.fnPicker.handler(action, body);
        }
        if (action === "addTool" && body) {
            M.canvas.addTool(body);
            M.macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (action === "clipboardText" && body) {
            M.canvas.adoptClipboardText(body.text);
            if (body.paste) pasteNow(body.inside);
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
            M.macroDirty = false;
            updateSaveBtnState();
            refreshMacroList();
            refreshBindList();
            return;
        }
        if (action === "profileSwitched") {
            loadMacro(null);
            macroSelect.value = "";
            refreshMacroList();
            refreshBindList();
            refreshToolList();
            refreshMeta();
            return;
        }
        if (action === "saveError") {
            M.macroDirty = true;
            updateSaveBtnState();
            refreshMacroList();
            refreshBindList();
            showTestToast("Save failed to compile: "
                + ((body && body.err) || "Unknown error"), "error", "close");
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
            if (M.testFromPad && window.gpSetFocus) {
                testBtn.dataset.gpBack = ".tool-block[data-sid]";
                window.gpSetFocus(testBtn);
            }
            M.testFromPad = false;
            if (body.ok) {
                testBtn.className = "macro-toolbar-btn macro-icon-btn success";
                showTestToast("Macro ran successfully", "success", "check");
                setTimeout(function() {
                    if (!M.testRunning) testBtn.className = "macro-toolbar-btn macro-icon-btn";
                }, 2500);
            } else {
                testBtn.className = "macro-toolbar-btn macro-icon-btn error";
                showTestToast(body.err || "Unknown error", "error", "close");
                setTimeout(function() {
                    if (!M.testRunning) testBtn.className = "macro-toolbar-btn macro-icon-btn";
                }, 5000);
            }
            return;
        }
        if (action === "recordStopped") {
            _setRecordingState(false);
            showTestToast("Recording stopped", "success", "check");
            overflowWrap.classList.add("open");
            if (M.recordFromPad && window.gpSetFocus) window.gpSetFocus(recordBtn);
            M.recordFromPad = false;
            return;
        }
        if (action === "recordStep" && body) {
            M.canvas.addTool({ action: body.action, params: body.params });
            M.macroDirty = true;
            updateSaveBtnState();
            return;
        }
    });
// END Panel handler //

// External API //
    window.macroLab = {
        canvas: M.canvas,
        editor: M.toolEditor,
        loadMacro: loadMacro,
        saveMacro: saveMacro,
        refreshList: refreshMacroList,
        setMacroList: setMacroList,
        setMacroDef: setMacroDef,
        setBindList: setBindList,
        refreshBinds: refreshBindList,
        focusSystemBinds: focusSystemBinds,
        setMeta: setMeta,
        setTargetApp: setTargetApp,
        refreshMeta: refreshMeta,
        addTool: function(def) { M.canvas.addTool(def); closeFnOverlay(); },
        setToolList: function(list) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(list);
            }
            if (typeof window.renderToolVariablesTab === "function") {
                window.renderToolVariablesTab();
            }
        },
        setPluginBlocks: function(list) {
            if (window.fnPicker && window.fnPicker.setPluginBlocks) {
                window.fnPicker.setPluginBlocks(list);
            }
        },
        setFunctionList: function(list) {
            window.msMacroFunctions = Array.isArray(list) ? list : [];
            if (window.renderPluginsPanel) window.renderPluginsPanel();
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
        startRecording: function() { if (!M.isRecording) recordBtn.click(); },
        stopRecording: function() { if (M.isRecording) recordBtn.click(); },
        isRecording: function() { return M.isRecording; },
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
