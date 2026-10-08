// ms_vpad Windows helper
#include <windows.h>
#include <setupapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

#define X360_VID 0x045E
#define X360_PID 0x028E
#define SONY_VID 0x054C
#define DS4_PID 0x05C4
#define DS4_V2_PID 0x09CC
#define SDL_TOUCHPAD 20
#define POLL_MS 2
#define DEADZONE 0.05
#define MOVE_EPS 0.01

// ViGEmBus Interface //
    static const GUID GUID_VIGEM_BUS = {
        0x96E42B22,
        0xF5E9,
        0x42F8,
        {
            0xB0,
            0x43,
            0xED,
            0x0F,
            0x93,
            0x2F,
            0x01,
            0x4F,
        },
    };

    #define VIGEM_IOCTL(i) CTL_CODE(FILE_DEVICE_BUS_EXTENDER, 0x801 + (i), METHOD_BUFFERED, FILE_WRITE_DATA)

    #define IOCTL_VIGEM_PLUGIN_TARGET VIGEM_IOCTL(0x000)
    #define IOCTL_VIGEM_UNPLUG_TARGET VIGEM_IOCTL(0x001)
    #define IOCTL_VIGEM_CHECK_VERSION VIGEM_IOCTL(0x002)
    #define IOCTL_VIGEM_WAIT_DEVICE_READY VIGEM_IOCTL(0x003)
    #define IOCTL_XUSB_SUBMIT_REPORT VIGEM_IOCTL(0x201)
    #define IOCTL_DS4_SUBMIT_REPORT VIGEM_IOCTL(0x202)

    #define TARGET_X360 0
    #define TARGET_DS4 2

    typedef struct {
        ULONG Size;
        ULONG Version;
    } VigemCheckVersion;

    typedef struct {
        ULONG Size;
        ULONG SerialNo;
        ULONG TargetType;
        USHORT VendorId;
        USHORT ProductId;
    } VigemPlugin;

    typedef struct {
        ULONG Size;
        ULONG SerialNo;
    } VigemSerial;

    typedef struct {
        USHORT wButtons;
        BYTE bLeftTrigger;
        BYTE bRightTrigger;
        SHORT sThumbLX;
        SHORT sThumbLY;
        SHORT sThumbRX;
        SHORT sThumbRY;
    } XusbReport;

    typedef struct {
        ULONG Size;
        ULONG SerialNo;
        XusbReport Report;
    } XusbSubmit;

    typedef struct {
        BYTE bThumbLX;
        BYTE bThumbLY;
        BYTE bThumbRX;
        BYTE bThumbRY;
        USHORT wButtons;
        BYTE bSpecial;
        BYTE bTriggerL;
        BYTE bTriggerR;
    } Ds4Report;

    typedef struct {
        ULONG Size;
        ULONG SerialNo;
        Ds4Report Report;
    } Ds4Submit;
// END ViGEmBus Interface //

// SDL2 Imports //
    typedef void SDL_GameController;

    static int (*SDL_Init)(unsigned);
    static int (*SDL_SetHint)(const char *, const char *);
    static const char *(*SDL_GetError)(void);
    static void (*SDL_PumpEvents)(void);
    static int (*SDL_NumJoysticks)(void);
    static int (*SDL_IsGameController)(int);
    static unsigned short (*SDL_JoystickGetDeviceVendor)(int);
    static unsigned short (*SDL_JoystickGetDeviceProduct)(int);
    static SDL_GameController *(*SDL_GameControllerOpen)(int);
    static void (*SDL_GameControllerClose)(SDL_GameController *);
    static int (*SDL_GameControllerGetAttached)(SDL_GameController *);
    static unsigned char (*SDL_GameControllerGetButton)(SDL_GameController *, int);
    static short (*SDL_GameControllerGetAxis)(SDL_GameController *, int);
    static const char *(*SDL_GameControllerName)(SDL_GameController *);
    static int (*SDL_GameControllerGetType)(SDL_GameController *);
    static unsigned short (*SDL_GameControllerGetVendor)(SDL_GameController *);
    static unsigned short (*SDL_GameControllerGetProduct)(SDL_GameController *);

    #define SDL_INIT_GAMECONTROLLER 0x00002000u

    static int loadSdl(void) {
        HMODULE m = LoadLibraryA("SDL2.dll");

        if (!m) return 0;

        #define BIND(f) if (!(f = (void *)GetProcAddress(m, #f))) return 0

        BIND(SDL_Init);
        BIND(SDL_SetHint);
        BIND(SDL_GetError);
        BIND(SDL_PumpEvents);
        BIND(SDL_NumJoysticks);
        BIND(SDL_IsGameController);
        BIND(SDL_JoystickGetDeviceVendor);
        BIND(SDL_JoystickGetDeviceProduct);
        BIND(SDL_GameControllerOpen);
        BIND(SDL_GameControllerClose);
        BIND(SDL_GameControllerGetAttached);
        BIND(SDL_GameControllerGetButton);
        BIND(SDL_GameControllerGetAxis);
        BIND(SDL_GameControllerName);
        BIND(SDL_GameControllerGetType);
        BIND(SDL_GameControllerGetVendor);
        BIND(SDL_GameControllerGetProduct);

        #undef BIND

        return 1;
    }
