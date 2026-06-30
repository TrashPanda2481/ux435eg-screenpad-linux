/*
 * wmi-set.c. Minimal C fallback for driving the ASUS UX435EG ScreenPad
 *
 * Same job as ux435-screenpad (the Python), but as a single self-contained
 * binary you can drop into a rescue initramfs / recovery shell where Python
 * may not be available. Talks to \_SB.ATKD.WMNB through /proc/acpi/call.
 *
 * Build:
 *     make            # dynamic
 *     make static     # -static (bring your own libc)
 *
 * Usage:
 *     wmi-set power on
 *     wmi-set power off
 *     wmi-set brightness 128
 *     wmi-set get
 *     wmi-set toggle
 *     wmi-set --debug brightness 200
 *     wmi-set --short power on          # use 8-byte bios_args form
 *
 * See src/README.md for the ACPI-level details.
 *
 * Author: chris (github.com/TrashPanda2481).
 */

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#define ACPI_CALL_PATH   "/proc/acpi/call"
#define WMNB_PATH        "\\_SB.ATKD.WMNB"

#define METHODID_DEVS    0x53564544u   /* 'DEVS' LE */
#define METHODID_DSTS    0x53545344u   /* 'DSTS' LE */

#define DEVID_POWER      0x00050031u
#define DEVID_LIGHT      0x00050032u

#define WMI_INSTANCE     0

#define BUFLEN_FULL      24
#define BUFLEN_SHORT     8

static int g_debug = 0;
static int g_buflen = BUFLEN_FULL;

static void eprintf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
}

/*
 * Build the WMNB input buffer:
 *   __packed { u32 dev_id; u32 ctrl_param; u32 pad[...]; }
 * `out` must hold at least `len` bytes. Returns 0 on ok, -1 on bad len.
 */
static int build_buffer(uint32_t dev_id, uint32_t ctrl_param,
                        uint8_t *out, size_t len) {
    if (len < 8 || (len % 4) != 0) return -1;
    memset(out, 0, len);
    /* little-endian store. X86_64 target, but do it explicitly anyway. */
    out[0] = (uint8_t)( dev_id        & 0xff);
    out[1] = (uint8_t)((dev_id  >> 8) & 0xff);
    out[2] = (uint8_t)((dev_id  >> 16) & 0xff);
    out[3] = (uint8_t)((dev_id  >> 24) & 0xff);
    out[4] = (uint8_t)( ctrl_param        & 0xff);
    out[5] = (uint8_t)((ctrl_param >> 8)  & 0xff);
    out[6] = (uint8_t)((ctrl_param >> 16) & 0xff);
    out[7] = (uint8_t)((ctrl_param >> 24) & 0xff);
    return 0;
}

static void hex_encode(const uint8_t *buf, size_t len, char *out) {
    static const char h[] = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        out[i * 2]     = h[(buf[i] >> 4) & 0xf];
        out[i * 2 + 1] = h[buf[i] & 0xf];
    }
    out[len * 2] = '\0';
}

/*
 * Parse acpi_call's reply: "0xN", decimal, "not called", "Error: ...".
 * On success sets *status and returns 0; on error returns -1 and writes
 * an English message to msg (size msglen).
 */
static int parse_reply(const char *reply, uint64_t *status,
                       char *msg, size_t msglen) {
    /* strip trailing whitespace/newlines */
    size_t n = strlen(reply);
    while (n > 0 && (reply[n-1] == '\n' || reply[n-1] == '\r' ||
                     reply[n-1] == ' '  || reply[n-1] == '\t')) {
        n--;
    }
    if (n == 0) {
        snprintf(msg, msglen, "empty reply from %s", ACPI_CALL_PATH);
        return -1;
    }
    char tmp[128];
    if (n >= sizeof(tmp)) n = sizeof(tmp) - 1;
    memcpy(tmp, reply, n);
    tmp[n] = '\0';

    if (strcmp(tmp, "not called") == 0) {
        snprintf(msg, msglen,
                 "acpi_call reports 'not called'. WMNB path %s may not "
                 "exist on this BIOS.", WMNB_PATH);
        return -1;
    }
    if (strncasecmp(tmp, "error", 5) == 0) {
        snprintf(msg, msglen, "ACPI error from WMNB: %s", tmp);
        return -1;
    }

    char *end = NULL;
    errno = 0;
    unsigned long long v;
    if (tmp[0] == '0' && (tmp[1] == 'x' || tmp[1] == 'X')) {
        v = strtoull(tmp + 2, &end, 16);
    } else {
        v = strtoull(tmp, &end, 10);
    }
    if (errno != 0 || end == NULL || *end != '\0') {
        snprintf(msg, msglen, "unparseable reply: %s", tmp);
        return -1;
    }
    *status = (uint64_t)v;
    return 0;
}

