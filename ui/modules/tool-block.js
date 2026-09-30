// // Shell sounds //
function _sfx(el, clickSlot) {
    el.addEventListener("mouseenter", function() {
        if (window.playSlot) window.playSlot("hover");
    });
    el.addEventListener("click", function() {
        if (window.playSlot) window.playSlot(clickSlot || "interact");
    });
    return el;
}

// // SVG icon cache //
const _svgCache = {};

async function fetchSVG(base, name) {
    if (_svgCache[name]) return _svgCache[name];
    const url = base + name + ".svg";
    try {
        const resp = await fetch(url);
        if (!resp.ok) return "";
        const raw = await resp.text();
        const inner = raw
            .replace(/<\?xml[^>]*\?>/g, "")
            .replace(/<!--[\s\S]*?-->/g, "")
            .trim();
        _svgCache[name] = inner;
        return inner;
    } catch (_) {
        return "";
    }
}

// // Action -> icon mapping //
const ACTION_ICON_MAP = {
    "ms.type":          "keyboard",
    "ms.press":         "keyboard",
    "ms.hold":          "keyboard",
    "ms.release":       "keyboard",
    "ms.wait":          "timer",
    "ms.copy":          "clipboard",
    "ms.paste":         "clipboard",
    "ms.cam":           "camera",
    "ms.cam.rebalance": "camera",
    "ms.cam.reset":     "camera",
    "ms.click":         "click",
    "ms.scroll":        "scroll",
    "ms.move":          "move",
    "ms.select":        "select",
    "ms.search":        "search",
    "ms.record":        "record",
    "ms.stop":          "stop",
    "ms.pause":         "pause",
    "ms.play":          "play",
    "ms.save":          "save",
    "ms.load":          "upload",
    "ms.alert":         "alert",
    "ms.refresh":       "refresh",
    "ms.pixelScan":     "pixelscan",
    "ms.window":        "window",
    "ms.input":         "inputs",
    "ms.variable":      "variable",
    "ms.watch":         "watcher",
    "if":               "branch",
    "for":              "loop",
    "while":            "repeat",
    "else":             "branch",
};

function iconForAction(action) {
    return ACTION_ICON_MAP[action] || "macros";
}

// // Parameter summary //

function paramSummary(action, params) {
    if (!params) return "";
    const keys = Object.keys(params);
    if (keys.length === 0) return "";
    if (action === "if" || action === "while") return params.condition || "";
    if (action === "for") {
        return (params.var || "i") + " = " + (params.from ?? 1) + " -> " + (params.to ?? 1);
    }
    const parts = [];
    for (let i = 0; i < Math.min(keys.length, 2); i++) {
        const k = keys[i];
        let v = params[k];
        if (Array.isArray(v)) {
            if (v.length === 0) continue;
            v = v.join("+");
        }
        if (typeof v === "string" && v.length > 16) v = v.slice(0, 14) + "...";
        parts.push(k + ": " + v);
    }
    return parts.join(", ");
}

// // Step ID generator //
  let _toolIdCounter = 0;
  function nextToolId() {
      return "_tool_" + (++_toolIdCounter) + "_" + Date.now().toString(36);
  }

  function deepClone(obj) {
      return JSON.parse(JSON.stringify(obj));
  }