// END SDL2 Imports //

// Names //
    typedef struct {
        const char *name;
        int sdl;
        USHORT xusb;
        USHORT ds4;
    } ButtonDef;

    static const ButtonDef BUTTONS[] = {
        { "a", 0, 0x1000, 0x0020 },
        { "b", 1, 0x2000, 0x0040 },
        { "x", 2, 0x4000, 0x0010 },
        { "y", 3, 0x8000, 0x0080 },
        { "options", 4, 0x0020, 0x1000 },
        { "home", 5, 0x0400, 0 },
        { "menu", 6, 0x0010, 0x2000 },
        { "l3", 7, 0x0040, 0x4000 },
        { "r3", 8, 0x0080, 0x8000 },
        { "l1", 9, 0x0100, 0x0100 },
        { "r1", 10, 0x0200, 0x0200 },
        { "up", 11, 0x0001, 0 },
        { "down", 12, 0x0002, 0 },
        { "left", 13, 0x0004, 0 },
        { "right", 14, 0x0008, 0 },
    };

    #define BTN_HOME 5
    #define BTN_UP 11
    #define BTN_DOWN 12
    #define BTN_LEFT 13
    #define BTN_RIGHT 14

    #define NBUTTONS (int)(sizeof(BUTTONS) / sizeof(BUTTONS[0]))

    static const char *AXES[] = {
        "lx",
        "ly",
        "rx",
        "ry",
        "l2",
        "r2",
    };

    #define NAXES 6

    static int buttonIndex(const char *n) {
        for (int i = 0; i < NBUTTONS; i++) {
            if (strcmp(BUTTONS[i].name, n) == 0) return i;
        }

        return -1;
    }

    static int axisIndex(const char *n) {
        for (int i = 0; i < NAXES; i++) {
            if (strcmp(AXES[i], n) == 0) return i;
        }

        return -1;
    }

    static const char *padType(SDL_GameController *gc) {
        int t = SDL_GameControllerGetType(gc);

        if (t == 3 || t == 4 || t == 7) return "ds4";

        if (t == 1 || t == 2) return "xbox";

        if (t == 5) return "switch";

        const char *raw = SDL_GameControllerName(gc);
        char n[128];
        size_t i = 0;

        for (; raw && raw[i] && i < sizeof(n) - 1; i++) {
            n[i] = (char)tolower((unsigned char)raw[i]);
        }

        n[i] = 0;

        if (strstr(n, "dualshock") || strstr(n, "dualsense") || strstr(n, "sony")) return "ds4";

        if (strstr(n, "xbox") || strstr(n, "microsoft")) return "xbox";

        if (strstr(n, "switch") || strstr(n, "nintendo") || strstr(n, "pro controller")) return "switch";

        return "generic";
    }
// END Names //

// Output //
    static CRITICAL_SECTION outLock;

    static void emitRaw(const char *json) {
        EnterCriticalSection(&outLock);

        fputs(json, stdout);

        fputc('\n', stdout);

        fflush(stdout);

        LeaveCriticalSection(&outLock);
    }

    static void emitf(const char *fmt, ...) {
        char buf[512];
        va_list ap;

        va_start(ap, fmt);

        vsnprintf(buf, sizeof(buf), fmt, ap);

        va_end(ap);

        emitRaw(buf);
    }

    static void jsonEscape(const char *in, char *out, size_t cap) {
        size_t o = 0;

        for (; in && *in && o + 2 < cap; in++) {
            unsigned char c = (unsigned char)*in;

            if (c == '"' || c == '\\') out[o++] = '\\';

            out[o++] = c < 0x20 ? ' ' : (char)c;
        }

        out[o] = 0;
    }