/*
 * Fire WMNB(instance, method_id, buffer) via /proc/acpi/call. Writes the
 * status word to *status. On error returns -1 and prints a message to stderr.
 */
static int call_wmnb(uint32_t method_id, uint32_t dev_id, uint32_t ctrl_param,
                     uint64_t *status) {
    if (access(ACPI_CALL_PATH, F_OK) != 0) {
        eprintf("error: %s does not exist.\n"
                "The acpi_call kernel module isn't loaded. On Debian:\n"
                "    sudo apt install acpi-call-dkms\n"
                "    sudo modprobe acpi_call\n",
                ACPI_CALL_PATH);
        return -1;
    }

    uint8_t buf[64];
    if (g_buflen > (int)sizeof(buf)) {
        eprintf("error: internal buffer too small for %d-byte payload\n",
                g_buflen);
        return -1;
    }
    if (build_buffer(dev_id, ctrl_param, buf, (size_t)g_buflen) != 0) {
        eprintf("error: bad buffer length %d\n", g_buflen);
        return -1;
    }

    char hex[sizeof(buf) * 2 + 1];
    hex_encode(buf, (size_t)g_buflen, hex);

    char cmd[256];
    int n = snprintf(cmd, sizeof(cmd), "%s %d 0x%08X b%s",
                     WMNB_PATH, WMI_INSTANCE, method_id, hex);
    if (n <= 0 || (size_t)n >= sizeof(cmd)) {
        eprintf("error: acpi_call command overflow\n");
        return -1;
    }

    if (g_debug) {
        fprintf(stderr, "[debug] buffer     : %s\n", hex);
        fprintf(stderr, "[debug] acpi_call  : %s\n", cmd);
    }

    int fd = open(ACPI_CALL_PATH, O_WRONLY);
    if (fd < 0) {
        if (errno == EACCES) {
            eprintf("error: permission denied writing %s. Run as root.\n",
                    ACPI_CALL_PATH);
        } else {
            eprintf("error: open %s for write: %s\n",
                    ACPI_CALL_PATH, strerror(errno));
        }
        return -1;
    }
    ssize_t w = write(fd, cmd, (size_t)n);
    int wsave = errno;
    close(fd);
    if (w < 0 || w != n) {
        eprintf("error: short write to %s: %s\n",
                ACPI_CALL_PATH,
                w < 0 ? strerror(wsave) : "partial");
        return -1;
    }

    fd = open(ACPI_CALL_PATH, O_RDONLY);
    if (fd < 0) {
        eprintf("error: open %s for read: %s\n",
                ACPI_CALL_PATH, strerror(errno));
        return -1;
    }
    char reply[256];
    ssize_t r = read(fd, reply, sizeof(reply) - 1);
    int rsave = errno;
    close(fd);
    if (r < 0) {
        eprintf("error: read %s: %s\n", ACPI_CALL_PATH, strerror(rsave));
        return -1;
    }
    reply[r] = '\0';
    /* acpi_call writes a NUL-terminated string; trim at first NUL just in case
     * the read grabbed trailing garbage. */
    reply[strcspn(reply, "\x00")] = '\0';

    if (g_debug) {
        fprintf(stderr, "[debug] reply text : %s\n", reply);
    }

    char errmsg[192];
    if (parse_reply(reply, status, errmsg, sizeof(errmsg)) != 0) {
        eprintf("error: %s\n", errmsg);
        return -1;
    }
    return 0;
}

/* ------------------------------ ops -------------------------------- */

static int op_power(int on) {
    uint64_t st;
    if (call_wmnb(METHODID_DEVS, DEVID_POWER, on ? 1u : 0u, &st) != 0)
        return 1;
    printf("power %s -> 0x%llX\n", on ? "on" : "off",
           (unsigned long long)st);
    return 0;
}

