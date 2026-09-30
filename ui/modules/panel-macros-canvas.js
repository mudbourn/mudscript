(function() {
    "use strict";

    if (typeof window !== "undefined") window.ToolCanvas = ToolCanvas;

    var _svgCache = {};

    // SVG loader //
      function _fetchSVG(name) {
          if (_svgCache[name]) return Promise.resolve(_svgCache[name]);
          if (window.ICONS && window.ICONS[name]) {
              _svgCache[name] = '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' + window.ICONS[name] + '</svg>';
              return Promise.resolve(_svgCache[name]);
          }
          return Promise.resolve("");
      }
    // END SVG loader //

    // Action to icon mapping //
      var ACTION_ICON = {
          "ms.type":"keyboard","ms.press":"keyboard","ms.hold":"keyboard","ms.release":"keyboard",
          "ms.wait":"timer","ms.copy":"clipboard","ms.paste":"clipboard",
          "ms.cam":"camera","ms.cam.rebalance":"camera","ms.cam.reset":"camera",
          "ms.Mouse":"click","ms.click":"click","ms.scroll":"scroll","ms.move":"move","ms.select":"select",
          "ms.search":"search","ms.record":"record","ms.stop":"stop","ms.pause":"pause",
          "ms.play":"play","ms.save":"save","ms.load":"upload","ms.alert":"alert",
          "ms.refresh":"refresh","ms.pixelScan":"pixelscan","ms.window":"window",
          "ms.input":"inputs","ms.variable":"variable","ms.watch":"watcher",
          "ms.sound":"sound","ms.gamepad":"controller","ms.gamepadStart":"controller","ms.gamepadBind":"controller",
          "ms.setMacros":"power","ms.enable":"power","ms.disable":"power",
          "ms.switchProfile":"settings","ms.switchPack":"macros",
          "ms.screenshot":"camera","ms.clipChanged":"clipboard",
          "ms.randWait":"timer","ms.jitter":"timer","ms.waitPixel":"pixelscan","ms.waitNotPixel":"pixelscan",
          "ms.ocr":"ocr","ms.readNumber":"ocr","ms.findText":"ocr","ms.waitText":"ocr",
          "ms.waitApp":"search","ms.waitNotApp":"search",
          "ms.focus":"window","ms.appRunning":"window","ms.appIsFront":"window",
          "ms.toggle":"keyboard","ms.multiPress":"keyboard",
          "ms.saveCursor":"select","ms.restoreCursor":"select",
          "ms.setVolume":"sound","ms.mute":"sound","ms.unmute":"sound",
          "ms.drag":"drag",
          "if":"branch","for":"loop","while":"repeat","repeat":"repeat","else":"branch",
          "var_set":"variable","var_add":"variable","var_sub":"variable","var_mul":"variable",
          "comment":"inputs","code":"macros","setting":"settings"
      };

      function iconFor(action) { return ACTION_ICON[action] || "macros"; }

      function condSummary(c) {
          if (c && typeof c === "object") {
              if (typeof c.__toolRef === "string") return 'ms.settings.get("' + c.__toolRef + '")';
              if (typeof c.__varRef === "string")  return 'ms.vars.get("' + c.__varRef + '")';
              return "";
          }
          return c || "";
      }
    // END Action to icon mapping //

    // Tool-ref label //
        function toolRefLabel(key) {
            var list = window.msMacroTools || [];
            for (var i = 0; i < list.length; i++) {
                var t = list[i];
                if (t && t.key === key) {
                    return (t.type || "tool") + " " + (t.label || t.key);
                }
            }
            return key;
        }
    // END //

    function paramSummary(action, params) {
        if (!params) return "";
        var keys = Object.keys(params);
        if (keys.length === 0) return "";
        if (action === "if" || action === "while" || action === "repeat") return condSummary(params.condition);
        if (action === "for") return (params.var||"i") + " = " + (params.from||1) + " -> " + (params.to||1);
        if (action === "comment") return params.text || "";
        if (action === "code") return (params.source||"").split("\n")[0] || "";
        if (action === "setting") return 'ms.settings.get("' + (params.key || "") + '")';
        if (action === "ms.dragPath") {
            var pts = (typeof params.points === "string" && params.points.trim())
                ? params.points.split(";").filter(function(s){ return s.trim(); }).length : 0;
            return (params.button || "Left") + " drag - " + pts + " pts";
        }
        if (action === "ms.switchProfile") return "profile: " + (params.name || "?");
        if (action === "ms.switchPack") return (params.kind || "macro") + " pack: " + (params.slug || "?");
        if (action === "var_set") return (params.name||"v") + " = " + (params.value!==undefined?params.value:"");
        if (action === "var_add" || action === "var_sub" || action === "var_mul") {
            var op = action==="var_add"?"+":action==="var_sub"?"-":"*";
            return (params.name||"v") + " " + op + "= " + (params.amount!==undefined?params.amount:1);
        }
        var parts = [];
        for (var i = 0; i < Math.min(keys.length, 2); i++) {
            var k = keys[i], v = params[k];
            if (v && typeof v === "object" && (v.__toolRef || v.__varRef)) {
                parts.push(k + ": " + toolRefLabel(v.__toolRef || v.__varRef));
                continue;
            }
            if (Array.isArray(v)) { if (v.length === 0) continue; v = v.join("+"); }
            if (typeof v === "string" && v.length > 16) v = v.slice(0,14) + "...";
            parts.push(k + ": " + v);
        }
        return parts.join(", ");
    }

    var _toolIdCounter = 0;
    function nextToolId() { return "_s" + (++_toolIdCounter) + "_" + Date.now().toString(36); }

    function deepClone(o) { return JSON.parse(JSON.stringify(o)); }

    var EMPTY_CLIP = "empty, click to paste";
    if (window.ICONS) window.ICONS["paste-in"] = '<path d="M15 10L20 15L15 20M4 4V11C4 13.2091 5.79086 15 8 15H20" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>';

// ToolCanvas class //
    function ToolCanvas(container, opts) {
        this._el = container;
        this._onChange = (opts && opts.onChange) || function(){};
        this._onSelect = (opts && opts.onSelect) || function(){};
        this._onContext = (opts && opts.onContext) || function(){};
        this._tools = [];
        this._map = {};
        this._selSet   = {};
        this._anchorId = null;
        this._selId    = null;
        this._dragId = null;
        this._dragGroup = null;
        this._root = document.createElement("div");
        this._root.className = "tool-canvas";
        this._el.appendChild(this._root);
        this._renderEmpty();
        this._preloadIcons();

        var self = this;
        this._root.gpReorderSelection = function(dir) {
            var sel = self._selList();
            if (!sel.length) return false;
            var order = self._docOrder();
            var selSet = {};
            for (var s = 0; s < sel.length; s++) selSet[sel[s]] = true;
            if (dir < 0) {
                for (var i = order.indexOf(sel[0]) - 1; i >= 0; i--) {
                    if (!selSet[order[i]]) { self.moveTools(sel, order[i], "above"); return true; }
                }
            } else {
                for (var j = order.indexOf(sel[sel.length - 1]) + 1; j < order.length; j++) {
                    if (!selSet[order[j]]) { self.moveTools(sel, order[j], "below"); return true; }
                }
            }
            return false;
        };
        this._root.gpDuplicateSelection = function() { return self.duplicateSelected(); };
        this._root.gpDeleteSelection = function() { return self.removeSelected(); };

        if (window.ResizeObserver) {
            this._ro = new ResizeObserver(function() { self._updateParamMarquee(); });
            this._ro.observe(this._root);
        }
    }

    ToolCanvas.prototype._preloadIcons = function() {
        var needed = ["drag","close","chevdown","macros","copy","paste"];
        for (var a in ACTION_ICON) { if (needed.indexOf(ACTION_ICON[a]) === -1) needed.push(ACTION_ICON[a]); }
        var self = this;
        var chain = Promise.resolve();
        needed.forEach(function(n) { chain = chain.then(function(){ return _fetchSVG(n); }); });
    };

    ToolCanvas.prototype._assignIds = function(steps) {
        for (var i = 0; i < steps.length; i++) {
            var s = steps[i];
            if (!s._sid) s._sid = nextToolId();
            this._map[s._sid] = s;
            if (s.then) this._assignIds(s.then);
            if (s.else) this._assignIds(s.else);
            if (s.body) this._assignIds(s.body);
        }
    };

    ToolCanvas.prototype.load = function(steps) {
        this._tools = steps || [];
        this._map = {};
        this._assignIds(this._tools);
        this._clearSelection();
        this._render();
    };
// END ToolCanvas class //

// Container actions carry nested child lists //
    function seedContainer(step) {
        if (step.action === "if") {
            if (!step.then) step.then = [];
            if (!step.else) step.else = [];
        } else if (step.action === "for" || step.action === "while" || step.action === "repeat") {
            if (!step.body) step.body = [];
        }
    }

    ToolCanvas.prototype.addTool = function(def, afterId) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        if (afterId) {
            var idx = this._findIdx(this._tools, afterId);
            if (idx !== -1) this._tools.splice(idx+1, 0, step);
            else this._tools.push(step);
        } else {
            this._tools.push(step);
        }
        this._render();
        this._fireChange();
        return step._sid;
    };
// END Container actions carry nested child lists //

// Insert a new top //
    ToolCanvas.prototype.insertDefAt = function(def, beforeSid) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        var idx = beforeSid ? this._findIdx(this._tools, beforeSid) : -1;
        if (idx !== -1) this._tools.splice(idx, 0, step);
        else this._tools.push(step);
        this._setSelection([step._sid]);
        this._render();
        this._fireChange();
        return step._sid;
    };

    ToolCanvas.prototype.removeTool = function(sid) {
        if (this._removeFrom(this._tools, sid)) {
            delete this._map[sid];
            this._deselectOne(sid);
            this._render();
            this._emitSelection();
            this._fireChange();
        }
    };

    ToolCanvas.prototype._removeFrom = function(list, sid) {
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) { list.splice(i,1); return true; }
            var s = list[i];
            if (s.then && this._removeFrom(s.then, sid)) return true;
            if (s.else && this._removeFrom(s.else, sid)) return true;
            if (s.body && this._removeFrom(s.body, sid)) return true;
        }
        return false;
    };

    ToolCanvas.prototype._findIdx = function(list, sid) {
        for (var i = 0; i < list.length; i++) { if (list[i]._sid === sid) return i; }
        return -1;
    };

    ToolCanvas.prototype.moveTool = function(dragId, targetId, pos) {
        var step = this._map[dragId];
        if (!step) return;
        this._removeFrom(this._tools, dragId);
        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                if (tgt.action === "if") { if(!tgt.then) tgt.then=[]; tgt.then.push(step); }
                else { if(!tgt.body) tgt.body=[]; tgt.body.push(step); }
            }
        } else {
            var ti = this._findIdx(this._tools, targetId);
            if (ti !== -1) this._tools.splice(pos==="above"?ti:ti+1, 0, step);
            else this._tools.push(step);
        }
        this._render();
        this._fireChange();
    };

    ToolCanvas.prototype._locate = function(sid, list) {
        list = list || this._tools;
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) return { list: list, idx: i };
            var s = list[i];
            var r = (s.then && this._locate(sid, s.then))
                 || (s.else && this._locate(sid, s.else))
                 || (s.body && this._locate(sid, s.body));
            if (r) return r;
        }
        return null;
    };
