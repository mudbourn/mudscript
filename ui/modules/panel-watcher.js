(function() {
"use strict";

  // Step categories //
      const CATS = [
          { id: "wait", label: "Waits", regex: /\] wait / },
          { id: "sound", label: "Sound calls", regex: /\] sound / },
          { id: "cam", label: "Camera moves", regex: /\] cam\.move/ },
          {
              id: "keys",
              label: "Key presses",
              regex: /\] (down|up) |\] type /,
          },
          { id: "mouse", label: "Mouse actions", regex: /\] Mouse / },
          { id: "scroll", label: "Scrolls", regex: /\] scroll / },
          { id: "copy", label: "Clipboard", regex: /\] copy/ },
      ];

      function stepCat(msg) {
          for (const c of CATS) {
              if (c.regex.test(msg)) return c.id;
          }
          return "other";
      }
  // END Step categories //

  // Panel container (for scoped DOM queries) //
      const _panel = document.querySelector('.panel-watcher');
  // END Panel container //

  // Mute state //
      const _muted = new Set();

      function isMuted(cat) { return _muted.has(cat); }

      function setMute(cat, on) {
          const log = _panel ? _panel.querySelector("#log") : document.getElementById("log");
          if (!log) return;
          if (on) {
              _muted.add(cat);
              log.classList.add("mute-" + cat);
          } else {
              _muted.delete(cat);
              log.classList.remove("mute-" + cat);
          }
          _updateFilterUI();
      }

      function _updateFilterUI() {
          const btn = document.getElementById("filter-btn");
          btn.classList.toggle("has-mutes", _muted.size > 0);
          btn.textContent =
              _muted.size > 0 ? "filter (" + _muted.size + ")" : "filter";
          CATS.forEach((c) => {
              const row = document.getElementById("frow-" + c.id);
              if (row) row.classList.toggle("muted", _muted.has(c.id));
          });
          const action = document.getElementById("filter-action");
          if (action) {
              action.textContent =
                  _muted.size === CATS.length ? "show all" : "hide all";
          }
      }
  // END Mute state //

  // Build filter panel //
      (function buildFilterPanel() {
          const CAT_DOT_COLORS = {
              wait: "var(--text3)",
              sound: "var(--warning)",
              cam: "var(--success)",
              keys: "var(--text2)",
              mouse: "var(--mouse)",
              scroll: "var(--scroll)",
              copy: "var(--accent)",
          };

          const panel = document.getElementById("filter-panel");

          CATS.forEach((c) => {
              const row = document.createElement("div");
              row.className = "filter-row";
              row.id = "frow-" + c.id;
              row.style.setProperty(
                  "--dot-clr",
                  CAT_DOT_COLORS[c.id] || "var(--text3)",
              );

              const dot = document.createElement("span");
              dot.className = "filter-dot";

              const lbl = document.createElement("span");
              lbl.className = "filter-label";
              lbl.textContent = c.label;

              row.append(dot, lbl);
              row.addEventListener("click", () =>
                  setMute(c.id, !isMuted(c.id)),
              );
              panel.appendChild(row);
          });

          const sep = document.createElement("div");
          sep.className = "filter-sep";
          panel.appendChild(sep);

          const clear = document.createElement("div");
          clear.className = "filter-clear";
          clear.id = "filter-action";
          clear.textContent = "hide all";
          clear.addEventListener("click", () => {
              if (_muted.size === CATS.length) {
                  [..._muted].forEach((id) => setMute(id, false));
              } else {
                  CATS.forEach((c) => setMute(c.id, true));
              }
          });
          panel.appendChild(clear);
      })();

      function toggleFilterPanel() {
          document
              .getElementById("filter-panel")
              .classList.toggle("open");
      }
      function closeFilterPanel() {
          document
              .getElementById("filter-panel")
              .classList.remove("open");
      }

      document.addEventListener("mousedown", (e) => {
          const panel = document.getElementById("filter-panel");
          const btn = document.getElementById("filter-btn");
          if (!panel.contains(e.target) && !btn.contains(e.target)) {
              closeFilterPanel();
          }
      });
  // END Build filter panel //

  // Watcher buildRow //
      function buildRow(entry) {
          if (entry.type === "step") {
              const row = document.createElement("div");
              row.className = "step";
              row.dataset.cat = stepCat(entry.msg || "");

              const ts = document.createElement("span");
              ts.className = "ts";
              ts.textContent = "[" + (entry.ts || "") + "]";

              const msg = document.createElement("span");
              msg.className = "tool-msg";
              msg.textContent = entry.msg || "";

              row.append(ts, msg);
              row.onmouseenter = function() { lp.playSlot("hover"); };
              row.onclick = lp._handleEntryClick;
              return row;
          }

          const row = document.createElement("div");
          row.className = "entry";

          const ts = document.createElement("span");
          ts.className = "ts";
          ts.textContent = "[" + (entry.ts || "") + "]";
          row.appendChild(ts);

          if (entry.type === "macro") {
              row.classList.add("entry-macro");

              const dot = document.createElement("span");
              dot.className = "dot";
              dot.innerHTML = ICONS.dot;
              row.appendChild(dot);

              const msg = document.createElement("span");
              msg.className = "msg";
              if (entry.parentLabel) {
                  msg.appendChild(
                      document.createTextNode(entry.parentLabel),
                  );
                  const sep = document.createElement("span");
                  sep.className = "sub-sep";
                  sep.innerHTML = ICONS["chevron-right"];
                  const sub = document.createElement("span");
                  sub.className = "sub-name";
                  sub.textContent = entry.label || entry.id || "";
                  msg.append(sep, sub);
              } else {
                  msg.textContent = entry.label || entry.id || "";
              }
              row.appendChild(msg);

              if (entry.trigger) {
                  const trig = document.createElement("span");
                  trig.className = "pill";
                  trig.textContent = entry.trigger;
                  row.appendChild(trig);
              }
          } else {
              const badge = document.createElement("span");
              badge.className = "badge badge-" + entry.type;
              badge.textContent = entry.type;
              row.appendChild(badge);

              const msg = document.createElement("span");
              msg.className = "msg";
              msg.textContent = entry.msg || "";
              row.appendChild(msg);
          }

          row.onmouseenter = function() { lp.playSlot("hover"); };
          row.onclick = lp._handleEntryClick;
          return row;
      }
  // END Watcher buildRow //

  // Create LogPanel //
      const lp = createLogPanel({
          channel: "watcher",
          buildRow,
          container: _panel,
          maxEntries: 500,
          scrollThresh: 48,
          clearAction: "clearLog",
      });
  // END Create LogPanel //

  // Expose globals for inline handlers //
      window._panelPauseFns['watcher'] = lp.togglePause;
      window.playSlot          = lp.playSlot;
      window.toggleFilterPanel = toggleFilterPanel;
      window.closePanel        = lp.closePanel;
      window.watcherApplyTheme = lp.applyTheme;
  // END Expose globals for inline handlers //

  // Watcher clearLog //
      function clearLog() {
          const log = _panel ? _panel.querySelector("#log") : document.getElementById("log");
          if (log) log.innerHTML = "";
          lp.sendToHost({ action: "clear" });
      }
      window._panelClearFns['watcher'] = clearLog;
  // END Watcher clearLog //

  // Init //
      document.addEventListener("DOMContentLoaded", () => {
          if (typeof registerPanel === "function") {
              registerPanel("watcher", function(action, body) {
                  if (action === "appendEntry" && body) lp.appendEntry(body);
                  else if (action === "loadHistory" && body) lp.loadHistory(body);
              });
          }
          if (window.shellPost) {
              var p = document.getElementById("panel");
              if (p) { p.style.borderRadius = "0"; p.style.clipPath = "none"; }
          }
          lp.sendToHost({ action: "ready" });
      });
  // END Init //
})();
