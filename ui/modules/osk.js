(function() {
"use strict";

    // On-screen keyboard driver for controller users. Opened by the gamepad nav
    // layer when A is pressed on a text field; driven entirely by the controller
    // (dpad picks a key, A presses it, B closes). It dismisses itself the moment
    // a real keyboard or mouse is used, so it never gets in the way of someone
    // who reaches for either.
    //
    // The visible keys live in a separate host-owned window (ui/ms_osk.html) that
    // can be dragged anywhere on screen, free of this window's frame. This module
    // stays the brain: it owns the layout, the cursor, and the text edits against
    // the focused field, and streams a serialisable board to the host — which
    // paints it into that window and moves it on request. Everything that touches
    // the field runs here, next to the field.

    var LETTERS = [
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
        ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
        ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '-'],
        ['{shift}', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '{back}'],
        ['{sym}', '{space}', '{enter}', '{done}'],
    ];

    var SYMBOLS = [
        ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')'],
        ['[', ']', '{', '}', '<', '>', '/', '\\', '|', '~'],
        ['-', '_', '=', '+', ';', ':', '"', "'", '`', '?'],
        ['{abc}', ',', '.', '{back}'],
        ['{space}', '{enter}', '{done}'],
    ];

    var SHIFTED = { '1': '!', '2': '@', '3': '#', '4': '$', '5': '%',
        '6': '^', '7': '&', '8': '*', '9': '(', '0': ')', '-': '_',
        ',': ';', '.': ':' };

    var KEY_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"'
        + ' stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';
    var SHIFT_SVG = KEY_SVG + '<path d="M9 19a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1v-6a1 1 0 0 1 1-1h3.293a.707.707 0 0 0 .5-1.207l-7.086-7.086a1 1 0 0 0-1.414 0l-7.086 7.086a.707.707 0 0 0 .5 1.207H8a1 1 0 0 1 1 1z"/></svg>';
    var BACK_SVG = KEY_SVG + '<path d="M10 5a2 2 0 0 0-1.344.519l-6.328 5.74a1 1 0 0 0 0 1.481l6.328 5.741A2 2 0 0 0 10 19h10a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2z"/><path d="m12 9 6 6"/><path d="m18 9-6 6"/></svg>';

    var LABELS = { '{shift}': SHIFT_SVG, '{back}': BACK_SVG, '{space}': 'space',
        '{enter}': '↵', '{done}': 'Done', '{sym}': '#+=', '{abc}': 'ABC' };

    var _symMode = false;
    function LAYOUT_() { return _symMode ? SYMBOLS : LETTERS; }

    var _open = false;
    var _r = 1, _c = 0;
    var _shift = false;
    var _target = null;
    var _openAt = 0;
    var _vcaret = null;

    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    // Reach the host over whichever window this module is running in — the shell
    // and every pop-out expose the same post helper. The host forwards a "_osk"
    // message to the keyboard window.
    function emit(op, extra) {
        var payload = { op: op };
        if (extra) { for (var k in extra) payload[k] = extra[k]; }
        var send = window.shellDispatch || window.shellPost;
        if (send) { try { send('_osk', 'osk', payload); } catch (e) {} }
    }

    // Face-button glyphs per controller type. GameController reports buttons by
    // position (a=bottom, b=right, x=left, y=top), so PlayStation maps to its
    // shapes and Nintendo swaps the printed labels to match its layout.
    var PS_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"'
        + ' stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">';
    var PS = {
        cross: PS_SVG + '<path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>',
        circle: PS_SVG + '<circle cx="12" cy="12" r="10"/></svg>',
        square: PS_SVG + '<rect width="18" height="18" x="3" y="3" rx="2"/></svg>',
        triangle: PS_SVG + '<path d="M13.73 4a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/></svg>',
    };
    var GLYPHS = {
        xbox:    { a: 'A', b: 'B', x: 'X', y: 'Y', menu: '☰', l1: 'LB', r1: 'RB', l2: 'LT', r2: 'RT' },
        generic: { a: 'A', b: 'B', x: 'X', y: 'Y', menu: '☰', l1: 'LB', r1: 'RB', l2: 'LT', r2: 'RT' },
        ds4:     { a: PS.cross, b: PS.circle, x: PS.square, y: PS.triangle, menu: 'Options', l1: 'L1', r1: 'R1', l2: 'L2', r2: 'R2' },
        'switch': { a: 'B', b: 'A', x: 'Y', y: 'X', menu: '+', l1: 'L', r1: 'R', l2: 'ZL', r2: 'ZR' },
    };
    var HINTS = [['a', 'Select'], ['b', 'Close'], ['x', BACK_SVG], ['y', 'Space'],
        ['l1', '◀'], ['r1', '▶'], ['l2', '#+='], ['r2', SHIFT_SVG], ['menu', 'Done']];

    function glyphSet() { return GLYPHS[window.__gpType] || GLYPHS.xbox; }

    function keyLabel(k) {
        if (LABELS[k]) return LABELS[k];
        if (_shift) return SHIFTED[k] || k.toUpperCase();
        return k;
    }

    var WIDE = { '{shift}': 1, '{back}': 1, '{enter}': 1, '{done}': 1, '{sym}': 1, '{abc}': 1 };

    // Serialise the current board into faces the keyboard window can paint
    // without any keyboard knowledge of its own — plain text or inline SVG per
    // key, plus a width class and the shift key's on-state.
    function faceOf(k) {
        var lbl = keyLabel(k);
        var f = {};
        if (lbl.charAt(0) === '<') f.svg = lbl; else f.t = lbl;
        if (k === '{space}') f.w = 'space';
        else if (WIDE[k]) f.w = 'wide';
        if (k === '{shift}' && _shift) f.on = true;
        return f;
    }

    function buildGrid() {
        var board = LAYOUT_();
        var grid = [];
        for (var r = 0; r < board.length; r++) {
            var row = [];
            for (var c = 0; c < board[r].length; c++) row.push(faceOf(board[r][c]));
            grid.push(row);
        }
        return grid;
    }

    function buildHints() {
        var g = glyphSet();
        var out = [];
        for (var i = 0; i < HINTS.length; i++) {
            var glyph = g[HINTS[i][0]], desc = HINTS[i][1];
            out.push({
                glyph: glyph.charAt(0) === '<' ? { svg: glyph } : { t: glyph },
                desc: desc.charAt(0) === '<' ? { svg: desc } : { t: desc },
            });
        }
        return out;
    }

    function renderPayload() {
        return { grid: buildGrid(), active: { r: _r, c: _c }, hints: buildHints() };
    }

    function pushRender() { if (_open) emit('render', renderPayload()); }

    function isTextField(el) {
        if (!el) return false;
        if (el.isContentEditable) return true;
        var t = el.tagName;
        if (t === 'TEXTAREA') return true;
        if (t !== 'INPUT') return false;
        var type = (el.getAttribute('type') || 'text').toLowerCase();
        return ['text', 'search', 'url', 'email', 'tel', 'number', 'password'].indexOf(type) !== -1;
    }

    function dispatchInput(el) {
        try { el.dispatchEvent(new Event('input', { bubbles: true })); } catch (e) {}
    }

    // number and email inputs throw on selectionStart / setRangeText in WebKit —
    // the selection API only covers these types — so anything else edits by whole
    // value (append / trim the tail) instead of by caret range.
    function canSelect(el) {
        if (el.tagName === 'TEXTAREA') return true;
        var type = (el.getAttribute('type') || 'text').toLowerCase();
        return ['text', 'search', 'url', 'tel', 'password'].indexOf(type) !== -1;
    }

    // number / email inputs can't use the selection API, so edits there run
    // against the whole value string. A virtual caret (_vcaret) tracks the edit
    // point so the bumpers can walk it and inserts/deletes land there, not only
    // at the tail. Everything else drives the native selection instead.
    function wholeValue(el) {
        return !el.isContentEditable
            && !(canSelect(el) && typeof el.setRangeText === 'function');
    }

    function insert(text) {
        var el = _target;
        if (!el) return;
        if (el.isContentEditable) {
            el.textContent += text;
        } else if (canSelect(el) && typeof el.setRangeText === 'function') {
            var s = el.selectionStart, e = el.selectionEnd;
            if (s == null) { s = e = (el.value || '').length; }
            el.setRangeText(text, s, e, 'end');
        } else {
            var v = el.value || '';
            if (_vcaret == null) _vcaret = v.length;
            el.value = v.slice(0, _vcaret) + text + v.slice(_vcaret);
            _vcaret += text.length;
        }
        dispatchInput(el);
    }

    function backspace() {
        var el = _target;
        if (!el) return;
        if (el.isContentEditable) {
            el.textContent = el.textContent.slice(0, -1);
            dispatchInput(el);
            return;
        }
        if (!canSelect(el) || typeof el.setRangeText !== 'function') {
            var v = el.value || '';
            if (_vcaret == null) _vcaret = v.length;
            if (_vcaret > 0) {
                el.value = v.slice(0, _vcaret - 1) + v.slice(_vcaret);
                _vcaret--;
            }
            dispatchInput(el);
            return;
        }
        var s = el.selectionStart, e = el.selectionEnd;
        if (s == null) { s = e = (el.value || '').length; }
        if (s === e && s > 0) el.setRangeText('', s - 1, s, 'end');
        else if (s !== e) el.setRangeText('', s, e, 'end');
        dispatchInput(el);
    }

    // Any real keyboard or mouse activity means the user has moved on from the
    // controller, so the keyboard bows out. mousemove is ignored briefly after
    // opening so the residual pointer position doesn't dismiss it instantly.
    function onRealKey(e) { if (e.isTrusted) close(); }
    function onRealMouseDown(e) { if (e.isTrusted) close(); }
    function onRealMouseMove(e) {
        if (e.isTrusted && Date.now() - _openAt > 350) close();
    }
    // Switching focus away from this window (to type in another app) should
    // also dismiss it, since a webview only sees keystrokes while it is focused.
    // Ignore the blur that can land as the keyboard window is brought to front
    // just after opening, so it doesn't dismiss itself instantly.
    function onBlur() { if (Date.now() - _openAt > 350) close(); }

    function addDismissListeners() {
        document.addEventListener('keydown', onRealKey, true);
        document.addEventListener('mousedown', onRealMouseDown, true);
        document.addEventListener('mousemove', onRealMouseMove, true);
        window.addEventListener('blur', onBlur, true);
    }
    function removeDismissListeners() {
        document.removeEventListener('keydown', onRealKey, true);
        document.removeEventListener('mousedown', onRealMouseDown, true);
        document.removeEventListener('mousemove', onRealMouseMove, true);
        window.removeEventListener('blur', onBlur, true);
    }

    function open(target) {
        if (!isTextField(target)) return false;
        _target = target;
        try { target.focus({ preventScroll: true }); } catch (e) {}
        _vcaret = wholeValue(target) ? (target.value || '').length : null;
        _shift = false;
        _symMode = false;
        _r = 1; _c = 0;
        _open = true;
        _openAt = Date.now();
        addDismissListeners();
        emit('open', renderPayload());
        playSlot('interact');
        return true;
    }

    function close() {
        if (!_open) return;
        _open = false;
        _target = null;
        removeDismissListeners();
        emit('close');
        playSlot('back');
    }

    function isOpen() { return _open; }

    function move(dir) {
        if (!_open) return;
        var board = LAYOUT_();
        if (dir === 'up') _r = (_r - 1 + board.length) % board.length;
        else if (dir === 'down') _r = (_r + 1) % board.length;
        else if (dir === 'left') _c = _c - 1;
        else if (dir === 'right') _c = _c + 1;
        var len = board[_r].length;
        if (_c < 0) _c = len - 1;
        if (_c >= len) _c = 0;
        pushRender();
        playSlot('hover');
    }

    function press() {
        if (!_open) return;
        var k = LAYOUT_()[_r][_c];
        if (k === '{shift}') { _shift = !_shift; pushRender(); playSlot('interact'); return; }
        if (k === '{sym}' || k === '{abc}') { _symMode = !_symMode; _shift = false; _r = 1; _c = 0; pushRender(); playSlot('interact'); return; }
        if (k === '{back}') { backspace(); playSlot('interact'); return; }
        if (k === '{done}') { close(); return; }
        if (k === '{space}') { insert(' '); playSlot('interact'); return; }
        if (k === '{enter}') {
            if (_target && _target.tagName === 'TEXTAREA') { insert('\n'); playSlot('interact'); }
            else { close(); }
            return;
        }
        insert(_shift ? (SHIFTED[k] || k.toUpperCase()) : k);
        if (_shift) { _shift = false; pushRender(); }
        playSlot('interact');
    }

    // Direct button shortcuts driven from the nav layer (Y = space, X = ⌫).
    function typeSpace() { if (_open) { insert(' '); playSlot('interact'); } }
    function doBackspace() { if (_open) { backspace(); playSlot('interact'); } }

    // Bumpers walk the caret through the text like the arrow keys would.
    function caret(delta) {
        var el = _target;
        if (!_open || !el) return;
        if (el.isContentEditable) {
            var sel = window.getSelection && window.getSelection();
            if (sel && sel.modify) sel.modify('move', delta < 0 ? 'backward' : 'forward', 'character');
        } else if (wholeValue(el)) {
            var wlen = (el.value || '').length;
            if (_vcaret == null) _vcaret = wlen;
            _vcaret = Math.max(0, Math.min(wlen, _vcaret + delta));
        } else if (typeof el.setSelectionRange === 'function') {
            var len = (el.value || '').length;
            var pos = el.selectionStart;
            if (pos == null) pos = len;
            pos = Math.max(0, Math.min(len, pos + delta));
            try { el.setSelectionRange(pos, pos); } catch (e) {}
        }
        playSlot('hover');
    }

    // Triggers shift the character set: one toggles upper/shifted glyphs (like
    // holding shift), the other swaps between the letter and symbol boards.
    function shiftToggle() { if (!_open) return; _shift = !_shift; pushRender(); playSlot('interact'); }
    function symToggle() { if (!_open) return; _symMode = !_symMode; _shift = false; _r = 1; _c = 0; pushRender(); playSlot('interact'); }

    // Right-stick drag: ask the host to move the keyboard window by a delta. The
    // window is free of this frame, so it can roam the whole screen.
    function nudge(dx, dy) {
        if (!_open || (!dx && !dy)) return;
        emit('move', { dx: dx * 0.14, dy: -dy * 0.14 });
    }

    window.MSOsk = {
        open: open, close: close, isOpen: isOpen,
        move: move, press: press, isTextField: isTextField,
        space: typeSpace, backspace: doBackspace,
        caretLeft: function() { caret(-1); }, caretRight: function() { caret(1); },
        shift: shiftToggle, symbols: symToggle,
        nudge: nudge,
    };
})();
