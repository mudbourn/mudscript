(function() {
    var tip = document.createElement("div");
    tip.className = "ms-tooltip";
    tip.setAttribute("role", "tooltip");
    document.body.appendChild(tip);

    var current = null, showTimer = null;
    var mouseX = 0, mouseY = 0;

    function textFor(el) {
        if (el.hasAttribute("title")) {
            el.setAttribute("data-tip", el.getAttribute("title"));
            el.removeAttribute("title");
        }
        return el.getAttribute("data-tip") || "";
    }
    function hide() {
        if (showTimer) { clearTimeout(showTimer); showTimer = null; }
        current = null;
        tip.classList.remove("show");
    }
    function place(el) {
        var tw = tip.offsetWidth, th = tip.offsetHeight;
        var edge = 8, x, y;
        if (el.hasAttribute("data-tip-follow")) {
            x = mouseX - tw / 2;
            y = mouseY - th - 12;
        } else {
            var r = el.getBoundingClientRect();
            x = r.left + r.width / 2 - tw / 2;
            y = r.bottom + 6;
            if (y + th + edge > window.innerHeight) y = r.top - th - 6;
        }
        x = Math.max(edge, Math.min(x, window.innerWidth - tw - edge));
        y = Math.max(edge, Math.min(y, window.innerHeight - th - edge));
        tip.style.left = Math.round(x) + "px";
        tip.style.top = Math.round(y) + "px";
    }

    document.addEventListener("mouseover", function(e) {
        var el = e.target && e.target.closest
            ? e.target.closest("[title],[data-tip]") : null;
        if (!el) return;
        var txt = textFor(el);
        if (!txt || current === el) return;
        current = el;
        if (showTimer) clearTimeout(showTimer);
        showTimer = setTimeout(function() {
            if (current !== el || !document.body.contains(el)) return;
            tip.textContent = txt;
            tip.classList.add("show");
            place(el);
        }, 350);
    });
    document.addEventListener("mouseout", function(e) {
        if (!current) return;
        var el = e.target && e.target.closest
            ? e.target.closest("[title],[data-tip]") : null;
        if (el === current) hide();
    });
    document.addEventListener("mousemove", function(e) {
        mouseX = e.clientX; mouseY = e.clientY;
        if (current && current.hasAttribute("data-tip-follow") && tip.classList.contains("show")) {
            place(current);
        }
    });
    document.addEventListener("mousedown", hide, true);
    window.addEventListener("scroll", hide, true);
    window.addEventListener("blur", hide);
})();
