// ms_gc_read — Gamepad input reader for mudscript (cross-platform / Windows).
//
// SDL2 port of mac/bin/ms_gc_read.swift. Emits the IDENTICAL JSON-line
// protocol so the same host glue (ms_core.lua gamepadStart) can consume it
// unchanged. Build produces ms_gc_read.exe on Windows; the same source also
// compiles on macOS/Linux against SDL2 for testing.
//
// Usage:
//   ms_gc_read              — daemon mode (events to stdout, one per line)
//   ms_gc_read --list       — list connected controllers, exit
//
// Output format (one JSON object per line, matching the Swift reader):
//   {"e":"press","b":"x","c":"ds4","p":0}
//   {"e":"release","b":"x","c":"ds4","p":0}
//   {"e":"move","b":"left","x":0.5,"y":-0.3,"c":"ds4","p":0}
//   {"e":"connect","c":"ds4","p":0}
//   {"e":"disconnect","c":"ds4","p":0}
//
// Button names: a,b,x,y,l1,r1,l2,r2,l3,r3,up,down,left,right,menu,options,home
//
// Convention notes (kept identical to the Swift reader):
//   * Stick Y is up-positive. SDL reports down-positive, so Y is negated.
//   * Stick deadzone 0.05; a move is emitted only when an axis changes > 0.01.
//   * Triggers (l2/r2) are reported as press/release buttons, not analog.

#include <SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <math.h>

#define MAX_CTRL 16
#define STICK_MAX 32767.0f
#define DEADZONE 0.05f
#define MOVE_EPS 0.01f
#define TRIGGER_PRESS 0.30f   // axis fraction at which l2/r2 count as pressed

typedef struct {
    bool inUse;
    SDL_GameController *gc;
    SDL_JoystickID id;
    const char *type;   // "ds4" | "xbox" | "switch" | "generic"
    int player;         // player slot (0-based)
    // Last-known analog state, for change detection.
    float lx, ly, rx, ry;
    bool l2, r2;        // trigger press states
} Ctrl;

static Ctrl g_ctrls[MAX_CTRL];

// ── Helpers ──────────────────────────────────────────────────────────

static const char *controller_type(SDL_GameController *gc) {
    SDL_GameControllerType t = SDL_GameControllerGetType(gc);
    switch (t) {
        case SDL_CONTROLLER_TYPE_PS3:
        case SDL_CONTROLLER_TYPE_PS4:
        case SDL_CONTROLLER_TYPE_PS5:
            return "ds4";
        case SDL_CONTROLLER_TYPE_XBOX360:
        case SDL_CONTROLLER_TYPE_XBOXONE:
            return "xbox";
        case SDL_CONTROLLER_TYPE_NINTENDO_SWITCH_PRO:
            return "switch";
        default: break;
    }
    // Fall back to the vendor name string, mirroring the Swift heuristic.
    const char *raw = SDL_GameControllerName(gc);
    if (raw) {
        char n[128];
        size_t i = 0;
        for (; raw[i] && i < sizeof(n) - 1; i++) {
            n[i] = (char)tolower((unsigned char)raw[i]);
        }
        n[i] = '\0';
        if (strstr(n, "dualshock") || strstr(n, "dualsense") || strstr(n, "sony"))
            return "ds4";
        if (strstr(n, "xbox") || strstr(n, "microsoft"))
            return "xbox";
        if (strstr(n, "switch") || strstr(n, "nintendo") || strstr(n, "pro controller"))
            return "switch";
    }
    return "generic";
}

static int player_slot(SDL_GameController *gc, int fallback) {
    int p = SDL_GameControllerGetPlayerIndex(gc);
    return p >= 0 ? p : fallback;
}

