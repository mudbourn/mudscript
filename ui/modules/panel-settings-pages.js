(function() {
    "use strict";
            const P = window.msSettings;
            const { S, showCtxMenu, sendToHost, playSlot, showAlert, openModal, h, toggle, seg, section, row, btnRow, actionBtn, divider, groupLabel } = P;
            const buildSlider = (...args) => P.buildSlider(...args);

        // Profiles, Developer and Help //
            function buildProfiles(root) {
                const current = S.currentProfile || "";
                const profiles = S.profiles || [];
                const hasOthers = profiles.some((n) => n !== current);

                root.appendChild(section("profiles-list", "Profiles",
                    (body) => buildProfileList(body, current, profiles),
                    current ? "Active: " + current : "None active"));

                root.appendChild(section("profiles-manage", "Manage",
                    (body) => buildProfileManage(body, current, profiles, hasOthers),
                    "Creating, saving, moving and clearing profiles"));
            }

            function profileMenuItems(name, isCurrent) {
                const items = [];
                items.push({
                    icon: "",
                    label: "Rename...",
                    action: async () => {
                        const r = await openModal(
                            "Rename Profile",
                            `New name for "${name}".`,
                            "Rename",
                            "Cancel",
                            true,
                            name,
                        );
                        const v = (r.value || "").trim();
                        if (r.confirmed && v)
                            sendToHost({ action: "renameProfile", name, newName: v });
                    },
                });
                if (!isCurrent) {
                    items.push({
                        icon: "",
                        label: "Switch to this profile",
                        action: async () => {
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        },
                    });
                }
                items.push({
                    icon: "",
                    label: "Export this profile...",
                    action: () =>
                        sendToHost(
                            isCurrent
                                ? { action: "exportPackage", type: "profile" }
                                : { action: "exportPackage", type: "profile", profileName: name },
                        ),
                });
                if (!isCurrent) {
                    items.push("divider");
                    items.push({
                        icon: "",
                        label: "Delete profile",
                        danger: true,
                        action: async () => {
                            const res = await openModal(
                                "Delete Profile",
                                `Delete "${name}"?\n\nThis cannot be undone.`,
                                "Delete",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "deleteProfile", name });
                        },
                    });
                }
                return items;
            }

            function buildProfileList(body, current, profiles) {
                const otherProfiles = profiles.filter((n) => n !== current);
                if (otherProfiles.length === 0 && !current) {
                    body.appendChild(
                        h(
                            "div",
                            { cls: "row disabled" },
                            h(
                                "div",
                                { cls: "row-label" },
                                "No saved profiles yet.",
                            ),
                        ),
                    );
                }

                for (const name of profiles) {
                    const isCurrent = name === current;
                    const r = h("div", {
                        cls: "row",
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, name));
                    if (isCurrent)
                        r.appendChild(
                            h("span", { cls: "pill success" }, "Active"),
                        );

                    const menuBtn = h(
                        "button",
                        {
                            cls: "row-menu-btn",
                            title: "Profile actions",
                            onmouseenter: () => playSlot("hover"),
                        },
                    );
                    menuBtn.innerHTML = window.icon ? window.icon("ellipsis") : "...";
                    menuBtn.addEventListener("click", (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        playSlot("interact");
                        const rect = menuBtn.getBoundingClientRect();
                        showCtxMenu(
                            rect.right,
                            rect.bottom,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    r.appendChild(menuBtn);

                    if (!isCurrent)
                        r.addEventListener("click", async () => {
                            playSlot("interact");
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        });

                    r.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(
                            e.clientX,
                            e.clientY,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    body.appendChild(r);
                }
            }

            function buildProfileManage(body, current, profiles, hasOthers) {
                const nameExists = current && profiles.some((n) => n === current);
                body.appendChild(
                    btnRow(
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action",
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: async () => {
                                        playSlot("interact");
                                        const r = await openModal(
                                            "Create New Profile",
                                            "Start it from your current macros, theme, settings, and sounds, or blank?",
                                            "Seed from current",
                                            "Start blank",
                                        );
                                        sendToHost({
                                            action: "createNewProfile",
                                            seed: r.confirmed,
                                        });
                                    },
                                },
                                "Create New Profile",
                            );
                            return b;
                        })(),
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action" + (!nameExists ? " disabled" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        if (!nameExists) return;
                                        playSlot("interact");
                                        sendToHost({ action: "saveCurrentProfile" });
                                    },
                                },
                                "Save Current Profile",
                            );
                            return b;
                        })(),
                    ),
                );
                body.appendChild(
                    btnRow(
                        actionBtn("Import Profile", "", () =>
                            sendToHost({ action: "importPackage" }),
                        ),
                        actionBtn("Export Profile", "", () =>
                            sendToHost({ action: "exportPackage", type: "profile" }),
                        ),
                    ),
                );
                if (hasOthers) {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Clear Saved Profiles",
                                "danger",
                                async () => {
                                    const res = await openModal(
                                        "Clear Saved Profiles",
                                        "Delete all saved profiles except the active one?\n\nThis cannot be undone.",
                                        "Delete All",
                                    );
                                    if (res.confirmed)
                                        sendToHost({ action: "clearProfiles" });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildDeveloper(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Open Log Folder", "", () =>
                            sendToHost({ action: "openDevLogs" }),
                        ),
                    ),
                );

                body.appendChild(divider());

                {
                    const errorTypes = [
                        { value: "integrity", label: "Integrity Error" },
                        { value: "unknownPlugin", label: "Unrecognized Plugin" },
                        { value: "noLedger", label: "Plugins Not Verified" },
                        { value: "sandbox", label: "Sandbox Violation" },
                    ];
                    let fakeErrKind = "integrity";
                    const mkSel =
                        window.createSelect ||
                        (typeof createSelect === "function" ? createSelect : null);
                    const controls = h("div", {
                        style: "display:flex; gap:8px; align-items:center;",
                    });
                    if (mkSel) {
                        controls.appendChild(
                            mkSel({
                                className: "input-sm",
                                options: errorTypes,
                                value: fakeErrKind,
                                onChange: (v) => {
                                    fakeErrKind = v || "integrity";
                                },
                            }),
                        );
                    }
                    controls.appendChild(
                        actionBtn("Trigger", "", () =>
                            sendToHost({
                                action: "showFakeError",
                                value: fakeErrKind,
                            }),
                        ),
                    );
                    body.appendChild(
                        row(
                            "Test Error Screen",
                            "Preview a Guardian error screen, badged as a preview",
                            controls,
                        ),
                    );
                }

                body.appendChild(divider());

                body.appendChild(
                    buildSlider(
                        "Log archive limit",
                        "Max archived log files kept per category in backups/",
                        0,
                        50,
                        1,
                        null,
                        S.devArchiveLimit ?? 15,
                        (v) =>
                            sendToHost({
                                action: "setDevArchiveLimit",
                                value: v,
                            }),
                        [
                            {
                                icon: "",
                                label: "Reset to default",
                                action: () =>
                                    sendToHost({
                                        action: "setDevArchiveLimit",
                                        value: 15,
                                    }),
                            },
                        ],
                    ),
                );

                const chan = S.updateChannel || "stable";
                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Update Channel",
                        chan === "testing"
                            ? "Checks GitHub Actions for latest testing build"
                            : "Checks MANIFEST.json for stable releases",
                        h(
                            "button",
                            {
                                cls: "btn-macro " + (chan === "testing" ? "btn-enable" : ""),
                                onmouseenter: () => playSlot("hover"),
                                onclick: () => {
                                    const next = chan === "testing" ? "stable" : "testing";
                                    sendToHost({
                                        action: "setUpdateChannel",
                                        value: next,
                                    });
                                },
                            },
                            chan === "testing" ? "Testing" : "Stable",
                        ),
                    ),
                );

                body.appendChild(divider());

                if (chan === "testing") {
                    const src = S.testingSource || "release";
                    body.appendChild(
                        row(
                            "Testing Source",
                            src === "artifact"
                                ? "Downloads from GitHub Actions artifacts (zip only)"
                                : "Downloads from GitHub Releases (signed manifests)",
                            h(
                                "button",
                                {
                                    cls: "btn-macro " + (src === "artifact" ? "btn-enable" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        const next = src === "artifact" ? "release" : "artifact";
                                        sendToHost({
                                            action: "setTestingSource",
                                            value: next,
                                        });
                                    },
                                },
                                src === "artifact" ? "Artifacts" : "Releases",
                            ),
                        ),
                    );

                    if (src === "artifact") {
                        const token = S.githubToken || "";
                        body.appendChild(
                            row(
                                "GitHub Token",
                                token ? "********" + token.slice(-4) : "Required for artifact downloads",
                                h("input", {
                                    type: "password",
                                    cls: "input-sm",
                                    placeholder: "ghp_...",
                                    value: token,
                                    onchange: (e) => {
                                        sendToHost({
                                            action: "setGithubToken",
                                            value: e.target.value,
                                        });
                                    },
                                }),
                            ),
                        );
                    }
                }

                body.appendChild(divider());

                const status = S.integrityStatus || "uninitialized";
                const hash = S.integrityHash
                    ? S.integrityHash.slice(0, 16) + "..."
                    : ",";
                const trusted = status === "trusted";

                let statusPill;
                if (status === "trusted")
                    statusPill = h(
                        "span",
                        { cls: "pill success", style: "font-weight:600" },
                        "Trusted",
                    );
                else if (status === "mismatch")
                    statusPill = h(
                        "span",
                        { cls: "pill danger", style: "font-weight:600" },
                        "Mismatch",
                    );
                else statusPill = h("span", { cls: "pill", style: "font-weight:600" }, "Not set");
                body.appendChild(row("System Integrity", hash, statusPill));

                const trustRow = h("div", {
                    cls: "row" + (trusted ? " disabled" : ""),
                    onmouseenter: () => {
                        if (!trusted) playSlot("hover");
                    },
                });
                trustRow.appendChild(
                    h(
                        "div",
                        { cls: "row-label" },
                        trusted
                            ? "Trust Current Version"
                            : "Trust Current Version...",
                    ),
                );
                if (!trusted) {
                    trustRow.addEventListener("click", async () => {
                        playSlot("interact");
                        const prompt =
                            status === "uninitialized"
                                ? `Seal this ms_core.lua as the trusted baseline?\nHash: ${hash}`
                                : `Hash mismatch, trust the CURRENT (possibly modified) version?\nHash: ${hash}`;
                        const r = await openModal(
                            "Trust Current Version",
                            prompt,
                            "Trust",
                        );
                        if (r.confirmed)
                            sendToHost({ action: "trustCurrentVersion" });
                    });
                }
                body.appendChild(trustRow);

                body.appendChild(
                    btnRow(
                        actionBtn("Check Integrity", "", () =>
                            sendToHost({ action: "checkIntegrity" }),
                        ),
                    ),
                );

                if (status !== "uninitialized") {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Delete Trusted Hash",
                                "danger",
                                async () => {
                                    const r = await openModal(
                                        "Delete Trusted Hash",
                                        "This removes integrity protection entirely.\n\n" +
                                            "From this point on mudscript will load ANY version of its code " +
                                            "without warning, including maliciously modified files.\n\n" +
                                            "You are on your own. Proceed only if you know what you are doing.",
                                        "Delete, I understand the risk",
                                    );
                                    if (r.confirmed)
                                        sendToHost({
                                            action: "deleteTrustedHash",
                                        });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildHelp(body) {
                const meta = S.macroMeta || {};
                const ver = S.msVersion || "dev";
                body.appendChild(
                    h(
                        "div",
                        { cls: "group-label" },
                        "mudscript HS utilities \u2013 Version: ",
                        h("span", { style: "text-transform: none" }, ver),
                    ),
                );

                const aboutBtn = actionBtn("About", "", () => {
                    sendToHost({
                        action: "alert",
                        msg: "mudscript HS utilities\nBy: mudbourn \u2014 mudbourn.info",
                        duration: 5,
                    });
                    if (meta.name) {
                        const line2 =
                            meta.name +
                            (meta.author ? `\nBy: ${meta.author}` : "") +
                            (meta.website ? `\n${meta.website}` : "");
                        sendToHost({
                            action: "alert",
                            msg: line2,
                            duration: 5,
                            noSound: true,
                        });
                    }
                });

                const docBtn = actionBtn("Documentation", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: (S.docsURL || "") + "?platform=mac",
                    }),
                );
                docBtn.style.flex = "1";

                const githubBtn = actionBtn("GitHub", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: "https://github.com/mudbourn/mudscript",
                    }),
                );
                githubBtn.style.flex = "1";

                if (S.updateManifestURL || S.updateChannel === "testing") {
                    const _chan = S.updateChannel || "stable";
                    const updateBtn = actionBtn(
                        "Check for Update",
                        "",
                        async () => {
                            const r = await openModal(
                                "Check for Update",
                                "Channel: " + _chan + "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                                "Update",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "checkForUpdate" });
                        },
                    );
                    body.appendChild(btnRow(aboutBtn, updateBtn));
                } else {
                    body.appendChild(btnRow(aboutBtn));
                }
                body.appendChild(btnRow(docBtn, githubBtn));

                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Update Alerts on Launch",
                        "Notify about app, plugin, and content updates at startup",
                        toggle(!(S.updateAlertsDisabled ?? false), (e) =>
                            sendToHost({
                                action: "setUpdateAlerts",
                                value: e.target.checked,
                            }),
                        ),
                    ),
                );
            }
        // END Profiles, Developer and Help //

            Object.assign(window.msSettings, {
                buildProfiles,
                buildDeveloper,
                buildHelp,
            });
    })();
