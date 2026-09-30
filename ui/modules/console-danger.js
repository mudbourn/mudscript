(function() {
    "use strict";

// Console first-open danger notice //
    var _pop = null;

    function show(onAck) {
        if (!window.msPopup || (_pop && _pop.isOpen())) return;
        function ack() {
            _pop = null;
            onAck();
        }
        _pop = window.msPopup.open({
            title:     "Console - use with care",
            tone:      "danger",
            noDone:    true,
            onCancel:  function() { setTimeout(ack, 0); },
            onConfirm: function() { _pop.close(); ack(); },
            build: function(p) {
                p.text([
                    ["This console runs ", { strong: "arbitrary Lua on your machine" },
                        " with the same access mudscript itself has: your files, input, and windows."],
                    [{ strong: "Never paste code you didn't write or don't fully understand." },
                        " A snippet someone hands you can look harmless and still delete files,"
                        + " log your keystrokes, or take over your session. If you can't say"
                        + " exactly what a line does, don't run it here."],
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

    function hide() {
        if (_pop && _pop.isOpen()) _pop.close();
        _pop = null;
    }

    window.msConsoleDanger = { show: show, hide: hide };
// END Console first-open danger notice //
})();
