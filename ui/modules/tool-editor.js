// Shell sounds //
  function _sfx(el, clickSlot) {
      el.addEventListener("mouseenter", function() {
          if (window.playSlot) window.playSlot("hover");
      });
      el.addEventListener("click", function() {
          if (window.playSlot) window.playSlot(clickSlot || "interact");
      });
      return el;
  }
// END Shell sounds //

// Parameter Definitions //
  const PARAM_DEFS = {
      "ms.type":          { key: "key", mods: "mods" },
      "ms.press":         { key: "key", mods: "mods" },
      "ms.hold":          { key: "key" },
      "ms.release":       { key: "key" },
      "ms.wait":          { ms: "number" },
      "ms.cam":           { dx: "number", dy: "number" },
      // NOTE: these option sets must match ms_core.lua's OPS/BTNS/REFS. They are
      // normally shadowed by the shared registry (see _getParamDefs); kept here
      // only as a correct fallback.
      "ms.Mouse":         { operation: { type: "select", options: ["Move","Click","DoubleClick","TripleClick","Drag","Press","Release"] },
                            button:    { type: "select", options: ["Left","Right","Center","Button4","Button5"] },
                            reference: { type: "select", options: ["Absolute","Mouse","WindowTL","WindowTR","WindowBL","WindowBR","WindowCenter","ScreenTL","ScreenTR","ScreenBL","ScreenBR","ScreenCenter"] },
                            x1: "number", y1: "number", x2: "number", y2: "number" },
      "ms.click":         { button: { type: "select", options: ["Left","Right","Center","Button4","Button5"] },
                            x: "number", y: "number" },
      "ms.scroll":        { direction: { type: "select", options: ["up","down","left","right"] }, clicks: "number" },
      "ms.copy":          { text: "string" },
      "ms.input":         { text: "string" },
      "ms.search":        { text: "string" },
      "ms.variable":      { name: "string", value: "string" },
      "ms.watch":         { event: "string" },
      "ms.window":        { operation: { type: "select", options: ["Move","Resize","Frame"] } },
      "ms.alert":         { text: "string" },
      "ms.load":          { path: "string" },
      "ms.save":          { path: "string" },
      "ms.pixelScan":     { region: "string" },
      "if":               { condition: "condition" },
      "while":            { condition: "condition" },
      "repeat":           { condition: "condition" },
      "for":              { var: "string", from: "number", to: "number", step: "number" },
      "call_fn":          { name: "string" },
      "hvar_set":         { name: "string", value: "string" },
      "var_set":          { name: "string", value: "string" },
      "var_add":          { name: "string", amount: "number" },
      "var_sub":          { name: "string", amount: "number" },
      "var_mul":          { name: "string", amount: "number" },
      "comment":          { text: "string" },
      "code":             { source: "condition" },
  };

  const STRUCTURAL_KEYS = new Set(["then", "else", "body"]);
// END Parameter Definitions //

// Key Normalization //
  function normalizeKey(e) {
      const map = {
          " ":           "space",
          "ArrowUp":     "up",
          "ArrowDown":   "down",
          "ArrowLeft":   "left",
          "ArrowRight":  "right",
          "Backspace":   "delete",
          "Escape":      "escape",
          "Enter":       "return",
          "Tab":         "tab",
          "CapsLock":    "capslock",
          "Shift":       "shift",
          "Control":     "ctrl",
          "Alt":         "alt",
          "Meta":        "cmd",
          "Delete":      "forwarddelete",
          "Home":        "home",
          "End":         "end",
          "PageUp":      "pageup",
          "PageDown":    "pagedown",
          "Insert":      "help",
          "F1": "f1", "F2": "f2", "F3": "f3", "F4": "f4",
          "F5": "f5", "F6": "f6", "F7": "f7", "F8": "f8",
          "F9": "f9", "F10": "f10", "F11": "f11", "F12": "f12",
      };
      if (map[e.key]) return map[e.key];
      if (e.key.length === 1) return e.key.toLowerCase();
      return e.key.toLowerCase();
  }

  function esc(s) {
      const d = document.createElement("div");
      d.appendChild(document.createTextNode(s));
      return d.innerHTML;
  }
// END Key Normalization //