// // CSS //
  let _cssInjected = false;

  function injectCSS() {
      if (_cssInjected) return;
      _cssInjected = true;
      const style = document.createElement("style");
            style.textContent = `
        /* // Step Canvas (ES module) // */
        .tool-canvas {
            display: flex;
            flex-direction: column;
            gap: 2px;
            padding: 8px;
            min-height: 100%;
            overflow-y: auto;
            position: relative;
        }

        .tool-canvas::-webkit-scrollbar { width: 4px; }
        .tool-canvas::-webkit-scrollbar-track { background: transparent; }
        .tool-canvas::-webkit-scrollbar-thumb { background: var(--border-dim); border-radius: 2px; }
        .tool-canvas::-webkit-scrollbar-thumb:hover { background: var(--border); }

        .tool-canvas-empty {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: var(--text3);
            font-size: 11px;
            padding: 40px 20px;
            text-align: center;
            gap: 6px;
            user-select: none;
        }
        .tool-canvas-empty .tool-canvas-empty-icon { font-size: 28px; opacity: 0.25; }
        .tool-canvas-empty .tool-canvas-empty-icon svg { width: 28px; height: 28px; }

        .tool-block {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 5px 8px;
            background: var(--surface);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            cursor: default;
            transition: background 0.1s, border-color 0.15s, box-shadow 0.15s;
            position: relative;
            user-select: none;
            -webkit-user-select: none;
            min-height: 32px;
        }
        .tool-block:hover { background: var(--surface2); border-color: var(--border); }
        .tool-block.selected {
            border-color: var(--accent);
            box-shadow: 0 0 0 1px var(--accent-glow-faint, color-mix(in srgb, var(--accent) 12%, transparent));
        }

        .tool-block.drag-over-above::before {
            content: "";
            position: absolute;
            top: -3px;
            left: 4px;
            right: 4px;
            height: 2px;
            background: var(--accent);
            border-radius: 1px;
            z-index: 10;
        }
        .tool-block.drag-over-below::after {
            content: "";
            position: absolute;
            bottom: -3px;
            left: 4px;
            right: 4px;
            height: 2px;
            background: var(--accent);
            border-radius: 1px;
            z-index: 10;
        }
        .tool-block.drag-over-nest {
            border-color: var(--accent);
            background: var(--accent-glow-faint, color-mix(in srgb, var(--accent) 12%, transparent));
        }
        .tool-block.dragging { opacity: 0.4; }

        .tool-drag-handle {
            width: 14px; height: 14px; flex-shrink: 0;
            display: flex; align-items: center; justify-content: center;
            cursor: grab; opacity: 0.35; transition: opacity 0.15s;
        }
        .tool-drag-handle:hover { opacity: 0.8; }
        .tool-drag-handle:active { cursor: grabbing; }
        .tool-drag-handle svg { width: 14px; height: 14px; }
        .tool-drag-handle svg path, .tool-drag-handle svg g { stroke: var(--text); fill: none; }

        .tool-icon {
            width: 16px; height: 16px; flex-shrink: 0;
            display: flex; align-items: center; justify-content: center;
        }
        .tool-icon svg { width: 14px; height: 14px; }
        .tool-icon svg path, .tool-icon svg g,
        .tool-icon svg circle, .tool-icon svg rect { stroke: var(--accent); fill: none; }

        .step-action-name {
            font-family: var(--font-mono);
            font-size: 11px; color: var(--text); font-weight: 600;
            white-space: nowrap; flex-shrink: 0;
        }
        .step-params {
            font-family: var(--font-mono);
            font-size: 10px; color: var(--text3);
            white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
            flex: 1; min-width: 0;
        }

        .step-actions {
            display: flex; align-items: center; gap: 2px;
            flex-shrink: 0; opacity: 0; transition: opacity 0.15s;
        }
        .tool-block:hover .step-actions { opacity: 1; }

        .step-action-btn {
            width: 18px; height: 18px;
            display: flex; align-items: center; justify-content: center;
            border-radius: var(--radius-s); cursor: pointer;
            opacity: 0.5; transition: opacity 0.1s, background 0.1s;
        }
        .step-action-btn:hover { opacity: 1; background: var(--hover); }
        .step-action-btn svg { width: 12px; height: 12px; }
        .step-action-btn svg path, .step-action-btn svg g { stroke: var(--text); fill: none; }
        .step-action-btn.del:hover { background: var(--danger-bg); }
        .step-action-btn.del:hover svg path { stroke: var(--danger); }

        .tool-block-container { display: flex; flex-direction: column; }

        .tool-nest-body {
            margin-left: 20px;
            border-left: 2px solid var(--border-dim);
            padding-left: 8px; padding-top: 2px; padding-bottom: 2px;
            display: flex; flex-direction: column; gap: 2px;
            min-height: 28px; position: relative;
        }
        .tool-nest-body.drag-target {
            border-left-color: var(--accent);
            background: var(--accent-glow-faint, color-mix(in srgb, var(--accent) 6%, transparent));
            border-radius: var(--radius);
        }
        .step-nest-label {
            font-size: 9px; font-weight: 700;
            text-transform: uppercase; letter-spacing: 0.6px;
            color: var(--text3); padding: 2px 0 0;
        }
        .tool-nest-body-empty {
            font-size: 10px; color: var(--text3);
            font-style: italic; padding: 4px 0; opacity: 0.6;
        }

        .tool-nest-toggle {
            width: 14px; height: 14px; flex-shrink: 0;
            display: flex; align-items: center; justify-content: center;
            cursor: pointer; opacity: 0.5;
            transition: opacity 0.15s, transform 0.15s;
            font-size: 10px; color: var(--text);
        }
        .tool-nest-toggle:hover { opacity: 1; }
        .tool-nest-toggle.collapsed { transform: rotate(-90deg); }
        .tool-nest-toggle svg { width: 12px; height: 12px; }
        .tool-nest-toggle svg path { stroke: var(--text); fill: none; }
        .tool-nest-body.collapsed { display: none; }
        .step-nest-label.collapsed { display: none; }
        `;
      document.head.appendChild(style);
  }