static int op_brightness(long value) {
    if (value < 0 || value > 255) {
        eprintf("error: brightness must be 0-255, got %ld\n", value);
        return 2;
    }
    uint64_t st;
    if (call_wmnb(METHODID_DEVS, DEVID_LIGHT, (uint32_t)value, &st) != 0)
        return 1;
    printf("brightness %ld -> 0x%llX\n", value, (unsigned long long)st);
    return 0;
}

static int op_get(void) {
    uint64_t p, l;
    if (call_wmnb(METHODID_DSTS, DEVID_POWER, 0, &p) != 0) return 1;
    if (call_wmnb(METHODID_DSTS, DEVID_LIGHT, 0, &l) != 0) return 1;
    int p_present = (p & 0x00010000ull) ? 1 : 0;
    int p_value   = (int)(p & 0xFFFFull);
    int l_present = (l & 0x00010000ull) ? 1 : 0;
    int l_value   = (int)(l & 0xFFFFull);
    printf("power      : %s (supported=%d, raw=0x%llX)\n",
           p_value ? "on" : "off", p_present, (unsigned long long)p);
    printf("brightness : %d (supported=%d, raw=0x%llX)\n",
           l_value, l_present, (unsigned long long)l);
    return 0;
}

static int op_toggle(void) {
    uint64_t p;
    if (call_wmnb(METHODID_DSTS, DEVID_POWER, 0, &p) != 0) return 1;
    int cur = (int)(p & 0xFFFFull);
    int new_on = !cur;
    uint64_t st;
    if (call_wmnb(METHODID_DEVS, DEVID_POWER, new_on ? 1u : 0u, &st) != 0)
        return 1;
    printf("toggle -> %s (0x%llX)\n",
           new_on ? "on" : "off", (unsigned long long)st);
    return 0;
}

static void usage(FILE *f) {
    fprintf(f,
        "wmi-set. Drive ASUS UX435EG ScreenPad via /proc/acpi/call\n"
        "usage:\n"
        "  wmi-set [--debug] [--short] power on|off\n"
        "  wmi-set [--debug] [--short] brightness <0-255>\n"
        "  wmi-set [--debug] [--short] get\n"
        "  wmi-set [--debug] [--short] toggle\n"
        "  wmi-set -h | --help\n"
        "\n"
        "  --debug   print the raw acpi_call command and reply\n"
        "  --short   use the 8-byte bios_args form\n");
}

int main(int argc, char **argv) {
    int i = 1;
    while (i < argc && argv[i][0] == '-') {
        if (strcmp(argv[i], "--debug") == 0) {
            g_debug = 1;
        } else if (strcmp(argv[i], "--short") == 0) {
            g_buflen = BUFLEN_SHORT;
        } else if (strcmp(argv[i], "-h") == 0 ||
                   strcmp(argv[i], "--help") == 0) {
            usage(stdout);
            return 0;
        } else if (strcmp(argv[i], "--") == 0) {
            i++;
            break;
        } else {
            eprintf("unknown flag: %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
        i++;
    }
    if (i >= argc) {
        usage(stderr);
        return 2;
    }

    const char *cmd = argv[i++];

    if (strcmp(cmd, "power") == 0) {
        if (i >= argc) { eprintf("power: missing on|off\n"); return 2; }
        const char *s = argv[i];
        if (strcasecmp(s, "on") == 0 || strcmp(s, "1") == 0)  return op_power(1);
        if (strcasecmp(s, "off") == 0 || strcmp(s, "0") == 0) return op_power(0);
        eprintf("power: expected on|off, got %s\n", s);
        return 2;
    }
    if (strcmp(cmd, "brightness") == 0) {
        if (i >= argc) { eprintf("brightness: missing value\n"); return 2; }
        char *end = NULL;
        errno = 0;
        long v = strtol(argv[i], &end, 0);   /* base 0 -> accepts 0x80 */
        if (errno != 0 || end == NULL || *end != '\0') {
            eprintf("brightness: not an integer: %s\n", argv[i]);
            return 2;
        }
        return op_brightness(v);
    }
    if (strcmp(cmd, "get") == 0)    return op_get();
    if (strcmp(cmd, "toggle") == 0) return op_toggle();

    eprintf("unknown command: %s\n", cmd);
    usage(stderr);
    return 2;
}