// CSS (injected once) //
  let _cssInjected = false;

  function injectCSS() {
      if (_cssInjected) return;
      _cssInjected = true;
      const style = document.createElement("style");
      style.id = "tool-editor-css";
      style.textContent = `
        /* // Step Inline Editor // */
        .tool-editor-panel {
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 0 0 var(--radius) var(--radius);
            margin: 0 2px 4px 2px;
            overflow: hidden;
            max-height: 0;
            opacity: 0;
            transition: max-height 0.25s ease, opacity 0.2s ease, padding 0.25s ease;
            padding: 0 12px;
            box-sizing: border-box;
            position: relative;
        }
        .tool-editor-panel.open {
            max-height: 500px;
            opacity: 1;
            padding: 10px 12px 12px 12px;
        }

        .tool-editor-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 10px;
            padding-bottom: 6px;
            border-bottom: 1px solid var(--border-dim);
        }
        .tool-editor-title {
            font-family: var(--font-mono);
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.6px;
            color: var(--text3);
        }
        .tool-editor-close {
            width: 18px; height: 18px;
            display: flex; align-items: center; justify-content: center;
            border-radius: var(--radius-s);
            cursor: pointer;
            opacity: 0.4;
            transition: opacity 0.1s, background 0.1s;
        }
        .tool-editor-close:hover {
            opacity: 1;
            background: var(--hover);
        }
        .tool-editor-close svg { width: 12px; height: 12px; }
        .tool-editor-close svg path { stroke: var(--text); fill: none; }

        /* // Form Grid // */
        .tool-editor-form {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        .tool-editor-row {
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .tool-editor-label {
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.6px;
            color: var(--text3);
            width: 80px;
            flex-shrink: 0;
            text-align: right;
            padding-right: 4px;
        }
        .tool-editor-control {
            flex: 1;
            min-width: 0;
            display: flex;
            align-items: center;
            gap: 4px;
        }

        /* // Text Input // */
        .tool-ed-text {
            width: 100%;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text);
            font-family: var(--font-mono);
            font-size: 11px;
            padding: 4px 7px;
            outline: none;
            transition: border-color 0.15s;
            user-select: text;
            -webkit-user-select: text;
            box-sizing: border-box;
        }
        .tool-ed-text:focus { border-color: var(--accent); }

        /* // Value / Tool bind switch // */
        .tool-editor-control.tool-ed-bindable { flex-wrap: wrap; }
        .tool-ed-bind-switch { display: inline-flex; border: 1px solid var(--border-dim); border-radius: var(--radius-s); overflow: hidden; }
        .tool-ed-bind-opt { background: var(--surface2); border: none; color: var(--text3); font-size: 8px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.4px; padding: 2px 6px; cursor: pointer; transition: all 0.1s; }
        .tool-ed-bind-opt:hover { color: var(--text); }
        .tool-ed-bind-opt.on { background: var(--accent-glow-faint); color: var(--accent-hi); }
        .tool-ed-bind-holder { flex: 1 1 100%; min-width: 0; display: flex; align-items: center; gap: 4px; }
        .tool-ed-tool-select { width: 100%; background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text); font-family: var(--font-mono); font-size: 11px; padding: 4px 7px; outline: none; cursor: pointer; box-sizing: border-box; }
        .tool-ed-tool-select:focus { border-color: var(--accent); }

        /* // Number Input // */
        .tool-ed-number-wrap {
            display: flex;
            align-items: center;
            gap: 0;
            flex: 1;
        }
        .tool-ed-number {
            width: 100%;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text);
            font-family: var(--font-mono);
            font-size: 11px;
            padding: 4px 7px;
            outline: none;
            transition: border-color 0.15s;
            user-select: text;
            -webkit-user-select: text;
            -moz-appearance: textfield;
            box-sizing: border-box;
        }
        .tool-ed-number::-webkit-inner-spin-button,
        .tool-ed-number::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }
        .tool-ed-number:focus { border-color: var(--accent); }

        .tool-ed-num-btn {
            width: 24px;
            height: 26px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            color: var(--text3);
            font-size: 13px;
            font-weight: 700;
            cursor: pointer;
            transition: background 0.1s, color 0.1s, border-color 0.1s;
            user-select: none;
            -webkit-user-select: none;
            flex-shrink: 0;
        }
        .tool-ed-num-btn:hover {
            background: var(--hover);
            color: var(--text);
            border-color: var(--border);
        }
        .tool-ed-num-btn:first-child { border-radius: var(--radius) 0 0 var(--radius); border-right: none; }
        .tool-ed-num-btn:last-child  { border-radius: 0 var(--radius) var(--radius) 0; border-left: none; }
        .tool-ed-num-btn:only-child  { border-radius: var(--radius); }

        /* // Key Capture Button // */
        .tool-ed-key-btn {
            display: inline-flex;
            align-items: center;
            justify-content: center;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text);
            font-family: var(--font-mono);
            font-size: 11px;
            padding: 4px 12px;
            cursor: pointer;
            transition: border-color 0.15s, background 0.15s;
            min-width: 50px;
            text-align: center;
            user-select: text;
            -webkit-user-select: text;
        }
        .tool-ed-key-btn:hover { border-color: var(--accent); }
        .tool-ed-key-btn.capturing {
            border-color: var(--accent);
            background: color-mix(in srgb, var(--accent) 15%, transparent);
            color: var(--accent-hi);
            animation: tool-ed-pulse 1s ease-in-out infinite;
        }
        @keyframes tool-ed-pulse {
            0%, 100% { opacity: 1; }
            50%      { opacity: 0.5; }
        }
        .tool-ed-key-hint {
            font-size: 9px;
            color: var(--text3);
            opacity: 0.6;
            font-style: italic;
        }

        /* // Modifier Chips // */
        .tool-ed-mods {
            display: flex;
            gap: 3px;
        }
        .tool-ed-mod-chip {
            display: flex;
            align-items: center;
            justify-content: center;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text3);
            font-family: var(--font-mono);
            font-size: 10px;
            font-weight: 600;
            padding: 3px 8px;
            cursor: pointer;
            transition: all 0.1s;
            user-select: none;
            -webkit-user-select: none;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }
        .tool-ed-mod-chip:hover {
            border-color: var(--accent);
            color: var(--text);
        }
        .tool-ed-mod-chip.on {
            background: color-mix(in srgb, var(--accent) 18%, transparent);
            border-color: var(--accent);
            color: var(--accent-hi);
        }

        /* // Select Dropdown // */
        .tool-ed-select {
            width: 100%;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text);
            font-family: var(--font-mono);
            font-size: 11px;
            padding: 4px 7px;
            outline: none;
            cursor: pointer;
            transition: border-color 0.15s;
            user-select: text;
            -webkit-user-select: text;
            -webkit-appearance: none;
            box-sizing: border-box;
        }
        .tool-ed-select:focus { border-color: var(--accent); }
        .tool-ed-select option { background: var(--surface); color: var(--text); }

        /* // Condition / Expression Editor // */
        .tool-ed-condition {
            width: 100%;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--accent-hi);
            font-family: var(--font-mono);
            font-size: 11px;
            padding: 5px 8px;
            outline: none;
            resize: vertical;
            min-height: 28px;
            max-height: 100px;
            line-height: 1.5;
            transition: border-color 0.15s;
            user-select: text;
            -webkit-user-select: text;
            box-sizing: border-box;
        }
        .tool-ed-condition:focus { border-color: var(--accent); }
        .tool-ed-condition::placeholder { color: var(--text3); opacity: 1; }

        /* // Live condition truth note // */
        .tool-ed-cond-live {
            margin-top: 6px;
            font-family: var(--font-mono);
            font-size: 10px;
            line-height: 1.4;
            letter-spacing: .3px;
            color: var(--text3);
        }
        .tool-ed-cond-live.cond-true    { color: var(--success); }
        .tool-ed-cond-live.cond-false   { color: var(--text3); }
        .tool-ed-cond-live.cond-missing { color: var(--warning); }

        /* // Array Editor // */
        .tool-ed-array {
            display: flex;
            flex-direction: column;
            gap: 4px;
            width: 100%;
        }
        .tool-ed-array-item {
            display: flex;
            align-items: center;
            gap: 4px;
        }
        .tool-ed-array-item .tool-ed-text { flex: 1; }
        .tool-ed-array-remove {
            width: 20px; height: 20px;
            display: flex; align-items: center; justify-content: center;
            border-radius: var(--radius-s);
            cursor: pointer;
            opacity: 0.4;
            transition: opacity 0.1s, background 0.1s;
            flex-shrink: 0;
            color: var(--text3);
            font-size: 14px;
            font-weight: 700;
        }
        .tool-ed-array-remove:hover { opacity: 1; background: var(--danger-bg); color: var(--danger); }
        .tool-ed-array-remove svg { width: 12px; height: 12px; }
        .tool-ed-array-remove svg path { stroke: currentColor; fill: none; }
        .tool-ed-array-add {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 3px 8px;
            background: var(--surface2);
            border: 1px solid var(--border-dim);
            border-radius: var(--radius);
            color: var(--text3);
            font-size: 10px;
            font-weight: 600;
            cursor: pointer;
            transition: border-color 0.1s, color 0.1s;
            align-self: flex-start;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }
        .tool-ed-array-add:hover { border-color: var(--accent); color: var(--text); }

        /* // No-params // */
        .tool-ed-no-params {
            color: var(--text3);
            font-size: 11px;
            font-style: italic;
            padding: 4px 0;
        }
        .tool-ed-setting-info { padding: 4px 0; }
        .tool-ed-setting-name { font-size: 13px; font-weight: 700; color: var(--text); }
        .tool-ed-setting-meta { font-size: 10px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--accent); margin-top: 2px; }
        .tool-ed-setting-hint { font-size: 11px; color: var(--text3); margin-top: 8px; line-height: 1.5; }
        .tool-ed-setting-hint code { font-family: var(--font-mono); font-size: 10.5px; color: var(--accent-hi, var(--accent)); background: color-mix(in srgb, var(--accent) 12%, transparent); padding: 1px 4px; border-radius: 3px; }
        `;
      document.head.appendChild(style);
  }