// // ToolCanvas class //
  export class ToolCanvas {
      constructor(container, opts = {}) {
          injectCSS();

          this._el = container;
          this._onChange = opts.onChange || (() => {});
          this._onSelect = opts.onSelect || (() => {});
          this._svgBase = opts.svgBase || "./svg/";

          // Internal storage
          this._tools = [];
          this._map = {};
          this._selId = null;
          this._dragId = null;

          // Build root
          this._root = document.createElement("div");
          this._root.className = "tool-canvas";
          this._el.appendChild(this._root);

          this._renderEmpty();
          this._preloadIcons();
      }

      // // Icon preloading //

      async _preloadIcons() {
          const needed = new Set(["drag", "close", "chevdown", "chevup", "trash", "edit", "macros", "tools"]);
          for (const action in ACTION_ICON_MAP) needed.add(ACTION_ICON_MAP[action]);
          for (const name of needed) await fetchSVG(this._svgBase, name);
      }

      // // Tool ID management //

      _assignIds(tools) {
          for (const tool of tools) {
              if (!tool._sid) tool._sid = nextToolId();
              this._map[tool._sid] = tool;
              if (tool.then) this._assignIds(tool.then);
              if (tool.else) this._assignIds(tool.else);
              if (tool.body) this._assignIds(tool.body);
          }
      }

      // // Load tools //

      load(tools) {
          this._tools = tools || [];
          this._map = {};
          this._assignIds(this._tools);
          this._selId = null;
          this._render();
      }

      // // Add a tool //

      addTool(toolDef, afterId) {
          const tool = deepClone(toolDef);
          tool._sid = nextToolId();
          this._map[tool._sid] = tool;

          if (afterId) {
              const idx = this._findIdx(this._tools, afterId);
              if (idx !== -1) this._tools.splice(idx + 1, 0, tool);
              else this._tools.push(tool);
          } else {
              this._tools.push(tool);
          }
          this._render();
          this._fireChange();
      }

      // // Remove a tool //

      removeTool(sid) {
          if (this._removeFrom(this._tools, sid)) {
              delete this._map[sid];
              if (this._selId === sid) this._selId = null;
              this._render();
              this._fireChange();
          }
      }

      _removeFrom(list, sid) {
          for (let i = 0; i < list.length; i++) {
              if (list[i]._sid === sid) { list.splice(i, 1); return true; }
              const s = list[i];
              if (s.then && this._removeFrom(s.then, sid)) return true;
              if (s.else && this._removeFrom(s.else, sid)) return true;
              if (s.body && this._removeFrom(s.body, sid)) return true;
          }
          return false;
      }

      _findIdx(list, sid) {
          for (let i = 0; i < list.length; i++) {
              if (list[i]._sid === sid) return i;
          }
          return -1;
      }

      // // Move tool //

      moveTool(dragId, targetId, pos) {
          const tool = this._map[dragId];
          if (!tool) return;
          this._removeFrom(this._tools, dragId);

          if (pos === "nest") {
              const tgt = this._map[targetId];
              if (tgt) {
                  if (tgt.action === "if") {
                      if (!tgt.then) tgt.then = [];
                      tgt.then.push(tool);
                  } else {
                      if (!tgt.body) tgt.body = [];
                      tgt.body.push(tool);
                  }
              }
          } else {
              const ti = this._findIdx(this._tools, targetId);
              if (ti !== -1) {
                  this._tools.splice(pos === "above" ? ti : ti + 1, 0, tool);
              } else {
                  this._tools.push(tool);
              }
          }
          this._render();
          this._fireChange();
      }

      // // Serialize //

      serialize() {
          return this._strip(deepClone(this._tools));
      }

      _strip(tools) {
          for (const tool of tools) {
              delete tool._sid;
              if (tool.then) this._strip(tool.then);
              if (tool.else) this._strip(tool.else);
              if (tool.body) this._strip(tool.body);
          }
          return tools;
      }

      // // Update params //

      updateTool(sid, newParams) {
          const tool = this._map[sid];
          if (!tool) return;
          Object.assign(tool.params, newParams);
          this._render();
          this._fireChange();
      }

      // // Selection //

      getSelectedId() { return this._selId; }
      getSelectedTool() { return this._selId ? this._map[this._selId] : null; }

      // // Clipboard (copy / cut / paste) //

      copySelected() {
          const tool = this.getSelectedTool();
          if (!tool) return false;
          const clone = deepClone(tool);
          this._strip([clone]);
          try { navigator.clipboard.writeText(JSON.stringify(clone)); } catch(e) {}
          this._clipboard = clone;
          return true;
      }

      cutSelected() {
          const sid = this._selId;
          if (!sid || !this._map[sid]) return false;
          this.copySelected();
          this.removeTool(sid);
          return true;
      }

      pasteAfter() {
          if (!this._clipboard) return false;
          const clone = deepClone(this._clipboard);
          clone._sid = nextToolId();
          this._map[clone._sid] = clone;
          // Assign IDs to children
          if (clone.then) this._assignIds(clone.then);
          if (clone.else) this._assignIds(clone.else);
          if (clone.body) this._assignIds(clone.body);

          const afterId = this._selId;
          if (afterId) {
              const idx = this._findIdx(this._tools, afterId);
              if (idx !== -1) this._tools.splice(idx + 1, 0, clone);
              else this._tools.push(clone);
          } else {
              this._tools.push(clone);
          }
          this._selId = clone._sid;
          this._render();
          this._fireChange();
          return true;
      }

      _selectTool(sid) {
          this._selId = sid;
          this._root.querySelectorAll(".tool-block.selected").forEach(el => el.classList.remove("selected"));
          const el = this._root.querySelector(
              `[data-sid="${sid}"] > .tool-block[data-sid="${sid}"], .tool-block[data-sid="${sid}"]`
          );
          if (el) el.classList.add("selected");
          this._onSelect(sid, this._map[sid]);
      }

      // // Fire change //

      _fireChange() { this._onChange(this.serialize()); }

      // // Render //

      _render() {
          this._root.innerHTML = "";
          if (this._tools.length === 0) { this._renderEmpty(); return; }
          for (const tool of this._tools) {
              this._root.appendChild(this._renderTool(tool));
          }
      }

      _renderEmpty() {
          this._root.innerHTML = "";
          const d = document.createElement("div");
          d.className = "tool-canvas-empty";
          d.innerHTML = '<span class="tool-canvas-empty-icon">' + (_svgCache["tools"] || "") + '</span>'
              + 'No tools yet<br><span style="font-size:10px">Click <b>+ Add Tool</b> to begin</span>';
          this._root.appendChild(d);
      }

      _isContainer(s) {
          return s.action === "if" || s.action === "for" || s.action === "while";
      }

      _renderTool(tool) {
          return this._isContainer(tool) ? this._renderContainer(tool) : this._renderLeaf(tool);
      }

      _renderLeaf(tool) {
          const el = document.createElement("div");
          el.className = "tool-block" + (tool._sid === this._selId ? " selected" : "");
          el.setAttribute("data-sid", tool._sid);
          el.setAttribute("draggable", "true");

          const handle = document.createElement("div");
          handle.className = "tool-drag-handle";
          handle.innerHTML = _svgCache["drag"] || "";
          el.appendChild(handle);

          const icon = document.createElement("div");
          icon.className = "tool-icon";
          icon.innerHTML = _svgCache[iconForAction(tool.action)] || "";
          el.appendChild(icon);

          const name = document.createElement("span");
          name.className = "step-action-name";
          name.textContent = tool.action;
          el.appendChild(name);

          const params = document.createElement("span");
          params.className = "step-params";
          params.textContent = paramSummary(tool.action, tool.params);
          el.appendChild(params);

          const acts = document.createElement("div");
          acts.className = "step-actions";
          const del = document.createElement("div");
          del.className = "step-action-btn del";
          del.innerHTML = _svgCache["trash"] || "x";
          _sfx(del, "back");
          del.addEventListener("click", e => { e.stopPropagation(); this.removeTool(tool._sid); });
          acts.appendChild(del);
          const editBtn = document.createElement("div");
          editBtn.className = "step-action-btn edit";
          editBtn.innerHTML = _svgCache["edit"] || "";
          _sfx(editBtn);
          editBtn.addEventListener("click", e => { e.stopPropagation(); this._selectTool(tool._sid); });
          acts.appendChild(editBtn);
          el.appendChild(acts);

          el.addEventListener("click", e => {
              if (e.target.closest(".step-action-btn") || e.target.closest(".tool-drag-handle")) return;
              this._selectTool(tool._sid);
          });
          this._wireDrag(el, tool);
          return el;
      }

      _renderContainer(tool) {
          const wrap = document.createElement("div");
          wrap.className = "tool-block-container";
          wrap.setAttribute("data-sid", tool._sid);

          const header = document.createElement("div");
          header.className = "tool-block" + (tool._sid === this._selId ? " selected" : "");
          header.setAttribute("data-sid", tool._sid);
          header.setAttribute("draggable", "true");

          const handle = document.createElement("div");
          handle.className = "tool-drag-handle";
          handle.innerHTML = _svgCache["drag"] || "";
          header.appendChild(handle);

          const toggle = document.createElement("div");
          toggle.className = "tool-nest-toggle";
          toggle.innerHTML = _svgCache["chevdown"] || "";
          _sfx(toggle);
          toggle.addEventListener("click", e => {
              e.stopPropagation();
              const collapsed = toggle.classList.toggle("collapsed");
              // Collapse every branch of THIS container, an `if` has both a
              // "then" and an "else" nest, each with its own label. A plain
              // querySelector(".tool-nest-body") stopped at "then" and left
              // "else" (and both labels) showing. Only direct children are
              // touched, so a nested block keeps its own collapse state.
              for (const child of wrap.children) {
                  if (child.classList.contains("tool-nest-body")
                      || child.classList.contains("step-nest-label")) {
                      child.classList.toggle("collapsed", collapsed);
                  }
              }
          });
          header.appendChild(toggle);

          const icon = document.createElement("div");
          icon.className = "tool-icon";
          icon.innerHTML = _svgCache[iconForAction(tool.action)] || "";
          header.appendChild(icon);

          const name = document.createElement("span");
          name.className = "step-action-name";
          name.textContent = tool.action;
          header.appendChild(name);

          const params = document.createElement("span");
          params.className = "step-params";
          params.textContent = paramSummary(tool.action, tool.params);
          header.appendChild(params);

          const acts = document.createElement("div");
          acts.className = "step-actions";
          const del = document.createElement("div");
          del.className = "step-action-btn del";
          del.innerHTML = _svgCache["trash"] || "x";
          _sfx(del, "back");
          del.addEventListener("click", e => { e.stopPropagation(); this.removeTool(tool._sid); });
          acts.appendChild(del);
          const editBtn = document.createElement("div");
          editBtn.className = "step-action-btn edit";
          editBtn.innerHTML = _svgCache["edit"] || "";
          _sfx(editBtn);
          editBtn.addEventListener("click", e => { e.stopPropagation(); this._selectTool(tool._sid); });
          acts.appendChild(editBtn);
          header.appendChild(acts);

          header.addEventListener("click", e => {
              if (e.target.closest(".step-action-btn") || e.target.closest(".tool-drag-handle") || e.target.closest(".tool-nest-toggle")) return;
              this._selectTool(tool._sid);
          });
          this._wireDrag(header, tool);
          wrap.appendChild(header);

          if (tool.action === "if") {
              const tl = document.createElement("div");
              tl.className = "step-nest-label"; tl.textContent = "then";
              wrap.appendChild(tl);
              wrap.appendChild(this._renderNest(tool.then || [], "then", tool));

              const el2 = document.createElement("div");
              el2.className = "step-nest-label"; el2.textContent = "else";
              wrap.appendChild(el2);
              wrap.appendChild(this._renderNest(tool.else || [], "else", tool));
          } else {
              wrap.appendChild(this._renderNest(tool.body || [], "body", tool));
          }
          return wrap;
      }

      _renderNest(tools, branch, parent) {
          const body = document.createElement("div");
          body.className = "tool-nest-body";
          body.setAttribute("data-nest-parent", parent._sid);
          body.setAttribute("data-nest-branch", branch);

          if (tools.length === 0) {
              const empty = document.createElement("div");
              empty.className = "tool-nest-body-empty";
              empty.textContent = "empty";
              body.appendChild(empty);
          } else {
              for (const child of tools) body.appendChild(this._renderTool(child));
          }

          body.addEventListener("dragover", e => {
              if (!this._dragId) return;
              e.preventDefault(); e.stopPropagation();
              e.dataTransfer.dropEffect = "move";
              body.classList.add("drag-target");
          });
          body.addEventListener("dragleave", () => body.classList.remove("drag-target"));
          body.addEventListener("drop", e => {
              e.preventDefault(); e.stopPropagation();
              if (!this._dragId) return;
              const tool = this._map[this._dragId];
              if (!tool) return;
              this._removeFrom(this._tools, this._dragId);
              if (branch === "then") { if (!parent.then) parent.then = []; parent.then.push(tool); }
              else if (branch === "else") { if (!parent.else) parent.else = []; parent.else.push(tool); }
              else { if (!parent.body) parent.body = []; parent.body.push(tool); }
              body.classList.remove("drag-target");
              this._dragId = null;
              this._render();
              this._fireChange();
          });
          return body;
      }

      // // Drag and drop //

      _isDesc(pid, cid) {
          const p = this._map[pid];
          if (!p) return false;
          const ch = [].concat(p.then || [], p.else || [], p.body || []);
          for (const c of ch) {
              if (c._sid === cid) return true;
              if (this._isDesc(c._sid, cid)) return true;
          }
          return false;
      }

      _wireDrag(el, tool) {
          el.addEventListener("dragstart", e => {
              this._dragId = tool._sid;
              el.classList.add("dragging");
              e.dataTransfer.effectAllowed = "move";
              e.dataTransfer.setData("text/plain", tool._sid);
              const ghost = el.cloneNode(true);
              ghost.style.width = el.offsetWidth + "px";
              ghost.style.opacity = "0.7";
              ghost.style.position = "absolute";
              ghost.style.top = "-1000px";
              document.body.appendChild(ghost);
              e.dataTransfer.setDragImage(ghost, 10, 10);
              requestAnimationFrame(() => ghost.remove());
          });

          el.addEventListener("dragend", () => {
              this._dragId = null;
              el.classList.remove("dragging");
              this._clearDrops();
          });

          el.addEventListener("dragover", e => {
              if (!this._dragId || this._dragId === tool._sid) return;
              e.preventDefault();
              e.dataTransfer.dropEffect = "move";
              const rect = el.getBoundingClientRect();
              const y = e.clientY - rect.top;
              const h = rect.height;
              const isC = this._isContainer(tool);
              el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
              if (isC && y > h * 0.3 && y < h * 0.7) el.classList.add("drag-over-nest");
              else if (y < h / 2) el.classList.add("drag-over-above");
              else el.classList.add("drag-over-below");
          });

          el.addEventListener("dragleave", () => {
              el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
          });

          el.addEventListener("drop", e => {
              e.preventDefault();
              e.stopPropagation();
              if (!this._dragId || this._dragId === tool._sid) return;
              const rect = el.getBoundingClientRect();
              const y = e.clientY - rect.top;
              const h = rect.height;
              const isC = this._isContainer(tool);
              let pos;
              if (isC && y > h * 0.3 && y < h * 0.7) pos = "nest";
              else if (y < h / 2) pos = "above";
              else pos = "below";
              if (pos === "nest" && this._isDesc(tool._sid, this._dragId)) { this._clearDrops(); return; }
              this.moveTool(this._dragId, tool._sid, pos);
              this._clearDrops();
          });
      }

      _clearDrops() {
          this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(el => {
              el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
          });
          this._root.querySelectorAll(".drag-target").forEach(el => el.classList.remove("drag-target"));
      }

      // // Destroy //

      destroy() {
          this._root.innerHTML = "";
          this._tools = [];
          this._map = {};
      }
  }
// // END ToolCanvas class //

// // Expose on window for IIFE contexts //
  if (typeof window !== "undefined") {
      window.ToolCanvas = ToolCanvas;
  }
// END Expose for IIFE contexts //
