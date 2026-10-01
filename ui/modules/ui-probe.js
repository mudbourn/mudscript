(function() {
    "use strict";

    // Helpers //
        var LAYOUT_PROPS = [
            "display",
            "position",
            "box-sizing",
            "flex-direction",
            "flex-wrap",
            "flex",
            "align-items",
            "justify-content",
            "gap",
            "grid-template-columns",
            "grid-template-rows",
            "overflow",
            "visibility",
            "opacity",
            "transform",
            "zoom"
        ];

        var MOTION_PROPS = [
            "transition-property",
            "transition-duration",
            "animation-name",
            "animation-duration"
        ];

        var CONTROL_SEL = "button, input, textarea, [role=button], .icon-btn, .ui-select";

        function list(sel, root) {
            if (!sel) return [];
            if (sel.nodeType === 1) return [sel];
            try {
                return Array.prototype.slice.call((root || document).querySelectorAll(sel));
            } catch (e) {
                return [];
            }
        }

        function label(el) {
            if (!el || el.nodeType !== 1) return String(el);
            var s = el.tagName.toLowerCase();
            if (el.id) s += "#" + el.id;
            var cls = (el.getAttribute("class") || "").trim();
            if (cls) s += "." + cls.split(/\s+/).slice(0, 4).join(".");
            return s;
        }

        function path(el) {
            var parts = [];
            var cur = el;
            while (cur && cur.nodeType === 1 && parts.length < 5) {
                parts.unshift(label(cur));
                if (cur.id) break;
                cur = cur.parentElement;
            }
            return parts.join(" > ");
        }

        function r1(n) {
            return Math.round(n * 10) / 10;
        }

        function box(el) {
            var r = el.getBoundingClientRect();
            return {
                x: r1(r.left),
                y: r1(r.top),
                w: r1(r.width),
                h: r1(r.height)
            };
        }

        function boxText(b) {
            return b.w + "x" + b.h + " @" + b.x + "," + b.y;
        }

        function shown(el) {
            if (!el.isConnected) return false;
            var cs = getComputedStyle(el);
            if (cs.display === "none" || cs.visibility === "hidden") return false;
            return el.getClientRects().length > 0;
        }

        function parked(el) {
            for (var p = el; p && p.nodeType === 1; p = p.parentElement) {
                var cs = getComputedStyle(p);
                if (cs.position !== "absolute" && cs.position !== "fixed") continue;
                if (cs.transform === "none" && cs.opacity !== "0") continue;
                var r = p.getBoundingClientRect();
                var vw = document.documentElement.clientWidth;
                var vh = document.documentElement.clientHeight;
                if (cs.opacity === "0" || r.left >= vw || r.right <= 0 || r.top >= vh || r.bottom <= 0) return true;
            }
            return false;
        }

        function inFlowRight(el) {
            var right = 0;
            Array.prototype.forEach.call(el.children, function(k) {
                if (!shown(k)) return;
                var p = getComputedStyle(k).position;
                if (p === "absolute" || p === "fixed") return;
                right = Math.max(right, k.getBoundingClientRect().right);
            });
            return right;
        }

        function clipsX(cs) {
            return cs.overflowX !== "visible";
        }

        function clipsY(cs) {
            return cs.overflowY !== "visible";
        }

        function scrollsX(cs) {
            return cs.overflowX === "auto" || cs.overflowX === "scroll";
        }

        function scrollsY(cs) {
            return cs.overflowY === "auto" || cs.overflowY === "scroll";
        }
    // END Helpers //

    // Inspect //
        function inspect(sel, opts) {
            opts = opts || {};
            var els = list(sel, opts.root);
            var name = typeof sel === "string" ? sel : label(sel);
            if (!els.length) return "probe: no match for " + name;
            var max = opts.max || 3;
            var out = ["probe: " + name + " (" + els.length + " match" + (els.length === 1 ? "" : "es") + ")"];
            els.slice(0, max).forEach(function(el, i) {
                out.push(inspectOne(el, i));
            });
            if (els.length > max) out.push("... " + (els.length - max) + " more");
            return out.join("\n");
        }

        function inspectOne(el, i) {
            var cs = getComputedStyle(el);
            var b = box(el);
            var lines = ["[" + i + "] " + path(el), "    box " + boxText(b) + (shown(el) ? "" : "  HIDDEN")];
            var layout = [];
            LAYOUT_PROPS.forEach(function(p) {
                var v = cs.getPropertyValue(p);
                if (v && v !== "normal" && v !== "none" && v !== "auto" && v !== "0" && v !== "1") layout.push(p + ":" + v);
            });
            lines.push("    layout " + layout.join("  "));
            lines.push("    size client " + el.clientWidth + "x" + el.clientHeight + "  scroll " + el.scrollWidth + "x" + el.scrollHeight + "  min-w " + cs.minWidth + "  max-w " + cs.maxWidth);
            var motion = MOTION_PROPS.map(function(p) {
                return p.replace("transition-", "t-").replace("animation-", "a-") + ":" + cs.getPropertyValue(p);
            });
            lines.push("    motion " + motion.join("  "));
            if (el.getAnimations) {
                var live = el.getAnimations().map(function(a) {
                    return (a.animationName || a.transitionProperty || "anim") + "(" + a.playState + ")";
                });
                if (live.length) lines.push("    running " + live.join(" "));
            }
            var kids = Array.prototype.slice.call(el.children).filter(shown);
            if (kids.length) {
                lines.push("    children " + kids.length + " (" + flowOf(kids) + ")");
                kids.slice(0, 12).forEach(function(k) {
                    var kb = box(k);
                    lines.push("      " + label(k) + "  " + kb.w + "x" + kb.h + " +" + r1(kb.x - b.x) + ",+" + r1(kb.y - b.y) + "  " + getComputedStyle(k).display);
                });
                if (kids.length > 12) lines.push("      ... " + (kids.length - 12) + " more");
            }
            var txt = (el.textContent || "").replace(/\s+/g, " ").trim();
            if (txt) lines.push("    text \"" + txt.slice(0, 80) + (txt.length > 80 ? "..." : "") + "\"");
            return lines.join("\n");
        }

        function flowOf(kids) {
            if (kids.length < 2) return "single";
            var rows = 1;
            var cols = 1;
            for (var i = 1; i < kids.length; i++) {
                var a = kids[i - 1].getBoundingClientRect();
                var b = kids[i].getBoundingClientRect();
                if (b.top >= a.bottom - 1) rows++;
                else if (b.left >= a.right - 1) cols++;
            }
            if (rows === 1) return "horizontal";
            if (cols === 1) return "vertical";
            return "mixed " + rows + " rows";
        }
    // END Inspect //

    // Tree //
        function tree(sel, depth) {
            var root = list(sel)[0];
            if (!root) return "probe: no match for " + sel;
            depth = depth == null ? 4 : depth;
            var out = [];
            (function walk(el, d) {
                if (!shown(el)) return;
                var cs = getComputedStyle(el);
                var extra = cs.display.indexOf("flex") >= 0 ? " " + cs.flexDirection : "";
                out.push(new Array(d + 1).join("  ") + label(el) + "  " + boxText(box(el)) + "  " + cs.display + extra);
                if (d >= depth) return;
                Array.prototype.forEach.call(el.children, function(k) {
                    walk(k, d + 1);
                });
            })(root, 0);
            return out.join("\n");
        }
    // END Tree //

    // Audit //
        function audit(sel, opts) {
            opts = opts || {};
            var root = list(sel || "body")[0];
            if (!root) return "probe: no match for " + sel;
            var issues = [];
            var push = function(kind, el, msg) {
                issues.push({
                    kind: kind,
                    el: el,
                    msg: msg
                });
            };
            var all = [root].concat(Array.prototype.slice.call(root.querySelectorAll("*")));
            all.forEach(function(el) {
                if (el.closest("svg") && el.tagName.toLowerCase() !== "svg") return;
                if (!shown(el) || parked(el)) return;
                auditClip(el, push);
                auditStack(el, push);
                auditControl(el, push);
                auditEscape(el, push);
            });
            auditVars(push);
            auditFonts(root, push);
            if (opts.kinds) {
                issues = issues.filter(function(it) {
                    return opts.kinds.indexOf(it.kind) >= 0;
                });
            }
            var counts = {};
            issues.forEach(function(it) {
                counts[it.kind] = (counts[it.kind] || 0) + 1;
            });
            var head = "audit: " + label(root) + "  " + issues.length + " issue(s)  " + JSON.stringify(counts);
            var max = opts.max || 60;
            var body = issues.slice(0, max).map(function(it) {
                return it.kind + "  " + (it.el ? path(it.el) : "-") + "\n    " + it.msg;
            });
            if (issues.length > max) body.push("... " + (issues.length - max) + " more");
            return [head].concat(body).join("\n");
        }

        function auditClip(el, push) {
            var cs = getComputedStyle(el);
            var tag = el.tagName.toLowerCase();
            if (tag === "input" || tag === "textarea" || tag === "select") return;
            if (el.closest("[aria-hidden='true']")) return;
            var overX = el.scrollWidth - el.clientWidth;
            var overY = el.scrollHeight - el.clientHeight;
            var flowOver = el.children.length ? inFlowRight(el) - el.getBoundingClientRect().right : overX;
            if (overX > 2 && flowOver > 2 && clipsX(cs) && !scrollsX(cs) && cs.textOverflow !== "ellipsis") {
                push("CLIP-X", el, "content " + el.scrollWidth + "px wide in " + el.clientWidth + "px box, clipped by overflow-x:" + cs.overflowX);
            }
            if (overY > 2 && clipsY(cs) && !scrollsY(cs) && el.clientHeight > 0) {
                push("CLIP-Y", el, "content " + el.scrollHeight + "px tall in " + el.clientHeight + "px box, clipped by overflow-y:" + cs.overflowY);
            }
        }

        function auditStack(el, push) {
            if (el.closest("svg")) return;
            var kids = Array.prototype.slice.call(el.children).filter(shown);
            if (kids.length < 2 || kids.length > 6) return;
            var small = kids.every(function(k) {
                var r = k.getBoundingClientRect();
                return r.width > 0 && r.width <= 48 && r.height <= 48;
            });
            if (!small) return;
            if (flowOf(kids) !== "vertical") return;
            var cs = getComputedStyle(el);
            if (cs.display.indexOf("flex") >= 0 && cs.flexDirection.indexOf("column") === 0) return;
            if (cs.display.indexOf("grid") >= 0) return;
            var need = kids.reduce(function(s, k) {
                return s + k.getBoundingClientRect().width;
            }, 0);
            push("STACKED", el, kids.length + " small children stack vertically in display:" + cs.display + " (width " + el.clientWidth + "px, row needs " + r1(need) + "px)");
        }

        function auditControl(el, push) {
            if (!el.matches(CONTROL_SEL)) return;
            var r = el.getBoundingClientRect();
            if (r.width < 1 || r.height < 1) {
                push("ZERO", el, "visible control with size " + r1(r.width) + "x" + r1(r.height));
                return;
            }
            var vw = document.documentElement.clientWidth;
            var vh = document.documentElement.clientHeight;
            if (r.right < 0 || r.bottom < 0 || r.left > vw || r.top > vh) {
                var inScroll = false;
                for (var p = el.parentElement; p; p = p.parentElement) {
                    var pcs = getComputedStyle(p);
                    if (scrollsX(pcs) || scrollsY(pcs)) {
                        inScroll = true;
                        break;
                    }
                }
                if (!inScroll) push("OFFSCREEN", el, "control at " + boxText(box(el)) + " outside viewport " + vw + "x" + vh);
            }
        }

        function auditEscape(el, push) {
            var parent = el.parentElement;
            if (!parent || parent === document.body) return;
            var cs = getComputedStyle(el);
            if (cs.position === "absolute" || cs.position === "fixed") return;
            var pcs = getComputedStyle(parent);
            if (!clipsX(pcs) || scrollsX(pcs) || scrollsY(pcs)) return;
            var r = el.getBoundingClientRect();
            var pr = parent.getBoundingClientRect();
            var over = Math.max(r.right - pr.right, pr.left - r.left);
            if (over > 2 && r.width > 0) push("ESCAPE", el, "sticks out " + r1(over) + "px past clipping parent " + label(parent) + ", hidden from view");
        }

        function auditVars(push) {
            var root = getComputedStyle(document.documentElement);
            var seen = {};
            var sheets = Array.prototype.slice.call(document.styleSheets);
            sheets.forEach(function(sh) {
                var rules;
                try {
                    rules = sh.cssRules;
                } catch (e) {
                    return;
                }
                Array.prototype.forEach.call(rules || [], function(rule) {
                    var text = rule.cssText || "";
                    var re = /var\(\s*(--[\w-]+)\s*\)/g;
                    var m;
                    while ((m = re.exec(text))) {
                        var name = m[1];
                        if (seen[name]) continue;
                        seen[name] = true;
                        if (root.getPropertyValue(name).trim() !== "") continue;
                        if (text.indexOf(name + ":") >= 0) continue;
                        if (defined(name)) continue;
                        push("UNDEF-VAR", null, name + " used without fallback and not defined on :root (" + (rule.selectorText || "rule").slice(0, 60) + ")");
                    }
                });
            });
        }

        function defined(name) {
            var sheets = Array.prototype.slice.call(document.styleSheets);
            for (var i = 0; i < sheets.length; i++) {
                var rules;
                try {
                    rules = sheets[i].cssRules;
                } catch (e) {
                    continue;
                }
                for (var j = 0; j < (rules || []).length; j++) {
                    if ((rules[j].cssText || "").indexOf(name + ":") >= 0) return true;
                }
            }
            return false;
        }

        function fontVars() {
            var root = getComputedStyle(document.documentElement);
            var names = {
                "--font": true,
                "--font-mono": true
            };
            Array.prototype.forEach.call(document.styleSheets, function(sh) {
                var rules;
                try {
                    rules = sh.cssRules;
                } catch (e) {
                    return;
                }
                Array.prototype.forEach.call(rules || [], function(rule) {
                    var m = (rule.cssText || "").match(/--font[\w-]*(?=\s*:)/g);
                    (m || []).forEach(function(n) {
                        names[n] = true;
                    });
                });
            });
            for (var i = 0; i < document.documentElement.style.length; i++) {
                var n = document.documentElement.style[i];
                if (n.indexOf("--font") === 0) names[n] = true;
            }
            var out = {};
            Object.keys(names).forEach(function(n) {
                var v = root.getPropertyValue(n).trim();
                if (v) out[n] = v;
            });
            return out;
        }

        function normFamily(v) {
            return String(v).split(",").map(function(f) {
                return f.trim().replace(/^["']|["']$/g, "").toLowerCase();
            }).join(",");
        }

        function auditFonts(root, push) {
            var vars = fontVars();
            var want = {};
            Object.keys(vars).forEach(function(n) {
                want[normFamily(vars[n])] = n;
            });
            if (!Object.keys(want).length) return;
            var expected = Object.keys(vars).map(function(n) {
                return n + "=" + vars[n];
            }).join("  ");
            var sel = "button, input, textarea, select, [contenteditable=true], [role=button]";
            var all = [root].concat(Array.prototype.slice.call(root.querySelectorAll("*")));
            var els = all.filter(function(el) {
                if (!el.matches || el.closest("svg")) return false;
                if (el.matches(sel)) return true;
                return Array.prototype.some.call(el.childNodes, function(n) {
                    return n.nodeType === 3 && n.nodeValue.trim() !== "";
                });
            });
            els.forEach(function(el) {
                if (!shown(el) || parked(el)) return;
                var t = (el.type || "").toLowerCase();
                if (t === "hidden" || t === "checkbox" || t === "radio" || t === "range") return;
                var fam = getComputedStyle(el).fontFamily;
                if (want[normFamily(fam)]) return;
                push("FONT", el, "<" + el.tagName.toLowerCase() + " class=\"" + (el.getAttribute("class") || "") + "\"> uses font-family " + fam + ", expected one of " + expected);
            });
        }

        function fonts(sel) {
            var out = [];
            auditFonts(list(sel || "body")[0] || document.body, function(kind, el, msg) {
                out.push(path(el) + "\n    " + msg);
            });
            return "fonts: " + out.length + " element(s) off theme font\n" + out.join("\n");
        }
    // END Audit //

    // Frames //
        function frames(sel, trigger, opts) {
            opts = opts || {};
            var el = list(sel)[0];
            if (!el) {
                probe.last = "probe: no match for " + sel;
                return Promise.resolve(probe.last);
            }
            var props = opts.props || ["height", "width", "opacity", "transform", "max-height"];
            var ms = opts.ms || 500;
            var target = opts.watch ? function() {
                return list(opts.watch)[0] || el;
            } : function() {
                return el;
            };
            var samples = [];
            var t0 = performance.now();
            function sample() {
                var w = target();
                var cs = getComputedStyle(w);
                var row = {
                    t: Math.round(performance.now() - t0),
                    h: r1(w.getBoundingClientRect().height),
                    w: r1(w.getBoundingClientRect().width)
                };
                props.forEach(function(p) {
                    if (p !== "height" && p !== "width") row[p] = cs.getPropertyValue(p);
                });
                samples.push(row);
            }
            sample();
            if (typeof trigger === "function") trigger(el);
            else if (trigger === "click") el.click();
            else if (typeof trigger === "string") el.classList.toggle(trigger);
            return new Promise(function(resolve) {
                function tick() {
                    sample();
                    if (performance.now() - t0 < ms) setTimeout(tick, 16);
                    else resolve(probe.last = framesReport(sel, samples, props));
                }
                setTimeout(tick, 16);
            });
        }

        function framesReport(sel, samples, props) {
            var first = samples[0];
            var last = samples[samples.length - 1];
            var keys = ["h", "w"].concat(props.filter(function(p) {
                return p !== "height" && p !== "width";
            }));
            var verdict = [];
            keys.forEach(function(k) {
                if (String(first[k]) === String(last[k])) return;
                var mids = {};
                samples.forEach(function(s) {
                    mids[String(s[k])] = true;
                });
                var steps = Object.keys(mids).length;
                verdict.push(k + ": " + first[k] + " -> " + last[k] + (steps > 2 ? "  ANIMATED (" + steps + " distinct values)" : "  JUMPED (no in-between frames)"));
            });
            if (!verdict.length) verdict.push("no watched property changed");
            if (document.hidden) verdict.push("WARNING page hidden, animation timeline is frozen so transitions cannot be measured");
            var rows = samples.filter(function(s, i) {
                return i === 0 || i === samples.length - 1 || i % 4 === 0;
            }).map(function(s) {
                return "  t=" + s.t + " " + keys.map(function(k) {
                    return k + "=" + s[k];
                }).join(" ");
            });
            return ["frames: " + (typeof sel === "string" ? sel : label(sel)) + "  " + samples.length + " samples"].concat(verdict, rows).join("\n");
        }

        function scrub(sel, steps) {
            var el = list(sel)[0];
            if (!el) return "probe: no match for " + sel;
            var anims = el.getAnimations ? el.getAnimations({ subtree: true }) : [];
            if (!anims.length) return "scrub: " + label(el) + " has no running animations or transitions";
            steps = steps || 6;
            var out = ["scrub: " + label(el) + "  " + anims.length + " animation(s)"];
            anims.forEach(function(a) {
                var t = a.effect.getComputedTiming();
                var total = t.endTime || 0;
                var node = a.effect.target;
                var name = a.transitionProperty || a.animationName || "keyframes";
                var row = [];
                a.pause();
                for (var i = 0; i <= steps; i++) {
                    a.currentTime = total * i / steps;
                    var r = node.getBoundingClientRect();
                    row.push(Math.round(100 * i / steps) + "%:" + r1(r.left) + "x," + r1(r.top) + "y " + r1(r.width) + "w " + r1(r.height) + "h/" + getComputedStyle(node).opacity);
                }
                a.play();
                out.push("  " + label(node) + " " + name + " " + total + "ms  " + row.join("  "));
            });
            return out.join("\n");
        }
    // END Frames //

    // Bridge Log //
        var bridgeLog = [];

        function tapBridge() {
            if (tapBridge.done || typeof window.shellDispatch !== "function") return;
            tapBridge.done = true;
            var orig = window.shellDispatch;
            window.shellDispatch = function(panel, action, body) {
                bridgeLog.push({
                    t: Math.round(performance.now()),
                    dir: "out",
                    panel: panel,
                    action: action,
                    body: body
                });
                if (bridgeLog.length > 400) bridgeLog.shift();
                return orig.apply(this, arguments);
            };
            var recv = window.shellReceive;
            if (typeof recv === "function") {
                window.shellReceive = function(panel, action, body) {
                    bridgeLog.push({
                        t: Math.round(performance.now()),
                        dir: "in",
                        panel: panel,
                        action: action,
                        body: body
                    });
                    if (bridgeLog.length > 400) bridgeLog.shift();
                    return recv.apply(this, arguments);
                };
            }
        }

        function bridge(n) {
            tapBridge();
            return bridgeLog.slice(-(n || 30)).map(function(m) {
                var b = m.body === undefined ? "" : JSON.stringify(m.body);
                return m.t + " " + (m.dir === "out" ? "js->lua " : "lua->js ") + m.panel + "." + m.action + " " + (b.length > 160 ? b.slice(0, 160) + "..." : b);
            }).join("\n") || "bridge: no traffic since tap";
        }
    // END Bridge Log //

    // Errors //
        var errors = [];

        window.addEventListener("error", function(e) {
            errors.push((e.filename || "").split("/").pop() + ":" + e.lineno + " " + e.message);
        });

        window.addEventListener("unhandledrejection", function(e) {
            errors.push("rejection " + (e.reason && (e.reason.message || e.reason)));
        });
    // END Errors //

    // Export //
        var probe = {
            inspect: inspect,
            tree: tree,
            audit: audit,
            frames: frames,
            scrub: scrub,
            fonts: fonts,
            bridge: bridge,
            errors: function() {
                return errors.length ? errors.join("\n") : "errors: none";
            },
            last: ""
        };

        window.msProbe = probe;

        document.addEventListener("DOMContentLoaded", tapBridge);
    // END Export //
})();
