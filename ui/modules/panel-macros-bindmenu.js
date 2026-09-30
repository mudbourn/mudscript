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
        if (e) _live.popup.setSub("Bind: " + (e.bind || "Unset"));
    }

    function openBindMenu(m, isSub, mode, ctx) {
        if (!window.msPopup) return;
        var editable = m.group !== "system" && !m.systemBind;
        window.msPopup.open({ title: m.label || m.id, sub: "Bind: " + (m.bind || "Unset"), build: function(p) {
            _live = { id: m.id, popup: p };
            if (isSub) {
                p.row("Capture", "What the next rebind records.", p.seg([
                    { value: false, label: "Modifier only" },
                    { value: true,  label: "Full trigger" },
                ], !!mode.full, function(v) { mode.full = v; }));
            }
            p.row("Rebind", "Press the new key or button next.", p.button("Capture", function() {
                p.close();
                if (isSub && !mode.full) {
                    post("startModRebind", { id: m.id });
                } else {
                    post("startRebind", { id: m.id, systemBind: m.systemBind || false });
                }
            }));
            if (isSub) {
                p.row("Parent", "Undo the link and bind this macro on its own.", p.button("Re-attach", function() {
                    p.close();
                    post("clearModifier", { id: m.id });
                }));
            } else {
                p.row("Default bind", null, p.button("Reset", function() {
                    p.close();
                    post("resetBind", { id: m.id, systemBind: m.systemBind || false });
                }));
            }
            if (!editable) return;
            p.row("Enabled", null, p.toggle(m.enabled, function(on) {
                post("setMacroEnabled", { id: m.id, value: on });
            }));
            if (m.bindType === "key" || m.bindType === "combo") {
                p.row("Ignore extra modifiers", "Fire even when other modifier keys are held.",
                    p.toggle(m.ignoreMods, function(on) {
                        post("setBindIgnoreMods", { id: m.id, value: on });
                    }));
            }
            var targets = linkTargets(m, ctx);
            if (targets.length) {
                var opts = m.parent ? targets : [{ value: "", label: "None", group: "" }].concat(targets);
                p.row("Linked to", "Fire as a sub-bind of another macro.",
                    p.select(opts, m.parent || "", function(v) {
                        if (v) post("bindToMacro", { id: m.id, targetId: v });
                    }));
            }
            p.action(p.button("Delete macro", function() {
                ctx.confirmDelete(m.label || m.id).then(function(ok) {
                    if (!ok) return;
                    p.close();
                    if (window.playSlot) playSlot("back");
                    shellPost("macros", "deleteMacro", { id: m.id });
                    ctx.onDelete(m.id);
                });
            }, "danger"));
            p.spacer();
            p.action(p.button("Done", function() { p.close(); }));
        } });
    }
// END Bind options menu //

    window.msBindMenu = { open: openBindMenu, refresh: refresh };
})();
