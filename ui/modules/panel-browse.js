(function() {
    "use strict";

    // State //
    let S = {
        entries:    null,
        loading:    false,
        error:      null,
        query:      "",
        type:       "all",
        loadedOnce: false,
    };

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    function send(action, body) {
        if (!window.shellPost) return;
        window.shellPost("browse", action, Object.assign({ action }, body || {}));
    }

    const TYPES = [
        { value: "all",     label: "All" },
        { value: "profile", label: "Profiles" },
        { value: "plugin",  label: "Plugins" },
        { value: "theme",   label: "Themes" },
        { value: "sound",   label: "Sounds" },
        { value: "macro",   label: "Macros" },
    ];


    // Data //
    function requestCatalog(opts) {
        S.loading = true;
        S.error   = null;
        render();
        send("browseList", Object.assign({ query: S.query, type: S.type }, opts || {}));
    }

    function refreshOnOpen() {
        if (S.loading) return;
        S.loadedOnce = true;
        requestCatalog({ force: true });
    }

    // Filtering //
    function visible() {
        const all = expandForBrowse(S.entries);
        const q = S.query.trim().toLowerCase();
        return all.filter((e) => {
            if (S.type !== "all" && e.type !== S.type) return false;
            if (!q) return true;
            return (e.name || "").toLowerCase().includes(q)
                || (e.author || "").toLowerCase().includes(q)
                || (e.description || "").toLowerCase().includes(q);
        });
    }

    function expandForBrowse(list) {
        const out = [];
        for (const e of (Array.isArray(list) ? list : [])) {
            out.push(e);
            const c = (e.type === "profile" && e.components
                && typeof e.components === "object") ? e.components : null;
            if (!c) continue;
            const baseName = (e.name || e.id).replace(/\s+profile$/i, "");
            for (const k of ["theme", "sound", "macro"]) {
                if (!c[k]) continue;
                out.push({
                    id: e.id + "::" + k,
                    installId: e.id,
                    component: k,
                    virtual: true,
                    type: k,
                    name: baseName,
                    version: e.version,
                    author: e.author,
                    website: e.website,
                    url: e.url,
                    sha256: e.sha256,
                    trust: e.trust,
                    installed:        e.installed,
                    installedVersion: e.installedVersion,
                    themeBonus: (k === "theme") && !!c.sound
                        && !(c.theme && c.theme.includesSounds),
                });
            }
        }
        return out;
    }

    function githubPageFor(url) {
        if (typeof url !== "string") return null;
        let m = url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)\/releases\/download\/([^/]+)\//);
        if (m) return "https://github.com/" + m[1] + "/" + m[2] + "/releases/tag/" + m[3];
        m = url.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+)/);
        if (m) return "https://github.com/" + m[1] + "/" + m[2];
        return null;
    }

    // Card //
    function packageCard(e) {
        const { h, actionBtn } = ui();
        const card = h("div", {
            cls: "browse-card",
            onmouseenter: () => playSlot("hover"),
        });

        const typeLabel = String((TYPES.find((x) => x.value === e.type) || {}).label
            || e.type).replace(/s$/, ""); // "Themes" -> "Theme"
        const baseName = (e.name || e.id)
            .replace(/\s*[,–-]\s*(Theme|Sound|Macro|Profile|Plugin)\s*$/i, "")
            .replace(/\s+(profile|theme|sound|macro|plugin)$/i, "")
            .trim() || (e.name || e.id);
        const displayName = baseName;

        const name = h("div", { cls: "browse-name" }, displayName);

        const bits = [];
        bits.push(typeLabel);
        if (e.version) bits.push("v" + e.version);
        if (e.author)  bits.push("by " + e.author);

        const id = h("div", { cls: "browse-card-id" },
            name,
            h("div", { cls: "browse-meta", title: bits.join("  ·  ") },
                bits.join("  ·  ")),
        );
        card.appendChild(h("div", { cls: "browse-card-top" }, id));

        if (e.description) {
            card.appendChild(h("div", { cls: "browse-desc" }, e.description));
        }

        const isVirtual = !!e.virtual;
        let includeThemeSounds = false;
        const isUpdate = !!e.installed;
        const installLabel = isUpdate ? "Update" : "Install";

        const actions = h("div", { cls: "browse-actions" });
        actions.appendChild(actionBtn(installLabel, "accent", () => {
            if (isVirtual) {
                send("browseInstall", {
                    id: e.installId,
                    component: e.component,
                    includeSounds: (e.component === "theme") ? includeThemeSounds : false,
                    label: e.name || e.id,
                });
            } else {
                send("browseInstall", { id: e.id, label: e.name || e.id });
            }
        }));
        if (e.website) {
            actions.appendChild(actionBtn("Website", "", () =>
                send("openURL", { url: e.website })));
        }
        const ghHref = githubPageFor(e.url);
        if (ghHref) {
            actions.appendChild(actionBtn("GitHub", "", () =>
                send("openURL", { url: ghHref })));
        }
        card.appendChild(actions);

        if (isVirtual && e.component === "theme" && e.themeBonus) {
            const bonus = h("label", { cls: "browse-bonus" });
            const cb = h("input", { type: "checkbox" });
            cb.addEventListener("change", () => { includeThemeSounds = cb.checked; });
            bonus.appendChild(cb);
            bonus.appendChild(h("span", {}, "Include sounds"));
            card.appendChild(bonus);
        }

        return card;
    }

    // Toolbar //
    function toolbar() {
        const { h, seg, actionBtn } = ui();
        const bar = h("div", { cls: "browse-toolbar" });

        const search = h("input", {
            cls: "browse-search",
            type: "text",
            placeholder: "Search the library...",
            value: S.query,
            oninput: (ev) => { S.query = ev.target.value; renderResults(); },
        });
        bar.appendChild(search);

        bar.appendChild(seg(TYPES, S.type, (v) => { S.type = v; renderResults(); }));

        bar.appendChild(actionBtn("Refresh", "", () => {
            playSlot("interact");
            requestCatalog({ force: true });
        }));

        return bar;
    }

    // Results region //
    function results() {
        const { h, groupLabel } = ui();
        const wrap = h("div", { cls: "browse-results" });

        if (S.loading && S.entries === null) {
            wrap.appendChild(h("div", { cls: "browse-empty" }, "Loading the library..."));
            return wrap;
        }
        if (S.error) {
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, "Could not load the library."),
                h("div", { cls: "browse-empty-sub" }, S.error),
            ));
            return wrap;
        }

        const list = visible();
        if (list.length === 0) {
            const catalogEmpty = !Array.isArray(S.entries) || S.entries.length === 0;
            wrap.appendChild(h("div", { cls: "browse-empty" },
                h("div", {}, catalogEmpty
                    ? "The library has no packages yet."
                    : "No packages match your search."),
                h("div", { cls: "browse-empty-sub" }, catalogEmpty
                    ? "New profiles, plugins, themes, sounds and macros show up "
                    + "here once they are published to the validated library."
                    : "Try a different search or type filter."),
            ));
            return wrap;
        }

        if (S.type === "all") {
            for (const t of TYPES) {
                if (t.value === "all") continue;
                const group = list.filter((e) => e.type === t.value);
                if (group.length === 0) continue;
                wrap.appendChild(groupLabel(t.label));
                for (const e of group) wrap.appendChild(packageCard(e));
            }
        } else {
            for (const e of list) wrap.appendChild(packageCard(e));
        }
        return wrap;
    }

    // Style //
    function ensureStyle() {
        if (document.getElementById("browse-style")) return;
        const css = `
        /* Fill the stage so the results box below can own a bounded height and
           actually scroll. Without min-height:0 a flex child refuses to shrink
           and the overflow never engages. */
        #browse-root { display:flex; flex-direction:column; gap:0;
            height:100%; min-height:0; }
        /* Give the scroll its own thin bar. Unstyled, each webview engine falls
           back to its OWN default: WKWebView (mac) draws a thin overlay bar, but
           WebView2/Chromium (Windows) draws the fat classic bar -- same CSS, two
           engines. scrollbar-width covers WKWebView + Chromium>=121; the
           ::-webkit-scrollbar rules cover every WebView2 build. Matches #scroll. */
        #browse-results-box { flex:1 1 auto; min-height:0; overflow-y:auto;
            scrollbar-width:thin; scrollbar-color:var(--surface2) transparent; }
        #browse-results-box::-webkit-scrollbar { width:4px; }
        #browse-results-box::-webkit-scrollbar-track { background:transparent; }
        #browse-results-box::-webkit-scrollbar-thumb { background:var(--surface2); border-radius:2px; }
        .browse-toolbar { display:flex; gap:8px; align-items:center;
            padding:10px 14px; flex:0 0 auto;
            background:var(--bg); border-bottom:1px solid var(--border-dim); }
        .browse-search { flex:1 1 auto; min-width:0; padding:6px 10px;
            border:1px solid var(--border); border-radius:var(--radius-s);
            background:var(--surface); color:var(--text);
            font-family:inherit; font-size:13px; outline:none; }
        .browse-search:focus { border-color:var(--accent); }
        .browse-search::placeholder { color:var(--text3); opacity:1; }
        .browse-results { display:flex; flex-direction:column; gap:8px;
            padding:12px 14px; }
        .browse-card { border:1px solid var(--border-dim);
            border-radius:var(--radius); background:var(--surface);
            padding:10px 12px; display:flex; flex-direction:column; gap:8px; }
        .browse-card-top { display:flex; justify-content:space-between;
            align-items:flex-start; gap:8px; }
        .browse-name { font-weight:600; color:var(--text);
            display:flex; align-items:center; gap:8px; flex-wrap:wrap; }
        .browse-meta { color:var(--text3); font-size:11px; margin-top:3px; }
        .browse-desc { color:var(--text2); font-size:12px; line-height:1.45; }
        .browse-actions { display:flex; gap:8px; }
        .browse-bonus { display:flex; align-items:center; gap:6px;
            color:var(--text2); font-size:11px; cursor:pointer; user-select:none; }
        /* Custom checkbox, the native macOS control ignores our theme, so we
           strip its appearance and draw a themed box + check ourselves. */
        .browse-bonus input[type="checkbox"] { -webkit-appearance:none;
            appearance:none; margin:0; width:14px; height:14px; flex:0 0 14px;
            border:1px solid var(--border); border-radius:3px;
            background:var(--surface); cursor:pointer; position:relative;
            transition:background 0.12s, border-color 0.12s; }
        .browse-bonus input[type="checkbox"]:hover { border-color:var(--accent); }
        /* The global input:focus-visible rule strips the outline, so a keyboard
           tab to this checkbox showed nothing, restore a themed focus ring. */
        .browse-bonus input[type="checkbox"]:focus-visible { box-shadow:0 0 0 2px var(--accent-hi); }
        .browse-bonus input[type="checkbox"]:checked { background:var(--accent);
            border-color:var(--accent); }
        .browse-bonus input[type="checkbox"]:checked::after { content:"";
            position:absolute; left:4px; top:1px; width:4px; height:8px;
            border:solid var(--bg); border-width:0 2px 2px 0;
            transform:rotate(45deg); }
        .browse-empty { padding:40px 16px; text-align:center;
            color:var(--text2); }
        .browse-empty-sub { margin-top:8px; color:var(--text3);
            font-size:12px; line-height:1.5; max-width:34ch;
            margin-left:auto; margin-right:auto; }
        `;
        const el = document.createElement("style");
        el.id = "browse-style";
        el.textContent = css;
        document.head.appendChild(el);
    }

    // Render //
    function render() {
        if (!ui()) return;
        const root = document.getElementById("browse-root");
        if (!root) return;
        ensureStyle();
        root.innerHTML = "";
        root.appendChild(toolbar());
        const box = document.createElement("div");
        box.id = "browse-results-box";
        box.appendChild(results());
        root.appendChild(box);
    }

    function renderResults() {
        if (!ui()) return;
        const box = document.getElementById("browse-results-box");
        if (!box) { render(); return; }
        box.innerHTML = "";
        box.appendChild(results());
    }

    // Bridge //
    if (window.registerPanel) {
        window.registerPanel("browse", function(action, body) {
            if (action === "catalog") {
                S.entries = Array.isArray(body && body.entries) ? body.entries : [];
                S.loading = false;
                S.error   = (body && body.error) || null;
                render();
            } else if (action === "error") {
                S.loading = false;
                S.error   = (body && body.message) || "Unknown error.";
                render();
            }
        });
    }

    const railBtn = document.querySelector('.rail-item[data-panel="browse"]');
    if (railBtn) railBtn.addEventListener("click", refreshOnOpen);

    window.renderBrowsePanel = render;

    })();