// END Insert a new top //

// Move a group of blocks //
    ToolCanvas.prototype.moveTools = function(dragIds, targetId, pos) {
        if (!dragIds || !dragIds.length) return;
        if (dragIds.indexOf(targetId) !== -1) return;
        var steps = [];
        for (var i = 0; i < dragIds.length; i++) {
            var s = this._map[dragIds[i]];
            if (s) { steps.push(s); this._removeFrom(this._tools, dragIds[i]); }
        }
        if (!steps.length) return;

        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                var branch = tgt.action === "if"
                    ? (tgt.then || (tgt.then = []))
                    : (tgt.body || (tgt.body = []));
                for (var j = 0; j < steps.length; j++) branch.push(steps[j]);
            }
        } else {
            var loc = this._locate(targetId);
            if (loc) {
                var at = pos === "above" ? loc.idx : loc.idx + 1;
                Array.prototype.splice.apply(loc.list, [at, 0].concat(steps));
            } else {
                for (var k = 0; k < steps.length; k++) this._tools.push(steps[k]);
            }
        }
        this._setSelection(dragIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        this._fireChange();
    };

    ToolCanvas.prototype.serialize = function() {
        return this._strip(deepClone(this._tools));
    };

    ToolCanvas.prototype._strip = function(steps) {
        for (var i=0;i<steps.length;i++) {
            delete steps[i]._sid;
            if (steps[i].then) this._strip(steps[i].then);
            if (steps[i].else) this._strip(steps[i].else);
            if (steps[i].body) this._strip(steps[i].body);
        }
        return steps;
    };

    ToolCanvas.prototype._fireChange = function() { this._onChange(this.serialize()); };

    ToolCanvas.prototype._render = function() {
        this._root.innerHTML = "";
        if (this._tools.length === 0) { this._renderEmpty(); return; }
        for (var i=0;i<this._tools.length;i++) {
            this._root.appendChild(this._renderTool(this._tools[i]));
        }
        this._updateParamMarquee();
        var self = this;
        requestAnimationFrame(function() { self._updateParamMarquee(); });
    };

    ToolCanvas.prototype._updateParamMarquee = function(el) {
        if (!this._root.offsetParent || this._root.clientWidth === 0) {
            var self = this;
            if (window.requestAnimationFrame) {
                requestAnimationFrame(function() {
                    requestAnimationFrame(function() {
                        if (self._root.offsetParent && self._root.clientWidth > 0) self._updateParamMarquee(el);
                    });
                });
            }
            return;
        }
        var params = el
            ? [el.querySelector(".tool-params")]
            : Array.prototype.slice.call(this._root.querySelectorAll(".tool-params"));
        for (var i = 0; i < params.length; i++) {
            var p = params[i];
            if (!p) continue;
            var shift = p.scrollWidth - p.clientWidth;
            if (shift > 2) {
                p.style.setProperty("--mq", "-" + shift + "px");
                p.classList.add("has-mq");
            } else {
                p.style.removeProperty("--mq");
                p.classList.remove("has-mq");
            }
        }
    };

    ToolCanvas.prototype._renderEmpty = function() {
        this._root.innerHTML = "";
        var d = document.createElement("div");
        d.className = "tool-canvas-empty";
        d.innerHTML = '<span class="tool-canvas-empty-icon"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></span>No modules yet<br><span style="font-size:10px">Click <b>+ Add Module</b> to begin</span>';
        this._root.appendChild(d);
    };

    ToolCanvas.prototype._isContainer = function(s) {
        return s.action==="if" || s.action==="for" || s.action==="while" || s.action==="repeat";
    };

    ToolCanvas.prototype._renderTool = function(step) {
        return this._isContainer(step) ? this._renderContainer(step) : this._renderLeaf(step);
    };

    ToolCanvas.prototype._renderLeaf = function(step) {
        var self = this;
        var isSetting = step.action === "setting";
        var el = document.createElement("div");
        el.className = "tool-block" + (this._isSelected(step._sid)?" selected":"")
            + (isSetting ? " tool-block-setting" : "");
        el.setAttribute("data-sid", step._sid);

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        el.appendChild(h);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        el.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        nm.textContent = isSetting
            ? ("Setting - " + ((step.params && (step.params.label || step.params.key)) || "?"))
            : step.action;
        el.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        el.appendChild(pm);

        el.appendChild(this._buildToolActions(step));

        el.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
            self._updateParamMarquee(el);
        });
        el.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn") || e.target.closest(".tool-drag-handle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        el.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
        });

        this._wireDrag(el, step);
        return el;
    };
