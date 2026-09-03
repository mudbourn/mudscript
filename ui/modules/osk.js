(function() {
"use strict";

    // Theme-compliant on-screen keyboard for controller users. Opened by the
    // gamepad nav layer when A is pressed on a text field; driven entirely by
    // the controller (dpad picks a key, A presses it, B closes). It dismisses
    // itself the moment a real keyboard or mouse is used, so it never gets in
    // the way of someone who reaches for either.

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

    var _root = null;
    var _keyEls = [];
    var _r = 1, _c = 0;
    var _shift = false;
    var _target = null;
    var _openAt = 0;

    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }

    function ensureStyle() {
        if (document.getElementById('osk-css')) return;
        var s = document.createElement('style');
        s.id = 'osk-css';
        s.textContent =
            '.osk { position: fixed; left: 50%; bottom: 14px; transform: translateX(-50%);'
            + ' z-index: 100000; display: flex; flex-direction: column; gap: 5px; padding: 10px;'
            + ' background: var(--surface, #1c1c1c); border: 1px solid var(--border, #333);'
            + ' border-radius: var(--radius, 8px); box-shadow: 0 8px 30px rgba(0,0,0,0.45);'
            + ' font-family: var(--font-mono, ui-monospace, monospace); user-select: none;'
            + ' transform-origin: bottom center; }'
            + '.osk-row { display: flex; gap: 5px; justify-content: center; }'
            + '.osk-key { min-width: 34px; height: 38px; padding: 0 8px; display: flex;'
            + ' align-items: center; justify-content: center; font-size: 15px;'
            + ' color: var(--text2, #cfcfcf); background: var(--surface2, #262626);'
            + ' border: 1px solid var(--border-dim, #2f2f2f); border-radius: var(--radius-s, 5px);'
            + ' cursor: default; transition: background 0.08s, color 0.08s, box-shadow 0.08s; }'
            + '.osk-key svg { width: 18px; height: 18px; display: block; }'
            + '.osk-key.osk-wide { min-width: 74px; }'
            + '.osk-key.osk-space { min-width: 200px; }'
            + '.osk-key.osk-active { color: var(--text, #fff); background: var(--hover, #333);'
            + ' box-shadow: inset 0 0 0 2px var(--accent-hi, var(--accent, #e0245e)); }'
            + '.osk-key.osk-on { color: var(--bg, #111); background: var(--accent, #e0245e);'
            + ' border-color: var(--accent, #e0245e); }'
            + '.osk[hidden] { display: none !important; }'
            + '.osk-hints { display: flex; flex-wrap: wrap; gap: 4px 12px; justify-content: center;'
            + ' margin-top: 3px; font-size: 11px; color: var(--text3, #888); }'
            + '.osk-hints b { color: var(--accent, #e0245e); font-weight: 700; margin-right: 3px; }'
            + '.osk-hints svg { width: 12px; height: 12px; vertical-align: -1px; }';
        (document.head || document.documentElement).appendChild(s);
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
    // slot → action label; the glyph is resolved from the live controller type.
    // A label beginning with '<' is inline SVG (shift / backspace icons).
    var HINTS = [['a', 'Select'], ['b', 'Close'], ['x', BACK_SVG], ['y', 'Space'],
        ['l1', '◀'], ['r1', '▶'], ['l2', '#+='], ['r2', SHIFT_SVG], ['menu', 'Done']];

    function glyphSet() { return GLYPHS[window.__gpType] || GLYPHS.xbox; }

    function keyLabel(k) {
        if (LABELS[k]) return LABELS[k];
        if (_shift) return SHIFTED[k] || k.toUpperCase();
        return k;
    }

    // Some key faces (shift, backspace) are inline SVG rather than a glyph, so
    // render markup when the label opens with a tag and plain text otherwise.
    function applyLabel(el, k) {
        var lbl = keyLabel(k);
        if (lbl.charAt(0) === '<') el.innerHTML = lbl; else el.textContent = lbl;
    }

    var WIDE = { '{shift}': 1, '{back}': 1, '{enter}': 1, '{done}': 1, '{sym}': 1, '{abc}': 1 };

    function build() {
        ensureStyle();
        _root = document.createElement('div');
        _root.className = 'osk';
        _keyEls = [];
        var board = LAYOUT_();
        for (var r = 0; r < board.length; r++) {
            var rowEl = document.createElement('div');
            rowEl.className = 'osk-row';
            var rowKeys = [];
            for (var c = 0; c < board[r].length; c++) {
                var k = board[r][c];
                var el = document.createElement('div');
                el.className = 'osk-key';
                if (k === '{space}') el.className += ' osk-space';
                else if (WIDE[k]) el.className += ' osk-wide';
                applyLabel(el, k);
                rowEl.appendChild(el);
                rowKeys.push(el);
            }
            _root.appendChild(rowEl);
            _keyEls.push(rowKeys);
        }
        var hints = document.createElement('div');
        hints.className = 'osk-hints';
        var g = glyphSet();
        for (var i = 0; i < HINTS.length; i++) {
            var span = document.createElement('span');
            var b = document.createElement('b');
            var glyph = g[HINTS[i][0]];
            if (glyph.charAt(0) === '<') b.innerHTML = glyph; else b.textContent = glyph;
            span.appendChild(b);
            var desc = HINTS[i][1];
            if (desc.charAt(0) === '<') {
                var dsp = document.createElement('span');
                dsp.innerHTML = desc;
                span.appendChild(dsp);
            } else {
                span.appendChild(document.createTextNode(desc));
            }
            hints.appendChild(span);
        }
        _root.appendChild(hints);
        document.body.appendChild(_root);
    }

    // Swap between the letter and symbol boards. They differ in shape, so the
    // DOM is torn down and rebuilt, keeping the cursor on a sane key.
    function rebuild() {
        var wasHidden = _root ? _root.hidden : true;
        if (_root && _root.parentNode) _root.parentNode.removeChild(_root);
        _root = null;
        build();
        _root.hidden = wasHidden;
        _r = 1; _c = 0;
        paint();
        if (!wasHidden && _target) positionAbove(_target);
    }

    function relabel() {
        var board = LAYOUT_();
        for (var r = 0; r < board.length; r++) {
            for (var c = 0; c < board[r].length; c++) {
                applyLabel(_keyEls[r][c], board[r][c]);
                _keyEls[r][c].classList.toggle('osk-on',
                    board[r][c] === '{shift}' && _shift);
            }
        }
    }

    function paint() {
        for (var r = 0; r < _keyEls.length; r++) {
            for (var c = 0; c < _keyEls[r].length; c++) {
                _keyEls[r][c].classList.toggle('osk-active', r === _r && c === _c);
            }
        }
    }

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
            el.value = (el.value || '') + text;
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
            el.value = (el.value || '').slice(0, -1);
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
    function onBlur() { close(); }

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

    // Shrink the board to fit when the host is narrower than its natural width
    // (the widest row would otherwise spill its right-hand keys off-screen), then
    // keep it docked at the bottom unless the field being edited sits low enough
    // that the docked board would cover it — only then lift the board clear above
    // the field, so a bottom-pinned field stays visible while a higher one leaves
    // the board where it belongs. The board is position:fixed inside the zoomed
    // shell root, so its offsetWidth/Height are already in zoomed px while
    // innerWidth/Height and getBoundingClientRect come back physical — fold the
    // physical values through the zoom or a magnified shell pushes it off-screen.
    function positionAbove(el) {
        if (!_root) return;
        _root.style.transform = 'translateX(-50%)';
        var zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
        var natural = _root.offsetWidth;
        var vw = window.innerWidth / zoom;
        var scale = vw > 16 ? Math.min(1, (vw - 16) / natural) : 1;
        _root.style.transform = 'translateX(-50%) scale(' + scale + ')';
        var base = 14;
        if (el) {
            var r = el.getBoundingClientRect();
            var vh = window.innerHeight / zoom;
            var rBottom = r.bottom / zoom, rTop = r.top / zoom;
            var h = _root.offsetHeight * scale;
            var dockedTop = vh - base - h;
            if (rBottom > dockedTop) {
                var desired = (vh - rTop) + 8;
                var maxBottom = vh - h - 8;
                if (desired > maxBottom) desired = Math.max(base, maxBottom);
                base = desired;
            }
        }
        _root.style.bottom = base + 'px';
    }

    function open(target) {
        if (!isTextField(target)) return false;
        _target = target;
        try { target.focus({ preventScroll: true }); } catch (e) {}
        _shift = false;
        _symMode = false;
        if (!_root) build(); else _root.hidden = false;
        _r = 1; _c = 0;
        relabel();
        paint();
        positionAbove(target);
        _openAt = Date.now();
        addDismissListeners();
        playSlot('interact');
        return true;
    }

    function close() {
        if (!_root || _root.hidden) return;
        _root.hidden = true;
        _target = null;
        removeDismissListeners();
        playSlot('back');
    }

    function isOpen() { return !!(_root && !_root.hidden); }

    function move(dir) {
        if (!isOpen()) return;
        var board = LAYOUT_();
        if (dir === 'up') _r = (_r - 1 + board.length) % board.length;
        else if (dir === 'down') _r = (_r + 1) % board.length;
        else if (dir === 'left') _c = _c - 1;
        else if (dir === 'right') _c = _c + 1;
        var len = board[_r].length;
        if (_c < 0) _c = len - 1;
        if (_c >= len) _c = 0;
        paint();
        playSlot('hover');
    }

    function press() {
        if (!isOpen()) return;
        var k = LAYOUT_()[_r][_c];
        if (k === '{shift}') { _shift = !_shift; relabel(); playSlot('interact'); return; }
        if (k === '{sym}' || k === '{abc}') { _symMode = !_symMode; _shift = false; rebuild(); playSlot('interact'); return; }
        if (k === '{back}') { backspace(); playSlot('interact'); return; }
        if (k === '{done}') { close(); return; }
        if (k === '{space}') { insert(' '); playSlot('interact'); return; }
        if (k === '{enter}') {
            if (_target && _target.tagName === 'TEXTAREA') { insert('\n'); playSlot('interact'); }
            else { close(); }
            return;
        }
        insert(_shift ? (SHIFTED[k] || k.toUpperCase()) : k);
        if (_shift) { _shift = false; relabel(); }
        playSlot('interact');
    }

    // Direct button shortcuts driven from the nav layer (Y = space, X = ⌫).
    function typeSpace() { if (isOpen()) { insert(' '); playSlot('interact'); } }
    function doBackspace() { if (isOpen()) { backspace(); playSlot('interact'); } }

    // Bumpers walk the caret through the text like the arrow keys would.
    function caret(delta) {
        var el = _target;
        if (!isOpen() || !el) return;
        if (el.isContentEditable) {
            var sel = window.getSelection && window.getSelection();
            if (sel && sel.modify) sel.modify('move', delta < 0 ? 'backward' : 'forward', 'character');
        } else if (canSelect(el) && typeof el.setSelectionRange === 'function') {
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
    function shiftToggle() { if (!isOpen()) return; _shift = !_shift; relabel(); playSlot('interact'); }
    function symToggle() { if (!isOpen()) return; _symMode = !_symMode; _shift = false; rebuild(); playSlot('interact'); }

    window.MSOsk = {
        open: open, close: close, isOpen: isOpen,
        move: move, press: press, isTextField: isTextField,
        space: typeSpace, backspace: doBackspace,
        caretLeft: function() { caret(-1); }, caretRight: function() { caret(1); },
        shift: shiftToggle, symbols: symToggle,
    };
})();
