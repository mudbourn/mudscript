#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, extname } from "node:path";
import { fileURLToPath } from "node:url";

// Setup //
    const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

    const BASELINE_PATH = join(ROOT, "bin", "lint-baseline.json");

    const MAX_LINES = 2000;

    const LANGS = {
        ".lua": "lua",
        ".js": "js",
        ".mjs": "js",
        ".html": "html",
        ".css": "css",
        ".sh": "sh",
        ".swift": "swift",
        ".md": "md",
    };

    const SKIP = [
        /^ignore\//,
        /^mac\/bin\/hidinject-rs\//,
        /node_modules\//,
        /^mac\/data\/ms_macros_visual\.lua$/,
    ];

    const MESSAGES = {
        "comment": "Only section markers may be comments. Delete this comment.",
        "marker-unclosed": "Section OPEN has no matching END.",
        "marker-wrong-closer": "Section marker uses another language's closer. Open and close with this file's comment characters.",
        "marker-orphan-end": "END marker has no OPEN above it.",
        "marker-label": "END label does not match its OPEN label.",
        "marker-indent": "END must sit at the same indent as its OPEN.",
        "marker-body-indent": "Section body must be indented one level deeper than its markers.",
        "marker-blank-after-open": "No blank line between an OPEN marker and its first line.",
        "marker-blank-before-end": "No blank line between a section's last line and its END.",
        "file-length": `File is over ${MAX_LINES} lines. Split it by function.`,
        "non-ascii": "Plain QWERTY characters only. Use an SVG from ui/svg for glyphs.",
        "semicolon": "No semicolons in Lua or prose.",
        "lua-inline-table": "A table with more than one field puts each field on its own line.",
        "luajit-syntax": "Lua 5.3+ operator. Hammerspoon runs LuaJIT: use bit.* or arithmetic.",
        "lua-native-dialog": "Native macOS dialogs draw behind the shell and softlock. Use ms.ui.modal.",
        "old-accent-literal": "Retired red accent. Use var(--accent) or color-mix on it.",
        "hardcoded-font": "Use var(--font-mono) or var(--font) instead of a literal font stack.",
        "hardcoded-color": "Literal color. Reference a theme var or color-mix on one.",
        "bad-custom-prop": "A theme variable name must start with --.",
        "bad-var-ref": "A var() reference must start with --.",
        "native-select": "Native select ignores the theme. Use window.createSelect().",
        "native-dialog": "confirm/alert/prompt are native dialogs. Use the shell modal.",
        "native-input": "This input type renders OS chrome. Build a themed control.",
        "native-menu-exempt": "A contextmenu suppressor may only exempt .allow-native-menu.",
        "unthemed-scrollbar": "Scroll container has no themed scrollbar.",
        "css-line-comment": "// is not a CSS comment and drops the next rule.",
        "undefined-call": "Calls a name this file never declares and no ui file makes global. Declare it, or share it on a window namespace.",
        "font-reset-missing": "Page lacks button, input, textarea, select { font: inherit } so controls fall back to the system font.",
    };
// END Setup //

// Arguments //
    const argv = process.argv.slice(2);

    const flags = new Set(argv.filter((a) => a.startsWith("--")));

    const baseIdx = argv.indexOf("--base");

    const baseRef = baseIdx >= 0 ? argv[baseIdx + 1] : null;

    const pathArgs = argv.filter((a, i) => !a.startsWith("--") && !(baseIdx >= 0 && i === baseIdx + 1));
// END Arguments //

// File Discovery //
    function git(args) {
        try {
            return execFileSync("git", args, {
                cwd: ROOT,
                encoding: "utf8",
                stdio: ["ignore", "pipe", "ignore"],
            });
        } catch {
            return null;
        }
    }

    function lintable(rel) {
        return LANGS[extname(rel)] && !SKIP.some((re) => re.test(rel)) && existsSync(join(ROOT, rel));
    }

    function allFiles() {
        const out = git(["ls-files", "-co", "--exclude-standard"]) || "";

        return [...new Set(out.split("\n").filter(Boolean))].filter(lintable).sort();
    }
// END File Discovery //

