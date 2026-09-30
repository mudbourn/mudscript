(function() {
    "use strict";

    window.msMacroRecord = function(ctx) {
        var M = ctx.M;

        var nameInput = ctx.nameInput;

        var iconOnly = ctx.iconOnly;

        var menuLabel = ctx.menuLabel;

        var testBtn = ctx.testBtn;

        var recordBtn = ctx.recordBtn;

        var recSettingsBtn = ctx.recSettingsBtn;

        var testToast = ctx.testToast;

        // Test Run //
            M.testRunning = false;
            M.testToastTimer = null;

            function showTestToast(msg, type, iconName) {
                if (iconName && window.icon) {
                    testToast.innerHTML = window.icon(iconName);
                    testToast.appendChild(document.createTextNode(" " + msg));
                } else {
                    testToast.textContent = msg;
                }
                testToast.className = "macro-test-toast show"
                    + (type === "error" ? " error-toast" : "")
                    + (type === "success" ? " success-toast" : "");
                if (M.testToastTimer) clearTimeout(M.testToastTimer);
                M.testToastTimer = setTimeout(function() {
                    testToast.className = "macro-test-toast";
                    M.testToastTimer = null;
                }, type === "error" ? 5000 : 2500);
            }

            function _resetTestBtn() {
                testBtn.className = "macro-toolbar-btn macro-icon-btn";
                testBtn.innerHTML = iconOnly("play");
                testBtn.disabled = false;
                M.testRunning = false;
            }

            testBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            M.testFromPad = false;

            testBtn.addEventListener("click", function() {
                if (M.testRunning) return;
                M.testFromPad = testBtn.classList.contains("gp-focus");
                var steps = M.canvas.serialize();
                if (!steps || steps.length === 0) {
                    if (window.playSlot) playSlot("back");
                    showTestToast("No steps to run", "error");
                    return;
                }
                if (window.playSlot) playSlot("interact");

                var macroId = M.currentMacroId || ("_test_" + Date.now().toString(36));
                var macroDef = {
                    id: macroId,
                    name: nameInput.value.trim() || macroId,
                    steps: steps,
                    hideShell: true,
                };

                M.testRunning = true;
                testBtn.className = "macro-toolbar-btn macro-icon-btn running";
                testBtn.innerHTML = iconOnly("timer");
                testBtn.disabled = true;

                if (window.shellPost) {
                    shellPost("macros", "testRun", macroDef);
                }

                setTimeout(function() {
                    if (M.testRunning) {
                        _resetTestBtn();
                        showTestToast("Test run timed out", "error");
                    }
                }, 35000);
            });

            M.isRecording = false;
        // END Test Run //

        // Recording options //
            var _REC_OPTS_KEY = "ms.macroRecordOpts";
            var _recOptDefaults = {
                recordDelays:       true,
                pressMode:          "type",
                recordDrags:        true,
                dragGranularity:    5,
                recordMouseMoves:   false,
                moveGranularity:    5,
                recordMouseButtons: true,
                recordWindowMove:   false,
                recordWindowResize: false,
                waitThreshold:      50
            };
            var _recOpts = (function() {
                var o = {};
                for (var k in _recOptDefaults) o[k] = _recOptDefaults[k];
                try {
                    var saved = JSON.parse(localStorage.getItem(_REC_OPTS_KEY) || "{}");
                    for (var k2 in saved) if (k2 in o) o[k2] = saved[k2];
                    if (o.pressMode === "press") o.pressMode = "pressRelease";
                } catch (e) {}
                return o;
            })();
            function _saveRecOpts() {
                try { localStorage.setItem(_REC_OPTS_KEY, JSON.stringify(_recOpts)); }
                catch (e) {}
            }

            function _setRecordingState(on) {
                M.isRecording = on;
                if (on) {
                    recordBtn.className = "macro-toolbar-btn recording";
                    recordBtn.innerHTML = menuLabel("stop", "Stop");
                    recordBtn.title = "Stop recording";
                } else {
                    recordBtn.className = "macro-toolbar-btn";
                    recordBtn.innerHTML = menuLabel("record", "Record");
                    recordBtn.title = "Record user actions into tools";
                }
            }

            recordBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            M.recordFromPad = false;
            recordBtn.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                if (!M.isRecording) {
                    M.recordFromPad = recordBtn.classList.contains("gp-focus");
                    if (window.shellPost) {
                        shellPost("macros", "startRecording", {
                            waitThreshold: _recOpts.waitThreshold,
                            options: _recOpts,
                            hideShell: true
                        });
                    }
                    _setRecordingState(true);
                } else {
                    if (window.shellPost) {
                        shellPost("macros", "stopRecording", {});
                    }
                    _setRecordingState(false);
                    showTestToast("Recording stopped", "success");
                }
            });
        // END Recording options //

        // Recording settings menu //
            function _openRecModal() {
                function set(key) {
                    return function(v) {
                        _recOpts[key] = v;
                        _saveRecOpts();
                    };
                }
                window.msPopup.open({
                    title: "Recording Settings",
                    sub: "Choose what a recording captures. Applied to the next recording you start.",
                    build: function(p) {
                        p.row("Record delays", "Insert wait modules for idle gaps between actions.",
                            p.toggle(_recOpts.recordDelays, set("recordDelays")));
                        p.row("Key presses", "How keystrokes are captured.", p.seg([
                            { value: "type",         label: "Type",  hint: "Full press+release keystroke (ms.type)" },
                            { value: "pressRelease", label: "Press", hint: "Separate press and release with real hold timing" },
                        ], _recOpts.pressMode, set("pressMode")));
                        p.row("Record mouse buttons", "Capture left/right/middle clicks.",
                            p.toggle(_recOpts.recordMouseButtons, set("recordMouseButtons")));
                        p.row("Record mouse drags", "Capture press-move-release as a drag gesture.",
                            p.toggle(_recOpts.recordDrags, set("recordDrags")));
                        p.row("Drag fidelity", "How closely a recorded drag follows your real path. Lower is coarser; higher tracks curves near 1:1. The whole gesture stays one module either way.",
                            p.range(1, 10, _recOpts.dragGranularity, set("dragGranularity")));
                        p.row("Record mouse movement", "Capture free cursor motion (no button held) as moveMouse steps.",
                            p.toggle(_recOpts.recordMouseMoves, set("recordMouseMoves")));
                        p.row("Movement fidelity", "How closely recorded movement follows your real path. Lower is coarser, higher tracks curves near 1:1.",
                            p.range(1, 10, _recOpts.moveGranularity, set("moveGranularity")));
                        p.row("Record window moves", "Capture moving the focused window.",
                            p.toggle(_recOpts.recordWindowMove, set("recordWindowMove")));
                        p.row("Record window resizes", "Capture resizing the focused window.",
                            p.toggle(_recOpts.recordWindowResize, set("recordWindowResize")));
                        p.action(p.button("Reset", function() {
                            for (var k in _recOptDefaults) _recOpts[k] = _recOptDefaults[k];
                            _saveRecOpts();
                            p.close();
                            _openRecModal();
                        }, "back"));
                        p.spacer();
                        p.action(p.button("Done", function() { p.close(); }, "primary"));
                    },
                });
            }

            recSettingsBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            recSettingsBtn.addEventListener("click", _openRecModal);
        // END Recording settings menu //

        return {
            showTestToast: showTestToast,
            _resetTestBtn: _resetTestBtn,
            _setRecordingState: _setRecordingState,
        };
    };
})();
