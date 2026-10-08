(function () {
    "use strict";
    if (window.msPad) return;

    // Aliases //
        var ALIAS = {
            lb: "l1",
            rb: "r1",
            l: "l1",
            r: "r1",
            lt: "l2",
            rt: "r2",
            zl: "l2",
            zr: "r2",
            ls: "l3",
            rs: "r3",
            lsb: "l3",
            rsb: "r3",
            cross: "a",
            circle: "b",
            square: "x",
            triangle: "y",
            start: "menu",
            plus: "menu",
            select: "options",
            back: "options",
            view: "options",
            share: "options",
            create: "options",
            minus: "options",
            guide: "home",
            xbox: "home",
            ps: "home",
            dup: "up",
            ddown: "down",
            dleft: "left",
            dright: "right",
            dpadup: "up",
            dpaddown: "down",
            dpadleft: "left",
            dpadright: "right",
        };
    // END Aliases //

    // Labels //
        var DPAD = {
            up: "Up",
            down: "Down",
            left: "Left",
            right: "Right",
        };

        function withDpad(set) {
            Object.keys(DPAD).forEach(function (k) { set[k] = DPAD[k]; });
            return set;
        }

        var LABELS = {
            xbox: withDpad({
                a: "A",
                b: "B",
                x: "X",
                y: "Y",
                l1: "LB",
                r1: "RB",
                l2: "LT",
                r2: "RT",
                l3: "LS",
                r3: "RS",
                menu: "Menu",
                options: "View",
                home: "Xbox",
            }),
            generic: withDpad({
                a: "A",
                b: "B",
                x: "X",
                y: "Y",
                l1: "LB",
                r1: "RB",
                l2: "LT",
                r2: "RT",
                l3: "LS",
                r3: "RS",
                menu: "Menu",
                options: "View",
                home: "Home",
            }),
            ds4: withDpad({
                a: "Cross",
                b: "Circle",
                x: "Square",
                y: "Triangle",
                l1: "L1",
                r1: "R1",
                l2: "L2",
                r2: "R2",
                l3: "L3",
                r3: "R3",
                menu: "Options",
                options: "Share",
                home: "PS",
            }),
            "switch": withDpad({
                a: "B",
                b: "A",
                x: "Y",
                y: "X",
                l1: "L",
                r1: "R",
                l2: "ZL",
                r2: "ZR",
                l3: "LS",
                r3: "RS",
                menu: "+",
                options: "-",
                home: "Home",
            }),
        };
    // END Labels //

    // API //
        function name(n) {
            var k = String(n == null ? "" : n).toLowerCase().replace(/^pad/, "").replace(/[\s_-]/g, "");
            return ALIAS[k] || k;
        }

        function type() {
            return LABELS[window.__gpType] ? window.__gpType : "xbox";
        }

        function label(n, padType) {
            var set = LABELS[padType || type()] || LABELS.xbox;
            return set[name(n)] || String(n == null ? "" : n).toUpperCase();
        }

        function options(list) {
            return (list || []).map(function (o) {
                var v = (o && typeof o === "object") ? o.value : o;
                return { value: v, label: label(v) };
            });
        }

        window.msPad = {
            name: name,
            type: type,
            label: label,
            options: options,
            BUTTONS: ["a", "b", "x", "y", "l1", "r1", "l2", "r2", "l3", "r3",
                "up", "down", "left", "right", "menu", "options", "home"],
        };
    // END API //
})();
