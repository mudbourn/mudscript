#!/usr/bin/env node
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Setup //
    const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

    const SVG_DIR = join(ROOT, "ui", "svg");

    export const OUT_PATH = join(ROOT, "ui", "modules", "icons.js");

    const PAINT = ["fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin"];
// END Setup //

// Build //
    function inner(src) {
        const open = src.match(/<svg\b([^>]*)>/);

        const body = src
            .slice(open.index + open[0].length, src.lastIndexOf("</svg>"))
            .replace(/<!--[\s\S]*?-->/g, "")
            .replace(/<title>[\s\S]*?<\/title>/g, "")
            .replace(/\s*\n\s*/g, " ")
            .trim();

        const attrs = {};

        for (const m of open[1].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[m[1]] = m[2];

        if (!attrs.fill && !attrs.stroke) attrs.fill = "currentColor";

        const paint = PAINT.filter((k) => attrs[k] && !(k === "fill" && attrs[k] === "none"))
            .map((k) => `${k}="${attrs[k]}"`);

        const box = (attrs.viewBox || "0 0 24 24").split(/\s+/).map(Number);

        const scale = box[2] && box[2] !== 24 ? 24 / box[2] : 1;

        const g = [];

        if (scale !== 1) g.push(`transform="scale(${scale.toFixed(4)})"`);

        g.push(...paint);

        return g.length ? `<g ${g.join(" ")}>${body}</g>` : body;
    }

    export function build() {
        const names = readdirSync(SVG_DIR).filter((f) => f.endsWith(".svg")).sort();

        const entries = names.map((f) => {
            const name = f.slice(0, -4);

            const key = /^[a-z_$][\w$]*$/i.test(name) ? name : JSON.stringify(name);

            const svg = inner(readFileSync(join(SVG_DIR, f), "utf8")).replace(/'/g, "\\'");

            return `        ${key}: '${svg}',`;
        });

        return [
            "(function() {",
            "    \"use strict\";",
            "",
            "// Icon map //",
            "    const ICONS = {",
            ...entries,
            "    };",
            "",
            "    function icon(name, cls) {",
            "        return '<svg class=\"' + (cls || 'icon') + '\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">' + (ICONS[name] || '') + '</svg>';",
            "    }",
            "",
            "    function iconNode(name, cls) {",
            "        const t = document.createElement('template');",
            "        t.innerHTML = icon(name, cls);",
            "        return t.content.firstChild;",
            "    }",
            "",
            "    if (!document.getElementById('icons-css')) {",
            "        const s = document.createElement('style');",
            "        s.id = 'icons-css';",
            "        s.textContent = '.icon-inline { width: 1em; height: 1em; vertical-align: -0.125em; flex-shrink: 0; }';",
            "        (document.head || document.documentElement).appendChild(s);",
            "    }",
            "",
            "    window.icon = icon;",
            "    window.iconNode = iconNode;",
            "    window.ICONS = ICONS;",
            "// END Icon map //",
            "})();",
            "",
        ].join("\n");
    }
// END Build //

// Run //
    if (process.argv[1] === fileURLToPath(import.meta.url)) {
        writeFileSync(OUT_PATH, build());

        console.log("gen-icons: wrote ui/modules/icons.js");
    }
// END Run //
