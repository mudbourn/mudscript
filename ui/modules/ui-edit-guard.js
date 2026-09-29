(function() {
    "use strict";

    // Edit Guard //
        function editGuard(scope, apply) {
            var deferred = null;
            var held = false;

            function editing() {
                if (held) return true;
                var a = document.activeElement;
                if (!a || !a.closest || !a.closest(scope)) return false;
                if (a.tagName === "TEXTAREA") return true;
                if (a.tagName !== "INPUT") return false;
                var type = (a.type || "text").toLowerCase();
                return type !== "checkbox" && type !== "radio" && type !== "range";
            }

            function flush() {
                setTimeout(function() {
                    if (deferred === null || editing()) return;
                    var next = deferred;
                    deferred = null;
                    apply(next);
                }, 0);
            }

            document.addEventListener("pointerdown", function(e) {
                var t = e.target;
                if (t && t.matches && t.matches('input[type="range"]') && t.closest(scope)) {
                    held = true;
                }
            }, true);
            document.addEventListener("pointerup", function() {
                if (!held) return;
                held = false;
                flush();
            }, true);
            document.addEventListener("focusout", flush, true);
            document.addEventListener("change", flush, true);
            window.addEventListener("blur", flush);

            return function(state) {
                if (editing()) {
                    deferred = state;
                    return;
                }
                deferred = null;
                apply(state);
            };
        }
    // END Edit Guard //

    window.msEditGuard = editGuard;
})();
