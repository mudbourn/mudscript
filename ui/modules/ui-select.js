(function() {
"use strict";
  // Styles //
      const SELECT_CSS = `
        .macro-select { position: relative; display: flex; align-items: center; gap: 6px; background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text); font-size: 11px; padding: 4px 8px; outline: none; font-family: inherit; cursor: pointer; min-width: 120px; }
        .macro-select:hover { border-color: var(--border); }
        .macro-select:focus, .macro-select.open { border-color: var(--accent); }
        .macro-select-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .macro-select-arrow { display: flex; align-items: center; font-size: 8px; color: var(--text3); flex-shrink: 0; }
        .macro-select-arrow .icon { width: 12px; height: 12px; }
        .macro-select-menu { display: none; position: absolute; top: calc(100% + 3px); left: 0; min-width: 100%; max-height: 260px; overflow-y: auto; background: var(--surface2); border: 1px solid var(--border); border-radius: var(--radius); z-index: 100; box-shadow: 0 4px 16px rgba(0,0,0,0.5); }
        .macro-select.open .macro-select-menu { display: block; }
        .macro-select-item { padding: 5px 10px; font-size: 11px; color: var(--text2); white-space: nowrap; cursor: pointer; transition: background 0.12s, color 0.12s; }
        .macro-select-item:hover { background: var(--hover); color: var(--text); }
        .macro-select-item.active { color: var(--accent); }
        .macro-select-item.gp-hi { background: var(--hover); color: var(--text); box-shadow: inset 0 0 0 1px var(--accent); }
        .macro-select-menu::-webkit-scrollbar { width: 4px; }
        .macro-select-menu::-webkit-scrollbar-track { background: transparent; }
        .macro-select-menu::-webkit-scrollbar-thumb { background: var(--border-dim); border-radius: 2px; }
        .macro-select-search { position: sticky; top: 0; z-index: 1; background: var(--surface2); padding: 5px; border-bottom: 1px solid var(--border-dim); }
        .macro-select-search input { width: 100%; box-sizing: border-box; background: var(--surface); border: 1px solid var(--border-dim); border-radius: var(--radius-s); color: var(--text); font-size: 11px; padding: 4px 7px; outline: none; font-family: inherit; }
        .macro-select-search input:focus { border-color: var(--accent); }
        .macro-select-group { padding: 6px 10px 2px; font-size: 9px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: var(--text3); pointer-events: none; }
        .macro-select-empty { padding: 8px 10px; font-size: 11px; color: var(--text3); font-style: italic; }
        `;

      function injectSelectStyles(doc) {
          doc = doc || document;
          if (doc.getElementById("ui-select-css")) return;
          const style = doc.createElement("style");
          style.id = "ui-select-css";
          style.textContent = SELECT_CSS;
          (doc.head || doc.documentElement).appendChild(style);
      }
  // END Styles //

  // Factory //
      function createSelect(opts) {
          opts = opts || {};
          injectSelectStyles(opts.doc);

          const doc = opts.doc || document;
          const root = doc.createElement("div");
          root.className = "macro-select" + (opts.className ? " " + opts.className : "");
          root.tabIndex = 0;
          if (opts.minWidth) root.style.minWidth = opts.minWidth + "px";

          const label = doc.createElement("span");
          label.className = "macro-select-label";
          root.appendChild(label);

          const arrow = doc.createElement("span");
          arrow.className = "macro-select-arrow";
          if (window.ICONS && window.ICONS.chevdown && typeof window.icon === "function") {
              arrow.innerHTML = window.icon("chevdown");
          } else {
              arrow.textContent = "▾";
          }
          root.appendChild(arrow);

          const menu = doc.createElement("div");
          menu.className = "macro-select-menu";
          root.appendChild(menu);

          let _opts = [];
          let _value = "";
          let _filter = "";
          let _gpIndex = -1;
          let _connCheck = null;

          // Optional structure: a sticky search box that filters the list, and
          // per-item group headers. Both are opt-in (opts.searchable / an option
          // carrying a `group`), so existing flat call sites are unaffected.
          let searchInput = null;
          let entriesWrap = menu;
          if (opts.searchable) {
              const searchWrap = doc.createElement("div");
              searchWrap.className = "macro-select-search";
              searchInput = doc.createElement("input");
              searchInput.type = "text";
              searchInput.placeholder = opts.searchPlaceholder || "Search…";
              searchInput.setAttribute("spellcheck", "false");
              searchInput.setAttribute("autocomplete", "off");
              searchInput.setAttribute("autocorrect", "off");
              searchInput.setAttribute("autocapitalize", "off");
              searchWrap.appendChild(searchInput);
              menu.appendChild(searchWrap);
              entriesWrap = doc.createElement("div");
              menu.appendChild(entriesWrap);
              // Typing filters; keep clicks/keys inside the control so the menu
              // stays open and global shortcuts don't fire.
              searchInput.addEventListener("input", () => { _filter = searchInput.value; renderEntries(); });
              searchInput.addEventListener("click", (e) => e.stopPropagation());
              searchInput.addEventListener("keydown", (e) => { if (e.key !== "Escape") e.stopPropagation(); });
          }

          function play(slot) { if (window.playSlot) window.playSlot(slot); }

          function normalise(list) {
              return (list || []).map((o) =>
                  (o && typeof o === "object")
                      ? { value: String(o.value), label: String(o.label == null ? o.value : o.label),
                          group: o.group == null ? "" : String(o.group) }
                      : { value: String(o), label: String(o), group: "" }
              );
          }

          function labelFor(v) {
              // Action selects (e.g. "+ Add step…") are menus, not a persistent
              // choice — always show the placeholder.
              if (opts.action) return opts.placeholder || "";
              for (const o of _opts) if (o.value === v) return o.label;
              return _opts.length ? _opts[0].label : (opts.placeholder || "");
          }

          // Controller highlight: the mouse uses :hover, but a gamepad has no
          // pointer, so a moved highlight (.gp-hi) marks the item A will pick.
          function gpItems() {
              return Array.prototype.slice.call(
                  entriesWrap.querySelectorAll(".macro-select-item"));
          }
          function gpClear() {
              gpItems().forEach((it) => it.classList.remove("gp-hi"));
              _gpIndex = -1;
          }
          function gpHighlight(i) {
              const items = gpItems();
              if (!items.length) { _gpIndex = -1; return; }
              _gpIndex = ((i % items.length) + items.length) % items.length;
              items.forEach((it, idx) => it.classList.toggle("gp-hi", idx === _gpIndex));
              items[_gpIndex].scrollIntoView({ block: "nearest" });
          }

          function close() {
              if (_connCheck) { clearInterval(_connCheck); _connCheck = null; }
              root.classList.remove("open");
              gpClear();
              // Return the menu from the body portal to the control, and drop
              // every inline style so the base .macro-select-menu rule hides it.
              if (menu.parentNode !== root) root.appendChild(menu);
              menu.style.display = "";
              menu.style.position = "";
              menu.style.left = "";
              menu.style.top = "";
              menu.style.bottom = "";
              menu.style.minWidth = "";
              menu.style.maxHeight = "";
          }

          function place() {
              const r   = root.getBoundingClientRect();
              const vh  = doc.documentElement.clientHeight;
              const gap = 3;

              // Anchor the menu with position:fixed, but a transformed ancestor
              // (the sliding fn-picker overlay sets transform: translateX(...))
              // becomes the containing block for fixed descendants — so fixed
              // coords resolve against that box, not the viewport, and the menu
              // lands off-screen. Measure the containing-block origin by parking
              // the menu at 0,0 first, then cancel it from every coordinate. Use
              // top for both anchors (no bottom, whose reference edge would also
              // be shifted) so the correction stays a simple subtraction.
              menu.style.position  = "fixed";
              menu.style.bottom    = "auto";
              menu.style.maxHeight = "none";
              menu.style.left      = "0px";
              menu.style.top       = "0px";
              const origin = menu.getBoundingClientRect();
              const ox = origin.left, oy = origin.top;

              const below = vh - r.bottom - gap;
              const above = r.top - gap;
              // Prefer opening downward. Only flip up when the space below is
              // genuinely cramped (can't show a usable, scrollable slice) and
              // there's more room above — otherwise let the menu scroll in place.
              const flip  = below < 140 && above > below;
              const maxH  = Math.max(80, Math.min(260, flip ? above : below));
              const menuH = Math.min(menu.scrollHeight, maxH);
              const topVp = flip ? (r.top - gap - menuH) : (r.bottom + gap);

              menu.style.left      = (r.left - ox) + "px";
              menu.style.top       = (topVp - oy) + "px";
              menu.style.minWidth  = r.width + "px";
              menu.style.maxHeight = maxH + "px";
          }

          function renderEntries() {
              entriesWrap.innerHTML = "";
              const q = _filter.trim().toLowerCase();
              const vis = q
                  ? _opts.filter((o) => o.label.toLowerCase().indexOf(q) !== -1
                        || (o.group && o.group.toLowerCase().indexOf(q) !== -1))
                  : _opts;
              if (!vis.length) {
                  const empty = doc.createElement("div");
                  empty.className = "macro-select-empty";
                  empty.textContent = "No matches";
                  entriesWrap.appendChild(empty);
                  return;
              }
              let lastGroup = null;
              vis.forEach((o) => {
                  if (o.group && o.group !== lastGroup) {
                      const hdr = doc.createElement("div");
                      hdr.className = "macro-select-group";
                      hdr.textContent = o.group;
                      entriesWrap.appendChild(hdr);
                      lastGroup = o.group;
                  }
                  const item = doc.createElement("div");
                  item.className = "macro-select-item" + (!opts.action && o.value === _value ? " active" : "");
                  item.textContent = o.label;
                  item.addEventListener("mouseenter", () => play("hover"));
                  item.addEventListener("click", (e) => {
                      e.stopPropagation();
                      play("interact");
                      close();
                      // Action menus fire every pick (including a repeat); plain
                      // selects ignore re-picking the current value.
                      if (!opts.action && o.value === _value) return;
                      _value = o.value;
                      render();
                      if (opts.onChange) opts.onChange(_value);
                      root.dispatchEvent(new Event("change"));
                  });
                  entriesWrap.appendChild(item);
              });
          }

          function render() {
              label.textContent = labelFor(_value);
              renderEntries();
          }

          root.setOptions = function(list) {
              _opts = normalise(list);
              if (!_opts.some((o) => o.value === _value)) {
                  _value = _opts.length ? _opts[0].value : "";
              }
              render();
          };

          Object.defineProperty(root, "value", {
              get: () => _value,
              set: (v) => { _value = v == null ? "" : String(v); render(); },
          });

          Object.defineProperty(root, "options", { get: () => _opts.slice() });

          root.addEventListener("mouseenter", () => play("hover"));
          root.addEventListener("click", (e) => {
              e.stopPropagation();
              if (root.classList.contains("open")) { close(); return; }
              play("interact");
              root.classList.add("open");
              _gpIndex = -1;
              // Portal the menu to <body> so it escapes the fn-picker overlay's
              // overflow:hidden (and any other clipping ancestor). It's a fixed,
              // viewport-anchored layer, so body is the safe parent; place()
              // still positions it against the control. close() restores it.
              (doc.body || doc.documentElement).appendChild(menu);
              menu.style.display = "block";
              // The menu now lives on <body>, so it survives its owning control
              // being torn out by a panel re-render — which would strand it open,
              // floating and detached. Watch the control and close if it leaves
              // the document.
              _connCheck = setInterval(function() { if (!root.isConnected) close(); }, 150);
              if (searchInput) {
                  _filter = "";
                  searchInput.value = "";
                  renderEntries();
                  setTimeout(() => searchInput.focus(), 0);
              }
              place();
          });
          doc.addEventListener("scroll", function(e) {
              if (menu.contains(e.target)) return;
              close();
          }, true);
          window.addEventListener("resize", close);
          root.addEventListener("keydown", (e) => {
              if (e.key === "Escape") close();
              e.stopPropagation();
          });
          // Close on any outside press. Capture phase so it still fires even
          // when a handler in between (the builder canvas) stops propagation on
          // the bubbling click. Presses on the control or its (now portaled)
          // menu are handled by their own listeners.
          doc.addEventListener("pointerdown", function(e) {
              if (!root.classList.contains("open")) return;
              if (root.contains(e.target) || menu.contains(e.target)) return;
              close();
          }, true);

          // Gamepad API, mirrored by gp-nav while this select is open: move the
          // highlight, pick the highlighted item (its click handler commits and
          // closes), or dismiss. Starting from the active item keeps the first
          // press landing where the eye already is.
          root.gpIsOpen = () => root.classList.contains("open");
          root.gpMove = (dir) => {
              const items = gpItems();
              if (!items.length) return;
              let start = _gpIndex;
              if (start < 0) start = items.findIndex((it) => it.classList.contains("active"));
              gpHighlight(start < 0 ? 0 : start + dir);
              play("hover");
          };
          root.gpPick = () => {
              const items = gpItems();
              let it = items[_gpIndex];
              if (!it) it = items.filter((x) => x.classList.contains("active"))[0] || items[0];
              if (it) it.click();
          };
          root.gpClose = () => close();

          root.setOptions(opts.options || []);
          if (opts.value !== undefined && opts.value !== null) root.value = opts.value;
          else if (!_opts.length && opts.placeholder) label.textContent = opts.placeholder;

          return root;
      }
  // END Factory //

  // Exports //
      window.createSelect       = createSelect;
      window.injectSelectStyles = injectSelectStyles;
      window.SELECT_CSS         = SELECT_CSS;
  // END Exports //
})();
