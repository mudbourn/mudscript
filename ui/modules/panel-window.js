(function() {
"use strict";
  // Window buildRow //
      function buildRow(entry) {
          const row = devfmt.windowRow(entry);

          row.onmouseenter = function() { lp.playSlot("hover"); };
          row.onclick = lp._handleEntryClick;

          return row;
      }
  // END Window buildRow //

  // Field helpers //
      function _q(sel) { return _panel ? _panel.querySelector(sel) : document.querySelector(".panel-window " + sel); }
      function setVal(sel, text) {
          const el = _q(sel); if (!el) return;
          const has = text != null && text !== "";
          el.textContent = has ? text : "-";
          el.classList.toggle("empty", !has);
      }
      const FLAG_OFF_LABEL = { visible: "Hidden" };
      const FLAG_ON_LABEL  = { visible: "Visible" };

      function setFlag(name, on) {
          const el = _q('[data-flag="' + name + '"]');
          if (!el) return;
          el.classList.toggle("on", !!on);
          const txt = on ? FLAG_ON_LABEL[name] : FLAG_OFF_LABEL[name];
          if (txt) el.textContent = txt;
      }
  // END Field helpers //

  // State updates //
      function updateCurrentWindow(s) {
          if (!s) return;
          setVal('[data-k="app"]', s.app);
          setVal('[data-k="pid"]', s.pid != null ? String(s.pid) : "");
          setVal('[data-k="bundle"]', s.bundleID);
          setVal('[data-k="title"]', s.title);
          setVal('[data-k="role"]', [s.role, s.subrole].filter(Boolean).join(" / "));
          setVal('[data-k="frame"]', devfmt.frame(s.frame));
          setVal('[data-k="screen"]', s.screen);
          setVal('[data-k="id"]', s.id != null ? String(s.id) : "");
          setFlag("standard", s.standard); setFlag("minimized", s.minimized);
          setFlag("fullscreen", s.fullscreen); setFlag("visible", s.visible);
      }

      function updateElement(e) {
          if (!e) return;
          const banner = _q(".ax-banner");
          if (e.axPermission === false) {
              if (banner) banner.classList.add("show");
              ["role","desc","title","value","ident","frame"].forEach((k) => setVal('[data-e="' + k + '"]', ""));
              return;
          }
          if (banner) banner.classList.remove("show");
          setVal('[data-e="role"]', e.role);
          setVal('[data-e="desc"]', e.roleDescription);
          setVal('[data-e="title"]', e.title);
          setVal('[data-e="value"]', e.value);
          setVal('[data-e="ident"]', e.identifier);
          setVal('[data-e="frame"]', devfmt.frame(e.frame));
      }

      function updateMousePos(p) {
          if (!p) return;
          if (p.sx != null) setVal('[data-cursor="screen"]', devfmt.coord(p.sx, p.sy));
          if (p.wx != null) setVal('[data-cursor="win"]', devfmt.coord(p.wx, p.wy));
          const cell = _q('[data-cursor="pixel"]');
          if (cell) {
              const sw = cell.querySelector(".pixel-swatch");
              const hx = cell.querySelector(".pixel-hex");
              if (p.pixel && p.pixel.hex) {
                  if (sw) { sw.style.background = p.pixel.hex; sw.style.display = ""; }
                  if (hx) hx.textContent = p.pixel.hex + devfmt.SEP + p.pixel.r + ", " + p.pixel.g + ", " + p.pixel.b;
                  cell.classList.remove("empty");
              } else {
                  if (sw) sw.style.display = "none";
                  if (hx) hx.textContent = devfmt.EMPTY;
                  cell.classList.add("empty");
              }
          }
      }

      function updateAll(payload) {
          if (lp.isPaused()) return;
          if (payload.window) updateCurrentWindow(payload.window);
          if (payload.element) updateElement(payload.element);
          if (payload.mouse) updateMousePos(payload.mouse);
          if (payload.events) payload.events.forEach(function(e) { appendEntry(e); });
      }
  // END State updates //

  // Flag event //
      function flagEvent(entry) {
          if (!entry) return;
          devfmt.windowFlag(_q(".flag-pill"), entry);
      }
  // END Flag event //

  // Window tabs //
      let _wtabs = null;
      function _tabs() {
          if (!_wtabs && _panel) {
              _wtabs = createTabs({
                  root: _panel,
                  tabSelector: ".wtab",
                  sectionSelector: ".wtab-section",
                  tabKey: (el) => el.dataset.wtab,
                  sectionKey: (el) => el.dataset.wsection,
                  onSame: () => playSlot("back"),
                  onSwitch(tab) {
                      playSlot("interact");
                      lp.sendToHost({ action: "tab", tab: tab });
                  },
              });
          }
          return _wtabs;
      }

      function switchWindowTab(tab) {
          const t = _tabs();
          if (t) t.switch(tab);
      }
      window.switchWindowTab = switchWindowTab;
  // END Window tabs //

  // Tab sync //
      function syncTab() {
          const active = _panel ? _panel.querySelector(".wtab.active") : null;
          lp.sendToHost({ action: "tab", tab: active ? active.dataset.wtab : "window" });
      }
  // END Tab sync //

  // Create LogPanel //
      const _panel = document.querySelector('.panel-window');
      const lp = createLogPanel({
          channel: "window",
          buildRow,
          container: _panel,
          maxEntries: 500,
          scrollThresh: 48,
          extractCopyText(el) {
              const ts = el.querySelector(".ts")?.textContent || "";
              const app = el.querySelector(".entry-app")?.textContent || "";
              const title = el.querySelector(".entry-title")?.textContent || "";
              const dim = el.querySelector(".dim-pill")?.textContent || "";
              const parts = [ts, app];
              if (title) parts.push(title);
              if (dim) parts.push(dim);
              return parts.join(" ");
          },
      });
  // END Create LogPanel //

  // Expose globals for inline handlers //
      window._panelPauseFns['window'] = lp.togglePause;
      window.playSlot    = lp.playSlot;
      window._panelClearFns['window'] = lp.clearLog;
      window.closePanel  = lp.closePanel;
      window.windowApplyTheme = lp.applyTheme;
  // END Expose globals for inline handlers //

  // Event log //
      function appendEntry(entry) {
          if (lp.isPaused()) return;
          const log = _q(".log");
          if (!log) return;
          const empty = log.querySelector(".log-empty");
          if (empty) empty.remove();
          flagEvent(entry);
          const atBottom = lp.isNearBottom(log);
          log.appendChild(buildRow(entry));
          lp.trimLog(log);
          if (atBottom) log.scrollTop = log.scrollHeight;
      }

      function loadHistory(entries) {
          const log = _q(".log");
          if (!log) return;
          if (!entries || entries.length === 0) {
              log.innerHTML = '<div class="log-empty">No window events yet</div>';
              return;
          }
          log.innerHTML = "";
          const capped = entries.length > lp.maxEntries ? entries.slice(-lp.maxEntries) : entries;
          const frag = document.createDocumentFragment();
          capped.forEach((e) => frag.appendChild(buildRow(e)));
          log.appendChild(frag);
          log.scrollTop = log.scrollHeight;
          flagEvent(capped[capped.length - 1]);
      }
  // END Event log //

  // Init //
      document.addEventListener("DOMContentLoaded", () => {
          if (typeof registerPanel === "function") {
              registerPanel("window", function(action, body) {
                  if (action === "appendEntry" && body) appendEntry(body);
                  else if (action === "updateAll" && body) updateAll(body);
                  else if (action === "updateCurrentWindow" && body) { if (!lp.isPaused()) updateCurrentWindow(body); }
                  else if (action === "updateElement" && body) { if (!lp.isPaused()) updateElement(body); }
                  else if (action === "updateMousePos" && body) { if (!lp.isPaused()) updateMousePos(body); }
                  else if (action === "loadHistory" && body) loadHistory(body);
                  else if (action === "syncTab") syncTab();
              });
          }
          if (window.shellPost) {
              var p = document.getElementById("panel");
              if (p) { p.style.borderRadius = "0"; p.style.clipPath = "none"; }
          }
          lp.sendToHost({ action: "ready" });
          syncTab();
      });
  // END Init //
})();
