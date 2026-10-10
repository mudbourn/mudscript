(function() {
"use strict";
  // Constants //
      const SEP = " - ";
      const EMPTY = "-";
      const MOD_ORDER = ["ctrl", "alt", "shift", "cmd"];

      const MOD_ALIAS = {
          control: "ctrl",
          option: "alt",
          opt: "alt",
          command: "cmd",
          meta: "cmd",
          win: "cmd",
      };

      const BTN_NAMES = {
          0: "Left",
          1: "Right",
          2: "Middle",
          3: "Btn4",
          4: "Btn5",
      };

      const BADGE = {
          focus: "badge-focus",
          move: "badge-move",
          resize: "badge-resize",
          minimize: "badge-state",
          unminimize: "badge-state",
          fullscreen: "badge-state",
      };

      const LABEL = {
          focus: "focused",
          move: "moved",
          resize: "resized",
          minimize: "minimized",
          unminimize: "restored",
          fullscreen: "fullscreen",
          hide: "hidden",
          show: "shown",
      };
  // END Constants //

  // Text formatters //
      function has(v) { return v != null && v !== ""; }

      function orEmpty(text) { return has(text) ? String(text) : EMPTY; }

      function coord(x, y) { return (x ?? "?") + ", " + (y ?? "?"); }

      function size(w, h) { return (w ?? "?") + " x " + (h ?? "?"); }

      function frame(f) { return f ? coord(f.x, f.y) + SEP + size(f.w, f.h) : ""; }

      function key(name, code) { return (has(name) ? name : "?") + " (" + (has(code) ? code : "?") + ")"; }

      function btnName(n) { return BTN_NAMES[n] ?? "M" + n; }

      function button(n) { return btnName(n) + " (" + n + ")"; }

      function scroll(direction, amount) { return direction + (amount > 1 ? " x" + amount : ""); }

      function eventLabel(type) { return LABEL[type] || type; }

      function eventDetail(entry) {
          if (entry.type === "move") return coord(entry.x, entry.y);
          if (entry.type === "resize") return size(entry.w, entry.h);
          return entry.app || "";
      }
  // END Text formatters //

  // Key ordering //
      function modRank(name) {
          let n = String(name || "").toLowerCase().replace(/^(left|right|l|r)[\s_-]?/, "");
          n = MOD_ALIAS[n] || n;
          const i = MOD_ORDER.indexOf(n);
          return i < 0 ? MOD_ORDER.length : i;
      }

      function keyName(e) { return typeof e === "object" && e !== null ? e.name : e; }

      function sortKeys(list) {
          return list.slice().sort(function(a, b) {
              const d = modRank(keyName(a)) - modRank(keyName(b));
              if (d !== 0) return d;
              return String(keyName(a)).localeCompare(String(keyName(b)));
          });
      }
  // END Key ordering //

  // DOM rendering //
      function mkSpan(cls, text) {
          const s = document.createElement("span");
          s.className = cls;
          s.textContent = text;
          return s;
      }

      function mkIcon(cls, name) {
          const s = document.createElement("span");
          s.className = cls;
          s.innerHTML = icon(name, "icon-inline");
          return s;
      }

      function renderFlag(el, label, value, detail, recent) {
          if (!el) return;
          el.textContent = "";
          el.appendChild(mkSpan("flag-label", label));
          el.appendChild(mkSpan("flag-value", orEmpty(value)));
          if (detail != null) el.appendChild(mkSpan("flag-detail", detail));
          el.classList.toggle("flag-recent", !!recent);
      }

      function renderPills(row, kind, texts) {
          if (!row) return;
          row.textContent = "";
          if (!texts || texts.length === 0) {
              row.appendChild(mkSpan("pill pill-empty", EMPTY));
              return;
          }
          texts.forEach(function(t) { row.appendChild(mkSpan("pill pill-" + kind, t)); });
      }

      function initFlags(root) {
          (root || document).querySelectorAll("[data-flag-label]").forEach(function(el) {
              renderFlag(el, el.dataset.flagLabel, "", el.hasAttribute("data-flag-detail") ? "" : null, false);
          });
      }
  // END DOM rendering //

  // Log rows //
      function windowRow(entry) {
          const row = document.createElement("div");
          const t = entry.type;
          row.className = "entry" + (t === "move" || t === "resize" ? " move-entry" : "");
          row.appendChild(mkSpan("ts", "[" + (entry.ts || "") + "]"));
          row.appendChild(mkSpan("badge " + (BADGE[t] || "badge-state"), eventLabel(t)));
          if (t === "focus") {
              row.appendChild(mkSpan("ename", entry.app || "?"));
              if (entry.title) row.appendChild(mkSpan("edetail", "- " + entry.title));
          } else if (t === "move" || t === "resize") {
              row.appendChild(mkSpan("edetail", eventDetail(entry)));
              if (entry.count > 1) row.appendChild(mkSpan("ecount", "x" + entry.count));
          } else if (t === "fullscreen") {
              row.appendChild(mkSpan("ename", entry.on ? "entered" : "exited"));
              if (entry.app) row.appendChild(mkSpan("edetail", "- " + entry.app));
          } else {
              if (entry.app) row.appendChild(mkSpan("ename", entry.app));
              if (entry.title) row.appendChild(mkSpan("edetail", "- " + entry.title));
          }
          return row;
      }

      function inputRow(entry) {
          const row = document.createElement("div");
          const t = entry.type;
          if (t === "mousemove") {
              row.className = "entry move-entry";
              row.append(
                  mkSpan("ts", "[" + (entry.ts || "") + "]"),
                  mkSpan("arrow arrow-move", "->"),
                  mkSpan("move-name", coord(entry.x, entry.y)),
              );
              return row;
          }
          row.className = "entry";
          row.appendChild(mkSpan("ts", "[" + (entry.ts || "") + "]"));
          if (t === "key") {
              row.append(
                  mkSpan("badge badge-key", "key"),
                  mkIcon("arrow " + (entry.down ? "arrow-key" : "arrow-key-up"), entry.down ? "arrow-down" : "arrow-up"),
                  mkSpan("key-name", key(entry.key, entry.keyCode)),
              );
          } else if (t === "mouse") {
              row.append(
                  mkSpan("badge badge-mouse", "mouse"),
                  mkIcon("arrow " + (entry.down ? "arrow-mouse" : "arrow-up"), entry.down ? "arrow-down" : "arrow-up"),
                  mkSpan("mouse-name", button(entry.button)),
                  mkSpan("dim", coord(entry.x, entry.y)),
              );
          } else if (t === "scroll") {
              row.append(
                  mkSpan("badge badge-scroll", "scroll"),
                  mkIcon("arrow arrow-scroll", entry.direction === "up" ? "arrow-up" : "arrow-down"),
                  mkSpan("scroll-name", scroll(entry.direction, entry.amount)),
              );
          }
          return row;
      }
  // END Log rows //

  // Bar helpers //
      function windowFlag(el, entry) {
          renderFlag(el, "Event", eventLabel(entry.type), eventDetail(entry), true);
      }

      function lastInput(entries) {
          const last = { key: null, mouse: null };
          (entries || []).forEach(function(e) {
              if (!e.down) return;
              if (e.type === "key") last.key = e;
              else if (e.type === "mouse") last.mouse = e;
          });
          return last;
      }

      function keyPills(list) {
          return sortKeys(list || []).map(function(e) {
              return typeof e === "object" && e !== null ? key(e.name, e.code) : String(e);
          });
      }

      function buttonPills(list) {
          const arr = Array.isArray(list) ? list : Object.values(list || {});
          return arr.slice().sort(function(a, b) { return a - b; }).map(button);
      }
  // END Bar helpers //

  window.devfmt = {
      SEP: SEP,
      EMPTY: EMPTY,
      has: has,
      orEmpty: orEmpty,
      coord: coord,
      size: size,
      frame: frame,
      key: key,
      btnName: btnName,
      button: button,
      scroll: scroll,
      eventLabel: eventLabel,
      eventDetail: eventDetail,
      sortKeys: sortKeys,
      mkSpan: mkSpan,
      renderFlag: renderFlag,
      renderPills: renderPills,
      initFlags: initFlags,
      windowRow: windowRow,
      inputRow: inputRow,
      windowFlag: windowFlag,
      lastInput: lastInput,
      keyPills: keyPills,
      buttonPills: buttonPills,
  };

  document.addEventListener("DOMContentLoaded", function() { initFlags(document); });
})();