// END Move a group of blocks //

// Copy / paste / delete controls shared by leaf and container blocks //
    ToolCanvas.prototype._buildToolActions = function(step) {
        var self = this;
        var acts = document.createElement("div");
        acts.className = "tool-actions";

        var cp = document.createElement("div");
        cp.className = "tool-action-btn copy";
        cp.title = "Copy module";
        cp.innerHTML = _svgCache["copy"] || (window.icon ? window.icon("copy") : "");
        cp.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        cp.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.copyStep(step._sid);
        });
        acts.appendChild(cp);

        var pt = document.createElement("div");
        pt.className = "tool-action-btn paste";
        pt.title = "Paste module after this one";
        pt.innerHTML = _svgCache["paste"] || (window.icon ? window.icon("paste") : "");
        pt.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        pt.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.pasteAfterId(step._sid);
        });
        acts.appendChild(pt);

        if (this._isContainer(step)) {
            var pin = document.createElement("div");
            pin.className = "tool-action-btn paste";
            pin.title = step.action === "if" ? "Paste module inside (then branch)" : "Paste module inside";
            pin.innerHTML = window.icon ? window.icon("paste-in") : "";
            pin.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            pin.addEventListener("click", function(e) {
                e.stopPropagation();
                if (window.playSlot) playSlot("interact");
                self.pasteInto(step._sid);
            });
            acts.appendChild(pin);
        }

        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.title = "Delete module";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        db.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("back");
            self.removeTool(step._sid);
        });
        acts.appendChild(db);

        return acts;
    };

    ToolCanvas.prototype._renderContainer = function(step) {
        var self = this;
        var wrap = document.createElement("div");
        wrap.className = "tool-block-container";
        wrap.setAttribute("data-sid", step._sid);

        var header = document.createElement("div");
        header.className = "tool-block" + (this._isSelected(step._sid)?" selected":"");
        header.setAttribute("data-sid", step._sid);

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        header.appendChild(h);

        var tg = document.createElement("div");
        tg.className = "tool-nest-toggle";
        tg.innerHTML = _svgCache["chevdown"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7 13L12 18L17 13M7 6L12 11L17 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        tg.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        tg.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            var collapsed = tg.classList.toggle("collapsed");
            for (var ci = 0; ci < wrap.children.length; ci++) {
                var child = wrap.children[ci];
                if (child.classList.contains("tool-nest-body")) window.msMotion ? msMotion.collapse(child, collapsed) : child.classList.toggle("collapsed", collapsed);
                else if (child.classList.contains("tool-nest-label")) child.classList.toggle("collapsed", collapsed);
            }
        });
        header.appendChild(tg);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        header.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        nm.textContent = step.action;
        header.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        header.appendChild(pm);

        header.appendChild(this._buildToolActions(step));

        header.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
            self._updateParamMarquee(header);
        });
        header.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn")||e.target.closest(".tool-drag-handle")||e.target.closest(".tool-nest-toggle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        header.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
        });
        this._wireDrag(header, step);

        wrap.appendChild(header);

        if (step.action === "if") {
            var tl = document.createElement("div"); tl.className="tool-nest-label"; tl.textContent="then"; wrap.appendChild(tl);
            wrap.appendChild(this._renderNest(step.then||[], "then", step));
            var el2 = document.createElement("div"); el2.className="tool-nest-label"; el2.textContent="else"; wrap.appendChild(el2);
            wrap.appendChild(this._renderNest(step.else||[], "else", step));
        } else {
            wrap.appendChild(this._renderNest(step.body||[], "body", step));
        }
        return wrap;
    };

    ToolCanvas.prototype._renderNest = function(steps, branch, parent) {
        var self = this;
        var body = document.createElement("div");
        body.className = "tool-nest-body";
        body.setAttribute("data-nest-parent", parent._sid);
        body.setAttribute("data-nest-branch", branch);

        if (steps.length === 0) {
            var emp = document.createElement("div");
            emp.className = "tool-nest-body-empty";
            emp.textContent = this._clipboard ? EMPTY_CLIP : "empty";
            emp.addEventListener("click", function(e) {
                e.stopPropagation();
                if (self.pasteInto(parent._sid, branch) && window.playSlot) playSlot("interact");
            });
            body.appendChild(emp);
        } else {
            for (var i=0;i<steps.length;i++) body.appendChild(this._renderTool(steps[i]));
        }

        return body;
    };


    ToolCanvas.prototype._isSelected = function(sid) {
        return !!this._selSet[sid];
    };
    ToolCanvas.prototype._selCount = function() {
        return Object.keys(this._selSet).length;
    };
    ToolCanvas.prototype._selList = function() {
        var self = this, out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (self._selSet[sid] && out.indexOf(sid) === -1) out.push(sid);
            });
        }
        for (var sid in this._selSet) { if (out.indexOf(sid) === -1) out.push(sid); }
        return out;
    };
    ToolCanvas.prototype._docOrder = function() {
        var out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (out.indexOf(sid) === -1) out.push(sid);
            });
        }
        return out;
    };
