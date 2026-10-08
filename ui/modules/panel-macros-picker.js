(function() {
    "use strict";

        const { REGISTRY, MOD_LIST, BINDABLE, enumDefault } = window.msMacroRegistry;

        var _selectedId  = null;
        var _paramValues = {};
        var _paramBind   = {};
        var _modState    = {};
        var _keyCapture  = null;
        var _toastTimer  = null;
        var _tools       = [];
        var _fnList      = [];
        var _view        = "module";

        var _profilesData = [];
        var _packData     = { macro: [], theme: [], sound: [] };
        var _choiceSelects = [];

        if (window.msProfilesClient) {
            window.msProfilesClient.subscribe(function(entries) {
                _profilesData = entries || [];
                refillChoiceSelects();
            });
        }
        if (window.msLibraryClient && window.msLibraryClient.subscribe) {
            ["macro", "theme", "sound"].forEach(function(kind) {
                window.msLibraryClient.subscribe(kind, function(entries) {
                    _packData[kind] = entries || [];
                    refillChoiceSelects();
                });
            });
        }

        function requestChoiceData(fn) {
            var wantProfiles = false, wantKinds = {};
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                if (p.type !== "choice") continue;
                if (p.source === "profiles") wantProfiles = true;
                else if (p.source === "macros" && window.shellPost) shellPost("macros", "listBinds", {});
                else if (p.source === "pack") {
                    ["macro", "theme", "sound"].forEach(function(k) { wantKinds[k] = true; });
                }
            }
            if (wantProfiles && window.msProfilesClient) window.msProfilesClient.request();
            if (window.msLibraryClient) {
                Object.keys(wantKinds).forEach(function(k) { window.msLibraryClient.request(k); });
            }
        }

        var slot = document.getElementById("slot-macros");
        if (!slot) return;

        var root = document.createElement("div");
        root.className = "fn-picker";

    // Left //
        var listPane = document.createElement("div");
        listPane.className = "fn-picker-list";

        var searchBox = document.createElement("div");
        searchBox.className = "fn-picker-search";
        var searchInput = document.createElement("input");
        searchInput.type = "text";
        searchInput.placeholder = "Search modules...";
        window.msTextHints(searchInput);
        searchBox.appendChild(searchInput);
        listPane.appendChild(searchBox);

        var entriesDiv = document.createElement("div");
        entriesDiv.className = "fn-picker-entries";
        listPane.appendChild(entriesDiv);

        var detailPane = document.createElement("div");
        detailPane.className = "fn-picker-detail";
        detailPane.innerHTML = '<div class="fn-detail-empty"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>Select a module from the list</div>';

        root.appendChild(listPane);
        root.appendChild(detailPane);
        slot.appendChild(root);

        var toast = document.createElement("div");
        toast.className = "fn-toast";
        document.body.appendChild(toast);
    // END Left //

    // Render Function List //
        var _catCollapsed = {};

        function makeEntryRow(fn) {
            var row = document.createElement("div");
            row.className = "fn-entry" + (_selectedId === fn.id ? " active" : "");
            row.setAttribute("data-fn-id", fn.id);

            var sigSpan = document.createElement("span");
            sigSpan.className = "fn-entry-sig";
            sigSpan.textContent = fn.label || fn.name;
            row.appendChild(sigSpan);

            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-fn", fn.id);
                e.dataTransfer.setData("text/plain", fn.name);
            });

            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                selectFunction(fn.id);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            return row;
        }
    // END Render Function List //

    // Build one draggable tool row //
        function makeToolRow(t) {
            var row = document.createElement("div");
            row.className = "fn-entry fn-tool-entry"
                + (_view === "tool" && _selectedId === t.key ? " active" : "");
            row.setAttribute("data-tool-key", t.key);

            var sig = document.createElement("span");
            sig.className = "fn-entry-sig";
            sig.textContent = t.label || t.key;
            row.appendChild(sig);

            var tag = document.createElement("span");
            tag.className = "fn-tool-tag fn-tool-tag-" + (t.source || "pack");
            tag.textContent = t.type;
            row.appendChild(tag);

            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-tool", t.key);
                e.dataTransfer.setData("text/plain", t.label || t.key);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                selectTool(t.key);
            });
            return row;
        }
    // END Build one draggable tool row //

    // Build one draggable function row //
        function makeFnCallRow(fn) {
            var id  = fn.id || fn.name;
            var row = document.createElement("div");
            row.className = "fn-entry fn-tool-entry";
            row.setAttribute("data-fn-call", id);

            var sig = document.createElement("span");
            sig.className = "fn-entry-sig";
            sig.textContent = fn.name || id;
            row.appendChild(sig);

            var tag = document.createElement("span");
            tag.className = "fn-tool-tag fn-tool-tag-" + (fn.source || "builder");
            tag.textContent = "function";
            row.appendChild(tag);

            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-callfn", id);
                e.dataTransfer.setData("text/plain", fn.name || id);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                if (window.macroLab && window.macroLab.addTool) {
                    window.macroLab.addTool({ action: "call_fn", params: { name: id } });
                }
            });
            return row;
        }
    // END Build one draggable function row //

    // Group tools by their section into collapsible headings //
        function renderToolsGroup(filter, searching) {
            var q = (filter || "").toLowerCase();
            var matches = _tools.filter(function(t) {
                if (!q) return true;
                return (t.label || "").toLowerCase().indexOf(q) !== -1
                    || (t.key || "").toLowerCase().indexOf(q) !== -1
                    || (t.section || "").toLowerCase().indexOf(q) !== -1
                    || "tool".indexOf(q) !== -1;
            });
            var fnMatches = _fnList.filter(function(f) {
                if (!q) return true;
                return (String(f.name || f.id)).toLowerCase().indexOf(q) !== -1
                    || "function tool".indexOf(q) !== -1;
            });
            var blockMatches = REGISTRY.filter(function(fn) {
                if (!fn.plugin) return false;
                if (!q) return true;
                return fn.label.toLowerCase().indexOf(q) !== -1
                    || fn.desc.toLowerCase().indexOf(q) !== -1
                    || fn.category.toLowerCase().indexOf(q) !== -1;
            });
            var searchingTools = q && "tool".indexOf(q) === -1
                && "function".indexOf(q) === -1;

            if (matches.length === 0 && fnMatches.length === 0 && blockMatches.length === 0) {
                if (searchingTools) return;
                renderToolSection("tools", [], [], filter, searching, true);
                return;
            }

            var order = [];
            var groups = {};
            matches.forEach(function(t) {
                var s = (t.section && String(t.section)) || "tools";
                if (!groups[s]) { groups[s] = []; order.push(s); }
                groups[s].push(t);
            });
            var blockGroups = {};
            blockMatches.forEach(function(fn) {
                var s = fn.category;
                if (!groups[s]) { groups[s] = []; order.push(s); }
                (blockGroups[s] = blockGroups[s] || []).push(fn);
            });
            if (fnMatches.length && !groups["tools"]) { groups["tools"] = []; order.push("tools"); }
            if (groups["tools"]) {
                order = ["tools"].concat(order.filter(function(s) { return s !== "tools"; }));
            }
            order.forEach(function(s) {
                renderToolSection(s, groups[s], s === "tools" ? fnMatches : [], filter, searching, false, blockGroups[s]);
            });
        }
    // END Group tools by their section into collapsible headings //

    // Render one Tools sub //
        function renderToolSection(section, rows, fns, filter, searching, emptyHint, blocks) {
            fns = fns || [];
            blocks = blocks || [];
            var key = "__tools:" + section;
            var collapsed = searching ? false : (_catCollapsed[key] !== false);

            var head = document.createElement("div");
            head.className = "fn-cat-head fn-cat-tools" + (collapsed ? " collapsed" : "");

            var chev = document.createElement("span");
            chev.className = "fn-cat-chev";
            chev.innerHTML = (typeof window.icon === "function"
                && window.ICONS && window.ICONS.chevdown)
                ? window.icon("chevdown") : "";
            head.appendChild(chev);

            var name = document.createElement("span");
            name.className = "fn-cat-name";
            name.textContent = section;
            head.appendChild(name);

            var count = document.createElement("span");
            count.className = "fn-cat-count";
            count.textContent = String(rows.length + fns.length + blocks.length);
            head.appendChild(count);

            head.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            if (!searching) {
                head.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    _catCollapsed[key] = !(_catCollapsed[key] !== false);
                    renderList(filter);
                });
            }
            var group = document.createElement("div");
            group.className = "fn-cat";
            group.appendChild(head);
            entriesDiv.appendChild(group);

            if (collapsed) return;

            rows.forEach(function(t) { group.appendChild(makeToolRow(t)); });
            fns.forEach(function(f) { group.appendChild(makeFnCallRow(f)); });
            blocks.forEach(function(fn) { group.appendChild(makeEntryRow(fn)); });

            if (emptyHint && rows.length === 0 && fns.length === 0) {
                var hint = document.createElement("div");
                hint.className = "fn-entry fn-tool-hint";
                hint.innerHTML = '<span class="fn-entry-sig">No tools, add one in the Tools panel</span>';
                group.appendChild(hint);
            }
        }

        function renderList(filter) {
            entriesDiv.innerHTML = "";
            var q = (filter || "").toLowerCase();
            var searching = q.length > 0;

            renderToolsGroup(filter, searching);

            var order = [];
            var groups = {};
            for (var i = 0; i < REGISTRY.length; i++) {
                var fn = REGISTRY[i];
                if (fn.plugin) continue;
                if (q && fn.name.toLowerCase().indexOf(q) === -1
                       && (fn.label || "").toLowerCase().indexOf(q) === -1
                       && fn.desc.toLowerCase().indexOf(q) === -1
                       && fn.category.toLowerCase().indexOf(q) === -1) {
                    continue;
                }
                var c = fn.category || "other";
                if (!groups[c]) { groups[c] = []; order.push(c); }
                groups[c].push(fn);
            }

            order.forEach(function(cat) {
                var collapsed = searching ? false : (_catCollapsed[cat] !== false);

                var head = document.createElement("div");
                head.className = "fn-cat-head" + (collapsed ? " collapsed" : "");

                var chev = document.createElement("span");
                chev.className = "fn-cat-chev";
                chev.innerHTML = (typeof window.icon === "function"
                    && window.ICONS && window.ICONS.chevdown)
                    ? window.icon("chevdown") : "";
                head.appendChild(chev);

                var name = document.createElement("span");
                name.className = "fn-cat-name";
                name.textContent = cat;
                head.appendChild(name);

                var count = document.createElement("span");
                count.className = "fn-cat-count";
                count.textContent = String(groups[cat].length);
                head.appendChild(count);

                head.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                if (!searching) {
                    head.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        _catCollapsed[cat] = !(_catCollapsed[cat] !== false);
                        renderList(filter);
                    });
                }
                var group = document.createElement("div");
                group.className = "fn-cat";
                group.appendChild(head);
                entriesDiv.appendChild(group);

                if (!collapsed) {
                    groups[cat].forEach(function(fn) {
                        group.appendChild(makeEntryRow(fn));
                    });
                }
            });
        }
    // END Render one Tools sub //

    // Select Function //
        function selectFunction(id) {
            _selectedId = id;
            _view = "module";
            _paramValues = {};
            _paramBind = {};
            _modState = {};
            _keyCapture = null;

            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active", items[i].getAttribute("data-fn-id") === id);
            }

            var fn = null;
            for (var j = 0; j < REGISTRY.length; j++) {
                if (REGISTRY[j].id === id) { fn = REGISTRY[j]; break; }
            }
            if (!fn) return;

            for (var k = 0; k < fn.params.length; k++) {
                var p = fn.params[k];
                if (p.type === "mods") {
                    _paramValues[p.name] = [];
                    _modState = { ctrl: false, alt: false, shift: false, cmd: false };
                } else if (p.type === "number") {
                    _paramValues[p.name] = p.default != null ? p.default : 0;
                } else if (p.type === "boolean") {
                    _paramValues[p.name] = false;
                } else if (p.type === "enum") {
                    _paramValues[p.name] = enumDefault(p);
                } else {
                    _paramValues[p.name] = "";
                }
            }

            renderDetail(fn);
        }

        function findTool(key) {
            for (var i = 0; i < _tools.length; i++) {
                if (_tools[i].key === key) return _tools[i];
            }
            return null;
        }
    // END Select Function //

    // Canvas step for a tool reference //
        function settingDefFor(t) {
            return {
                action: "setting",
                params: { key: t.key, label: t.label || t.key, type: t.type },
            };
        }

        function selectTool(key) {
            _view = "tool";
            _selectedId = key;
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active",
                    items[i].getAttribute("data-tool-key") === key);
            }
            renderToolDetail(findTool(key));
        }

        function renderToolDetail(t) {
            if (!t) { detailPane.innerHTML = ''; return; }
            var html = '';
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(t.label || t.key) + '</div>';
            html += '<div class="fn-detail-desc">'
                + esc(t.hint || 'A ' + t.type + ' tool. Wire it into a module parameter to read its value live.')
                + '</div>';
            html += '</div>';

            html += '<div class="fn-detail-body"><div class="fn-params">';
            html += toolMetaRow("Key", t.key);
            html += toolMetaRow("Type", t.type);
            html += toolMetaRow("Source",
                t.source === "builder" ? "Authored here" : "Declared in the pack");
            if (t.type === "slider") {
                html += toolMetaRow("Range", (t.min != null ? t.min : "?")
                    + " - " + (t.max != null ? t.max : "?")
                    + (t.step ? " (step " + t.step + ")" : ""));
            }
            if (t.type === "seg" && t.options) {
                var labels = t.options.map(function(o) { return o.label; }).join(", ");
                html += toolMetaRow("Options", labels);
            }
            if (t.default !== undefined && t.default !== null && t.default !== "") {
                html += toolMetaRow("Default", String(t.default));
            }
            html += '<div class="fn-tool-usehint">Reads as <code>ms.settings.get("'
                + esc(t.key) + '")</code>. To use it, add a module and switch any '
                + 'value field to <b>Tool</b>, then pick this.</div>';
            html += '</div></div>';

            html += '<div class="fn-detail-footer">';
            html += '<button class="fn-add-btn" id="fn-tool-add">Add to Macro</button>';
            if (t.source === "builder") {
                html += '<button class="fn-add-btn fn-tool-delete" id="fn-tool-delete">Delete Tool</button>';
            }
            html += '</div>';

            detailPane.innerHTML = html;

            var add = document.getElementById("fn-tool-add");
            if (add) {
                add.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                add.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    if (window.macroLab && window.macroLab.addTool) {
                        window.macroLab.addTool(settingDefFor(t));
                    }
                });
            }

            var del = document.getElementById("fn-tool-delete");
            if (del) {
                del.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                del.addEventListener("click", function() {
                    if (window.playSlot) playSlot("back");
                    if (window.macroLab && window.macroLab.deleteTool) {
                        window.macroLab.deleteTool(t.key);
                    }
                });
            }
        }

        function toolMetaRow(label, value) {
            return '<div class="fn-param-group fn-tool-meta"><div class="fn-param-label">'
                + esc(label) + '</div><div class="fn-tool-meta-val">'
                + esc(String(value)) + '</div></div>';
        }
    // END Canvas step for a tool reference //

    // Render Detail Panel //
        function renderDetail(fn) {
            var html = '';

            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(fn.label || fn.name) + '</div>';
            html += '<div class="fn-detail-desc">' + esc(fn.desc) + '</div>';
            html += '</div>';

            html += '<div class="fn-detail-body">';
            if (fn.params.length === 0) {
                html += '<div class="fn-no-params">This function takes no parameters.</div>';
            } else {
                html += '<div class="fn-params">';
                for (var i = 0; i < fn.params.length; i++) {
                    var p = fn.params[i];
                    html += renderParamField(p);
                }
                html += '</div>';
            }
            html += '</div>';

            html += '<div class="fn-detail-footer">';
            html += '<button class="fn-add-btn" id="fn-add-btn">Add Module</button>';
            html += '<span class="fn-tool-preview" id="fn-tool-preview"></span>';
            html += '</div>';

            detailPane.innerHTML = html;

            wireParamInputs(fn);

            var addBtn = document.getElementById("fn-add-btn");
            if (addBtn) {
                addBtn.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                addBtn.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    addToMacro(fn);
                });
            }

            updatePreview(fn);
        }

        function toolSelectOptions() {
            if (_tools.length === 0) {
                return [{ value: "", label: "No tools, create one first" }];
            }
            var opts = [{ value: "", label: "Pick a tool..." }];
            _tools.forEach(function(t) {
                opts.push({ value: t.key, label: (t.label || t.key) + "  -  " + t.type });
            });
            return opts;
        }

        var _toolSelects = {};

        function setToolInfo(name, key) {
            var el = detailPane.querySelector('[data-toolinfo="' + name + '"]');
            if (!el) return;
            var t = key && findTool(key);
            el.innerHTML = t ? ("Sets the <b>" + esc(t.type) + "</b> tool's value:") : "";
        }

        function currentToolValue(t) {
            if (t.value !== undefined && t.value !== null) return t.value;
            return (t.default !== undefined) ? t.default : null;
        }

        function commitToolValue(t, value, name) {
            t.value = value;
            if (window.shellPost) {
                shellPost("macros", "userSettingChange", {
                    action: "userSettingChange",
                    key: t.key,
                    value: value,
                });
            }
        }
    // END Render Detail Panel //

    // Inline value editor under the tool picker //
        function mountToolValue(name, key) {
            var wrap = detailPane.querySelector('[data-toolval="' + name + '"]');
            if (!wrap) return;
            wrap.innerHTML = "";
            var t = key && findTool(key);
            if (!t) return;
            var val = currentToolValue(t);

            if (t.type === "toggle") {
                var on = (val === true || val === "true");
                var lab = document.createElement("label");
                lab.className = "toggle fn-param-toggle";
                var cb = document.createElement("input");
                cb.type = "checkbox";
                cb.checked = on;
                var track = document.createElement("span");
                track.className = "toggle-track";
                var thumb = document.createElement("span");
                thumb.className = "toggle-thumb";
                lab.appendChild(cb);
                lab.appendChild(track);
                lab.appendChild(thumb);
                cb.addEventListener("change", function() {
                    if (window.playSlot) playSlot(cb.checked ? "toggleOn" : "toggleOff");
                    commitToolValue(t, cb.checked, name);
                });
                wrap.appendChild(lab);

            } else if (t.type === "seg") {
                var seg = document.createElement("div");
                seg.className = "fn-tool-seg";
                (t.options || []).forEach(function(o) {
                    var b = document.createElement("button");
                    b.className = "fn-tool-seg-opt" + (o.value === val ? " on" : "");
                    b.textContent = o.label;
                    b.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    b.addEventListener("click", function() {
                        var opts = seg.querySelectorAll(".fn-tool-seg-opt");
                        for (var i = 0; i < opts.length; i++) opts[i].classList.remove("on");
                        b.classList.add("on");
                        if (window.playSlot) playSlot("interact");
                        commitToolValue(t, o.value, name);
                    });
                    seg.appendChild(b);
                });
                wrap.appendChild(seg);

            } else if (t.type === "slider") {
                var row = document.createElement("div");
                row.className = "fn-tool-slider";
                var range = document.createElement("input");
                range.type = "range";
                range.min = (t.min != null ? t.min : 0);
                range.max = (t.max != null ? t.max : 100);
                range.step = (t.step != null ? t.step : 1);
                var num = (typeof val === "number") ? val : parseFloat(val);
                if (isNaN(num)) num = Number(range.min);
                range.value = num;
                var read = document.createElement("span");
                read.className = "fn-tool-slider-val";
                var fmt = function(v) { return String(v) + (t.unit ? (" " + t.unit) : ""); };
                read.textContent = fmt(num);
                range.addEventListener("input", function() {
                    read.textContent = fmt(parseFloat(range.value));
                });
                range.addEventListener("change", function() {
                    commitToolValue(t, parseFloat(range.value), name);
                });
                row.appendChild(range);
                row.appendChild(read);
                wrap.appendChild(row);
            }
        }

        function refreshToolBind(name, key) {
            setToolInfo(name, key);
            mountToolValue(name, key);
        }
    // END Inline value editor under the tool picker //

    // Replace each tool //
        function mountToolSelects(fn) {
            _toolSelects = {};
            if (typeof window.createSelect !== "function") return;
            var mounts = detailPane.querySelectorAll(".fn-tool-select-mount");
            for (var i = 0; i < mounts.length; i++) {
                (function(mount) {
                    var name = mount.getAttribute("data-toolmount");
                    var sel = window.createSelect({
                        options: toolSelectOptions(),
                        value: _paramBind[name] || "",
                        className: "fn-tool-select",
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramBind[name] = v;
                            _paramValues[name] = { __toolRef: v };
                            refreshToolBind(name, v);
                            updatePreview(fn);
                        },
                    });
                    sel.setAttribute("data-toolsel", name);
                    mount.appendChild(sel);
                    _toolSelects[name] = sel;
                    refreshToolBind(name, _paramBind[name] || "");
                })(mounts[i]);
            }
        }
    // END Replace each tool //

    // Param field rendering //
        function renderParamField(p) {
            var bindable = !!BINDABLE[p.type];
            var bound = bindable && !!_paramBind[p.name];

            var html = '<div class="fn-param-group fn-param' + (bound ? ' bound' : '')
                + '" data-pname="' + esc(p.name) + '">';
            html += '<div class="fn-param-label">' + esc(p.label);
            html += ' <span class="fn-param-type">' + esc(p.type) + '</span>';
            if (p.required) html += ' <span style="color:var(--danger)">*</span>';
            if (bindable) {
                html += '<span class="fn-bind-switch">'
                    + '<button class="fn-bind-opt' + (bound ? '' : ' on') + '" data-bindmode="literal" data-param="'
                    + esc(p.name) + '">Value</button>'
                    + '<button class="fn-bind-opt' + (bound ? ' on' : '') + '" data-bindmode="tool" data-param="'
                    + esc(p.name) + '">Tool</button></span>';
            }
            html += '</div>';

            html += '<div class="fn-param-literal" data-lit="' + esc(p.name) + '"'
                + (bound ? ' style="display:none"' : '') + '>';
            switch (p.type) {
                case "string":
                    html += '<input type="text" data-param="' + esc(p.name) + '" placeholder="Enter text..." autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">';
                    break;

                case "number":
                    html += '<input type="number" data-param="' + esc(p.name) + '" value="0" step="1">';
                    break;

                case "enum":
                    html += '<div class="fn-enum-select-mount" data-enummount="' + esc(p.name) + '"></div>';
                    break;

                case "choice":
                    html += '<div class="fn-choice-select-mount" data-choicemount="' + esc(p.name)
                        + '" data-choicesrc="' + esc(p.source || "")
                        + '" data-choicekind="' + esc(p.kind || "")
                        + '" data-choicedep="' + esc(p.dependsOn || "") + '"></div>';
                    break;

                case "boolean":
                    html += '<label class="toggle fn-param-toggle">'
                        + '<input type="checkbox" data-param="' + esc(p.name) + '">'
                        + '<span class="toggle-track"></span>'
                        + '<span class="toggle-thumb"></span></label>';
                    break;

                case "key":
                    html += '<div class="fn-key-capture">';
                    html += '<button class="fn-key-btn" data-param="' + esc(p.name) + '" data-key-capture>Click to set</button>';
                    html += '<span class="fn-key-hint">press a key...</span>';
                    html += '</div>';
                    break;

                case "mods":
                    html += '<div class="fn-mods-row">';
                    for (var i = 0; i < MOD_LIST.length; i++) {
                        html += '<button class="fn-mod-chip" data-mod="' + MOD_LIST[i] + '">' + MOD_LIST[i] + '</button>';
                    }
                    html += '</div>';
                    break;

                case "condition":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="1" placeholder="Lua expression..." spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;

                case "code":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="3" placeholder="Lua source..." spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;
            }
            html += '</div>';

            if (bindable) {
                html += '<div class="fn-param-tool" data-toolwrap="' + esc(p.name) + '"'
                    + (bound ? '' : ' style="display:none"') + '>';
                html += '<div class="fn-tool-select-mount" data-toolmount="' + esc(p.name) + '"></div>';
                html += '<div class="fn-tool-info" data-toolinfo="' + esc(p.name) + '"></div>';
                html += '<div class="fn-tool-value" data-toolval="' + esc(p.name) + '"></div>';
                html += '</div>';
            }

            html += '</div>';
            return html;
        }
    // END Param field rendering //

    // Wire up input events //
        function wireParamInputs(fn) {
            var inputs = detailPane.querySelectorAll("input[data-param], textarea[data-param]");
            for (var i = 0; i < inputs.length; i++) {
                (function(inp) {
                    var name = inp.getAttribute("data-param");
                    var evt = (inp.type === "checkbox") ? "change" : "input";
                    inp.addEventListener(evt, function() {
                        if (inp.type === "checkbox") {
                            _paramValues[name] = inp.checked;
                            if (window.playSlot) playSlot(inp.checked ? "toggleOn" : "toggleOff");
                        } else if (inp.type === "number") {
                            _paramValues[name] = parseFloat(inp.value) || 0;
                        } else {
                            _paramValues[name] = inp.value;
                        }
                        updatePreview(fn);
                    });
                    if (inp.tagName === "TEXTAREA") {
                        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
                    }
                })(inputs[i]);
            }

            var keyBtns = detailPane.querySelectorAll("[data-key-capture]");
            for (var j = 0; j < keyBtns.length; j++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    btn.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    btn.addEventListener("click", function(e) {
                        e.stopPropagation();
                        if (window.playSlot) playSlot("interact");
                        startKeyCapture(name, btn, fn);
                    });
                })(keyBtns[j]);
            }

            var modChips = detailPane.querySelectorAll("[data-mod]");
            for (var k = 0; k < modChips.length; k++) {
                (function(chip) {
                    var mod = chip.getAttribute("data-mod");
                    chip.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    chip.addEventListener("click", function() {
                        _modState[mod] = !_modState[mod];
                        if (window.playSlot) playSlot(_modState[mod] ? "toggleOn" : "toggleOff");
                        chip.classList.toggle("on", _modState[mod]);
                        var mods = [];
                        for (var m = 0; m < MOD_LIST.length; m++) {
                            if (_modState[MOD_LIST[m]]) mods.push(MOD_LIST[m]);
                        }
                        for (var n = 0; n < fn.params.length; n++) {
                            if (fn.params[n].type === "mods") {
                                _paramValues[fn.params[n].name] = mods;
                                break;
                            }
                        }
                        updatePreview(fn);
                    });
                })(modChips[k]);
            }

            var switches = detailPane.querySelectorAll(".fn-bind-opt");
            for (var s = 0; s < switches.length; s++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    var mode = btn.getAttribute("data-bindmode");
                    btn.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        var group = detailPane.querySelector('.fn-param[data-pname="' + name + '"]');
                        if (!group) return;
                        var lit  = group.querySelector('[data-lit="' + name + '"]');
                        var tool = group.querySelector('[data-toolwrap="' + name + '"]');
                        var opts = group.querySelectorAll('.fn-bind-opt');
                        opts.forEach(function(o) {
                            o.classList.toggle("on", o.getAttribute("data-bindmode") === mode);
                        });
                        if (mode === "tool") {
                            group.classList.add("bound");
                            if (lit)  lit.style.display  = "none";
                            if (tool) tool.style.display = "";
                            var selEl = group.querySelector('[data-toolsel="' + name + '"]');
                            _paramBind[name] = (selEl && selEl.value) ? selEl.value : "";
                            if (_paramBind[name]) {
                                _paramValues[name] = { __toolRef: _paramBind[name] };
                            }
                            refreshToolBind(name, _paramBind[name] || "");
                        } else {
                            group.classList.remove("bound");
                            if (lit)  lit.style.display  = "";
                            if (tool) tool.style.display = "none";
                            delete _paramBind[name];
                            var litInput = group.querySelector('[data-param="' + name + '"]');
                            if (litInput) {
                                _paramValues[name] = (litInput.type === "number")
                                    ? (parseFloat(litInput.value) || 0) : litInput.value;
                            } else {
                                _paramValues[name] = "";
                            }
                        }
                        updatePreview(fn);
                    });
                })(switches[s]);
            }

            mountEnumSelects(fn);

            _choiceSelects = [];
            mountChoiceSelects(fn);
            requestChoiceData(fn);

            mountToolSelects(fn);
        }
    // END Wire up input events //

    // Replace each enum mount point with a themed createSelect //
        function mountEnumSelects(fn) {
            if (typeof window.createSelect !== "function") return;
            var byName = {};
            for (var i = 0; i < fn.params.length; i++) byName[fn.params[i].name] = fn.params[i];
            var mounts = detailPane.querySelectorAll(".fn-enum-select-mount");
            for (var m = 0; m < mounts.length; m++) {
                (function(mount) {
                    var name = mount.getAttribute("data-enummount");
                    var p = byName[name];
                    if (!p) return;
                    var sel = window.createSelect({
                        options: p.options || [],
                        value: _paramValues[name] || "",
                        className: "fn-enum-select",
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramValues[name] = v;
                            refillChoiceSelects();
                            updatePreview(fn);
                        },
                    });
                    mount.appendChild(sel);
                })(mounts[m]);
            }
        }
    // END Replace each enum mount point with a themed createSelect //

    // Options for a "choice" param //
        function choiceOptions(p) {
            var opts = [];
            var seen = {};
            function add(value, label) {
                if (value == null || seen[value]) return;
                seen[value] = true;
                opts.push({ value: String(value), label: label });
            }
            if (p.source === "macros") {
                add("", "All macros");
                (window.msMacroCatalog || []).forEach(function(m) {
                    add(m.id, m.label || m.id);
                    (m.subs || []).forEach(function(sub) { add(sub.id, (sub.label || sub.id) + " (sub)"); });
                });
            } else if (p.source === "profiles") {
                for (var i = 0; i < _profilesData.length; i++) {
                    var e = _profilesData[i];
                    add(e.name, e.active ? e.name + " (active)" : e.name);
                }
            } else if (p.source === "pack") {
                var kind = (p.dependsOn && _paramValues[p.dependsOn]) || p.kind || "macro";
                var list = _packData[kind] || [];
                for (var j = 0; j < list.length; j++) {
                    var pk = list[j];
                    add(pk.slug, pk.active ? pk.name + " (active)" : pk.name);
                }
            }
            var cur = _paramValues[p.name];
            if (cur && !seen[cur]) add(cur, cur + " (not installed)");
            if (!opts.length) add("", "None available");
            return opts;
        }
    // END Options for a "choice" param //

    // Replace each choice mount point with a live //
        function mountChoiceSelects(fn) {
            if (typeof window.createSelect !== "function") return;
            var byName = {};
            for (var i = 0; i < fn.params.length; i++) byName[fn.params[i].name] = fn.params[i];
            var mounts = detailPane.querySelectorAll(".fn-choice-select-mount");
            for (var m = 0; m < mounts.length; m++) {
                (function(mount) {
                    var name = mount.getAttribute("data-choicemount");
                    var p = byName[name];
                    if (!p) return;
                    var opts = choiceOptions(p);
                    if (!_paramValues[name] && opts.length && opts[0].value) {
                        _paramValues[name] = opts[0].value;
                    }
                    var sel = window.createSelect({
                        options: opts,
                        value: _paramValues[name] || "",
                        className: "fn-choice-select",
                        searchable: opts.length > 8,
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramValues[name] = v;
                            updatePreview(fn);
                        },
                    });
                    mount.appendChild(sel);
                    _choiceSelects.push({ sel: sel, param: p, fn: fn });
                })(mounts[m]);
            }
        }

        function refillChoiceSelects() {
            for (var i = 0; i < _choiceSelects.length; i++) {
                var c = _choiceSelects[i];
                if (!c.sel.isConnected) continue;
                var opts = choiceOptions(c.param);
                var keep = c.sel.value;
                c.sel.setOptions(opts);
                var has = false;
                for (var j = 0; j < opts.length; j++) if (opts[j].value === keep) { has = true; break; }
                if (has) c.sel.value = keep;
                _paramValues[c.param.name] = c.sel.value;
            }
        }
    // END Replace each choice mount point with a live //

    // Key Capture //
        function startKeyCapture(paramName, btn, fn) {
            if (_keyCapture) {
                var prevBtn = detailPane.querySelector(".fn-key-btn.capturing");
                if (prevBtn) prevBtn.classList.remove("capturing");
                document.removeEventListener("keydown", _keyCaptureHandler, true);
            }

            _keyCapture = paramName;
            btn.classList.add("capturing");
            btn.textContent = "...";

            function handler(e) {
                e.preventDefault();
                e.stopPropagation();

                var key = normalizeKey(e);
                _paramValues[paramName] = key;

                btn.classList.remove("capturing");
                btn.textContent = key || "???";
                btn.classList.remove("fn-key-btn");
                btn.classList.add("fn-key-btn");

                document.removeEventListener("keydown", handler, true);
                _keyCapture = null;
                _keyCaptureHandler = null;
                updatePreview(fn);
            }

            _keyCaptureHandler = handler;
            document.addEventListener("keydown", handler, true);
        }

        var _keyCaptureHandler = null;

        function normalizeKey(e) {
            var map = {
                " ": "space",
                "ArrowUp": "up",
                "ArrowDown": "down",
                "ArrowLeft": "left",
                "ArrowRight": "right",
                "Backspace": "delete",
                "Escape": "escape",
                "Enter": "return",
                "Tab": "tab"
            };
            if (map[e.key]) return map[e.key];
            if (e.key.length === 1) return e.key.toLowerCase();
            return e.key.toLowerCase();
        }
    // END Key Capture //

    // Step Preview //
        function updatePreview(fn) {
            var el = document.getElementById("fn-tool-preview");
            if (!el) return;

            var parts = [];
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                if (val && typeof val === "object" && val.__toolRef) {
                    parts.push(p.name + ':ms.settings.get("' + val.__toolRef + '")');
                } else if (p.type === "mods") {
                    parts.push(p.name + ":[" + (val || []).join(",") + "]");
                } else if (p.type === "string" || p.type === "enum") {
                    parts.push(p.name + ':"' + (val || "") + '"');
                } else {
                    parts.push(p.name + ":" + (val !== undefined ? val : ""));
                }
            }
            el.textContent = fn.name + "(" + parts.join(", ") + ")";
        }
    // END Step Preview //

    // Add to Macro //
        function addToMacro(fn) {
            var params = {};
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                if (_paramBind[p.name] !== undefined && !_paramBind[p.name]) {
                    showToast("Pick a tool for: " + p.label);
                    return;
                }
                if (val && typeof val === "object" && val.__toolRef) {
                    params[p.name] = { __toolRef: val.__toolRef };
                    continue;
                }
                if (p.required && p.type === "string" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.required && p.type === "key" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.type === "mods") {
                    params[p.name] = val || [];
                } else {
                    params[p.name] = val;
                }
            }

            var step = {
                action: fn.name,
                params: params
            };
            if (fn.plugin) {
                step.argOrder = fn.params.map(function(p) { return p.name; });
            }
            if (window.macroLab && window.macroLab.addTool) {
                window.macroLab.addTool(step);
            }
            window.shellPost("macros", "addTool", step);

            showToast("Added: " + (fn.label || fn.name));
        }

        function showToast(msg) {
            toast.textContent = msg;
            toast.classList.add("show");
            if (_toastTimer) clearTimeout(_toastTimer);
            _toastTimer = setTimeout(function() {
                toast.classList.remove("show");
                _toastTimer = null;
            }, 1800);
        }

        function esc(s) {
            var d = document.createElement("div");
            d.appendChild(document.createTextNode(s));
            return d.innerHTML;
        }

        searchInput.addEventListener("input", function() {
            renderList(searchInput.value);
        });

        searchInput.addEventListener("keydown", function(e) {
            e.stopPropagation();
        });

        function setFunctionList(list) {
            _fnList = Array.isArray(list) ? list : [];
            renderList(searchInput.value);
        }

        function _fnPickerHandler(action, body) {
            if (action === "functions" && Array.isArray(body)) {
                setFunctionList(body);
            }
            if (action === "selectFunction" && body && body.name) {
                selectFunction(body.name);
            }
        }

        function setPluginBlocks(list) {
            for (var i = REGISTRY.length - 1; i >= 0; i--) {
                if (REGISTRY[i].plugin) REGISTRY.splice(i, 1);
            }
            (Array.isArray(list) ? list : []).forEach(function(b) {
                if (!b || typeof b.id !== "string") return;
                var params = Array.isArray(b.params) ? b.params : [];
                REGISTRY.push({
                    id: b.id,
                    name: b.id,
                    label: b.name || b.id,
                    sig: b.id + "(" + params.map(function(p) { return p.name; }).join(", ") + ")",
                    desc: b.desc || "",
                    category: b.category || "plugin",
                    params: params,
                    plugin: true
                });
            });
            renderList(searchInput.value);
        }

        function setToolList(list) {
            _tools = Array.isArray(list) ? list : [];
            window.msMacroTools = _tools;
            renderList(searchInput.value);
            if (_view === "tool" && _selectedId) {
                var t = findTool(_selectedId);
                if (t) renderToolDetail(t); else { detailPane.innerHTML = ''; _view = "module"; }
            } else {
                for (var name in _toolSelects) {
                    if (!_toolSelects.hasOwnProperty(name)) continue;
                    var picked = _paramBind[name] || "";
                    _toolSelects[name].setOptions(toolSelectOptions());
                    _toolSelects[name].value = picked;
                }
            }
        }

        window.fnPicker = {
            refreshChoices: function() { refillChoiceSelects(); },
            focusSearch: function() {
                setTimeout(function() {
                    searchInput.focus({ preventScroll: true });
                    searchInput.select();
                }, 0);
            },
            select: selectFunction,
            registry: REGISTRY,
            showToast: showToast,
            setToolList: setToolList,
            setFunctionList: setFunctionList,
            setPluginBlocks: setPluginBlocks,
            settingDef: settingDefFor,
            handler: _fnPickerHandler
        };

        renderList("");
    // END Add to Macro //
    })();