// END CSS//

// ToolEditor Class //
  class ToolEditor {
      constructor(opts = {}) {
          injectCSS();

          this._canvas  = opts.canvas;
          this._svgBase = opts.svgBase || "./svg/";
          this._onUpdate = opts.onUpdate || (() => {});

          this._toolSid   = null;
          this._toolEl    = null;
          this._panelEl   = null;
          this._formEl    = null;
          this._open      = false;
          this._capturingKey = null;
          this._keyHandler = null;

          this._hookCanvasRender();

          this._onEscape = (e) => {
              if (e.key === "Escape" && this._open) {
                  e.stopPropagation();
                  this.close();
              }
          };
      }

      static _isToolRef(v) {
          return !!(v && typeof v === "object"
              && (typeof v.__toolRef === "string" || typeof v.__varRef === "string"));
      }
      static _refKey(v) {
          if (!v || typeof v !== "object") return "";
          if (typeof v.__toolRef === "string") return v.__toolRef;
          if (typeof v.__varRef === "string")  return v.__varRef;
          return "";
      }
      static _refFor(key) {
          const tools = ToolEditor._toolList();
          for (let i = 0; i < tools.length; i++) {
              if (tools[i].key === key && tools[i].kind === "var") {
                  return { __varRef: key };
              }
          }
          return { __toolRef: key };
      }
      static _toolList() {
          return Array.isArray(window.msMacroTools) ? window.msMacroTools : [];
      }
      // Evaluate a Lua-style truthiness for a tool/var's current value: only
      // nil and false are falsey (0 and "" are true), matching the runtime.
      static _luaTruthy(v) {
          return !(v === null || v === undefined || v === false);
      }
      // Paint the live-truth note for a condition wired to a tool/var. Reads
      // the tool's current value from the same list the picker shows.
      static _renderCondLive(el, value) {
          el.className = "tool-ed-cond-live";
          el.textContent = "";
          if (!value || typeof value !== "object") { el.style.display = "none"; return; }
          const key = ToolEditor._refKey(value);
          const t = ToolEditor._toolList().find((x) => x.key === key);
          if (!t) {
              el.style.display = "";
              el.classList.add("cond-missing");
              el.textContent = "⚠ unknown tool “" + key + "” — branch will run the else path";
              return;
          }
          const truthy = ToolEditor._luaTruthy(t.value);
          el.style.display = "";
          el.classList.add(truthy ? "cond-true" : "cond-false");
          el.textContent = (truthy ? "● true" : "○ false")
              + " → runs the " + (truthy ? "then" : "else") + " branch";
      }

      _hookCanvasRender() {
          if (!this._canvas) return;
          const origRender = this._canvas._render;
          if (typeof origRender !== "function") return;

          const editor = this;
          this._canvas._render = function() {
              origRender.call(this);
              if (editor._open && editor._toolSid) {
                  editor._reInject();
              }
          };
      }

      _reInject() {
          if (!this._toolSid) return;
          const tool = this._canvas._map[this._toolSid];
          if (!tool) {
              this.close();
              return;
          }
          const root = this._canvas._root;
          if (!root) { this.close(); return; }

          const newEl = root.querySelector(
              `[data-sid="${this._toolSid}"] > .tool-block[data-sid="${this._toolSid}"], ` +
              `.tool-block[data-sid="${this._toolSid}"]`
          );
          if (!newEl) { this.close(); return; }

          this._toolEl = newEl;
          this._buildForm(tool);
          if (this._panelEl && !this._panelEl.parentNode) {
              this._toolEl.parentNode.insertBefore(this._panelEl, this._toolEl.nextSibling);
          }
      }

      // Open & Close //
        open(sid) {
            if (!this._canvas) return;
            const tool = this._canvas._map[sid];
            if (!tool) return;

            const root = this._canvas._root;
            if (!root) return;
            const stepEl = root.querySelector(
                `[data-sid="${sid}"] > .tool-block[data-sid="${sid}"], ` +
                `.tool-block[data-sid="${sid}"]`
            );
            if (!stepEl) return;

            this._hardClose();

            this._toolSid = sid;
            this._toolEl  = stepEl;
            this._open    = true;

            this._panelEl = document.createElement("div");
            this._panelEl.className = "tool-editor-panel";

            this._buildForm(tool);

            stepEl.parentNode.insertBefore(this._panelEl, stepEl.nextSibling);

            requestAnimationFrame(() => {
                if (this._panelEl) this._panelEl.classList.add("open");
            });

            setTimeout(() => {
                document.addEventListener("click", this._onClickOutside = (e) => {
                    if (!this._panelEl) return;
                    if (!this._panelEl.contains(e.target) && !this._toolEl.contains(e.target)) {
                        this.close();
                    }
                }, true);
                document.addEventListener("keydown", this._onEscape, true);
            }, 50);
        }

        close() {
            if (!this._open) return;
            this._open = false;

            this._cancelCapture();

            if (this._onClickOutside) {
                document.removeEventListener("click", this._onClickOutside, true);
                this._onClickOutside = null;
            }
            document.removeEventListener("keydown", this._onEscape, true);

            this._removePanel();
            this._toolSid = null;
            this._toolEl  = null;
        }

        _hardClose() {
            this._cancelCapture();
            if (this._onClickOutside) {
                document.removeEventListener("click", this._onClickOutside, true);
                this._onClickOutside = null;
            }
            document.removeEventListener("keydown", this._onEscape, true);

            const root = this._canvas && this._canvas._root;
            if (root) {
                const strays = root.querySelectorAll(".tool-editor-panel");
                for (let i = 0; i < strays.length; i++) {
                    const el = strays[i];
                    if (el.parentNode) el.parentNode.removeChild(el);
                }
            }
            if (this._panelEl && this._panelEl.parentNode) {
                this._panelEl.parentNode.removeChild(this._panelEl);
            }
            this._panelEl = null;
            this._formEl  = null;
            this._open    = false;
        }

        _removePanel() {
            if (this._panelEl && this._panelEl.parentNode) {
                this._panelEl.classList.remove("open");
                const panel = this._panelEl;
                setTimeout(() => {
                    if (panel.parentNode) panel.parentNode.removeChild(panel);
                }, 260);
            }
            this._panelEl = null;
            this._formEl  = null;
        }
      // END Open & Close //

      // Build Form //
        _buildForm(tool) {
            if (!this._panelEl) return;
            this._panelEl.innerHTML = "";

            const header = document.createElement("div");
            header.className = "tool-editor-header";

            const title = document.createElement("div");
            title.className = "tool-editor-title";
            title.textContent = tool.action === "setting"
                ? "Shared setting"
                : tool.action + ", parameters";
            header.appendChild(title);

            const closeBtn = document.createElement("div");
            closeBtn.className = "tool-editor-close";
            closeBtn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12" stroke-width="2" stroke-linecap="round"/></svg>';
            _sfx(closeBtn, "back");
            closeBtn.addEventListener("click", (e) => { e.stopPropagation(); this.close(); });
            header.appendChild(closeBtn);

            this._panelEl.appendChild(header);

            this._formEl = document.createElement("div");
            this._formEl.className = "tool-editor-form";
            this._panelEl.appendChild(this._formEl);

            if (tool.action === "setting") {
                const p = tool.params || {};
                const info = document.createElement("div");
                info.className = "tool-ed-setting-info";
                const key = p.key || "?";
                info.innerHTML =
                    '<div class="tool-ed-setting-name">' + esc(p.label || key) + '</div>' +
                    '<div class="tool-ed-setting-meta">' + esc(p.type || "setting") +
                        ' &middot; shared across macros</div>' +
                    '<div class="tool-ed-setting-hint">Reads live as ' +
                        '<code>ms.settings.get("' + esc(key) + '")</code>.<br>' +
                        'Wire any Value field to <b>Tool</b> and pick this to use it. ' +
                        'Edit its value in the Settings panel.</div>';
                this._formEl.appendChild(info);
                return;
            }

            const defs = this._getParamDefs(tool);
            const keys = Object.keys(defs);

            if (keys.length === 0) {
                const nope = document.createElement("div");
                nope.className = "tool-ed-no-params";
                nope.textContent = "No editable parameters.";
                this._formEl.appendChild(nope);
                return;
            }

            for (const key of keys) {
                const def = defs[key];
                const value = tool.params ? tool.params[key] : undefined;
                const row = this._buildParamRow(key, def, value, tool._sid);
                if (row) this._formEl.appendChild(row);
            }
        }

        _getParamDefs(tool) {
            const action = tool.action;

            // Prefer the shared Add-Module registry (window.fnPicker.registry) so
            // the inline editor and the add panel agree on param types and — for
            // enums — the exact constant sets ms_core.lua asserts on. An `enum`
            // param maps to this editor's `select` control.
            const reg = window.fnPicker && window.fnPicker.registry;
            if (reg) {
                for (let i = 0; i < reg.length; i++) {
                    if (reg[i].id !== action && reg[i].name !== action) continue;
                    const defs = {};
                    (reg[i].params || []).forEach(function(p) {
                        if (p.type === "enum") {
                            defs[p.name] = { type: "select", options: p.options || [] };
                        } else {
                            defs[p.name] = { type: p.type };
                        }
                    });
                    return defs;
                }
            }

            if (PARAM_DEFS[action]) {
                const defs = {};
                for (const [key, typeOrDef] of Object.entries(PARAM_DEFS[action])) {
                    if (typeof typeOrDef === "string") {
                        defs[key] = { type: typeOrDef };
                    } else {
                        defs[key] = typeOrDef;
                    }
                }
                return defs;
            }

            if (!tool.params) return {};
            const defs = {};
            for (const [key, value] of Object.entries(tool.params)) {
                if (STRUCTURAL_KEYS.has(key)) continue;
                defs[key] = { type: this._inferType(key, value) };
            }
            return defs;
        }

        _inferType(key, value) {
            if (key === "key")  return "key";
            if (key === "mods") return "mods";
            if (key === "condition" || key === "expr") return "condition";

            if (Array.isArray(value)) return "array";
            if (typeof value === "number") return "number";
            return "string";
        }
      // END Build Form //

      // Build Parameter Row //
        _buildParamRow(key, def, value, sid) {
            const row = document.createElement("div");
            row.className = "tool-editor-row";

            const label = document.createElement("div");
            label.className = "tool-editor-label";
            label.textContent = key;
            row.appendChild(label);

            const control = document.createElement("div");
            control.className = "tool-editor-control";

            const bindable = (def.type === "string" || def.type === "number"
                || def.type === "condition" || def.type === undefined);
            const bound = ToolEditor._isToolRef(value);

            if (bindable) {
                control.classList.add("tool-ed-bindable");
                const sw = document.createElement("span");
                sw.className = "tool-ed-bind-switch";
                const litBtn = document.createElement("button");
                litBtn.className = "tool-ed-bind-opt" + (bound ? "" : " on");
                litBtn.textContent = "Value";
                const toolBtn = document.createElement("button");
                toolBtn.className = "tool-ed-bind-opt" + (bound ? " on" : "");
                toolBtn.textContent = "Tool";
                sw.appendChild(litBtn);
                sw.appendChild(toolBtn);

                const holder = document.createElement("div");
                holder.className = "tool-ed-bind-holder";
                control.appendChild(sw);
                control.appendChild(holder);

                // For a condition wired to a tool/var, show how it evaluates
                // right now, so the branch's live truth is visible at a glance.
                const note = (def.type === "condition")
                    ? document.createElement("div") : null;
                if (note) { note.className = "tool-ed-cond-live"; control.appendChild(note); }

                const render = () => {
                    holder.innerHTML = "";
                    const nowBound = ToolEditor._isToolRef(value);
                    litBtn.classList.toggle("on", !nowBound);
                    toolBtn.classList.toggle("on", nowBound);
                    if (nowBound) {
                        holder.appendChild(this._createToolSelect(key, value, sid));
                    } else {
                        holder.appendChild(this._buildLiteralControl(def, key, value, sid));
                    }
                    if (note) ToolEditor._renderCondLive(note, nowBound ? value : null);
                };
                _sfx(litBtn); _sfx(toolBtn);
                litBtn.addEventListener("click", (e) => {
                    e.stopPropagation();
                    value = def.type === "number" ? 0 : "";
                    this._updateParam(sid, key, value);
                    render();
                });
                toolBtn.addEventListener("click", (e) => {
                    e.stopPropagation();
                    const tools = ToolEditor._toolList();
                    const first = tools.length ? tools[0].key : "";
                    value = ToolEditor._refFor(first);
                    this._updateParam(sid, key, value);
                    render();
                });
                render();
                row.appendChild(control);
                return row;
            }

            control.appendChild(this._buildLiteralControl(def, key, value, sid));
            row.appendChild(control);
            return row;
        }

        _buildLiteralControl(def, key, value, sid) {
            switch (def.type) {
                case "string":    return this._createStringInput(key, value, sid);
                case "number":    return this._createNumberInput(key, value, sid);
                case "key":       return this._createKeyCapture(key, value, sid);
                case "mods":      return this._createModChips(key, value, sid);
                case "select":    return this._createSelectInput(key, value, def.options, sid);
                case "condition": return this._createConditionInput(key, value, sid);
                case "array":     return this._createArrayEditor(key, value, sid);
                default:          return this._createStringInput(key, value, sid);
            }
        }

        _createToolSelect(key, value, sid) {
            const tools = ToolEditor._toolList();
            const current = ToolEditor._refKey(value);

            const options = tools.map((t) => ({
                value: t.key,
                label: (t.label || t.key) + "  ·  " + t.type,
            }));
            let seen = tools.some((t) => t.key === current);
            if (current && !seen) {
                options.push({ value: current, label: current + "  (missing)" });
            }

            if (typeof window.createSelect === "function") {
                return window.createSelect({
                    className:   "tool-ed-tool-select",
                    options:     options,
                    value:       current,
                    placeholder: "No tools, create one in Add Module",
                    onChange:    (v) => this._updateParam(sid, key, ToolEditor._refFor(v)),
                });
            }

            // createSelect is a shell global and should always be present; the
            // fallback is a themed, non-interactive placeholder (never a native
            // <select>, which would ignore the theme) so a missing global fails
            // visibly instead of rendering OS chrome.
            const ph = document.createElement("div");
            ph.className = "tool-ed-tool-select";
            const chosen = options.find((o) => o.value === current);
            ph.textContent = chosen ? chosen.label
                : (options.length ? "Select a tool…" : "No tools, create one in Add Module");
            return ph;
        }
      // END Build Parameter Row //

      // Input Widgets //
        _createStringInput(key, value, sid) {
            const inp = document.createElement("input");
            inp.type = "text";
            inp.className = "tool-ed-text";
            inp.value = (value !== undefined && value !== null) ? String(value) : "";
            inp.placeholder = key + "...";
            inp.setAttribute("spellcheck", "false");
            inp.setAttribute("autocomplete", "off");
            inp.setAttribute("autocorrect", "off");
            inp.setAttribute("autocapitalize", "off");

            inp.addEventListener("input", () => {
                this._updateParam(sid, key, inp.value, true);
            });
            inp.addEventListener("keydown", (e) => e.stopPropagation());

            return inp;
        }

        _createNumberInput(key, value, sid) {
            const wrap = document.createElement("div");
            wrap.className = "tool-ed-number-wrap";

            const btnMinus = document.createElement("button");
            btnMinus.className = "tool-ed-num-btn";
            btnMinus.textContent = "−";
            wrap.appendChild(btnMinus);

            const inp = document.createElement("input");
            inp.type = "number";
            inp.className = "tool-ed-number";
            inp.value = (value !== undefined && value !== null) ? String(value) : "0";
            inp.step = "1";
            wrap.appendChild(inp);

            const btnPlus = document.createElement("button");
            btnPlus.className = "tool-ed-num-btn";
            btnPlus.textContent = "+";
            wrap.appendChild(btnPlus);

            const emit = () => {
                const v = parseFloat(inp.value) || 0;
                this._updateParam(sid, key, v, true);
            };

            inp.addEventListener("input", emit);
            inp.addEventListener("keydown", (e) => {
                e.stopPropagation();
                if (e.key === "ArrowUp")   { inp.value = String((parseFloat(inp.value)||0) + (e.shiftKey ? 10 : 1)); emit(); e.preventDefault(); }
                if (e.key === "ArrowDown") { inp.value = String((parseFloat(inp.value)||0) - (e.shiftKey ? 10 : 1)); emit(); e.preventDefault(); }
            });

            const step = (delta) => {
                inp.value = String((parseFloat(inp.value)||0) + delta);
                emit();
            };
            _sfx(btnMinus);
            _sfx(btnPlus);
            btnMinus.addEventListener("click", (e) => { e.stopPropagation(); step(e.shiftKey ? -10 : -1); });
            btnPlus.addEventListener("click",  (e) => { e.stopPropagation(); step(e.shiftKey ? 10 : 1); });

            return wrap;
        }

        _createKeyCapture(key, value, sid) {
            const wrap = document.createElement("div");
            wrap.style.cssText = "display:flex;align-items:center;gap:8px";

            const btn = document.createElement("button");
            btn.className = "tool-ed-key-btn";
            btn.textContent = (value != null && value !== "") ? String(value) : "Click to set";
            wrap.appendChild(btn);

            const hint = document.createElement("span");
            hint.className = "tool-ed-key-hint";
            hint.textContent = "press a key...";
            wrap.appendChild(hint);

            _sfx(btn);
            btn.addEventListener("click", (e) => {
                e.stopPropagation();
                this._startCapture(key, btn, sid);
            });

            return wrap;
        }

        _startCapture(key, btn, sid) {
            this._cancelCapture();

            btn.classList.add("capturing");
            btn.textContent = "...";

            const handler = (e) => {
                e.preventDefault();
                e.stopPropagation();

                const normalized = normalizeKey(e);
                this._updateParam(sid, key, normalized);

                btn.classList.remove("capturing");
                btn.textContent = normalized || "???";

                document.removeEventListener("keydown", handler, true);
                this._capturingKey = null;
                this._keyHandler = null;
            };

            this._capturingKey = key;
            this._keyHandler = handler;
            document.addEventListener("keydown", handler, true);
        }

        _cancelCapture() {
            if (this._keyHandler) {
                document.removeEventListener("keydown", this._keyHandler, true);
                this._keyHandler = null;
                this._capturingKey = null;
            }
        }

        _createModChips(key, value, sid) {
            const MOD_LIST = ["ctrl", "alt", "shift", "cmd"];
            const currentMods = Array.isArray(value) ? value : [];

            const wrap = document.createElement("div");
            wrap.className = "tool-ed-mods";

            for (const mod of MOD_LIST) {
                const chip = document.createElement("button");
                chip.className = "tool-ed-mod-chip" + (currentMods.includes(mod) ? " on" : "");
                chip.textContent = mod;
                _sfx(chip);
                chip.addEventListener("click", (e) => {
                    e.stopPropagation();
                    chip.classList.toggle("on");
                    // Gather active mods
                    const active = [];
                    wrap.querySelectorAll(".tool-ed-mod-chip.on").forEach(c => active.push(c.textContent));
                    this._updateParam(sid, key, active);
                });
                wrap.appendChild(chip);
            }

            return wrap;
        }

        _createSelectInput(key, value, options, sid) {
            if (!options || options.length === 0) {
                options = [String(value || "")];
            }

            const sel = createSelect({
                options: options,
                value: (value !== undefined && value !== null) ? String(value) : undefined,
                className: "tool-ed-select",
                onChange: (v) => this._updateParam(sid, key, v),
            });

            return sel;
        }

        _createConditionInput(key, value, sid) {
            const ta = document.createElement("textarea");
            ta.className = "tool-ed-condition";
            ta.rows = 1;
            ta.value = (value !== undefined && value !== null) ? String(value) : "";
            ta.placeholder = "Lua expression...";
            ta.setAttribute("spellcheck", "false");
            ta.setAttribute("autocomplete", "off");
            ta.setAttribute("autocorrect", "off");
            ta.setAttribute("autocapitalize", "off");

            const autoResize = () => {
                ta.style.height = "auto";
                ta.style.height = Math.min(ta.scrollHeight, 100) + "px";
            };

            ta.addEventListener("input", () => {
                this._updateParam(sid, key, ta.value, true);
                autoResize();
            });
            ta.addEventListener("keydown", (e) => e.stopPropagation());

            requestAnimationFrame(autoResize);

            return ta;
        }

        _createArrayEditor(key, value, sid) {
            const items = Array.isArray(value) ? [...value] : [];
            const wrap = document.createElement("div");
            wrap.className = "tool-ed-array";

            const renderItems = () => {
                wrap.querySelectorAll(".tool-ed-array-item").forEach(el => el.remove());

                for (let i = 0; i < items.length; i++) {
                    const itemRow = document.createElement("div");
                    itemRow.className = "tool-ed-array-item";

                    const inp = document.createElement("input");
                    inp.type = "text";
                    inp.className = "tool-ed-text";
                    inp.value = String(items[i]);
                    inp.setAttribute("spellcheck", "false");
                    inp.setAttribute("autocomplete", "off");
                    inp.setAttribute("autocorrect", "off");
                    inp.setAttribute("autocapitalize", "off");
                    inp.addEventListener("input", () => {
                        items[i] = inp.value;
                        this._updateParam(sid, key, [...items], true);
                    });
                    inp.addEventListener("keydown", (e) => e.stopPropagation());
                    itemRow.appendChild(inp);

                    const removeBtn = document.createElement("div");
                    removeBtn.className = "tool-ed-array-remove";
                    removeBtn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12" stroke-width="2" stroke-linecap="round"/></svg>';
                    _sfx(removeBtn, "back");
                    removeBtn.addEventListener("click", (e) => {
                        e.stopPropagation();
                        items.splice(i, 1);
                        this._updateParam(sid, key, [...items]);
                        renderItems();
                    });
                    itemRow.appendChild(removeBtn);

                    wrap.appendChild(itemRow);
                }
            };

            renderItems();

            const addBtn = document.createElement("button");
            addBtn.className = "tool-ed-array-add";
            addBtn.textContent = "+ add item";
            _sfx(addBtn);
            addBtn.addEventListener("click", (e) => {
                e.stopPropagation();
                items.push("");
                this._updateParam(sid, key, [...items]);
                renderItems();
            });
            wrap.appendChild(addBtn);

            return wrap;
        }
      // END Input Widgets //

      // Update Parameter //
        _updateParam(sid, key, value, quiet) {
            if (!this._canvas) return;
            this._canvas.updateTool(sid, { [key]: value }, quiet ? { quiet: true } : undefined);
            this._onUpdate(sid, { [key]: value });
        }
      // END Update Parameter //

      // Destroy //
        destroy() {
            this.close();
            this._canvas = null;
        }
      // END Destroy //
  }