// END Copy / paste / delete controls shared by leaf and container blocks //

// Update state //
    ToolCanvas.prototype._setSelection = function(ids) {
        this._selSet = {};
        for (var i = 0; i < ids.length; i++) { if (ids[i]) this._selSet[ids[i]] = true; }
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
        if (ids.length) this._anchorId = ids[ids.length - 1];
    };
    ToolCanvas.prototype._clearSelection = function() {
        this._selSet = {};
        this._selId = null;
        this._anchorId = null;
    };
    ToolCanvas.prototype._deselectOne = function(sid) {
        delete this._selSet[sid];
        if (this._anchorId === sid) this._anchorId = null;
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
    };

    ToolCanvas.prototype._applySelectionClasses = function() {
        var self = this;
        if (!this._root) return;
        this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
            var sid = el.getAttribute("data-sid");
            el.classList.toggle("selected", !!self._selSet[sid]);
        });
    };

    ToolCanvas.prototype._emitSelection = function() {
        this._onSelect(this._selId, this._selId ? this._map[this._selId] : null);
    };
// END Update state //

// Click routing //
    ToolCanvas.prototype._clickSelect = function(sid, e) {
        var meta  = e && (e.metaKey || e.ctrlKey);
        var shift = e && e.shiftKey;

        if (meta) {
            if (this._selSet[sid]) this._deselectOne(sid);
            else { this._selSet[sid] = true; this._anchorId = sid;
                   var k = Object.keys(this._selSet); this._selId = k.length === 1 ? k[0] : null; }
        } else if (shift && this._anchorId && this._anchorId !== sid) {
            var order = this._docOrder();
            var a = order.indexOf(this._anchorId), b = order.indexOf(sid);
            if (a === -1 || b === -1) { this._setSelection([sid]); }
            else {
                var lo = Math.min(a, b), hi = Math.max(a, b);
                this._selSet = {};
                for (var i = lo; i <= hi; i++) this._selSet[order[i]] = true;
                this._selId = (hi - lo === 0) ? order[lo] : null;
            }
        } else {
            if (this._selId === sid && this._selCount() === 1) this._clearSelection();
            else this._setSelection([sid]);
        }

        this._applySelectionClasses();
        this._emitSelection();
    };
