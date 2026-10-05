(function() {
    "use strict";

    // Factory //
        var COALESCE_MS = 1500;

        function typingTarget() {
            var el = document.activeElement;
            if (!el || !el.closest) return null;
            return el.closest("input, textarea, [contenteditable='true']");
        }

        function createHistory(opts) {
            var limit = opts.limit || 64;
            var stack = [];
            var index = -1;
            var restoring = false;
            var lastKey = null;
            var lastAt = 0;
            var listeners = [];

            function notify() { listeners.forEach(function(fn) { fn(); }); }

            function snap() { return JSON.stringify(opts.capture()); }

            function apply() {
                restoring = true;
                try {
                    opts.restore(JSON.parse(stack[index]));
                } finally {
                    restoring = false;
                }
                lastKey = null;
                notify();
            }

            return {
                reset: function() {
                    stack = [snap()];
                    index = 0;
                    lastKey = null;
                    notify();
                },
                record: function() {
                    if (restoring) return;
                    if (index < 0) { this.reset(); return; }
                    var s = snap();
                    if (s === stack[index]) return;
                    var key = typingTarget();
                    var now = Date.now();
                    stack.length = index + 1;
                    if (key && key === lastKey && index > 0 && now - lastAt < COALESCE_MS) {
                        stack[index] = s;
                    } else {
                        stack.push(s);
                        if (stack.length > limit + 1) stack.shift();
                        index = stack.length - 1;
                    }
                    lastKey = key;
                    lastAt = now;
                    notify();
                },
                undo: function() {
                    if (index <= 0) return false;
                    index--;
                    apply();
                    return true;
                },
                redo: function() {
                    if (index >= stack.length - 1) return false;
                    index++;
                    apply();
                    return true;
                },
                canUndo: function() { return index > 0; },
                canRedo: function() { return index < stack.length - 1; },
                listen: function(fn) { listeners.push(fn); },
            };
        }
    // END Factory //

    // Undo and redo keys outside text fields //
        function historyKey(e) {
            if (!msMod(e) || typingTarget()) return null;
            var k = e.key.toLowerCase();
            if (k === "z") return e.shiftKey ? "redo" : "undo";
            if (k === "y") return "redo";
            return null;
        }
    // END Undo and redo keys outside text fields //

    // Undo and redo menu buttons //
        var ICON_PATHS = {
            undo: '<path d="M9 14L4 9L9 4M4 9H14.5C17.5376 9 20 11.4624 20 14.5C20 17.5376 17.5376 20 14.5 20H11" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
            redo: '<path d="M15 14L20 9L15 4M20 9H9.5C6.46243 9 4 11.4624 4 14.5C4 17.5376 6.46243 20 9.5 20H13" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
        };

        function historyButtons(hist, cls) {
            var out = {};
            ["undo", "redo"].forEach(function(which) {
                var b = document.createElement("button");
                b.className = cls;
                b.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
                    + ICON_PATHS[which] + '</svg><span>' + (which === "undo" ? "Undo" : "Redo") + '</span>';
                b.title = msKeyLabel(which === "undo" ? "Undo (Cmd+Z)" : "Redo (Shift+Cmd+Z)").replace("Shift+Ctrl+Z", "Ctrl+Y");
                b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
                b.addEventListener("click", function() {
                    if (hist[which]() && window.playSlot) playSlot("interact");
                });
                out[which] = b;
            });
            function refresh() {
                out.undo.disabled = !hist.canUndo();
                out.redo.disabled = !hist.canRedo();
                out.undo.style.opacity = out.undo.disabled ? "0.4" : "";
                out.redo.style.opacity = out.redo.disabled ? "0.4" : "";
            }
            hist.listen(refresh);
            refresh();
            return out;
        }
    // END Undo and redo menu buttons //

    window.createHistory = createHistory;
    window.msHistoryButtons = historyButtons;
    window.msHistoryKey = historyKey;
})();
