(function() {
    "use strict";

// Candidate macros this one can be tethered to //
    function linkTargets(m, ctx) {
        var exclude = {};
        exclude[m.id] = true;
        (function walk(node) {
            (node.subs || []).forEach(function(s) { exclude[s.id] = true; walk(s); });
        })(m);
        var out = [];
        ctx.list().forEach(function(top) {
            function consider(x) {
                if (exclude[x.id]) return;
                if (x.group === "system" || x.systemBind) return;
                out.push({ value: x.id, label: x.label || x.id, group: top.label || top.id });
            }
            consider(top);
            (top.subs || []).forEach(consider);
        });
        return out;
    }
// END Candidate macros this one can be tethered to //

// Bind options menu //
    function post(action, body) {
        body.action = action;
        shellPost("macros", action, body);
    }

    var _live = null;

    function findEntry(list, id) {
        var hit = null;
        (list || []).forEach(function(top) {
            if (top.id === id) hit = top;
            (top.subs || []).forEach(function(s) { if (s.id === id) hit = s; });
        });
        return hit;
    }

    function refresh(list) {
        if (!_live || !_live.popup.isOpen()) return;
        var e = findEntry(list, _live.id);
        if (!e) return;
        _live.popup.setSub(subText(e));
        _live.popup.clear();
        fill(_live.popup, e, _live.ctx);
    }

    function subText(m) {
        if (m.parent) {
            return "Hold " + (m.linkMods || "its modifier") + " with "
                + (m.linkParent || m.parent) + "'s trigger, fires on " + (m.bind || "Unset");
        }
        return "Bind: " + (m.bind || "Unset");
    }

    function fill(p, m, ctx) {
        var linked = !!m.parent;
        var editable = m.group !== "system" && !m.systemBind;
        p.row("Rebind",
            linked
                ? "Press the modifier held with the linked macro's trigger."
                : "Press the new key or button next.",
            p.button("Capture", function() {
                p.close();
                if (linked) {
                    post("startModRebind", { id: m.id });
                } else {
                    post("startRebind", { id: m.id, systemBind: m.systemBind || false });
                }
            }));
        if (!linked) {
            p.row("Default bind", null, p.button("Reset", function() {
                p.close();
                post("resetBind", { id: m.id, systemBind: m.systemBind || false });
            }));
        }
        if (m.systemBind && m.bindType) {
            p.row("Ignore extra modifiers", "Fire even when other modifier keys are held.",
                p.toggle(m.ignoreMods, function(on) {
                    post("setSystemBindIgnoreMods", { id: m.id, value: on });
                }));
            if (m.bindType === "key") {
                p.row("Swallow input", "Keep the key from reaching the app while the bind is live.",
                    p.toggle(m.swallow, function(on) {
                        post("setSystemBindSwallow", { id: m.id, value: on });
                    }));
            }
            p.row("Unbind", "Turn this bind off. Capture or Reset brings it back.", p.button("Unbind", function() {
                p.close();
                post("unbindSystem", { id: m.id });
            }));
        }
        if (editable) {
            p.row("Enabled", null, p.toggle(m.enabled, function(on) {
                post("setMacroEnabled", { id: m.id, value: on });
            }));
            if (m.bindType) {
                p.row("Ignore extra modifiers", "Fire even when other modifier keys are held.",
                    p.toggle(m.ignoreMods, function(on) {
                        post("setBindIgnoreMods", { id: m.id, value: on });
                    }));
            }
            if (m.bindType === "key" || m.bindType === "combo") {
                p.row("Swallow input", "Keep the trigger from reaching the app while macros are on.",
                    p.toggle(m.swallow, function(on) {
                        post("setBindSwallow", { id: m.id, value: on });
                    }));
            }
            var opts = [{ value: "", label: "None", group: "" }].concat(linkTargets(m, ctx));
            p.row("Linked to",
                linked
                    ? "Fires on the linked macro's trigger plus this bind's modifier. Pick None to capture its own bind."
                    : "Fire on another macro's trigger plus a modifier.",
                p.select(opts, m.parent || "", function(v) {
                    if (v === (m.parent || "")) return;
                    if (v) {
                        post("bindToMacro", { id: m.id, targetId: v });
                    } else {
                        p.close();
                        post("startRebind", { id: m.id, systemBind: false });
                    }
                }));
            p.action(p.button("Delete macro", function() {
                ctx.confirmDelete(m.label || m.id).then(function(ok) {
                    if (!ok) return;
                    p.close();
                    if (window.playSlot) playSlot("back");
                    shellPost("macros", "deleteMacro", { id: m.id });
                    ctx.onDelete(m.id);
                });
            }, "danger"));
        }
        p.spacer();
        p.action(p.button("Done", function() { p.close(); }));
    }

    function openBindMenu(m, ctx) {
        if (!window.msPopup) return;
        window.msPopup.open({ title: m.label || m.id, sub: subText(m), build: function(p) {
            _live = { id: m.id, popup: p, ctx: ctx };
            fill(p, m, ctx);
        } });
    }
// END Bind options menu //

    window.msBindMenu = { open: openBindMenu, refresh: refresh };
})();