// END Click routing //

// Public //
    ToolCanvas.prototype.select = function(ids) {
        this._setSelection(ids || []);
        this._applySelectionClasses();
        this._emitSelection();
    };
    ToolCanvas.prototype.clearSelection = function() {
        this._clearSelection();
        this._applySelectionClasses();
        this._emitSelection();
    };

    ToolCanvas.prototype._isDesc = function(pid, cid) {
        var p = this._map[pid]; if (!p) return false;
        var ch = [].concat(p.then||[], p.else||[], p.body||[]);
        for (var i=0;i<ch.length;i++) {
            if (ch[i]._sid===cid) return true;
            if (this._isDesc(ch[i]._sid, cid)) return true;
        }
        return false;
    };

    ToolCanvas.prototype._wireDrag = function(el, step) {
        var self = this;
        el.addEventListener("mousedown", function(e) {
            if (e.button !== 0) return;
            if (e.target.closest(".tool-action-btn")) return;
            if (e.target.closest(".tool-nest-toggle")) return;
            e.preventDefault();
            self._beginPointerDrag(el, step, e);
        });
    };
// END Public //

// Runs a single reorder gesture //
    ToolCanvas.prototype._beginPointerDrag = function(el, step, downEvt) {
        var self = this;
        var startX = downEvt.clientX, startY = downEvt.clientY;
        var THRESH = 4;
        var started = false;
        var ghost = null, offX = 0, offY = 0;
        var group = null;
        var target = null;
        var scroller = self._el;

        function begin() {
            started = true;
            if (self._isSelected(step._sid) && self._selCount() > 1) {
                group = self._selList();
            } else {
                group = [step._sid];
                if (!self._isSelected(step._sid)) self.select([step._sid]);
            }
            self._dragId = step._sid;
            self._dragGroup = group;
            group.forEach(function(sid) {
                var d = self._root.querySelector('.tool-block[data-sid="'+sid+'"]');
                if (d) d.classList.add("dragging");
            });
            ghost = el.cloneNode(true);
            ghost.classList.add("tool-drag-ghost");
            ghost.style.width = el.offsetWidth + "px";
            var r = el.getBoundingClientRect();
            offX = startX - r.left; offY = startY - r.top;
            if (group.length > 1) {
                var badge = document.createElement("div");
                badge.className = "tool-drag-badge";
                badge.textContent = group.length;
                ghost.appendChild(badge);
            }
            document.body.appendChild(ghost);
            document.body.classList.add("tool-dragging-active");
            moveGhost(startX, startY);
            if (window.playSlot) playSlot("interact");
        }

        function moveGhost(x, y) {
            if (ghost) { ghost.style.left = (x - offX) + "px"; ghost.style.top = (y - offY) + "px"; }
        }

        function hitTest(x, y) {
            self._clearDrops();
            target = null;
            var under = document.elementFromPoint(x, y);
            if (!under || !under.closest) return;

            var blockEl = under.closest(".tool-block[data-sid]");
            if (blockEl && group.indexOf(blockEl.getAttribute("data-sid")) !== -1) {
                blockEl = null;
            }
            if (blockEl) {
                var tid = blockEl.getAttribute("data-sid");
                var tstep = self._map[tid];
                var rect = blockEl.getBoundingClientRect();
                var ry = y - rect.top, h = rect.height;
                var pos;
                if (tstep && self._isContainer(tstep) && ry > h*0.3 && ry < h*0.7) pos = "nest";
                else if (ry < h/2) pos = "above";
                else pos = "below";
                if (pos === "nest") {
                    for (var i = 0; i < group.length; i++) {
                        if (group[i] === tid || self._isDesc(group[i], tid)) return;
                    }
                }
                blockEl.classList.add(pos === "nest" ? "drag-over-nest"
                    : pos === "above" ? "drag-over-above" : "drag-over-below");
                target = { kind: "block", sid: tid, pos: pos };
                return;
            }

            var nestEl = under.closest(".tool-nest-body");
            if (nestEl) {
                var psid = nestEl.getAttribute("data-nest-parent");
                for (var j = 0; j < group.length; j++) {
                    if (group[j] === psid || self._isDesc(group[j], psid)) return;
                }
                nestEl.classList.add("drag-target");
                target = { kind: "nest", parent: psid, branch: nestEl.getAttribute("data-nest-branch") };
            }
        }

        function autoscroll(y) {
            if (!scroller) return;
            var r = scroller.getBoundingClientRect(), M = 28;
            if (y < r.top + M) scroller.scrollTop -= 10;
            else if (y > r.bottom - M) scroller.scrollTop += 10;
        }

        function onMove(e) {
            if (!started) {
                if (Math.abs(e.clientX - startX) < THRESH && Math.abs(e.clientY - startY) < THRESH) return;
                begin();
            }
            e.preventDefault();
            moveGhost(e.clientX, e.clientY);
            autoscroll(e.clientY);
            hitTest(e.clientX, e.clientY);
        }

        function commit() {
            if (!target) return;
            if (target.kind === "block") self.moveTools(group, target.sid, target.pos);
            else self._commitNest(group, target.parent, target.branch);
        }

        function cleanup() {
            document.removeEventListener("mousemove", onMove, true);
            document.removeEventListener("mouseup", onUp, true);
            document.removeEventListener("keydown", onKey, true);
            if (ghost) ghost.remove();
            ghost = null;
            document.body.classList.remove("tool-dragging-active");
            self._root.querySelectorAll(".tool-block.dragging").forEach(function(d) {
                d.classList.remove("dragging");
            });
            self._clearDrops();
            self._dragId = null; self._dragGroup = null;
        }

        function onUp(e) {
            if (started) {
                e.preventDefault(); e.stopPropagation();
                commit();
                var swallow = function(ev) {
                    ev.stopPropagation(); ev.preventDefault();
                    document.removeEventListener("click", swallow, true);
                };
                document.addEventListener("click", swallow, true);
            }
            cleanup();
        }
        function onKey(e) { if (e.key === "Escape") { target = null; cleanup(); } }

        document.addEventListener("mousemove", onMove, true);
        document.addEventListener("mouseup", onUp, true);
        document.addEventListener("keydown", onKey, true);
    };
