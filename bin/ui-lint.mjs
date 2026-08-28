#!/usr/bin/env node
/**
 * ui-lint — guards the shell UI against two recurring regressions:
 *
 *   1. Hardcoded theme values. Component modules must read colors and fonts
 *      from CSS variables (var(--accent), var(--font-mono), …), never bake in
 *      literals. A literal only looks right on the theme it was copied from —
 *      e.g. rgba(196,26,26,…) is the OLD default red accent and renders wrong
 *      on every custom theme. Fonts likewise: "SF Mono", "Menlo", … ignore
 *      the user's --font-mono.
 *
 *   2. Native macOS controls. A native <select>, confirm()/alert()/prompt(),
 *      an OS-chrome input (type=date/time/color/file), or a contextmenu
 *      suppressor that exempts text fields (re-opening the OS-drawn native
 *      menu) is drawn by macOS in its own style and ignores the theme — and a
 *      native modal can sit behind the always-on-top shell and softlock. Use
 *      createSelect(), the shell's own modal, and the `allow-native-menu`
 *      opt-in class instead.
 *
 * Scope:
 *   - color/font literal rules apply to ui/modules/*.js (the consumers that
 *     must theme). The .html files DEFINE the palette, so their literals are
 *     the source of truth and are exempt.
 *   - native-control rules apply to modules and html alike.
 *
 * Escape hatch: put `ui-lint-allow` in a comment on the offending line or the
 * line directly above it to grandfather a deliberate, documented exception.
 *
 * Exit code 1 on any violation, 0 when clean. No dependencies — plain Node.
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const UI = join(ROOT, "ui");
const MAC = join(ROOT, "mac");

// ── File discovery ──────────────────────────────────────────────────────────
function walk(dir, out = []) {
    for (const name of readdirSync(dir)) {
        const p = join(dir, name);
        const s = statSync(p);
        if (s.isDirectory()) walk(p, out);
        else out.push(p);
    }
    return out;
}

const files = walk(UI).filter((f) => /\.(js|html)$/.test(f));

// The shared config (mac/) is the ONLY tree that runs on both hosts — LuaJIT on
// Windows, Lua 5.4 on Hammerspoon — so it is the only place the number-model
// split can bite (see the numfmt rule below). The hs/ shims are LuaJIT-only and
// cannot diverge, so they are deliberately out of scope here.
let luaFiles = [];
try { luaFiles = walk(MAC).filter((f) => /\.lua$/.test(f)); } catch { /* mac/ absent */ }

// Files exempt from the color/native-input rules because their whole job is to
// edit colors: a theme editor legitimately holds hex strings and an OS color
// picker (<input type="color">) is the right control for picking a color.
const COLOR_EDITOR = /ui\/modules\/panel-theme\.js$/;

