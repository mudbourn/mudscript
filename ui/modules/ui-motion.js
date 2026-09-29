(function() {
    "use strict";

    // Motion //
        function glideOnWrap(row) {
            if (!window.ResizeObserver) return;
            var snap = function() {
                return Array.prototype.map.call(row.children, function(k) {
                    return k.getBoundingClientRect();
                });
            };
            var rows = function(rects) {
                var n = 0;
                var bottom = -Infinity;
                rects.forEach(function(r) {
                    if (!r.width) return;
                    if (r.top >= bottom - 1) n++;
                    bottom = r.top >= bottom - 1 ? r.bottom : Math.max(bottom, r.bottom);
                });
                return n;
            };
            var prev = null;
            var running = [];
            var onResize = function() {
                if (!row.getClientRects().length || !row.getBoundingClientRect().width) {
                    prev = null;
                    return;
                }
                var next = snap();
                var from = prev;
                if (running.length) {
                    from = next;
                    running.forEach(function(a) {
                        a.cancel();
                    });
                    running = [];
                    next = snap();
                }
                if (prev && prev.length === next.length && rows(prev) && rows(next) && rows(prev) !== rows(next)) {
                    var box = row.getBoundingClientRect();
                    Array.prototype.forEach.call(row.children, function(k, i) {
                        var maxLeft = box.right - next[i].width;
                        var maxTop = box.bottom - next[i].height;
                        var startLeft = Math.max(box.left, Math.min(from[i].left, maxLeft));
                        var startTop = Math.max(box.top, Math.min(from[i].top, maxTop));
                        var dx = startLeft - next[i].left;
                        var dy = startTop - next[i].top;
                        if (!k.animate || (Math.abs(dx) < 1 && Math.abs(dy) < 1)) return;
                        var anim = k.animate([
                            { transform: "translate(" + dx + "px," + dy + "px)" },
                            { transform: "none" }
                        ], {
                            duration: 180,
                            easing: "ease"
                        });
                        running.push(anim);
                        anim.onfinish = function() {
                            running = running.filter(function(r) {
                                return r !== anim;
                            });
                        };
                    });
                }
                prev = next;
            };
            new ResizeObserver(onResize).observe(row);
            return onResize;
        }

        function collapse(el, shut) {
            if (el._nestAnim) el._nestAnim.cancel();
            if (!shut) el.classList.remove("collapsed");
            var full = el.scrollHeight;
            if (!el.animate || !full) {
                el.classList.toggle("collapsed", shut);
                return;
            }
            el.style.overflow = "hidden";
            var open = {
                height: full + "px",
                opacity: 1
            };
            var closed = {
                height: "0px",
                minHeight: "0px",
                opacity: 0,
                paddingTop: "0px",
                paddingBottom: "0px"
            };
            var anim = el.animate(shut ? [open, closed] : [closed, open], {
                duration: 180,
                easing: "ease"
            });
            el._nestAnim = anim;
            var settle = function() {
                if (el._nestAnim !== anim) return;
                el._nestAnim = null;
                el.style.overflow = "";
                if (shut) el.classList.add("collapsed");
            };
            anim.onfinish = settle;
            setTimeout(settle, 230);
        }
    // END Motion //

    window.msMotion = {
        collapse: collapse,
        glideOnWrap: glideOnWrap
    };
})();
