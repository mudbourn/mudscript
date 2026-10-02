(function() {
    "use strict";

// Edit handwritten macros first-open notice //
    var _pop = null;

    function ack() {
        _pop = null;
        if (window.shellPost) shellPost("macros", "editMacros", {
            action: "editMacros",
            ack:    true,
        });
    }

    function show() {
        if (!window.msPopup || (_pop && _pop.isOpen())) return;
        _pop = window.msPopup.open({
            title:    "Edit handwritten macros",
            tone:     "danger",
            noDone:   true,
            onCancel: function() { _pop = null; },
            build: function(p) {
                p.text([
                    ["You are about to open ", { strong: "ms_macros.lua" },
                        ", the handwritten macro script."],
                    ["Visual builder macros are stored separately as JSON and are"
                        + " not usually edited by hand in a text editor."],
                ]);
                p.spacer();
                var btn = p.action(p.button("I understand", function() {
                    p.close();
                    ack();
                }, "danger-solid"));
                setTimeout(function() { btn.focus(); }, 50);
            },
        });
    }

    window.msEditMacrosNotice = { show: show };
// END Edit handwritten macros first-open notice //
})();