static const char *button_name(Uint8 sdlButton) {
    switch (sdlButton) {
        case SDL_CONTROLLER_BUTTON_A: return "a";
        case SDL_CONTROLLER_BUTTON_B: return "b";
        case SDL_CONTROLLER_BUTTON_X: return "x";
        case SDL_CONTROLLER_BUTTON_Y: return "y";
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: return "l1";
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return "r1";
        case SDL_CONTROLLER_BUTTON_LEFTSTICK: return "l3";
        case SDL_CONTROLLER_BUTTON_RIGHTSTICK: return "r3";
        case SDL_CONTROLLER_BUTTON_DPAD_UP: return "up";
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN: return "down";
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT: return "left";
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: return "right";
        case SDL_CONTROLLER_BUTTON_START: return "menu";
        case SDL_CONTROLLER_BUTTON_BACK: return "options";
        case SDL_CONTROLLER_BUTTON_GUIDE: return "home";
        default: return NULL;
    }
}

// ── Output ───────────────────────────────────────────────────────────

static void emit_button(const char *ev, const char *btn, const char *type, int p) {
    printf("{\"e\":\"%s\",\"b\":\"%s\",\"c\":\"%s\",\"p\":%d}\n", ev, btn, type, p);
    fflush(stdout);
}

static void emit_move(const char *stick, float x, float y, const char *type, int p) {
    // %g keeps the compact numeric form the Swift reader produced (e.g. 0.5, 0).
    printf("{\"e\":\"move\",\"b\":\"%s\",\"x\":%g,\"y\":%g,\"c\":\"%s\",\"p\":%d}\n",
           stick, (double)x, (double)y, type, p);
    fflush(stdout);
}

static void emit_conn(const char *ev, const char *type, int p) {
    printf("{\"e\":\"%s\",\"c\":\"%s\",\"p\":%d}\n", ev, type, p);
    fflush(stdout);
}

// ── Controller table ─────────────────────────────────────────────────

static Ctrl *find_by_id(SDL_JoystickID id) {
    for (int i = 0; i < MAX_CTRL; i++) {
        if (g_ctrls[i].inUse && g_ctrls[i].id == id) return &g_ctrls[i];
    }
    return NULL;
}

static void add_controller(int deviceIndex) {
    if (!SDL_IsGameController(deviceIndex)) return;
    SDL_GameController *gc = SDL_GameControllerOpen(deviceIndex);
    if (!gc) return;
    SDL_Joystick *js = SDL_GameControllerGetJoystick(gc);
    SDL_JoystickID id = SDL_JoystickInstanceID(js);
    if (find_by_id(id)) return;   // already tracked

    int slot = -1;
    for (int i = 0; i < MAX_CTRL; i++) {
        if (!g_ctrls[i].inUse) { slot = i; break; }
    }
    if (slot < 0) { SDL_GameControllerClose(gc); return; }

    Ctrl *c = &g_ctrls[slot];
    memset(c, 0, sizeof(*c));
    c->inUse = true;
    c->gc = gc;
    c->id = id;
    c->type = controller_type(gc);
    c->player = player_slot(gc, slot);
    emit_conn("connect", c->type, c->player);
}

static void remove_controller(SDL_JoystickID id) {
    Ctrl *c = find_by_id(id);
    if (!c) return;
    emit_conn("disconnect", c->type, c->player);
    if (c->gc) SDL_GameControllerClose(c->gc);
    c->inUse = false;
    c->gc = NULL;
}

// ── Axis handling ────────────────────────────────────────────────────

static float norm(Sint16 raw) {
    float v = (float)raw / STICK_MAX;
    if (v > 1.0f) v = 1.0f;
    if (v < -1.0f) v = -1.0f;
    return v;
}

