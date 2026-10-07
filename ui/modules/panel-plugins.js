(function() {
"use strict";

  // State //
      let S = {};

      function ui() { return window.msUI || null; }
      function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

      function send(action, body) {
          if (!window.shellPost) return;
          window.shellPost("plugins", action, Object.assign({ action }, body || {}));
      }
  // END State //

  // Status vocabulary //
      const STATUS = {
          modified: {
              pill:  "danger",
              label: "Modified",
              note:  "The files changed after this plugin was installed. "
                   + "Guardian will block the next start until it is removed or "
                   + "re-imported.",
          },
          unrecorded: {
              pill:  "danger",
              label: "Unrecognized",
              note:  "This plugin was not installed through mudscript, so there "
                   + "is no record of where it came from. Guardian will block "
                   + "the next start until it is removed or re-imported.",
          },
      };
  // END Status vocabulary //

  // Manage //
      function pluginTools(dir) {
          const settings = (S.userSettings || []).filter((it) => it.plugin === dir);
          const menus = (S.userMenus || []).filter((m) => m.plugin === dir);
          const fns = (window.msMacroFunctions || []).filter((fn) => fn.plugin === dir);
          return {
              settings,
              menus,
              fns,
              count: settings.filter((it) => it.type !== "divider").length + menus.length + fns.length,
          };
      }

      function openManage(p) {
          const P = window.msSettings;
          if (!window.msPopup || !P) return;
          playSlot("interact");
          window.msPopup.open({
              title: p.name || p.dir,
              sub: "Settings this plugin adds. Macros read them like any other tool.",
              width: 520,
              build: (pop) => {
                  const tools = pluginTools(p.dir);
                  const body = pop.add(document.createElement("div"));
                  body.className = "plugin-manage";
                  if (tools.settings.length) P.renderItemsCollapsed(body, tools.settings);
                  for (const menu of tools.menus) {
                      body.appendChild(ui().groupLabel(menu.title || menu.id));
                      P.buildUserSection(body, menu);
                  }
                  if (tools.fns.length) {
                      const { h, groupLabel, actionBtn } = ui();
                      body.appendChild(groupLabel("Functions"));
                      for (const fn of tools.fns) {
                          const lbl = h("div", { cls: "row-label" }, fn.name || fn.id);
                          lbl.appendChild(h("small", {}, "call by id '" + fn.id + "'"));
                          body.appendChild(h("div", { cls: "row" }, lbl,
                              actionBtn("Call in macro", "", () => {
                                  if (window.macroLab && window.macroLab.addTool) {
                                      window.macroLab.addTool({
                                          action: "call_fn",
                                          params: { name: fn.id },
                                      });
                                      pop.close();
                                  } else {
                                      P.showAlert("Open a macro in the Macros panel first.");
                                  }
                              })));
                      }
                  }
              },
          });
      }
  // END Manage //

  // Card //
      function pluginCard(p) {
          const { h, toggle, actionBtn } = ui();
          const flagged = p.status !== "ok";

          const card = h("div", {
              cls: "plugin-card"
                  + (flagged ? " flagged" : "")
                  + (p.enabled ? "" : " off"),
              onmouseenter: () => playSlot("hover"),
          });

          // Identity //
              const name = h("div", { cls: "plugin-name" }, p.name || p.dir);
              const st = STATUS[p.status];
              if (st) name.appendChild(h("span", { cls: "pill " + st.pill }, st.label));
              if (!p.enabled) name.appendChild(h("span", { cls: "pill" }, "Off"));
          // END //

          const bits = [];
          if (p.version) bits.push("v" + p.version);
          if (p.author) bits.push("by " + p.author);
          bits.push(p.dir);
          if (p.installedAt) {
              const d = String(p.installedAt).slice(0, 10);
              if (d) bits.push("installed " + d);
          }

          const id = h("div", { cls: "plugin-card-id" },
              name,
              h("div", { cls: "plugin-meta", title: bits.join("  -  ") }, bits.join("  -  ")),
          );

          const top = h("div", { cls: "plugin-card-top" }, id);
          if (!flagged) {
              top.appendChild(toggle(p.enabled, (e) => {
                  send("setPluginEnabled", { dir: p.dir, value: e.target.checked });
              }));
          }
          card.appendChild(top);

          if (p.description) {
              card.appendChild(h("div", { cls: "plugin-desc" }, p.description));
          }

          // Notes //
              if (st) {
                  card.appendChild(h("div", { cls: "plugin-note danger" }, st.note));
              } else if (p.loadError) {
                  card.appendChild(h("div", { cls: "plugin-note danger" },
                      "Failed to load: " + p.loadError));
              } else if (p.enabled && !p.running) {
                  card.appendChild(h("div", { cls: "plugin-note danger" },
                      "Enabled, but not running. Reload to try again."));
              }
          // END //

          // Actions //
              const actions = h("div", { cls: "plugin-actions" });
              if (pluginTools(p.dir).count) {
                  actions.appendChild(actionBtn("Manage", "", () => openManage(p)));
              }
              actions.appendChild(actionBtn("Remove", "danger", () =>
                  send("removePlugin", { dir: p.dir, label: p.name || p.dir })));
              if (p.website) {
                  actions.appendChild(actionBtn("Website", "", () =>
                      send("openURL", { url: p.website })));
              }
              card.appendChild(actions);
          // END //

          return card;
      }
  // END Card //

  // Body //
      function build(body) {
          const { h, groupLabel, btnRow, actionBtn } = ui();
          const list = Array.isArray(S.plugins) ? S.plugins : [];

          if (list.length === 0) {
              body.appendChild(h("div", { cls: "plugins-empty" },
                  h("div", {}, "No plugins installed."),
                  h("div", { style: "margin-top:8px" },
                      "Plugins run as code, so they can only be imported from "
                      + "the validated library."),
              ));
          } else {
              const flagged = list.filter((p) => p.status !== "ok");
              const clean   = list.filter((p) => p.status === "ok");

              for (const p of flagged) body.appendChild(pluginCard(p));
              if (flagged.length && clean.length) {
                  body.appendChild(groupLabel("Installed"));
              }
              for (const p of clean) body.appendChild(pluginCard(p));
          }

          body.appendChild(h("div", { style: "height:10px" }));
          body.appendChild(h("div", { cls: "section" },
              h("div", { cls: "section-body open", style: "padding-top:4px" },
                  btnRow(
                      actionBtn("Import Plugin...", "", () =>
                          send("importPackage", {})),
                      actionBtn("Open Folder", "", () =>
                          send("openPluginsFolder", {})),
                  ),
              ),
          ));
      }
  // END Body //

  // Render //
      function renderPluginsPanel(state) {
          if (state) S = state;
          if (!ui()) return;

          const el = document.getElementById("plugins-scroll");
          if (!el) return;
          const scrollTop = el.scrollTop;
          el.innerHTML = "";
          build(el);
          el.scrollTop = scrollTop;
      }
      window.renderPluginsPanel = renderPluginsPanel;
  // END Render //
})();