// ── Rules ───────────────────────────────────────────────────────────────────
const BANNED_FONTS = /font-family\s*:\s*[^;]*|font\s*:\s*[^;{]*/i;
const FONT_LITERAL = /["']?(SF Mono|Menlo|Consolas|-apple-system|BlinkMacSystemFont|Segoe UI|Helvetica|Arial|Roboto|Times New Roman)["']?/i;

const OLD_ACCENT = /(rgba?\(\s*196\s*,\s*26\s*,\s*26|#c41a1a)/i;

// A color literal in a stylesheet context. We match hex and functional colors;
// black/white scrims and shadows are allowed (they are theme-independent).
const COLOR_LITERAL = /(#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|hsla?\([^)]*\))/g;
const NEUTRAL = /^(#(0{3,4}|0{6}|0{8})|#(f{3,4}|f{6}|f{8})|rgba?\(\s*0\s*,\s*0\s*,\s*0[^)]*\)|rgba?\(\s*255\s*,\s*255\s*,\s*255[^)]*\))$/i;
const SVG_ATTR = /(fill|stroke|stop-color)\s*=\s*["']/i; // colors inside embedded SVG markup
// var(--x, <fallback>) — the variable IS referenced; the literal is only a
// defensive fallback for a missing token, so it is not a theming violation.
const VAR_FALLBACK = /var\(\s*--[\w-]+\s*,[^)]*\)/g;

// createElement("select") is always code. The `<select` markup form and the
// dialog calls are matched only on non-comment lines, so prose that merely
// names the control (doc comments, rationale) is not a violation.
const NATIVE_SELECT_CODE = /(document\.)?createElement\(\s*["']select["']\s*\)/i;
const NATIVE_SELECT_MARKUP = /<select[\s>]/i;
const NATIVE_DIALOG = /(^|[^.\w])(window\.)?(confirm|alert|prompt)\s*\(/;
const NATIVE_INPUT = /type\s*=\s*["'](date|time|datetime-local|month|week|color|file)["']/i;

// A contextmenu suppressor that early-returns for editable elements re-opens
// the OS-drawn native menu on those fields — the menu ignores the theme (and a
// blanket `input, textarea` exemption hits EVERY field). The shell suppresses
// the native menu by default; a field that truly wants native copy/paste opts
// in with the `allow-native-menu` class, so the suppressor exempts only that.
const CONTEXTMENU_HANDLER = /addEventListener\(\s*["']contextmenu["']|\boncontextmenu\s*=/;
const EDITABLE_EXEMPT = /\.closest\(\s*["'][^)]*\b(input|textarea|contenteditable)\b/;

// A line whose meaningful content is a comment (JS // /* */, HTML <!-- -->).
function isComment(line) {
    const t = line.trim();
    return t.startsWith("//") || t.startsWith("*") || t.startsWith("/*")
        || t.startsWith("<!--") || t.startsWith("-->") || t === "*/";
}
// Theme-engine lines that DEFINE a CSS variable's value (the palette source of
// truth), e.g. root.setProperty("--accent-glow", `rgba(...)`).
const VAR_DEFINITION = /setProperty\(\s*["']--/;

const findings = [];
function report(file, lineNo, rule, text, hint) {
    findings.push({ file: relative(ROOT, file), lineNo, rule, text: text.trim().slice(0, 120), hint });
}

for (const file of files) {
    const rel = file.replace(/\\/g, "/");
    const isModule = /ui\/modules\/[^/]+\.js$/.test(rel);
    const isColorEditor = COLOR_EDITOR.test(rel);
    // Themed shell HTML (popouts, overlays) consumes theme vars, so the font
    // rule applies there too. ms_guardian.html is excluded: it is the pre-boot
    // integrity screen and renders before the theme vars are injected, so its
    // font stacks are standalone by necessity.
    const isThemedHtml = /ui\/[^/]+\.html$/.test(rel) && !/ms_guardian\.html$/.test(rel);
    const src = readFileSync(file, "utf8");
    const lines = src.split(/\r?\n/);

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        // A `ui-lint-allow` comment on the line itself or within the two lines
        // above suppresses it — two, so an allow can sit above a multi-line
        // statement (e.g. an `if (…\n && native(…))` condition).
        const allowed = /ui-lint-allow/.test(line)
            || (i > 0 && /ui-lint-allow/.test(lines[i - 1]))
            || (i > 1 && /ui-lint-allow/.test(lines[i - 2]));
        if (allowed) continue;

        // A line whose meaningful content is a comment; several rules skip these
        // so prose that merely names a color or control is not a violation.
        const comment = isComment(line);

        // Rule 1a — the old default-red accent, wrong on every current theme.
        if (OLD_ACCENT.test(line)) {
            report(file, i + 1, "old-accent-literal", line,
                "This is the retired red accent. Use var(--accent) / color-mix(in srgb, var(--accent) N%, transparent).");
        }

        // Rule 1b — hardcoded font stacks (consumers must use the var). Applies
        // to component modules and themed shell HTML alike.
        if (isModule || isThemedHtml) {
            const fontDecl = line.match(BANNED_FONTS);
            if (fontDecl && !/var\(--font/.test(fontDecl[0])
                && !/--font[\w-]*\s*:/.test(line)   // a --font var DEFINITION is fine
                && FONT_LITERAL.test(fontDecl[0])) {
                report(file, i + 1, "hardcoded-font", line,
                    "Use var(--font-mono) or var(--font) instead of a literal family stack.");
            }
        }

        // Rule 1d — a CSS custom property written with the wrong sigil. A theme
        // applier that calls setProperty("//accent", …) or ("-accent", …) sets
        // an invalid property name the browser silently drops, so the theme
        // never lands. Custom properties must begin with exactly two dashes.
        // Only a name starting with "//" or a single "-" (not "--") is flagged,
        // so legitimate setProperty("opacity", …) on a real property is untouched.
        const badProp = line.match(/setProperty\(\s*["'](\/\/[^"']*|-(?!-)[^"']*)["']/);
        if (badProp) {
            report(file, i + 1, "bad-custom-prop", line,
                `setProperty("${badProp[1]}", …) — a theme variable must start with "--" (this "//"/"-" name is silently ignored).`);
        }

        // Rule 1e — the same wrong-sigil typo on the CONSUMPTION side: a CSS
        // string that reads var(//x) or var(-x) (single dash) instead of
        // var(--x). The reference is invalid, so the property falls back to its
        // inherited/initial value — e.g. a placeholder color silently reverts to
        // the field's own --text and renders bright. Matched anywhere on the
        // line (these live inside JS template-literal CSS as well as .html).
        const badVar = line.match(/var\(\s*(\/\/[\w-]+|-(?!-)[\w-]+)/);
        if (badVar) {
            report(file, i + 1, "bad-var-ref", line,
                `var(${badVar[1]}…) — a theme variable reference must start with "--" (this "//"/"-" ref is invalid and silently falls back).`);
        }

        // Rule 1c — hardcoded color literals in the modules that must theme, and
        // in the shell/popout HTML component rules (the palette DEFINITIONS in
        // :root are exempted below by the `--x:` / setProperty("--x") guards, so
        // only literal colors baked into component rules are flagged).
        if (isModule || isThemedHtml) {
            // (skip the color editor, neutrals, SVG attributes, and CSS-variable
            // definitions — both `--x:` in a stylesheet and setProperty("--x", …)).
            if (!isColorEditor && !comment && !SVG_ATTR.test(line)
                && !/--[\w-]+\s*:/.test(line) && !VAR_DEFINITION.test(line)) {
                // Drop var(--x, fallback) groups first so a defensive fallback
                // literal is not mistaken for a hardcoded component color.
                const scan = line.replace(VAR_FALLBACK, "var()");
                let m;
                COLOR_LITERAL.lastIndex = 0;
                while ((m = COLOR_LITERAL.exec(scan)) !== null) {
                    const lit = m[1];
                    if (NEUTRAL.test(lit)) continue;
                    report(file, i + 1, "hardcoded-color", line,
                        `Literal ${lit} — reference a theme var (var(--accent), var(--surface2), …) or color-mix on one.`);
                    break;
                }
            }
        }

        // Rule 2 — native macOS controls (all UI files). Comment prose that
        // merely names a control is not a violation.
        if (NATIVE_SELECT_CODE.test(line) || (!comment && NATIVE_SELECT_MARKUP.test(line))) {
            report(file, i + 1, "native-select", line,
                "Native <select> is drawn by macOS and ignores the theme. Use window.createSelect().");
        }
        if (!comment && NATIVE_DIALOG.test(line)) {
            report(file, i + 1, "native-dialog", line,
                "confirm()/alert()/prompt() are native macOS dialogs (and can softlock behind the shell). Use the shell's themed modal.");
        }
        if (!isColorEditor && NATIVE_INPUT.test(line)) {
            report(file, i + 1, "native-input", line,
                "This input renders OS chrome. Build a themed control, or add `ui-lint-allow` if the OS control is intended.");
        }

        // Rule 2b — a contextmenu handler that exempts editable elements. Scoped
        // to contextmenu registrations (the exempt line usually sits 1-3 lines
        // below), so keydown handlers that legitimately skip typing in a field
        // are not touched. The sanctioned exemption targets `.allow-native-menu`.
        if (!comment && CONTEXTMENU_HANDLER.test(line)) {
            for (let j = i + 1; j <= i + 4 && j < lines.length; j++) {
                const look = lines[j];
                if (CONTEXTMENU_HANDLER.test(look)) break; // next handler; stop
                if (!EDITABLE_EXEMPT.test(look)) continue;
                const okd = /ui-lint-allow/.test(look)
                    || /ui-lint-allow/.test(lines[j - 1] || "");
                if (okd) break;
                report(file, j + 1, "native-menu-exempt", look,
                    "A contextmenu suppressor must not exempt input/textarea/contenteditable — that leaks the OS native menu. Exempt only `.allow-native-menu` (the opt-in for fields that need native copy/paste).");
                break;
            }
        }
    }
}

// ── Rule 3 — numeric-format divergence tripwire (mac/*.lua) ──────────────────
// The config runs on two number models: LuaJIT (all doubles) on Windows and Lua
// 5.4 (distinct int/float subtypes) on Hammerspoon. Under 5.4, `/` and `^` ALWAYS
// yield a float, so 1920/2 stringifies as "960.0" there but "960" on LuaJIT —
// silent, non-fatal text divergence in any label / filename / settings key. (`+`
// `-` `*` on integers stay integers on 5.4, so they are NOT flagged; `//` is
// floor-div and safe.) The safe idiom is string.format("%d", math.floor(n)).
//
// This is a TRIPWIRE, not a sweep: it fires ONLY when a bare `/` or `^` sits
// DIRECTLY inside tostring(...) or DIRECTLY adjacent to `..` — the one pattern
// that is unambiguously wrong. It cannot see a float laundered through a local
// (that is what smoke.lua's VALUE SKEW bucket is for). A line already using
// math.floor/ceil/tointeger or a %d format is treated as handled. Matches zero
// lines in the current config; annotate a deliberate float with `ui-lint-allow`.
const HANDLED = /math\.(floor|ceil|tointeger)|string\.format|%d/;
// bare division `/` (not `//`) or power `^`, between two value operands
const ARITH = "[\\w.)%\\]]\\s*[\\/^]\\s*[\\w.(]";
const TOSTRING_ARITH = new RegExp("tostring\\([^)]*" + ARITH + "[^)]*\\)");
const CONCAT_ARITH = new RegExp(
    // ..  <operand> / <operand>          OR        <operand> / <operand>  ..
    "\\.\\.[^;]*?" + ARITH + "|" + ARITH + "[^;]*?\\.\\.");

function stripLua(line) {
    // drop line comments and string bodies so a `/` in a path/URL or a comment
    // is never mistaken for arithmetic; collapse `//` so floor-div can't match.
    return line
        .replace(/--.*$/, "")
        .replace(/"(?:[^"\\]|\\.)*"/g, '""')
        .replace(/'(?:[^'\\]|\\.)*'/g, "''")
        .replace(/\/\//g, "¦");
}

for (const file of luaFiles) {
    const lines = readFileSync(file, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        if (/ui-lint-allow/.test(raw) || (i > 0 && /ui-lint-allow/.test(lines[i - 1]))) continue;
        const s = stripLua(raw);
        if (!s.includes("tostring(") && !s.includes("..")) continue;
        if (HANDLED.test(s)) continue;
        if (TOSTRING_ARITH.test(s) || CONCAT_ARITH.test(s)) {
            report(file, i + 1, "numfmt-float", raw,
                "A `/` or `^` result reaching a string renders as \"960.0\" on Lua 5.4 but \"960\" on LuaJIT. Wrap with string.format(\"%d\", math.floor(n)) — or `ui-lint-allow` if a float is intended.");
        }
    }
}

// ── Report ──────────────────────────────────────────────────────────────────
if (findings.length === 0) {
    console.log("ui-lint: clean — no hardcoded theme values or native controls found.");
    process.exit(0);
}

const byRule = {};
for (const f of findings) (byRule[f.rule] ||= []).push(f);

console.error(`ui-lint: ${findings.length} violation(s) found\n`);
for (const rule of Object.keys(byRule)) {
    console.error(`  [${rule}]`);
    for (const f of byRule[rule]) {
        console.error(`    ${f.file}:${f.lineNo}`);
        console.error(`      ${f.text}`);
        console.error(`      → ${f.hint}`);
    }
    console.error("");
}
console.error("Fix these, or annotate a deliberate exception with a `ui-lint-allow` comment on the line (or the line above).");
process.exit(1);