static void handle_axis(Ctrl *c, Uint8 axis, Sint16 value) {
    switch (axis) {
        case SDL_CONTROLLER_AXIS_LEFTX:
        case SDL_CONTROLLER_AXIS_LEFTY: {
            float lx = norm(SDL_GameControllerGetAxis(c->gc, SDL_CONTROLLER_AXIS_LEFTX));
            float ly = -norm(SDL_GameControllerGetAxis(c->gc, SDL_CONTROLLER_AXIS_LEFTY));
            if (fabsf(lx - c->lx) > MOVE_EPS || fabsf(ly - c->ly) > MOVE_EPS) {
                c->lx = lx; c->ly = ly;
                float sx = fabsf(lx) < DEADZONE ? 0.0f : lx;
                float sy = fabsf(ly) < DEADZONE ? 0.0f : ly;
                emit_move("left", sx, sy, c->type, c->player);
            }
            break;
        }
        case SDL_CONTROLLER_AXIS_RIGHTX:
        case SDL_CONTROLLER_AXIS_RIGHTY: {
            float rx = norm(SDL_GameControllerGetAxis(c->gc, SDL_CONTROLLER_AXIS_RIGHTX));
            float ry = -norm(SDL_GameControllerGetAxis(c->gc, SDL_CONTROLLER_AXIS_RIGHTY));
            if (fabsf(rx - c->rx) > MOVE_EPS || fabsf(ry - c->ry) > MOVE_EPS) {
                c->rx = rx; c->ry = ry;
                float sx = fabsf(rx) < DEADZONE ? 0.0f : rx;
                float sy = fabsf(ry) < DEADZONE ? 0.0f : ry;
                emit_move("right", sx, sy, c->type, c->player);
            }
            break;
        }
        case SDL_CONTROLLER_AXIS_TRIGGERLEFT: {
            bool pressed = ((float)value / STICK_MAX) > TRIGGER_PRESS;
            if (pressed != c->l2) {
                c->l2 = pressed;
                emit_button(pressed ? "press" : "release", "l2", c->type, c->player);
            }
            break;
        }
        case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: {
            bool pressed = ((float)value / STICK_MAX) > TRIGGER_PRESS;
            if (pressed != c->r2) {
                c->r2 = pressed;
                emit_button(pressed ? "press" : "release", "r2", c->type, c->player);
            }
            break;
        }
        default: break;
    }
}

// ── Entry point ──────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    // Keep reading input even when the host window is not focused — the
    // mudscript host runs in the background.
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");

    if (SDL_Init(SDL_INIT_GAMECONTROLLER) != 0) {
        fprintf(stderr, "ms_gc_read: SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    bool listMode = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--list") == 0) listMode = true;
    }

    if (listMode) {
        int n = SDL_NumJoysticks();
        int found = 0;
        for (int i = 0; i < n; i++) {
            if (!SDL_IsGameController(i)) continue;
            SDL_GameController *gc = SDL_GameControllerOpen(i);
            if (!gc) continue;
            const char *name = SDL_GameControllerName(gc);
            printf("[%d] %s (%s) extended=true\n",
                   found, name ? name : "Unknown", controller_type(gc));
            SDL_GameControllerClose(gc);
            found++;
        }
        if (found == 0) fprintf(stderr, "No controllers connected.\n");
        SDL_Quit();
        return 0;
    }

    // Daemon mode.
    fprintf(stderr, "ms_gc_read: ready\n");

    // Pick up controllers already attached at launch.
    for (int i = 0; i < SDL_NumJoysticks(); i++) {
        add_controller(i);
    }

    SDL_Event ev;
    bool running = true;
    while (running) {
        // Block until an event arrives (100ms wake so signals/EOF are noticed).
        if (!SDL_WaitEventTimeout(&ev, 100)) continue;
        switch (ev.type) {
            case SDL_CONTROLLERDEVICEADDED:
                add_controller(ev.cdevice.which);
                break;
            case SDL_CONTROLLERDEVICEREMOVED:
                remove_controller(ev.cdevice.which);
                break;
            case SDL_CONTROLLERBUTTONDOWN:
            case SDL_CONTROLLERBUTTONUP: {
                Ctrl *c = find_by_id(ev.cbutton.which);
                if (!c) break;
                const char *name = button_name(ev.cbutton.button);
                if (!name) break;
                emit_button(ev.type == SDL_CONTROLLERBUTTONDOWN ? "press" : "release",
                            name, c->type, c->player);
                break;
            }
            case SDL_CONTROLLERAXISMOTION: {
                Ctrl *c = find_by_id(ev.caxis.which);
                if (!c) break;
                handle_axis(c, ev.caxis.axis, ev.caxis.value);
                break;
            }
            case SDL_QUIT:
                running = false;
                break;
            default: break;
        }
    }

    SDL_Quit();
    return 0;
}