// END ToolEditor Class //

// Expose for IIFE contexts //
if (typeof window !== "undefined") {
    window.ToolEditor = ToolEditor;

    // Remember the last-focused Value field so the Variable tab can insert a
    // {name} token straight into it. Both string values (.tool-ed-text) and
    // condition/expression fields (.tool-ed-condition) qualify: the compiler
    // expands {name} in each context (a quoted concat in strings, a bare
    // ms.vars.get in expressions), so the token is uniformly valid.
    document.addEventListener("focusin", function(e) {
        var t = e.target;
        if (t && t.classList &&
            (t.classList.contains("tool-ed-text")
             || t.classList.contains("tool-ed-condition"))) {
            window._msLastValueField = t;
        }
    }, true);

    // Insert `token` at the caret of the last-focused Value field. Returns true
    // when it landed in a field; false (caller falls back to clipboard) when no
    // live field is focused — e.g. it was popped out or the editor closed.
    window.msInsertValueToken = function(token) {
        var el = window._msLastValueField;
        if (!el || !el.isConnected || el.offsetParent === null) return false;
        var start = el.selectionStart, end = el.selectionEnd;
        if (typeof start !== "number") { start = el.value.length; end = start; }
        el.value = el.value.slice(0, start) + token + el.value.slice(end);
        var caret = start + token.length;
        el.focus();
        try { el.setSelectionRange(caret, caret); } catch (err) {}
        // Fire input so ToolEditor persists the edited value live.
        el.dispatchEvent(new Event("input", { bubbles: true }));
        return true;
    };
}