// END Output //

// HidHide //
    static char hidHideCli[MAX_PATH];
    static char hidden[16][256];
    static int nHidden;
    static char hiddenFile[MAX_PATH];

    static void saveHidden(void) {
        FILE *f;

        if (!nHidden) {
            DeleteFileA(hiddenFile);
            return;
        }

        f = fopen(hiddenFile, "w");

        if (!f) return;

        for (int i = 0; i < nHidden; i++) {
            fprintf(f, "%s\n", hidden[i]);
        }

        fclose(f);
    }

    static void runHidHide(const char *args) {
        char cmd[1024];
        STARTUPINFOA si;
        PROCESS_INFORMATION pi;

        snprintf(cmd, sizeof(cmd), "\"%s\" %s", hidHideCli, args);

        memset(&si, 0, sizeof(si));

        si.cb = sizeof(si);

        if (!CreateProcessA(NULL, cmd, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) return;

        WaitForSingleObject(pi.hProcess, 5000);

        CloseHandle(pi.hProcess);

        CloseHandle(pi.hThread);
    }

    static void hidHideInit(void) {
        char self[MAX_PATH];
        char args[MAX_PATH + 32];
        const char *pf = getenv("ProgramFiles");

        GetModuleFileNameA(NULL, self, sizeof(self));

        snprintf(hiddenFile, sizeof(hiddenFile), "%s", self);

        strcpy(strrchr(hiddenFile, '\\') + 1, "ms_vpad.hidden");

        snprintf(hidHideCli, sizeof(hidHideCli), "%s\\Nefarius Software Solutions\\HidHide\\x64\\HidHideCLI.exe", pf ? pf : "C:\\Program Files");

        if (GetFileAttributesA(hidHideCli) == INVALID_FILE_ATTRIBUTES) {
            hidHideCli[0] = 0;
            return;
        }

        snprintf(args, sizeof(args), "--app-reg \"%s\"", self);

        runHidHide(args);
    }

    static int isHidden(const char *id) {
        for (int i = 0; i < nHidden; i++) {
            if (strcmp(hidden[i], id) == 0) return 1;
        }

        return 0;
    }

    static void hidePad(unsigned short vid, unsigned short pid) {
        char key[32];
        char id[256];
        char args[320];
        SP_DEVINFO_DATA dev;
        HDEVINFO set;

        if (!hidHideCli[0]) return;

        snprintf(key, sizeof(key), "VID_%04X&PID_%04X", vid, pid);

        set = SetupDiGetClassDevsA(NULL, NULL, NULL, DIGCF_ALLCLASSES | DIGCF_PRESENT);

        if (set == INVALID_HANDLE_VALUE) return;

        dev.cbSize = sizeof(dev);

        for (DWORD i = 0; SetupDiEnumDeviceInfo(set, i, &dev) && nHidden < 16; i++) {
            if (!SetupDiGetDeviceInstanceIdA(set, &dev, id, sizeof(id), NULL)) continue;

            if (!strstr(id, key)) continue;

            if (strncmp(id, "HID\\", 4) != 0 && strncmp(id, "USB\\", 4) != 0) continue;

            if (isHidden(id)) continue;

            strcpy(hidden[nHidden++], id);

            saveHidden();

            snprintf(args, sizeof(args), "--dev-hide \"%s\"", id);

            runHidHide(args);
        }

        SetupDiDestroyDeviceInfoList(set);

        if (nHidden) runHidHide("--cloak-on");
    }

    static void unhidePads(void) {
        char args[320];

        for (int i = 0; i < nHidden; i++) {
            snprintf(args, sizeof(args), "--dev-unhide \"%.255s\"", hidden[i]);

            runHidHide(args);
        }

        nHidden = 0;

        saveHidden();
    }

    static void unhideLeftovers(void) {
        char line[256];
        FILE *f;

        if (!hidHideCli[0]) return;

        f = fopen(hiddenFile, "r");

        if (!f) return;

        while (nHidden < 16 && fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\r\n")] = 0;

            if (line[0]) strcpy(hidden[nHidden++], line);
        }

        fclose(f);

        unhidePads();
    }
// END HidHide //

// Virtual Pad //
    static HANDLE bus = INVALID_HANDLE_VALUE;
    static ULONG serial;
    static ULONG virtType;
    static USHORT virtVid;
    static USHORT virtPid;

    static int busIoctl(DWORD code, void *buf, DWORD size) {
        DWORD got = 0;

        return DeviceIoControl(bus, code, buf, size, buf, size, &got, NULL) ? 1 : 0;
    }

    static int openBus(void) {
        SP_DEVICE_INTERFACE_DATA ifd;
        PSP_DEVICE_INTERFACE_DETAIL_DATA_A detail;
        DWORD need = 0;
        HDEVINFO set = SetupDiGetClassDevsA(&GUID_VIGEM_BUS, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        VigemCheckVersion ver;

        if (set == INVALID_HANDLE_VALUE) return 0;

        ifd.cbSize = sizeof(ifd);

        if (!SetupDiEnumDeviceInterfaces(set, NULL, &GUID_VIGEM_BUS, 0, &ifd)) {
            SetupDiDestroyDeviceInfoList(set);
            return 0;
        }

        SetupDiGetDeviceInterfaceDetailA(set, &ifd, NULL, 0, &need, NULL);

        detail = malloc(need);

        detail->cbSize = sizeof(*detail);

        if (SetupDiGetDeviceInterfaceDetailA(set, &ifd, detail, need, NULL, NULL)) {
            bus = CreateFileA(detail->DevicePath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        }

        free(detail);

        SetupDiDestroyDeviceInfoList(set);

        if (bus == INVALID_HANDLE_VALUE) return 0;

        ver.Size = sizeof(ver);
        ver.Version = 1;

        return busIoctl(IOCTL_VIGEM_CHECK_VERSION, &ver, sizeof(ver));
    }

    static int plugVirtual(ULONG type, USHORT vid, USHORT pid) {
        VigemPlugin p;
        VigemSerial w;

        for (ULONG s = 1; s <= 16; s++) {
            p.Size = sizeof(p);
            p.SerialNo = s;
            p.TargetType = type;
            p.VendorId = vid;
            p.ProductId = pid;

            if (busIoctl(IOCTL_VIGEM_PLUGIN_TARGET, &p, sizeof(p))) {
                serial = s;
                virtType = type;
                virtVid = vid;
                virtPid = pid;
                w.Size = sizeof(w);
                w.SerialNo = s;

                busIoctl(IOCTL_VIGEM_WAIT_DEVICE_READY, &w, sizeof(w));

                return 1;
            }
        }

        return 0;
    }

    static void unplugVirtual(void) {
        VigemSerial u;

        if (!serial) return;

        u.Size = sizeof(u);
        u.SerialNo = serial;

        busIoctl(IOCTL_VIGEM_UNPLUG_TARGET, &u, sizeof(u));

        serial = 0;
    }

    static void submitXusb(const XusbReport *r) {
        XusbSubmit s;

        if (!serial) return;

        s.Size = sizeof(s);
        s.SerialNo = serial;
        s.Report = *r;

        busIoctl(IOCTL_XUSB_SUBMIT_REPORT, &s, sizeof(s));
    }

    static void submitDs4(const Ds4Report *r) {
        Ds4Submit s;

        if (!serial) return;

        s.Size = sizeof(s);
        s.SerialNo = serial;
        s.Report = *r;

        busIoctl(IOCTL_DS4_SUBMIT_REPORT, &s, sizeof(s));
    }
// END Virtual Pad //

// Macro State //
    static CRITICAL_SECTION cmdLock;
    static int macroButtons[NBUTTONS];
    static int macroTrigger[2];
    static int axisSet[NAXES];
    static double axisVal[NAXES];
    static volatile LONG dirty;
    static volatile LONG stdinClosed;
    static volatile LONG padLive;

    static void handle(char *line) {
        char *cmd = strtok(line, " \r");
        char *a = strtok(NULL, " \r");
        char *b = strtok(NULL, " \r");
        int i;

        if (!cmd) return;

        if (!padLive) {
            emitRaw("{\"e\":\"error\",\"m\":\"no controller connected\"}");
            return;
        }

        EnterCriticalSection(&cmdLock);

        if (strcmp(cmd, "btn") == 0 && a && b) {
            if ((i = buttonIndex(a)) >= 0) macroButtons[i] = b[0] == '1';
            else if (strcmp(a, "l2") == 0) macroTrigger[0] = b[0] == '1';
            else if (strcmp(a, "r2") == 0) macroTrigger[1] = b[0] == '1';
        } else if (strcmp(cmd, "axis") == 0 && a && b && (i = axisIndex(a)) >= 0) {
            axisSet[i] = strcmp(b, "off") != 0;
            axisVal[i] = axisSet[i] ? atof(b) : 0;
        } else if (strcmp(cmd, "reset") == 0) {
            memset(macroButtons, 0, sizeof(macroButtons));
            memset(macroTrigger, 0, sizeof(macroTrigger));
            memset(axisSet, 0, sizeof(axisSet));
        }

        LeaveCriticalSection(&cmdLock);

        InterlockedExchange(&dirty, 1);
    }

    static DWORD WINAPI stdinThread(void *arg) {
        HANDLE in = GetStdHandle(STD_INPUT_HANDLE);
        char buf[1024];
        char line[256];
        int len = 0;
        DWORD got;

        (void)arg;

        while (ReadFile(in, buf, sizeof(buf), &got, NULL) && got > 0) {
            for (DWORD i = 0; i < got; i++) {
                if (buf[i] == '\n') {
                    line[len] = 0;
                    handle(line);
                    len = 0;
                } else if (len < (int)sizeof(line) - 1) {
                    line[len++] = buf[i];
                }
            }
        }

        InterlockedExchange(&stdinClosed, 1);

        return 0;
    }
// END Macro State //

// Physical Pad //
    typedef struct {
        SDL_GameController *gc;
        const char *type;
        int buttons[NBUTTONS];
        int trig[2];
        int touch;
        double axes[NAXES];
        double sent[NAXES];
    } Pad;

    static Pad pad;

    static int isVirtual(int index) {
        return virtVid && SDL_JoystickGetDeviceVendor(index) == virtVid && SDL_JoystickGetDeviceProduct(index) == virtPid;
    }

    static double dz(double v) {
        return fabs(v) < DEADZONE ? 0 : v;
    }

    static double stickNorm(short raw) {
        double v = raw / 32767.0;

        return v < -1 ? -1 : v;
    }

    static void physical(const char *body) {
        emitf("{\"e\":\"pad\",\"ev\":{%s,\"c\":\"%s\",\"p\":1}}", body, pad.type);
    }

    static int readPad(void) {
        int changed = 0;
        char body[160];

        for (int i = 0; i < NBUTTONS; i++) {
            int now = SDL_GameControllerGetButton(pad.gc, BUTTONS[i].sdl) ? 1 : 0;

            if (now != pad.buttons[i]) {
                pad.buttons[i] = now;
                changed = 1;
                snprintf(body, sizeof(body), "\"e\":\"%s\",\"b\":\"%s\"", now ? "press" : "release", BUTTONS[i].name);

                physical(body);
            }
        }

        int touch = SDL_GameControllerGetButton(pad.gc, SDL_TOUCHPAD) ? 1 : 0;

        if (touch != pad.touch) {
            pad.touch = touch;
            changed = 1;
        }

        for (int i = 0; i < NAXES; i++) {
            short raw = SDL_GameControllerGetAxis(pad.gc, i);
            double v = i < 4 ? stickNorm(raw) : raw / 32767.0;

            if (v != pad.axes[i]) changed = 1;

            pad.axes[i] = v;
        }

        for (int t = 0; t < 2; t++) {
            double v = pad.axes[4 + t];
            int now = v > 0.5;

            if (now != pad.trig[t]) {
                pad.trig[t] = now;
                snprintf(body, sizeof(body), "\"e\":\"%s\",\"b\":\"%s\"", now ? "press" : "release", AXES[4 + t]);

                physical(body);
            }

            if (fabs(v - pad.sent[4 + t]) > MOVE_EPS) {
                pad.sent[4 + t] = v;
                snprintf(body, sizeof(body), "\"e\":\"trigger\",\"b\":\"%s\",\"v\":%.4f", AXES[4 + t], v);

                physical(body);
            }
        }

        for (int s = 0; s < 2; s++) {
            double x = pad.axes[s * 2];
            double y = pad.axes[s * 2 + 1];

            if (fabs(x - pad.sent[s * 2]) > MOVE_EPS || fabs(y - pad.sent[s * 2 + 1]) > MOVE_EPS) {
                pad.sent[s * 2] = x;
                pad.sent[s * 2 + 1] = y;
                snprintf(body, sizeof(body), "\"e\":\"move\",\"b\":\"%s\",\"x\":%.4f,\"y\":%.4f", s ? "right" : "left", dz(x), dz(-y));

                physical(body);
            }
        }

        return changed;
    }

    static short toThumb(double v) {
        if (v > 1) v = 1;

        if (v < -1) v = -1;

        return (short)(v * 32767);
    }

    static BYTE toTrigger(double v) {
        if (v > 1) v = 1;

        if (v < 0) v = 0;

        return (BYTE)(v * 255);
    }

    static BYTE toDs4Stick(double v) {
        if (v > 1) v = 1;

        if (v < -1) v = -1;

        return (BYTE)lround((v + 1) * 127.5);
    }

    static USHORT ds4Hat(int up, int down, int left, int right) {
        static const USHORT HAT[3][3] = {
            {
                7,
                0,
                1,
            },
            {
                6,
                8,
                2,
            },
            {
                5,
                4,
                3,
            },
        };
        int row = up && !down ? 0 : down && !up ? 2 : 1;
        int col = left && !right ? 0 : right && !left ? 2 : 1;

        return HAT[row][col];
    }

    static void composeDs4(const int *held, const double *ax) {
        Ds4Report r;

        memset(&r, 0, sizeof(r));

        for (int i = 0; i < NBUTTONS; i++) {
            if (held[i]) r.wButtons |= BUTTONS[i].ds4;
        }

        r.wButtons |= ds4Hat(held[BTN_UP], held[BTN_DOWN], held[BTN_LEFT], held[BTN_RIGHT]);

        if (ax[4] > 0.5) r.wButtons |= 0x0400;

        if (ax[5] > 0.5) r.wButtons |= 0x0800;

        r.bSpecial = (held[BTN_HOME] ? 0x01 : 0) | (pad.touch ? 0x02 : 0);
        r.bThumbLX = toDs4Stick(ax[0]);
        r.bThumbLY = toDs4Stick(ax[1]);
        r.bThumbRX = toDs4Stick(ax[2]);
        r.bThumbRY = toDs4Stick(ax[3]);
        r.bTriggerL = toTrigger(ax[4]);
        r.bTriggerR = toTrigger(ax[5]);

        submitDs4(&r);
    }

    static void composeXusb(const int *held, const double *ax) {
        XusbReport r;

        memset(&r, 0, sizeof(r));

        for (int i = 0; i < NBUTTONS; i++) {
            if (held[i]) r.wButtons |= BUTTONS[i].xusb;
        }

        r.sThumbLX = toThumb(ax[0]);
        r.sThumbLY = toThumb(-ax[1]);
        r.sThumbRX = toThumb(ax[2]);
        r.sThumbRY = toThumb(-ax[3]);
        r.bLeftTrigger = toTrigger(ax[4]);
        r.bRightTrigger = toTrigger(ax[5]);

        submitXusb(&r);
    }

    static void compose(void) {
        int held[NBUTTONS];
        double ax[NAXES];

        EnterCriticalSection(&cmdLock);

        for (int i = 0; i < NBUTTONS; i++) {
            held[i] = pad.buttons[i] || macroButtons[i];
        }

        for (int i = 0; i < NAXES; i++) {
            ax[i] = axisSet[i] ? axisVal[i] : pad.axes[i];
        }

        if (macroTrigger[0]) ax[4] = 1;

        if (macroTrigger[1]) ax[5] = 1;

        LeaveCriticalSection(&cmdLock);

        if (virtType == TARGET_DS4) composeDs4(held, ax);
        else composeXusb(held, ax);
    }

    static int plugClone(unsigned short vid, unsigned short pid) {
        if (strcmp(pad.type, "ds4") != 0) return plugVirtual(TARGET_X360, X360_VID, X360_PID);

        if (vid == SONY_VID && (pid == DS4_PID || pid == DS4_V2_PID)) return plugVirtual(TARGET_DS4, vid, pid);

        return plugVirtual(TARGET_DS4, SONY_VID, DS4_V2_PID);
    }

    static void attach(int index) {
        char name[160];
        unsigned short vid;
        unsigned short pid;

        memset(&pad, 0, sizeof(pad));

        pad.gc = SDL_GameControllerOpen(index);

        if (!pad.gc) return;

        for (int i = 0; i < NAXES; i++) {
            pad.sent[i] = 9;
        }

        pad.type = padType(pad.gc);
        vid = SDL_GameControllerGetVendor(pad.gc);
        pid = SDL_GameControllerGetProduct(pad.gc);

        hidePad(vid, pid);

        if (!plugClone(vid, pid)) {
            emitRaw("{\"e\":\"error\",\"m\":\"ViGEmBus refused the virtual pad\"}");
            SDL_GameControllerClose(pad.gc);
            pad.gc = NULL;
            unhidePads();
            return;
        }

        jsonEscape(SDL_GameControllerName(pad.gc), name, sizeof(name));

        emitf("{\"e\":\"ready\",\"name\":\"%s\",\"vid\":%u,\"pid\":%u}", name, vid, pid);

        if (!hidHideCli[0]) emitRaw("{\"e\":\"nohidhide\"}");

        physical("\"e\":\"connect\"");

        InterlockedExchange(&padLive, 1);

        readPad();

        compose();
    }

    static void detach(void) {
        InterlockedExchange(&padLive, 0);

        physical("\"e\":\"disconnect\"");

        emitRaw("{\"e\":\"lost\"}");

        SDL_GameControllerClose(pad.gc);

        pad.gc = NULL;

        unplugVirtual();

        EnterCriticalSection(&cmdLock);

        memset(macroButtons, 0, sizeof(macroButtons));
        memset(macroTrigger, 0, sizeof(macroTrigger));
        memset(axisSet, 0, sizeof(axisSet));

        LeaveCriticalSection(&cmdLock);
    }

    static int cloneIds(int index) {
        unsigned short vid = SDL_JoystickGetDeviceVendor(index);
        unsigned short pid = SDL_JoystickGetDeviceProduct(index);

        if (vid == X360_VID && pid == X360_PID) return 1;

        return vid == SONY_VID && (pid == DS4_PID || pid == DS4_V2_PID);
    }

    static void findPad(void) {
        int n = SDL_NumJoysticks();

        for (int pass = 0; pass < 2 && !pad.gc; pass++) {
            for (int i = 0; i < n && !pad.gc; i++) {
                if (!SDL_IsGameController(i) || isVirtual(i)) continue;

                if (pass == 0 && cloneIds(i)) continue;

                attach(i);
            }
        }
    }
// END Physical Pad //

// Main //
    static void teardown(void) {
        if (pad.gc) detach();

        unhidePads();

        if (bus != INVALID_HANDLE_VALUE) CloseHandle(bus);
    }

    static BOOL WINAPI onConsole(DWORD sig) {
        (void)sig;

        teardown();

        ExitProcess(0);

        return TRUE;
    }

    static LONG WINAPI onCrash(EXCEPTION_POINTERS *info) {
        (void)info;

        unhidePads();

        return EXCEPTION_CONTINUE_SEARCH;
    }

    int main(int argc, char **argv) {
        InitializeCriticalSection(&outLock);

        InitializeCriticalSection(&cmdLock);

        hidHideInit();

        unhideLeftovers();

        if (argc > 1 && strcmp(argv[1], "--unhide") == 0) return 0;

        SetUnhandledExceptionFilter(onCrash);

        if (!loadSdl()) {
            emitRaw("{\"e\":\"error\",\"m\":\"SDL2.dll not found beside ms_vpad.exe\"}");
            return 2;
        }

        if (!openBus()) {
            emitRaw("{\"e\":\"error\",\"m\":\"ViGEmBus driver not installed\"}");
            return 3;
        }

        SDL_SetHint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1");

        SDL_SetHint("SDL_JOYSTICK_RAWINPUT", "0");

        if (SDL_Init(SDL_INIT_GAMECONTROLLER) != 0) {
            emitRaw("{\"e\":\"error\",\"m\":\"SDL init failed\"}");
            return 4;
        }

        SetConsoleCtrlHandler(onConsole, TRUE);

        CreateThread(NULL, 0, stdinThread, NULL, 0, NULL);

        emitRaw("{\"e\":\"waiting\"}");

        while (!stdinClosed) {
            SDL_PumpEvents();

            if (pad.gc && !SDL_GameControllerGetAttached(pad.gc)) {
                detach();
            }

            if (!pad.gc) {
                findPad();
            } else {
                int changed = readPad();

                if (changed || InterlockedExchange(&dirty, 0)) compose();
            }

            Sleep(POLL_MS);
        }

        teardown();

        return 0;
    }
// END Main //