// END Runs a single reorder gesture //

// Drop a group into a container branch //
    ToolCanvas.prototype._commitNest = function(group, parentSid, branch) {
        var parent = this._map[parentSid];
        if (!parent) return;
        for (var i = 0; i < group.length; i++) {
            if (group[i] === parentSid || this._isDesc(group[i], parentSid)) return;
        }
        var steps = [];
        for (var g = 0; g < group.length; g++) {
            var st = this._map[group[g]];
            if (st) { steps.push(st); this._removeFrom(this._tools, group[g]); }
        }
        if (!steps.length) return;
        var dst = branch === "then" ? (parent.then || (parent.then = []))
                : branch === "else" ? (parent.else || (parent.else = []))
                : (parent.body || (parent.body = []));
        for (var k = 0; k < steps.length; k++) dst.push(steps[k]);
        this._setSelection(group);
        this._render(); this._applySelectionClasses(); this._emitSelection(); this._fireChange();
    };

    ToolCanvas.prototype._clearDrops = function() {
        this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(function(el) {
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
        });
        this._root.querySelectorAll(".drag-target").forEach(function(el) { el.classList.remove("drag-target"); });
    };

    ToolCanvas.prototype.updateTool = function(sid, params, opts) {
        var s = this._map[sid]; if (!s) return;
        for (var k in params) { if (params.hasOwnProperty(k)) s.params[k] = params[k]; }
        if (opts && opts.quiet) {
            this._patchSummary(sid);
            this._fireChange();
            return;
        }
        this._render(); this._fireChange();
    };

    ToolCanvas.prototype._patchSummary = function(sid) {
        var s = this._map[sid]; if (!s || !this._root) return;
        var block = this._root.querySelector('.tool-block[data-sid="' + sid + '"]');
        if (!block) return;
        var el = block.querySelector(":scope > .tool-params");
        if (el) el.textContent = paramSummary(s.action, s.params);
    };

    ToolCanvas.prototype.getSelectedId = function() { return this._selId; };
    ToolCanvas.prototype.getSelectedTool = function() { return this._selId ? this._map[this._selId] : null; };
    ToolCanvas.prototype.hasSelection = function() { return this._selCount() > 0; };
    ToolCanvas.prototype.getSelectedIds = function() { return this._selList(); };
    ToolCanvas.prototype.selectAll = function() {
        var ids = this._tools.map(function(s) { return s._sid; });
        this.select(ids);
    };
