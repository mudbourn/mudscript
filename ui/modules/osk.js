(function() {
"use strict";

    // Theme-compliant on-screen keyboard for controller users. Opened by the
    // gamepad nav layer when A is pressed on a text field; driven entirely by
    // the controller (dpad picks a key, A presses it, B closes). It dismisses
    // itself the moment a real keyboard or mouse is used, so it never gets in
    // the way of someone who reaches for either.

    var LAYOUT = [
        ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
        ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
        ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', '-'],
        ['{shift}', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '{back}'],
        ['{space}', '{enter}', '{done}'],
    ];

    var SHIFTED = { '1': '!', '2': '@', '3': '#', '4': '$', '5': '%',
        '6': '^', '7': '&', '8': '*', '9': '(', '0': ')', '-': '_',
        ',': ';', '.': ':' };

    var LABELS = { '{shift}': '⇧', '{back}': '⌫', '{space}': 'space',
        '{enter}': '↵', '{done}': 'Done' };

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
            + ' max-width: 96vw; }'
            + '.osk-row { display: flex; gap: 5px; justify-content: center; }'
            + '.osk-key { min-width: 34px; height: 38px; padding: 0 8px; display: flex;'
            + ' align-items: center; justify-content: center; font-size: 15px;'
            + ' color: var(--text2, #cfcfcf); background: var(--surface2, #262626);'
            + ' border: 1px solid var(--border-dim, #2f2f2f); border-radius: var(--radius-s, 5px);'
            + ' cursor: default; transition: background 0.08s, color 0.08s, box-shadow 0.08s; }'
            + '.osk-key.osk-wide { min-width: 74px; }'
            + '.osk-key.osk-space { min-width: 200px; }'
            + '.osk-key.osk-active { color: var(--text, #fff); background: var(--hover, #333);'
            + ' box-shadow: inset 0 0 0 2px var(--accent-hi, var(--accent, #e0245e)); }'
            + '.osk-key.osk-on { color: var(--bg, #111); background: var(--accent, #e0245e);'
            + ' border-color: var(--accent, #e0245e); }';
        (document.head || document.documentElement).appendChild(s);
    }

    function keyLabel(k) {
        if (LABELS[k]) return LABELS[k];
        if (_shift) return SHIFTED[k] || k.toUpperCase();
        return k;
    }

    function build() {
        ensureStyle();
        _root = document.createElement('div');
        _root.className = 'osk';
        _keyEls = [];
        for (var r = 0; r < LAYOUT.length; r++) {
            var rowEl = document.createElement('div');
            rowEl.className = 'osk-row';
            var rowKeys = [];
            for (var c = 0; c < LAYOUT[r].length; c++) {
                var k = LAYOUT[r][c];
                var el = document.createElement('div');
                el.className = 'osk-key';
                if (k === '{space}') el.className += ' osk-space';
                else if (k === '{shift}' || k === '{back}' || k === '{enter}' || k === '{done}') el.className += ' osk-wide';
                el.textContent = keyLabel(k);
                rowEl.appendChild(el);
                rowKeys.push(el);
            }
            _root.appendChild(rowEl);
            _keyEls.push(rowKeys);
        }
        document.body.appendChild(_root);
    }

    function relabel() {
        for (var r = 0; r < LAYOUT.length; r++) {
            for (var c = 0; c < LAYOUT[r].length; c++) {
                _keyEls[r][c].textContent = keyLabel(LAYOUT[r][c]);
                _keyEls[r][c].classList.toggle('osk-on',
                    LAYOUT[r][c] === '{shift}' && _shift);
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

    function insert(text) {
        var el = _target;
        if (!el) return;
        if (el.isContentEditable) {
            el.textContent += text;
        } else if (typeof el.setRangeText === 'function') {
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
        if (typeof el.setRangeText !== 'function') {
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

    function addDismissListeners() {
        document.addEventListener('keydown', onRealKey, true);
        document.addEventListener('mousedown', onRealMouseDown, true);
        document.addEventListener('mousemove', onRealMouseMove, true);
    }
    function removeDismissListeners() {
        document.removeEventListener('keydown', onRealKey, true);
        document.removeEventListener('mousedown', onRealMouseDown, true);
        document.removeEventListener('mousemove', onRealMouseMove, true);
    }

    function open(target) {
        if (!isTextField(target)) return false;
        _target = target;
        try { target.focus({ preventScroll: true }); } catch (e) {}
        if (!_root) build(); else _root.hidden = false;
        _shift = false;
        _r = 1; _c = 0;
        relabel();
        paint();
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
        if (dir === 'up') _r = (_r - 1 + LAYOUT.length) % LAYOUT.length;
        else if (dir === 'down') _r = (_r + 1) % LAYOUT.length;
        else if (dir === 'left') _c = _c - 1;
        else if (dir === 'right') _c = _c + 1;
        var len = LAYOUT[_r].length;
        if (_c < 0) _c = len - 1;
        if (_c >= len) _c = 0;
        if (_c >= len) _c = len - 1;
        paint();
        playSlot('hover');
    }

    function press() {
        if (!isOpen()) return;
        var k = LAYOUT[_r][_c];
        if (k === '{shift}') { _shift = !_shift; relabel(); playSlot('interact'); return; }
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

    window.MSOsk = {
        open: open, close: close, isOpen: isOpen,
        move: move, press: press, isTextField: isTextField,
    };
})();