// Scanner //
    function scanLua(src, add) {
        let i = 0;

        while (i < src.length) {
            const c = src[i];

            if (c === "-" && src[i + 1] === "-") {
                const long = /^--\[(=*)\[/.exec(src.slice(i, i + 64));

                if (long) {
                    const close = "]" + long[1] + "]";

                    const end = src.indexOf(close, i);

                    const stop = end < 0 ? src.length : end + close.length;

                    add("comment", i, stop);

                    i = stop;
                    continue;
                }

                const nl = src.indexOf("\n", i);

                const stop = nl < 0 ? src.length : nl;

                add("comment", i, stop);

                i = stop;
                continue;
            }

            const longStr = c === "[" ? /^\[(=*)\[/.exec(src.slice(i, i + 64)) : null;

            if (longStr) {
                const close = "]" + longStr[1] + "]";

                const end = src.indexOf(close, i);

                const stop = end < 0 ? src.length : end + close.length;

                add("string", i + longStr[0].length, stop - close.length);

                i = stop;
                continue;
            }

            if (c === '"' || c === "'") {
                let j = i + 1;

                while (j < src.length && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1;

                add("string", i + 1, j);

                i = j + 1;
                continue;
            }

            i++;
        }
    }

    const REGEX_BEFORE = /(^|[(,=:[!&|?{};+\-*%<>~^]|\breturn|\btypeof|\bcase|\bdo|\belse|\bin|\bof)\s*$/;

    function scanJs(src, add, opts = {}) {
        let i = 0;

        const braces = [];

        const templateAt = (start) => {
            let j = start;

            let from = start;

            while (j < src.length) {
                if (src[j] === "\\") {
                    j += 2;
                    continue;
                }

                if (src[j] === "`") {
                    add("string", from, j);
                    return j + 1;
                }

                if (src[j] === "$" && src[j + 1] === "{") {
                    add("string", from, j);
                    braces.push("tpl");
                    return -(j + 2);
                }

                j++;
            }

            add("string", from, src.length);
            return src.length;
        };

        while (i < src.length) {
            const c = src[i];

            if (opts.stop && src.startsWith(opts.stop, i)) break;

            if (c === "/" && src[i + 1] === "/") {
                const nl = src.indexOf("\n", i);

                const stop = nl < 0 ? src.length : nl;

                add("comment", i, stop);

                i = stop;
                continue;
            }

            if (c === "/" && src[i + 1] === "*") {
                const end = src.indexOf("*/", i + 2);

                const stop = end < 0 ? src.length : end + 2;

                add("comment", i, stop);

                i = stop;
                continue;
            }

            if (c === '"' || c === "'" || (c === '"' && opts.swift)) {
                if (opts.swift && src.startsWith('"""', i)) {
                    const end = src.indexOf('"""', i + 3);

                    const stop = end < 0 ? src.length : end;

                    add("string", i + 3, stop);

                    i = stop + 3;
                    continue;
                }

                let j = i + 1;

                while (j < src.length && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1;

                add("string", i + 1, j);

                i = j + 1;
                continue;
            }

            if (c === "`" && !opts.swift) {
                const r = templateAt(i + 1);

                i = Math.abs(r);
                continue;
            }

            if (c === "{") {
                braces.push("{");
                i++;
                continue;
            }

            if (c === "}") {
                const top = braces.pop();

                if (top === "tpl") {
                    const r = templateAt(i + 1);

                    i = Math.abs(r);
                    continue;
                }

                i++;
                continue;
            }

            if (c === "/" && !opts.swift) {
                const lineStart = src.lastIndexOf("\n", i - 1) + 1;

                if (REGEX_BEFORE.test(src.slice(Math.max(lineStart, i - 40), i))) {
                    let j = i + 1;

                    let inClass = false;

                    while (j < src.length && src[j] !== "\n") {
                        if (src[j] === "\\") {
                            j += 2;
                            continue;
                        }

                        if (src[j] === "[") inClass = true;
                        else if (src[j] === "]") inClass = false;
                        else if (src[j] === "/" && !inClass) break;

                        j++;
                    }

                    add("string", i + 1, j);

                    i = j + 1;
                    continue;
                }
            }

            i++;
        }

        return i;
    }

    function scanCss(src, add, opts = {}) {
        let i = 0;

        while (i < src.length) {
            if (opts.stop && src.startsWith(opts.stop, i)) break;

            const c = src[i];

            if (c === "/" && src[i + 1] === "*") {
                const end = src.indexOf("*/", i + 2);

                const stop = end < 0 ? src.length : end + 2;

                add("comment", i, stop);

                i = stop;
                continue;
            }

            if (c === '"' || c === "'") {
                let j = i + 1;

                while (j < src.length && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1;

                add("string", i + 1, j);

                i = j + 1;
                continue;
            }

            i++;
        }

        return i;
    }

    function scanHtml(src, add) {
        let i = 0;

        while (i < src.length) {
            if (src.startsWith("<!--", i)) {
                const end = src.indexOf("-->", i + 4);

                const stop = end < 0 ? src.length : end + 3;

                add("comment", i, stop);

                i = stop;
                continue;
            }

            const tag = /^<(script|style)\b[^>]*>/i.exec(src.slice(i, i + 400));

            if (tag) {
                const bodyStart = i + tag[0].length;

                const closeTag = "</" + tag[1].toLowerCase();

                const lower = src.toLowerCase();

                const bodyEnd = lower.indexOf(closeTag, bodyStart);

                const stop = bodyEnd < 0 ? src.length : bodyEnd;

                const body = src.slice(bodyStart, stop);

                const shifted = (kind, a, b) => add(kind, a + bodyStart, b + bodyStart);

                if (tag[1].toLowerCase() === "script") scanJs(body, shifted);
                else scanCss(body, shifted);

                i = stop;
                continue;
            }

            i++;
        }
    }

    function scanSh(src, add) {
        let i = 0;

        let heredoc = null;

        while (i < src.length) {
            const c = src[i];

            const lineStart = i === 0 || src[i - 1] === "\n";

            if (heredoc && lineStart) {
                const nl = src.indexOf("\n", i);

                const stop = nl < 0 ? src.length : nl;

                const text = src.slice(i, stop).replace(/^\t+/, "");

                add("string", i, stop);

                if (text === heredoc) heredoc = null;

                i = stop + 1;
                continue;
            }

            if (c === "#" && (i === 0 || /\s/.test(src[i - 1]))) {
                const nl = src.indexOf("\n", i);

                const stop = nl < 0 ? src.length : nl;

                if (!(i === 0 && src[1] === "!")) add("comment", i, stop);

                i = stop;
                continue;
            }

            const hd = c === "<" ? /^<<-?\s*['"]?(\w+)['"]?/.exec(src.slice(i, i + 64)) : null;

            if (hd) {
                heredoc = hd[1];

                i += hd[0].length;
                continue;
            }

            if (c === '"' || c === "'") {
                let j = i + 1;

                while (j < src.length && src[j] !== c) j += src[j] === "\\" && c === '"' ? 2 : 1;

                add("string", i + 1, j);

                i = j + 1;
                continue;
            }

            i++;
        }
    }

    function scanMd(src, add) {
        const re = /^(```|~~~)[\s\S]*?^\1[^\n]*$|`[^`\n]*`/gm;

        let m;

        while ((m = re.exec(src)) !== null) add("string", m.index, m.index + m[0].length);
    }

    const SCANNERS = {
        lua: scanLua,
        js: scanJs,
        html: scanHtml,
        css: scanCss,
        sh: scanSh,
        swift: (src, add) => scanJs(src, add, { swift: true }),
        md: scanMd,
    };

    function scan(src, lang) {
        const mask = src.split("");

        const comments = [];

        const inside = new Uint8Array(src.length + 1);

        const add = (kind, a, b) => {
            if (b <= a) return;

            for (let k = a; k < b; k++) {
                if (src[k] !== "\n") mask[k] = " ";

                inside[k] = kind === "comment" ? 2 : 1;
            }

            if (kind === "comment") comments.push([a, b]);
        };

        SCANNERS[lang](src, add);

        const lines = src.split("\n");

        const info = [];

        let off = 0;

        for (let n = 0; n < lines.length; n++) {
            info.push({
                raw: lines[n],
                code: mask.slice(off, off + lines[n].length).join(""),
                startsInString: off > 0 && inside[off - 1] === 1 && inside[off] === 1,
                offset: off,
            });

            off += lines[n].length + 1;
        }

        const lineOf = (pos) => {
            let lo = 0;

            let hi = info.length - 1;

            while (lo < hi) {
                const mid = (lo + hi + 1) >> 1;

                if (info[mid].offset <= pos) lo = mid;
                else hi = mid - 1;
            }

            return lo;
        };

        const commentList = comments.map(([a, b]) => {
            const n = lineOf(a);

            const line = info[n];

            const text = src.slice(a, b);

            const full = !text.includes("\n")
                && line.raw.slice(0, a - line.offset).trim() === ""
                && line.raw.slice(b - line.offset).trim() === "";

            return {
                line: n,
                endLine: lineOf(b - 1),
                text,
                full,
            };
        });

        return {
            lines: info,
            comments: commentList,
        };
    }
// END Scanner //

// Findings //
    function makeReporter(rel, lines) {
        const found = [];

        const report = (rule, n, detail) => {
            found.push({
                file: rel,
                line: n + 1,
                rule,
                text: (lines[n] || "").trim().slice(0, 110),
                detail,
            });
        };

        return {
            found,
            report,
        };
    }

    function allowedBy(lines, n, rule) {
        const re = new RegExp("\\blint-allow\\s+" + rule.replace(/-/g, "\\-") + "\\b");

        return re.test(lines[n] || "") || (n > 0 && re.test(lines[n - 1]));
    }

    function legacyAllowed(lines, n) {
        return [0, 1, 2].some((d) => n - d >= 0 && /ui-lint-allow/.test(lines[n - d]));
    }
// END Findings //

// Style Rules //
    const MARKER_SHAPES = {
        lua: [/^--\s+(.+?)\s+--$/],
        js: [/^\/\/\s+(.+?)\s+\/\/$/, /^\/\*\s+(.+?)\s+\*\/$/],
        swift: [/^\/\/\s+(.+?)\s+\/\/$/],
        css: [/^\/\*\s+(.+?)\s+\*\/$/],
        html: [/^<!--\s+(.+?)\s+-->$/, /^\/\/\s+(.+?)\s+\/\/$/, /^\/\*\s+(.+?)\s+\*\/$/],
        sh: [/^#\s+(.+?)\s+#$/],
        md: [],
    };

    const DIRECTIVE = /\b(ui-)?lint-allow\b|^#!|^\/\/\/?\s*<reference/;

    function indentOf(raw) {
        const m = /^[ \t]*/.exec(raw)[0];

        return m.replace(/\t/g, "    ").length;
    }

    function markerLabel(comment, lang) {
        if (!comment.full) return null;

        for (const re of MARKER_SHAPES[lang] || []) {
            const m = re.exec(comment.text.trim());

            if (m && !/--|\/\/|\*\/|-->/.test(m[1])) return m[1];
        }

        return null;
    }

    function checkComments(ctx) {
        const { scanned, lang, report } = ctx;

        const stack = [];

        for (const c of scanned.comments) {
            const label = markerLabel(c, lang);

            if (label === null) {
                const t = c.text.trim();

                const ends = /^(--|\/\/|#|\/\*|<!--) [^\s].{0,60} (--|\/\/|#|\*\/|-->)$/.exec(t);

                const pairs = {
                    "--": "--",
                    "//": "//",
                    "#": "#",
                    "/*": "*/",
                    "<!--": "-->",
                };

                const mixed = c.full && ends && pairs[ends[1]] !== ends[2] && !/^(\/\/|#|--)\s+(--|\/\/)/.test(t);

                if (mixed) report("marker-wrong-closer", c.line);
                else if (!DIRECTIVE.test(c.text)) report("comment", c.line);

                continue;
            }

            const n = c.line;

            const indent = indentOf(scanned.lines[n].raw);

            const isEnd = /^END(\s|$)/.test(label);

            if (!isEnd) {
                stack.push({
                    n,
                    indent,
                    label,
                });

                if (n + 1 < scanned.lines.length && scanned.lines[n + 1].raw.trim() === "") {
                    report("marker-blank-after-open", n);
                }

                continue;
            }

            const open = stack.pop();

            if (!open) {
                report("marker-orphan-end", n);
                continue;
            }

            const endLabel = label.replace(/^END\s*/, "");

            if (endLabel && !open.label.startsWith(endLabel)) report("marker-label", n, `OPEN is "${open.label}"`);

            if (indent !== open.indent) report("marker-indent", n);

            if (n > 0 && scanned.lines[n - 1].raw.trim() === "") report("marker-blank-before-end", n);

            for (let k = open.n + 1; k < n; k++) {
                const l = scanned.lines[k];

                if (l.raw.trim() === "" || l.startsInString) continue;

                if (indentOf(l.raw) <= open.indent) {
                    report("marker-body-indent", k, `inside "${open.label}"`);
                    break;
                }
            }
        }

        for (const open of stack) report("marker-unclosed", open.n, open.label);
    }

    function checkText(ctx) {
        const { scanned, lang, report, lines } = ctx;

        if (lines.length > MAX_LINES) report("file-length", MAX_LINES, `${lines.length} lines`);

        lines.forEach((raw, n) => {
            if (/[^\x09\x20-\x7e]/.test(raw)) report("non-ascii", n);
        });

        if (lang === "lua") {
            scanned.lines.forEach((l, n) => {
                if (l.code.includes(";")) report("semicolon", n);
            });
        }

        if (lang === "md") {
            scanned.lines.forEach((l, n) => {
                if (/;/.test(l.code.replace(/<[^>]+>|&\w+;/g, ""))) report("semicolon", n);
            });
        }
    }

    function inlineTable(code) {
        for (let a = 0; a < code.length; a++) {
            if (code[a] !== "{") continue;

            let depth = 0;

            let commas = 0;

            for (let b = a; b < code.length; b++) {
                const ch = code[b];

                if (ch === "{" || ch === "(" || ch === "[") depth++;
                else if (ch === "}" || ch === ")" || ch === "]") {
                    depth--;

                    if (depth === 0) {
                        if (commas > 0 && code.slice(a + 1, b).trim().replace(/,$/, "").includes(",")) return true;
                        break;
                    }
                } else if (ch === "," && depth === 1) commas++;
            }
        }

        return false;
    }

    function checkLua(ctx) {
        const { scanned, report, rel } = ctx;

        const nativeOk = /ms_guardian\.lua$/.test(rel);

        scanned.lines.forEach((l, n) => {
            const code = l.code;

            if (inlineTable(code)) report("lua-inline-table", n);

            if (/\/\/|<<|>>|[&|]|~(?!=)/.test(code)) report("luajit-syntax", n);

            if (!nativeOk && /hs\.dialog\.blockAlert|hs\.alert\.show|hs\.chooser\b/.test(code)) {
                report("lua-native-dialog", n);
            }
        });
    }
// END Style Rules //

// UI Rules //
    const FONT_DECL = /font-family\s*:\s*[^;]*|font\s*:\s*[^;{]*/i;

    const FONT_LITERAL = /["']?(SF Mono|Menlo|Consolas|-apple-system|BlinkMacSystemFont|Segoe UI|Helvetica|Arial|Roboto|Times New Roman)["']?/i;

    const OLD_ACCENT = /(rgba?\(\s*196\s*,\s*26\s*,\s*26|#c41a1a)/i;

    const COLOR_LITERAL = /(#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\))/g;

    const NEUTRAL = /^(#(0{3,4}|0{6}|0{8})|#(f{3,4}|f{6}|f{8})|rgba?\(\s*0\s*,\s*0\s*,\s*0[^)]*\)|rgba?\(\s*255\s*,\s*255\s*,\s*255[^)]*\))$/i;

    const SVG_ATTR = /(fill|stroke|stop-color)\s*=\s*["']/i;

    const VAR_FALLBACK = /var\(\s*--[\w-]+\s*,[^)]*\)/g;

    const NATIVE_SELECT_CODE = /createElement\(\s*["']select["']\s*\)/i;

    const NATIVE_SELECT_MARKUP = /<select[\s>]/i;

    const NATIVE_DIALOG = /(^|[^.\w])(window\.)?(confirm|alert|prompt)\s*\(/;

    const NATIVE_INPUT = /type\s*=\s*["'](date|time|datetime-local|month|week|color|file)["']/i;

    const CONTEXTMENU_HANDLER = /addEventListener\(\s*["']contextmenu["']|\boncontextmenu\s*=/;

    const EDITABLE_EXEMPT = /\.closest\(\s*["'][^)]*\b(input|textarea|contenteditable)\b/;

    const COLOR_EDITOR = /^ui\/modules\/panel-theme\.js$/;

    function checkUi(ctx) {
        const { rel, lines, scanned, report } = ctx;

        const isModule = /^ui\/modules\/[^/]+\.js$/.test(rel);

        const isThemedHtml = /^ui\/[^/]+\.html$/.test(rel) && !/ms_guardian\.html$/.test(rel);

        const isColorEditor = COLOR_EDITOR.test(rel);

        const themed = isModule || isThemedHtml;

        lines.forEach((line, n) => {
            if (legacyAllowed(lines, n)) return;

            const comment = scanned.lines[n].code.trim() === "" && line.trim() !== "";

            if (OLD_ACCENT.test(line)) report("old-accent-literal", n);

            if (themed) {
                const decl = line.match(FONT_DECL);

                if (decl && !/var\(--font/.test(decl[0]) && !/--font[\w-]*\s*:/.test(line) && FONT_LITERAL.test(decl[0])) {
                    report("hardcoded-font", n);
                }
            }

            if (/setProperty\(\s*["'](\/\/[^"']*|-(?!-)[^"']*)["']/.test(line)) report("bad-custom-prop", n);

            if (/var\(\s*(\/\/[\w-]+|-(?!-)[\w-]+)/.test(line)) report("bad-var-ref", n);

            if (themed && !isColorEditor && !comment && !SVG_ATTR.test(line)
                && !/--[\w-]+\s*:/.test(line) && !/setProperty\(\s*["']--/.test(line)) {
                const found = [...line.replace(VAR_FALLBACK, "var()").matchAll(COLOR_LITERAL)]
                    .find((m) => !NEUTRAL.test(m[1]));

                if (found) report("hardcoded-color", n, found[1]);
            }

            if (NATIVE_SELECT_CODE.test(line) || (!comment && NATIVE_SELECT_MARKUP.test(line))) report("native-select", n);

            if (!comment && NATIVE_DIALOG.test(scanned.lines[n].code)) report("native-dialog", n);

            if (!isColorEditor && NATIVE_INPUT.test(line)) report("native-input", n);

            if (!comment && CONTEXTMENU_HANDLER.test(line)) {
                for (let j = n + 1; j <= n + 4 && j < lines.length; j++) {
                    if (CONTEXTMENU_HANDLER.test(lines[j])) break;

                    if (!EDITABLE_EXEMPT.test(lines[j])) continue;

                    if (!legacyAllowed(lines, j)) report("native-menu-exempt", j);
                    break;
                }
            }
        });
    }

    const SB_SELECTOR = /([^{}\n,]+)::-webkit-scrollbar/g;

    const OVERFLOW_SCROLL = /overflow(-[xy])?\s*:\s*(auto|scroll|overlay)/i;

    const INLINE_STYLE = /\.style\b|cssText|setProperty\(\s*["']overflow/;

    function subjectTokens(sel) {
        const base = sel.replace(/::[\w-].*$/, "").replace(/:[\w-]+(\([^)]*\))?/g, "");

        const chunks = base.trim().split(/[\s>+~]+/).filter(Boolean);

        return new Set((chunks[chunks.length - 1] || "").match(/[.#][\w-]+/g) || []);
    }

    function selectorOpener(line) {
        if (!line.includes("{")) return null;

        const head = line.slice(0, line.indexOf("{"));

        if (/[()=`]|=>|\b(function|if|for|while|return|switch|else|const|let|var)\b/.test(head)) return null;

        const t = head.trim();

        return t && /^[.#:[\w*]/.test(t) ? t : null;
    }

    function collectScrollbarRules(uiFiles) {
        const styled = [];

        for (const rel of uiFiles) {
            const src = readFileSync(join(ROOT, rel), "utf8");

            for (const m of src.matchAll(SB_SELECTOR)) {
                for (const member of m[1].split(",")) {
                    const set = subjectTokens(member);

                    if (set.size > 0) styled.push(set);
                }
            }
        }

        return styled;
    }

    function checkScrollbars(ctx, styled) {
        const { lines, report } = ctx;

        const covered = (subject) => subject.size === 0 || styled.some((s) => [...s].every((t) => subject.has(t)));

        lines.forEach((line, n) => {
            if (!OVERFLOW_SCROLL.test(line) || INLINE_STYLE.test(line)) return;

            if (ctx.scanned.lines[n].code.trim() === "" || legacyAllowed(lines, n)) return;

            let sel = null;

            let openIdx = n;

            const same = line.match(/([.#:[][^{};]*)\{/);

            if (same) sel = same[1].trim();
            else {
                for (let k = n; k >= 0 && k > n - 40; k--) {
                    if (k < n && /^\s*\}/.test(lines[k])) break;

                    const s = selectorOpener(lines[k]);

                    if (s) {
                        sel = s;
                        openIdx = k;
                        break;
                    }
                }
            }

            if (!sel) return;

            let block = "";

            for (let k = openIdx; k < lines.length && k < openIdx + 60; k++) {
                block += lines[k] + "\n";

                if (lines[k].includes("}")) break;
            }

            if (/scrollbar-(color|width)\s*:/i.test(block)) return;

            const members = sel.split(",").map((s) => s.trim()).filter(Boolean);

            if (members.length && !members.some((m) => covered(subjectTokens(m)))) report("unthemed-scrollbar", n, sel.slice(0, 40));
        });
    }

    function checkFontReset(ctx) {
        const { src, rel, report } = ctx;

        if (!/^ui\/[^/]+\.html$/.test(rel)) return;

        const covered = new Set();

        for (const m of src.matchAll(/([^{}]+)\{([^}]*)\}/g)) {
            if (!/\bfont(-family)?\s*:\s*inherit\b/.test(m[2])) continue;

            for (const sel of m[1].split(",")) {
                const tag = sel.trim().match(/^(button|input|textarea|select)$/);

                if (tag) covered.add(tag[1]);
            }
        }

        if (covered.size < 4) report("font-reset-missing", 0, ["button", "input", "textarea", "select"].filter((t) => !covered.has(t)).join(" "));
    }

    function checkCssLineComments(ctx) {
        const { src, rel, report } = ctx;

        const blocks = [];

        if (rel.endsWith(".html")) {
            for (const m of src.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)) blocks.push([m.index + m[0].indexOf(m[1]), m[1]]);
        }

        for (const m of src.matchAll(/`([^`]*)`/g)) {
            if (/[.#][\w-]+\s*\{[^}]*:[^}]*;/.test(m[1])) blocks.push([m.index + 1, m[1]]);
        }

        for (const [off, css] of blocks) {
            const clean = css.replace(/\/\*[\s\S]*?\*\//g, (c) => c.replace(/[^\n]/g, " "));

            const base = src.slice(0, off).split("\n").length - 1;

            clean.split("\n").forEach((line, i) => {
                if (/^\s*\/\/|[;{}]\s*\/\/(?!\S*:\/\/)/.test(line)) report("css-line-comment", base + i);
            });
        }
    }
// END UI Rules //

// Undefined Call Rule //
    const IDENT = "[A-Za-z_$][\\w$]*";

    const KEYWORDS = new Set([
        "if", "for", "while", "switch", "catch", "function", "return", "typeof", "new", "do",
        "else", "void", "delete", "await", "yield", "in", "of", "instanceof", "super", "import", "async",
    ]);

    const BROWSER_GLOBALS = [
        "window", "document", "navigator", "location", "history", "screen", "performance",
        "alert", "confirm", "prompt", "getComputedStyle", "matchMedia", "requestAnimationFrame",
        "cancelAnimationFrame", "requestIdleCallback", "cancelIdleCallback", "getSelection",
        "Image", "Audio", "Option", "Node", "Element", "HTMLElement", "Event", "CustomEvent",
        "KeyboardEvent", "MouseEvent", "PointerEvent", "MutationObserver", "ResizeObserver",
        "IntersectionObserver", "DOMParser", "XMLSerializer", "FileReader", "Blob", "File",
        "FormData", "Headers", "Request", "Response", "XMLHttpRequest", "localStorage",
        "sessionStorage", "CSS", "FontFace", "DOMRect", "Range", "getEventListeners",
    ];

    const JS_GLOBALS = new Set([...Object.getOwnPropertyNames(globalThis), ...BROWSER_GLOBALS]);

    function declaredNames(code) {
        const names = new Set();

        const addList = (list) => {
            for (const part of list.split(",")) {
                const m = part.replace(/=.*$/s, "").match(new RegExp("(" + IDENT + ")\\s*$"));

                if (m) names.add(m[1]);
            }
        };

        for (const m of code.matchAll(new RegExp("\\b(?:function|class)\\s*\\*?\\s*(" + IDENT + ")", "g"))) names.add(m[1]);

        for (const m of code.matchAll(new RegExp("\\b(?:var|let|const)\\s+(" + IDENT + ")", "g"))) names.add(m[1]);

        for (const m of code.matchAll(/\b(?:var|let|const)\s+[{[]([^}\]]*)[}\]]/g)) addList(m[1].replace(/[\w$]+\s*:/g, ""));

        for (const m of code.matchAll(/\b(?:function\b[^(]*|catch\s*)\(([^)]*)\)/g)) addList(m[1].replace(/[{}[\]]/g, ""));

        for (const m of code.matchAll(/\(([^()]*)\)\s*=>/g)) addList(m[1].replace(/[{}[\]]/g, ""));

        for (const m of code.matchAll(new RegExp("(" + IDENT + ")\\s*=>", "g"))) names.add(m[1]);

        for (const m of code.matchAll(new RegExp("^\\s*(?:(?:static|async|get|set)\\s+)*(" + IDENT + ")\\s*\\([^)]*\\)\\s*\\{", "gm"))) names.add(m[1]);

        for (const m of code.matchAll(new RegExp("\\bimport\\s+(" + IDENT + ")", "g"))) names.add(m[1]);

        for (const m of code.matchAll(/\bimport\s*\{([^}]*)\}/g)) addList(m[1].replace(/\w+\s+as\s+/g, ""));

        return names;
    }

    function collectGlobals(uiFiles) {
        const globals = new Set(JS_GLOBALS);

        for (const rel of uiFiles) {
            const src = readFileSync(join(ROOT, rel), "utf8");

            for (const m of src.matchAll(new RegExp("\\bwindow\\.(" + IDENT + ")\\s*=(?!=)", "g"))) globals.add(m[1]);

            const wrapped = /^\s*(?:"use strict";?\s*)?\(function\s*\(/.test(src.replace(/^(\s*\/\/.*\n)*/, ""));

            if (/\.html$/.test(rel) || !wrapped) {
                for (const name of declaredNames(src)) globals.add(name);
            }
        }

        return globals;
    }

    function checkUndefinedCalls(ctx, globals) {
        const { lines, scanned, report } = ctx;

        const code = scanned.lines.map((l) => l.code).join("\n");

        const local = declaredNames(code);

        const call = new RegExp("(^|[^.\\w$])(" + IDENT + ")\\s*\\(", "g");

        lines.forEach((_, n) => {
            const text = scanned.lines[n].code;

            for (const m of text.matchAll(call)) {
                const name = m[2];

                if (KEYWORDS.has(name) || local.has(name) || globals.has(name)) continue;

                report("undefined-call", n, name);
            }
        });
    }
// END Undefined Call Rule //

// Lint Runner //
    function lintFile(rel, styled, globals) {
        const src = readFileSync(join(ROOT, rel), "utf8");

        const lang = LANGS[extname(rel)];

        const lines = src.split("\n");

        const scanned = scan(src, lang);

        const { found, report: raw } = makeReporter(rel, lines);

        const report = (rule, n, detail) => {
            if (!allowedBy(lines, n, rule)) raw(rule, n, detail);
        };

        const ctx = {
            rel,
            src,
            lang,
            lines,
            scanned,
            report,
        };

        checkText(ctx);

        if (lang !== "md") checkComments(ctx);

        if (lang === "lua") checkLua(ctx);

        if (/^ui\/.*\.(js|html)$/.test(rel)) {
            checkUi(ctx);

            checkScrollbars(ctx, styled);

            checkCssLineComments(ctx);

            checkFontReset(ctx);
        }

        if (/^ui\/modules\/[^/]+\.js$/.test(rel)) checkUndefinedCalls(ctx, globals);

        return found;
    }

    function tally(findings) {
        const counts = {};

        for (const f of findings) {
            counts[f.file] ||= {};

            const weight = f.rule === "file-length" ? parseInt(f.detail, 10) : 1;

            counts[f.file][f.rule] = (counts[f.file][f.rule] || 0) + weight;
        }

        return counts;
    }

    function readBaseline(text) {
        try {
            return JSON.parse(text);
        } catch {
            return {};
        }
    }

    function totals(counts) {
        const out = {};

        for (const rules of Object.values(counts)) {
            for (const [rule, n] of Object.entries(rules)) out[rule] = (out[rule] || 0) + n;
        }

        return out;
    }

    function changedLines(rel) {
        const tracked = git(["ls-files", "--error-unmatch", rel]);

        if (tracked === null) return null;

        const diff = git(["diff", "-U0", "HEAD", "--", rel]) || "";

        const set = new Set();

        for (const m of diff.matchAll(/^@@ -\S+ \+(\d+)(?:,(\d+))? @@/gm)) {
            const start = Number(m[1]);

            const len = m[2] === undefined ? 1 : Number(m[2]);

            for (let k = start - 3; k < start + len + 3; k++) set.add(k);
        }

        return set;
    }

    function print(list, heading) {
        if (!list.length) return;

        console.error(heading);

        for (const f of list) {

            const extra = f.detail ? ` (${f.detail})` : "";

            console.error(`  ${f.file}:${f.line}  ${f.rule}  ${MESSAGES[f.rule]}${extra}`);

            if (f.text) console.error(`      ${f.text}`);
        }

        console.error("");
    }

    function main() {
        const everything = allFiles();

        const uiFiles = everything.filter((f) => /^ui\/.*\.(js|html)$/.test(f));

        const styled = collectScrollbarRules(uiFiles);

        const globals = collectGlobals(uiFiles);

        const targets = pathArgs.length
            ? pathArgs.map((p) => p.replace(/^\.\//, "").replace(ROOT + "/", "")).filter(lintable)
            : everything;

        const findings = targets.flatMap((rel) => lintFile(rel, styled, globals));

        const counts = tally(findings);

        if (flags.has("--update-baseline")) {
            const previous = existsSync(BASELINE_PATH) ? totals(readBaseline(readFileSync(BASELINE_PATH, "utf8"))) : null;

            const next = totals(counts);

            const grown = previous ? Object.keys(next).filter((r) => next[r] > (previous[r] || 0)) : [];

            if (grown.length && !flags.has("--allow-increase")) {
                console.error("lint: refusing to raise the baseline. These rule totals grew:");

                for (const r of grown) console.error(`  ${r}  ${previous[r] || 0} -> ${next[r]}`);

                console.error("Fix the new violations. Moving code between files keeps totals equal and is allowed.");
                return 1;
            }

            const sorted = Object.fromEntries(Object.keys(counts).sort().map((file) => [
                file,
                Object.fromEntries(Object.keys(counts[file]).sort().map((r) => [r, counts[file][r]])),
            ]));

            writeFileSync(BASELINE_PATH, JSON.stringify(sorted, null, 2) + "\n");

            console.log(`lint: baseline written, ${findings.length} known violation(s) across ${Object.keys(sorted).length} file(s).`);
            return 0;
        }

        if (flags.has("--all")) {
            if (!findings.length) console.log("lint: clean, no violations.");

            print(findings, `lint: ${findings.length} violation(s), baseline ignored`);
            return findings.length ? 1 : 0;
        }

        const baseline = existsSync(BASELINE_PATH) ? readBaseline(readFileSync(BASELINE_PATH, "utf8")) : {};

        let failed = false;

        const over = [];

        const stale = [];

        for (const rel of targets) {
            const have = counts[rel] || {};

            const allowed = baseline[rel] || {};

            const rules = new Set([...Object.keys(have), ...Object.keys(allowed)]);

            for (const rule of rules) {
                const now = have[rule] || 0;

                const was = allowed[rule] || 0;

                if (now > was) over.push([rel, rule, now, was]);
                else if (now < was) stale.push([rel, rule, now, was]);
            }
        }

        for (const [rel, rule, now, was] of over) {
            failed = true;

            const hits = findings.filter((f) => f.file === rel && f.rule === rule);

            const touched = changedLines(rel);

            const near = touched ? hits.filter((f) => touched.has(f.line)) : hits;

            const shown = near.length ? near : hits;

            const where = near.length && touched ? "on or near changed lines" : "in file";

            print(shown, `${rel}  ${rule}  ${now} found, baseline allows ${was}. Showing ${shown.length} ${where}:`);
        }

        if (!pathArgs.length && stale.length) {
            failed = true;

            console.error("lint: violations were fixed but the baseline still allows them. Tighten it:");

            for (const [rel, rule, now, was] of stale) console.error(`  ${rel}  ${rule}  ${was} -> ${now}`);

            console.error("  run: node bin/lint.mjs --update-baseline\n");
        }

        if (baseRef) {
            const text = git(["show", `${baseRef}:bin/lint-baseline.json`]);

            const before = totals(readBaseline(text || "{}"));

            const after = totals(baseline);

            for (const rule of text ? Object.keys(after) : []) {
                if ((after[rule] || 0) > (before[rule] || 0)) {
                    failed = true;

                    console.error(`lint: baseline total for ${rule} grew ${before[rule] || 0} -> ${after[rule]} vs ${baseRef}. Fix the new violations instead of baselining them.`);
                }
            }
        }

        const debt = findings.length;

        if (!failed) {
            console.log(`lint: clean against baseline (${debt} known violation(s) remain as debt).`);
            return 0;
        }

        console.error(`lint: failed. Fix the listed lines, or mark a deliberate exception with a "lint-allow <rule>" comment on or above the line.`);
        return 1;
    }

    process.exit(main());
// END Lint Runner //