// END Drop a group into a container branch //

// Clipboard //
    ToolCanvas.prototype._setClipboard = function(steps) {
        var clones = deepClone(steps);
        this._strip(clones);
        try { navigator.clipboard.writeText(JSON.stringify(clones.length === 1 ? clones[0] : clones)); } catch(e) {}
        this._clipboard = clones;
        if (this._root) {
            this._root.classList.add("has-clip");
            this._root.querySelectorAll(".tool-nest-body-empty").forEach(function(el) { el.textContent = EMPTY_CLIP; });
        }
        return true;
    };
    ToolCanvas.prototype.copyStep = function(sid) {
        var step = sid ? this._map[sid] : null;
        if (!step) return false;
        return this._setClipboard([step]);
    };
    ToolCanvas.prototype.copySelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        var steps = [];
        for (var i = 0; i < ids.length; i++) { if (this._map[ids[i]]) steps.push(this._map[ids[i]]); }
        if (!steps.length) return false;
        return this._setClipboard(steps);
    };
    ToolCanvas.prototype.cutSelected = function() {
        if (!this.copySelected()) return false;
        this.removeSelected();
        return true;
    };
    ToolCanvas.prototype.removeSelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        for (var i = 0; i < ids.length; i++) {
            if (this._removeFrom(this._tools, ids[i])) delete this._map[ids[i]];
        }
        this._clearSelection();
        this._render();
        this._emitSelection();
        this._fireChange();
        return true;
    };
// END Clipboard //

