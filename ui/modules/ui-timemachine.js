(function() {
    "use strict";

// State //
    var _items = [];
    var _dir = "";
    var _selected = null;
    var _pop = null;
    var _view = null;
// END State //

// Format //
    function pad(n) {
        return n < 10 ? "0" + n : String(n);
    }

    function fmtDate(sec) {
        var d = new Date(sec * 1000);
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
            + " " + pad(d.getHours()) + ":" + pad(d.getMinutes());
    }

    function fmtAge(sec) {
        var diff = Math.max(0, Math.floor(Date.now() / 1000 - sec));
        if (diff < 60) return "just now";
        if (diff < 3600) return Math.floor(diff / 60) + " min ago";
        if (diff < 86400) return Math.floor(diff / 3600) + " h ago";
        return Math.floor(diff / 86400) + " d ago";
    }

    function fmtSize(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1048576) return Math.round(bytes / 1024) + " KB";
        return (bytes / 1048576).toFixed(1) + " MB";
    }

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text != null) e.textContent = text;
        return e;
    }

    function send(action, extra) {
        var body = { action: action };
        for (var k in extra) body[k] = extra[k];
        if (window.shellPost) shellPost("settings", action, body);
    }
// END Format //

// Render //
    function selectedItem() {
        for (var i = 0; i < _items.length; i++) {
            if (_items[i].id === _selected) return _items[i];
        }
        return null;
    }

    function renderDetail(box) {
        box.innerHTML = "";
        var it = selectedItem();
        if (!it) {
            box.style.display = "none";
            return;
        }
        box.style.display = "";
        var lines = [
            ["Taken", fmtDate(it.time) + " (" + fmtAge(it.time) + ")"],
            ["Profile", it.profile || "unknown"],
            ["Reason", it.reason],
            ["Size", fmtSize(it.size || 0)],
        ];
        if (it.lastChecked && it.lastChecked - it.time >= 60) {
            lines.push(["Unchanged since", fmtDate(it.lastChecked)]);
        }
        lines.forEach(function(l) {
            var line = el("div");
            line.appendChild(el("strong", null, l[0] + ": "));
            line.appendChild(document.createTextNode(l[1]));
            box.appendChild(line);
        });
    }

    function renderList() {
        if (!_view) return;
        _view.list.innerHTML = "";
        if (!_items.length) {
            _view.list.appendChild(el("div", "tm-empty", "No backups yet."));
        }
        _items.forEach(function(it) {
            var b = el("button", "tm-item" + (it.id === _selected ? " active" : ""));
            var main = el("div", "tm-item-main");
            main.appendChild(el("div", "tm-item-date", fmtDate(it.time)));
            var sub = fmtAge(it.time) + " - " + (it.profile || "unknown profile");
            if (it.lastChecked && it.lastChecked - it.time >= 60) {
                sub += " - unchanged since " + fmtDate(it.lastChecked);
            }
            main.appendChild(el("div", "tm-item-sub", sub));
            b.appendChild(main);
            b.appendChild(el("span", "tm-badge " + it.reason, it.reason));
            b.appendChild(el("span", "tm-size", fmtSize(it.size || 0)));
            b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
            b.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                _selected = it.id;
                renderList();
            });
            _view.list.appendChild(b);
        });
        renderDetail(_view.detail);
        var has = !!selectedItem();
        _view.restore.disabled = !has;
        _view.del.disabled = !has;
    }

    function receive(items, dir) {
        _items = Array.isArray(items) ? items : [];
        _dir = dir || _dir;
        if (!selectedItem()) _selected = _items.length ? _items[0].id : null;
        renderList();
    }
// END Render //

// Open //
    function open() {
        if (!window.msPopup || (_pop && _pop.isOpen())) return;
        _pop = window.msPopup.open({
            title: "Time Machine",
            sub: "Automatic and manual snapshots of your setup. Restoring backs up the current setup first.",
            width: 520,
            noDone: true,
            onClose: function() {
                _pop = null;
                _view = null;
            },
            build: function(p) {
                var list = p.add(el("div", "tm-list"));
                var detail = p.add(el("div", "tm-detail"));
                detail.style.display = "none";
                p.actions.classList.add("fill");
                var del = p.action(p.button("Delete", function() {
                    var it = selectedItem();
                    if (it) send("backupDelete", { id: it.id });
                }, "danger"));
                p.spacer();
                p.action(p.button("Close", function() { p.close(); }, "back"));
                var restore = p.action(p.button("Restore", function() {
                    var it = selectedItem();
                    if (!it) return;
                    p.close();
                    send("backupRestore", { id: it.id });
                }, "primary"));
                _view = { list: list, detail: detail, restore: restore, del: del };
                renderList();
            },
        });
        send("backupsList", {});
    }
// END Open //

    if (window.registerPanel) {
        window.registerPanel("backups", function(action, body) {
            if (action === "list" && body) receive(body.items, body.dir);
        });
    }

    window.msTimeMachine = { open: open };
})();
