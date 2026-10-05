(function() {
    var _drag = null;
    var header = document.querySelector('.panel-popped #header');
    if (!header) return;
    header.addEventListener('mousedown', function(e) {
        if (e.button !== 0) return;
        if (e.target.closest('.header-btns')) return;
        _drag = { ox: e.screenX, oy: e.screenY };
        function onMove(ev) {
            if (!_drag) return;
            shellDispatch('_shell', 'move', { dx: ev.screenX - _drag.ox, dy: ev.screenY - _drag.oy });
            _drag.ox = ev.screenX;
            _drag.oy = ev.screenY;
        }
        function onUp() {
            _drag = null;
            window.removeEventListener('mousemove', onMove);
            window.removeEventListener('mouseup', onUp);
        }
        window.addEventListener('mousemove', onMove);
        window.addEventListener('mouseup', onUp);
    });
})();

(function() {
"use strict";

window.shellDispatch = function(panel, action, body) {
    try {
        window.webkit.messageHandlers.msShell.postMessage(
            JSON.stringify({ panel: panel, action: action, body: body })
        );
    } catch(e) {}
};

window.shellPost = function(panel, action, body) {
    shellDispatch(panel, action, body);
};

function _postJsError(kind, msg, src, line, col, stack) {
    try {
        window.webkit.messageHandlers.msShell.postMessage(
            JSON.stringify({ panel: "_shell", action: "jsError", body: {
                kind: kind, msg: String(msg == null ? "" : msg),
                src: src || "", line: line || 0, col: col || 0,
                stack: stack ? String(stack) : ""
            } })
        );
    } catch(e) {}
}
window.addEventListener("error", function(e) {
    _postJsError("error", e && e.message, e && e.filename,
        e && e.lineno, e && e.colno, e && e.error && e.error.stack);
});
window.addEventListener("unhandledrejection", function(e) {
    var r = e && e.reason;
    _postJsError("unhandledrejection", r && (r.message || r),
        "", 0, 0, r && r.stack);
});

var _panelHandlers = {};
window.registerPanel = function(name, handler) {
    _panelHandlers[name] = handler;
};

(function() {
    var kinds = {};
    var answered = {};
    var retryTimers = {};
    var cache = {};
    var subs = {};
    function post(action, body) {
        if (window.shellPost) window.shellPost('library', action,
            Object.assign({ action: action }, body || {}));
    }
    function requestUntilAnswered(kind) {
        post('libraryList', { kind: kind });
        if (answered[kind] || retryTimers[kind]) return;
        var attempts = 0;
        retryTimers[kind] = setInterval(function() {
            if (answered[kind] || attempts >= 10) {
                clearInterval(retryTimers[kind]);
                retryTimers[kind] = null;
                return;
            }
            attempts++;
            post('libraryList', { kind: kind });
        }, 500);
    }
    window.msLibraryClient = {
        on:       function(kind, fn) { kinds[kind] = fn; },
        request:  function(kind) { requestUntilAnswered(kind); },
        get:      function(kind) { return cache[kind] ? cache[kind].slice() : []; },
        subscribe: function(kind, fn) {
            (subs[kind] = subs[kind] || []).push(fn);
            if (cache[kind]) { try { fn(cache[kind].slice()); } catch (e) {} }
            requestUntilAnswered(kind);
        },
        activate: function(kind, slug, name) {
            post('libraryActivate', { kind: kind, slug: slug, name: name });
        },
        remove:   function(kind, slug) { post('libraryRemove', { kind: kind, slug: slug }); },
        capture:  function(kind, name) { post('libraryCapture', { kind: kind, name: name }); },
        rename:   function(kind, slug, name) { post('libraryRename', { kind: kind, slug: slug, name: name }); },
        createEmpty: function(kind, name, seed) { post('libraryCreateEmpty', { kind: kind, name: name, seed: seed === true }); },
        clear:    function(kind) { post('libraryClear', { kind: kind }); },
    };
    window.registerPanel('library', function(kind, payload) {
        answered[kind] = true;
        if (retryTimers[kind]) {
            clearInterval(retryTimers[kind]);
            retryTimers[kind] = null;
        }
        var entries = (payload && payload.entries) || [];
        cache[kind] = entries;
        var fn = kinds[kind];
        if (fn) fn(entries.slice());
        var list = subs[kind];
        if (list) for (var i = 0; i < list.length; i++) {
            try { list[i](entries.slice()); } catch (e) {}
        }
    });
})();

(function() {
    var subs = [];
    var cache = null;
    var answered = false, retry = null, attempts = 0;
    function post() {
        if (window.shellPost) {
            window.shellPost('macros', 'profilesList', { action: 'profilesList' });
        }
    }
    function requestUntilAnswered() {
        post();
        if (answered || retry) return;
        attempts = 0;
        retry = setInterval(function() {
            if (answered || attempts >= 10) {
                clearInterval(retry); retry = null; return;
            }
            attempts++;
            post();
        }, 500);
    }
    window.msProfilesClient = {
        request: requestUntilAnswered,
        get: function() { return cache ? cache.slice() : []; },
        subscribe: function(fn) {
            subs.push(fn);
            if (cache) { try { fn(cache.slice()); } catch (e) {} }
            requestUntilAnswered();
        },
    };
    window.registerPanel('profileList', function(action, payload) {
        answered = true;
        if (retry) { clearInterval(retry); retry = null; }
        cache = (payload && payload.entries) || [];
        for (var i = 0; i < subs.length; i++) {
            try { subs[i](cache.slice()); } catch (e) {}
        }
    });
})();

document.addEventListener("contextmenu", function(e) {
    var t = e.target;
    if (t && t.closest && t.closest(".allow-native-menu")) return;
    e.preventDefault();
});

window.shellReceive = function(panel, action, body) {
    if (action === 'poppedOut') {
        window._poppedOutPanels[panel] = true;
        var railItem = document.querySelector('.rail-item[data-panel="' + panel + '"]');
        if (railItem) {
            railItem.classList.add('popped-out');
            railItem.classList.remove('active');
        }
        var inlinePanel = document.querySelector('.panel-' + panel);
        if (inlinePanel) inlinePanel.style.display = 'none';
        if (currentPanel === panel) {
            var names = { console: 'Console', watcher: 'Macro Monitor', keys: 'Input Monitor', window: 'Window Monitor' };
            var label = document.getElementById('popped-label');
            if (label) label.textContent = (names[panel] || panel) + ' is popped out';
            document.querySelectorAll('[class^="panel-"]').forEach(function(el) { el.style.display = 'none'; });
            var popped = document.querySelector('.panel-popped');
            if (popped) popped.style.display = 'flex';
            document.querySelectorAll('.rail-item').forEach(function(btn) { btn.classList.remove('active'); });
            currentPanel = '_popped';
            shellDispatch('_shell', 'navigate', { panel: '_popped' });
        }
        return;
    }
    if (action === 'poppedIn') {
        delete window._poppedOutPanels[panel];
        var railItem = document.querySelector('.rail-item[data-panel="' + panel + '"]');
        if (railItem) railItem.classList.remove('popped-out');
        var fn = window._panelPoppedInFns[panel];
        if (fn) { try { fn(); } catch(e) {} }
        showPanel(panel);
        return;
    }
    var handler = _panelHandlers[panel];
    if (handler) {
        try { handler(action, body); } catch(e) {
            console.error("[shell] panel handler error:", panel, action, e);
        }
    }
};

window.currentPanel = 'console';

window._poppedOutPanels = {};
window._panelPoppedInFns = {};

window.popOutPanel = function(id) {
    shellDispatch('_shell', 'popOut', { panel: id });
};

window._panelPauseFns = {};
window.togglePause = function() {
    var fn = window._panelPauseFns[window.currentPanel];
    if (fn) fn();
};

window._panelClearFns = {};
window.clearLog = function() {
    var fn = window._panelClearFns[window.currentPanel];
    if (fn) fn();
};

window.setPanelWatermark = function(id) {
    var wm = document.getElementById('panel-watermark');
    if (!wm) return;
    var src = document.querySelector('.rail-item[data-panel="' + id + '"] .icon');
    wm.textContent = '';
    if (src) wm.appendChild(src.cloneNode(true));
};

window.showPanel = function(id) {
    setPanelWatermark(id);
    if (window._poppedOutPanels[id]) {
        var names = { console: 'Console', watcher: 'Macro Monitor', keys: 'Input Monitor', window: 'Window Monitor' };
        var label = document.getElementById('popped-label');
        if (label) label.textContent = (names[id] || id) + ' is popped out';
        document.querySelectorAll('[class^="panel-"]').forEach(function(el) { el.style.display = 'none'; });
        var popped = document.querySelector('.panel-popped');
        if (popped) popped.style.display = 'flex';
        document.querySelectorAll('.rail-item').forEach(function(btn) { btn.classList.remove('active'); });
        var railItem = document.querySelector('.rail-item[data-panel="' + id + '"]');
        if (railItem) railItem.classList.add('active');
        currentPanel = '_popped';
        shellDispatch('_shell', 'navigate', { panel: '_popped' });
        shellDispatch('_shell', 'focusPopOut', { panel: id });
        return;
    }
    document.querySelectorAll('[class^="panel-"]').forEach(function(el) {
        el.style.display = 'none';
    });
    var target = document.querySelector('.panel-' + id);
    if (target) target.style.display = 'flex';
    document.querySelectorAll('.rail-item').forEach(function(btn) {
        btn.classList.toggle('active', btn.dataset.panel === id);
    });
    currentPanel = id;
    shellDispatch('_shell', 'navigate', { panel: id });
    if (id === 'console' && typeof window._maybeShowConsoleDanger === 'function') {
        window._maybeShowConsoleDanger();
    }
};

(function() {
    function railItems() {
        return Array.prototype.slice.call(document.querySelectorAll('.rail-item[data-panel]'))
            .filter(function(b) {
                var r = b.getBoundingClientRect();
                return (r.width || r.height) && !b.classList.contains('popped-out');
            });
    }

    window.installGpNav({
        scope: function() {
            if (currentPanel === '_popped') return null;
            return document.querySelector('.panel-' + currentPanel);
        },
        panelKey: function() { return currentPanel; },
        sound: function(slot) { shellDispatch('_shell', 'playSlot', { slot: slot }); },
        closeRoot: function() { shellDispatch('_shell', 'close', {}); },
        announce: function(text) { shellDispatch('_shell', 'announce', { text: text }); },
        toggleRail: function() {
            if (window._shellToggleRail) window._shellToggleRail();
            else document.body.classList.toggle('rail-collapsed');
        },
        switchWindow: function() {
            if (typeof popOutPanel === 'function') popOutPanel(currentPanel);
        },
        switchPanel: function(delta) {
            var items = railItems();
            if (!items.length) return;
            var cur = -1;
            for (var i = 0; i < items.length; i++) {
                if (items[i].getAttribute('data-panel') === currentPanel) { cur = i; break; }
            }
            var ni = cur === -1 ? 0 : cur + delta;
            if (ni < 0) ni = items.length - 1;
            if (ni >= items.length) ni = 0;
            shellDispatch('_shell', 'playSlot', { slot: 'interact' });
            showPanel(items[ni].getAttribute('data-panel'));
            if (window.gpNavInit) window.gpNavInit();
        },
    });
})();

window._shellApplyTheme = function(theme) {
    if (!theme || typeof theme !== 'object') return;
    var r = document.documentElement.style;
    if (theme.bg) r.setProperty('--bg', theme.bg);
    if (theme.surface) r.setProperty('--surface', theme.surface);
    if (theme.surface2) r.setProperty('--surface2', theme.surface2);
    if (theme.hover) r.setProperty('--hover', theme.hover);
    if (theme.surface3) {
        r.setProperty('--surface3', theme.surface3);
    } else if (theme.surface2 && theme.hover) {
        var _hx = function(h) {
            h = String(h).replace('#', '').replace(/^(.)(.)(.)$/, '$1$1$2$2$3$3').slice(0, 6);
            if (h.length !== 6) return null;
            var n = parseInt(h, 16);
            if (isNaN(n)) return null;
            return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
        };
        var s2 = _hx(theme.surface2), hv = _hx(theme.hover);
        if (s2 && hv) {
            var mix = function(i) { return Math.floor((s2[i] + hv[i]) / 2); };
            r.setProperty('--surface3', 'rgb('
                + mix(0) + ',' + mix(1) + ',' + mix(2) + ')');
        }
    }
    if (theme.accent) r.setProperty('--accent', theme.accent);
    if (theme.accentHi) r.setProperty('--accent-hi', theme.accentHi);
    if (theme.success) r.setProperty('--success', theme.success);
    if (theme.dangerBg) r.setProperty('--danger-bg', theme.dangerBg);
    if (theme.danger) r.setProperty('--danger', theme.danger);
    if (theme.warning) r.setProperty('--warning', theme.warning);
    if (theme.text) r.setProperty('--text', theme.text);
    if (theme.text2) r.setProperty('--text2', theme.text2);
    if (theme.text3) r.setProperty('--text3', theme.text3);
    if (theme.border) r.setProperty('--border', theme.border);
    if (theme.borderDim) r.setProperty('--border-dim', theme.borderDim);
    if (theme.accentGlow) r.setProperty('--accent-glow', theme.accentGlow);
    if (theme.accentGlowFaint) r.setProperty('--accent-glow-faint', theme.accentGlowFaint);
    if (theme.dangerGlow) r.setProperty('--danger-glow', theme.dangerGlow);
    if (theme.dangerBorder) r.setProperty('--danger-border', theme.dangerBorder);
    if (theme.key) r.setProperty('--key', theme.key);
    if (theme.mouse) r.setProperty('--mouse', theme.mouse);
    if (theme.scroll) r.setProperty('--scroll', theme.scroll);
    if (theme.radius !== undefined) {
        r.setProperty('--radius', theme.radius + 'px');
        r.setProperty('--radius-s', Math.max(0, theme.radius - 1) + 'px');
    }
    if (theme.font) {
        if (theme.fontURL) {
            var el = document.getElementById('_ms-custom-font');
            if (!el) { el = document.createElement('style'); el.id = '_ms-custom-font'; document.head.appendChild(el); }
            el.textContent = '@font-face { font-family: "' + theme.font + '"; src: url("' + theme.fontURL + '"); }';
        }
        document.documentElement.style.setProperty('--font', '"' + theme.font + '", Arial, Helvetica, sans-serif');
    }
    if (window.consoleApplyTheme) window.consoleApplyTheme(theme);
    if (window.watcherApplyTheme) window.watcherApplyTheme(theme);
    if (window.keysApplyTheme) window.keysApplyTheme(theme);
    if (window.windowApplyTheme) window.windowApplyTheme(theme);
    if (window.settingsApplyTheme) window.settingsApplyTheme(theme);
};

window.applyTheme = window._shellApplyTheme;

document.querySelectorAll('.rail-item').forEach(function(btn) {
    btn.addEventListener('mouseenter', function() {
        shellDispatch('_shell', 'playSlot', { slot: 'hover' });
    });
    btn.addEventListener('click', function() {
        var panel = btn.getAttribute('data-panel');
        if (!panel) return;
        if (currentPanel === panel && !window._poppedOutPanels[panel]) {
            shellDispatch('_shell', 'playSlot', { slot: 'back' });
            return;
        }
        shellDispatch('_shell', 'playSlot', { slot: 'interact' });
        showPanel(panel);
    });
});

var _kbNav = false;
document.addEventListener('keydown', function(e) {
    if (e.key === 'Tab' || (e.key && e.key.indexOf('Arrow') === 0)) _kbNav = true;
}, true);

document.addEventListener('keydown', function(e) {
    if (e.key !== 'Enter' || e.isComposing || e.defaultPrevented) return;
    var t = e.target;
    if (!t || t.tagName !== 'INPUT') return;
    var type = (t.type || 'text').toLowerCase();
    if (type === 'checkbox' || type === 'radio' || type === 'button'
        || type === 'submit' || type === 'reset' || type === 'range'
        || type === 'file' || type === 'color') return;
    if (t.id === 'code-input' || t.classList.contains('ms-pop-input')) return;
    t.blur();
}, true);
document.addEventListener('keydown', function(e) {
    if (msMod(e) && (e.key === 'p' || e.key === 'P')) {
        e.preventDefault();
    }
}, true);
document.addEventListener('keydown', function(e) {
    if (!msMod(e) || e.altKey) return;
    var k = e.key;
    var msg = null;
    if (k === '=' || k === '+') msg = { delta: 0.1 };
    else if (k === '-' || k === '_') msg = { delta: -0.1 };
    else if (k === '0') msg = { reset: true };
    if (!msg) return;
    e.preventDefault();
    if (window.shellPost) {
        window.shellPost('settings', 'setUiZoom',
            Object.assign({ action: 'setUiZoom' }, msg));
    }
}, true);

try { window.print = function() {}; } catch (e) {}

document.addEventListener('mousedown', function() { _kbNav = false; }, true);
document.addEventListener('focusin', function() {
    if (_kbNav && window.playSlot) playSlot('hover');
});
document.addEventListener('focusin', function(e) {
    var t = e.target;
    if (!t) return;
    if (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable) {
        t.setAttribute('autocapitalize', 'off');
        t.setAttribute('autocorrect', 'off');
        t.setAttribute('spellcheck', 'false');
        if (t.tagName === 'INPUT' && !t.hasAttribute('autocomplete')) {
            t.setAttribute('autocomplete', 'off');
        }
    }
});

(function() {
    var body = document.body;
    var root = document.getElementById('shell-root');
    var divider = document.getElementById('rail-divider');
    var handle = document.getElementById('rail-handle');
    if (!root || !divider || !handle) return;

    var KEY_COLLAPSED = 'ms.rail.collapsed';
    var KEY_HANDLE_Y = 'ms.rail.handleY';
    var KEY_WIDTH = 'ms.rail.width';
    var HOT_ZONE = 52;
    var RAIL_MIN = 140;
    var RAIL_MAX = Math.round(RAIL_MIN * 2.15);

    function currentRailW() {
        var v = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rail-w'));
        return isNaN(v) ? RAIL_MIN : v;
    }
    function setRailW(w) {
        w = Math.max(RAIL_MIN, Math.min(w, RAIL_MAX));
        document.documentElement.style.setProperty('--rail-w', w + 'px');
    }

    var hot = false;
    function setHot(on) {
        if (on === hot) return;
        hot = on;
        body.classList.toggle('rail-hot', on);
    }

    function clampY(y) {
        var h = handle.offsetHeight || 46;
        return Math.max(8, Math.min(y, root.clientHeight - h - 8));
    }
    function placeHandle(y) { handle.style.top = clampY(y) + 'px'; }
    function restoreHandleY() {
        var v = null;
        try { v = localStorage.getItem(KEY_HANDLE_Y); } catch (e) {}
        if (v != null) { placeHandle(parseFloat(v)); return; }
        var vh = root.clientHeight || window.innerHeight || 0;
        if (vh <= 0) { requestAnimationFrame(restoreHandleY); return; }
        placeHandle((vh - (handle.offsetHeight || 46)) / 2);
    }
    function persistCollapsed(on) {
        try { localStorage.setItem(KEY_COLLAPSED, on ? '1' : '0'); } catch (e) {}
    }

    function collapse() {
        body.classList.add('rail-collapsed');
        restoreHandleY();
        setHot(false);
        persistCollapsed(true);
        shellDispatch('_shell', 'playSlot', { slot: 'back' });
    }
    function expand() {
        body.classList.remove('rail-collapsed');
        setHot(false);
        persistCollapsed(false);
        shellDispatch('_shell', 'playSlot', { slot: 'interact' });
    }
    window._shellToggleRail = function() {
        if (body.classList.contains('rail-collapsed')) expand();
        else collapse();
    };

    divider.addEventListener('mouseenter', function() {
        shellDispatch('_shell', 'playSlot', { slot: 'hover' });
    });

    var rResizing = false, rMoved = false, rStartX = 0, rStartW = 0;
    divider.addEventListener('mousedown', function(e) {
        rResizing = true; rMoved = false;
        rStartX = e.clientX;
        rStartW = currentRailW();
        body.classList.add('rail-resizing');
        e.preventDefault();
    });
    document.addEventListener('mousemove', function(e) {
        if (!rResizing) return;
        var dx = e.clientX - rStartX;
        if (Math.abs(dx) > 3) rMoved = true;
        setRailW(rStartW + dx);
    });
    document.addEventListener('mouseup', function() {
        if (!rResizing) return;
        rResizing = false;
        body.classList.remove('rail-resizing');
        if (rMoved) {
            try { localStorage.setItem(KEY_WIDTH, currentRailW()); } catch (e) {}
        } else {
            collapse();
        }
    });

    var dragging = false, moved = false, startY = 0, startTop = 0;
    handle.addEventListener('mousedown', function(e) {
        dragging = true; moved = false;
        startY = e.clientY;
        startTop = parseFloat(handle.style.top) || 0;
        handle.classList.add('dragging');
        e.preventDefault();
    });
    document.addEventListener('mousemove', function(e) {
        if (dragging) {
            var dy = e.clientY - startY;
            if (Math.abs(dy) > 3) moved = true;
            placeHandle(startTop + dy);
            return;
        }
        setHot(body.classList.contains('rail-collapsed') && e.clientX <= HOT_ZONE);
    });
    document.addEventListener('mouseup', function(e) {
        if (!dragging) return;
        dragging = false;
        handle.classList.remove('dragging');
        if (moved) {
            try { localStorage.setItem(KEY_HANDLE_Y, parseFloat(handle.style.top) || 0); } catch (err) {}
            setHot(e.clientX <= HOT_ZONE);
        } else {
            expand();
        }
    });
    window.addEventListener('resize', function() {
        if (body.classList.contains('rail-collapsed')) placeHandle(parseFloat(handle.style.top) || 0);
    });

    var savedW = null;
    try { savedW = localStorage.getItem(KEY_WIDTH); } catch (e) {}
    if (savedW != null) setRailW(parseFloat(savedW));

    var wasCollapsed = false;
    try { wasCollapsed = localStorage.getItem(KEY_COLLAPSED) === '1'; } catch (e) {}
    if (wasCollapsed) { body.classList.add('rail-collapsed'); restoreHandleY(); }
})();

document.addEventListener('DOMContentLoaded', function() {
    shellDispatch('_shell', 'ready', { version: '0.2.0' });
    showPanel('macros');
});

})();