// Paste the clipboard modules after `afterId` //
    ToolCanvas.prototype._insertClones = function(list, at, sources) {
        var newIds = [];
        for (var i = 0; i < sources.length; i++) {
            var clone = deepClone(sources[i]);
            this._strip([clone]);
            clone._sid = nextToolId();
            this._map[clone._sid] = clone;
            if (clone.then) this._assignIds(clone.then);
            if (clone.else) this._assignIds(clone.else);
            if (clone.body) this._assignIds(clone.body);
            list.splice(at + i, 0, clone);
            newIds.push(clone._sid);
        }
        if (!newIds.length) return false;
        this._setSelection(newIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        this._fireChange();
        return newIds[newIds.length - 1];
    };
    ToolCanvas.prototype._clipEntries = function() {
        if (!this._clipboard) return [];
        return Array.isArray(this._clipboard) ? this._clipboard : [this._clipboard];
    };
    ToolCanvas.prototype.pasteAfterId = function(afterId) {
        var entries = this._clipEntries();
        if (!entries.length) return false;
        var loc = afterId ? this._locate(afterId) : null;
        return !!this._insertClones(loc ? loc.list : this._tools, loc ? loc.idx + 1 : 0, entries);
    };
    ToolCanvas.prototype.pasteAfter = function() {
        var ids = this._selList();
        return this.pasteAfterId(ids.length ? ids[ids.length - 1] : null);
    };
    ToolCanvas.prototype.pasteInto = function(parentSid, branch) {
        var parent = this._map[parentSid];
        var entries = this._clipEntries();
        if (!parent || !this._isContainer(parent) || !entries.length) return false;
        branch = branch || (parent.action === "if" ? "then" : "body");
        if (!parent[branch]) parent[branch] = [];
        return !!this._insertClones(parent[branch], parent[branch].length, entries);
    };
    ToolCanvas.prototype.pasteInside = function() {
        var ids = this._selList();
        return ids.length ? this.pasteInto(ids[ids.length - 1]) : false;
    };
// END Paste the clipboard modules after `afterId` //

// Clone the selected blocks in place //
    ToolCanvas.prototype.duplicateSelected = function() {
        var ids = this._selList();
        var loc = ids.length ? this._locate(ids[ids.length - 1]) : null;
        if (!loc) return false;
        var sources = [];
        for (var i = 0; i < ids.length; i++) { if (this._map[ids[i]]) sources.push(this._map[ids[i]]); }
        return this._insertClones(loc.list, loc.idx + 1, sources);
    };
// END Clone the selected blocks in place //

// Wrap the selected siblings in a new container //
    var WRAP_ACTIONS = ["if", "while", "for", "repeat"];

    ToolCanvas.prototype.wrapSelected = function(def) {
        var ids = this._selList();
        var first = ids.length ? this._locate(ids[0]) : null;
        if (!first || !def) return false;
        var list = first.list;
        var idxs = [];
        for (var i = 0; i < ids.length; i++) {
            var loc = this._locate(ids[i]);
            if (loc && loc.list === list) idxs.push(loc.idx);
        }
        idxs.sort(function(a, b) { return a - b; });
        var box = deepClone(def);
        seedContainer(box);
        box._sid = nextToolId();
        this._map[box._sid] = box;
        var branch = box.action === "if" ? "then" : "body";
        for (var k = idxs.length - 1; k >= 0; k--) box[branch].unshift(list.splice(idxs[k], 1)[0]);
        list.splice(idxs[0], 0, box);
        this._setSelection([box._sid]);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        this._fireChange();
        return box._sid;
    };

    ToolCanvas.prototype.openWrapMenu = function() {
        var self = this;
        var ids = this._selList();
        if (!ids.length || !this.defFor) return false;
        var anchor = this._root.querySelector('.tool-block[data-sid="' + ids[0] + '"]');
        var r = (anchor || this._root).getBoundingClientRect();
        var menu = document.createElement("div");
        menu.className = "macro-overflow-menu";
        menu.style.cssText = "display:flex;flex-direction:column;position:fixed;z-index:1000;left:" + (r.left + 24) + "px;top:" + (r.bottom + 2) + "px";
        var close = function() {
            menu.remove();
            document.removeEventListener("mousedown", outside, true);
            document.removeEventListener("keydown", onKey, true);
        };
        var outside = function(e) { if (!menu.contains(e.target)) close(); };
        var onKey = function(e) { if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); } };
        WRAP_ACTIONS.forEach(function(action) {
            var b = document.createElement("button");
            b.className = "macro-toolbar-btn";
            b.innerHTML = (_svgCache[iconFor(action)] || "") + "<span>Wrap in " + action + "</span>";
            b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            b.addEventListener("click", function() {
                close();
                if (self.wrapSelected(self.defFor(action)) && window.playSlot) playSlot("interact");
            });
            menu.appendChild(b);
        });
        document.body.appendChild(menu);
        document.addEventListener("mousedown", outside, true);
        document.addEventListener("keydown", onKey, true);
        return true;
    };
// END Wrap the selected siblings in a new container //

    window.msSvgCache = _svgCache;
    window.msFetchSVG = _fetchSVG;
})();
