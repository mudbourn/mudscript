(function() {
    "use strict";

// Update first-run notice //
    var _pop = null;

    function ack() {
        _pop = null;
        if (window.shellPost) shellPost("settings", "checkForUpdate", {
            action: "checkForUpdate",
            ack:    true,
        });
    }

    function show(channel) {
        if (!window.msPopup || (_pop && _pop.isOpen())) return;
        var testing = channel === "testing";
        _pop = window.msPopup.open({
            title:    "Updating mudscript",
            tone:     "danger",
            noDone:   true,
            onCancel: function() { _pop = null; },
            build: function(p) {
                var lines = [
                    ["Updating downloads the latest ", { strong: testing ? "testing build" : "release" },
                        " and replaces mudscript's app files: core, lib, ui and the bundled plugins."],
                    ["Your macros, profiles and settings are kept. The files it replaces are"
                        + " backed up to ", { strong: "backups/updates/" }, " first, then mudscript restarts."],
                ];
                if (testing) lines.push([{ strong: "Testing builds are unreleased." },
                    " They are cut from every push and can be broken. Switch the channel back"
                    + " to Stable for official releases."]);
                p.text(lines);
                p.spacer();
                var btn = p.action(p.button("I understand", function() {
                    p.close();
                    ack();
                }, "danger-solid"));
                setTimeout(function() { btn.focus(); }, 50);
            },
        });
    }

    window.msUpdateNotice = { show: show };
// END Update first-run notice //
})();
