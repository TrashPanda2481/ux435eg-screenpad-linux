# Makefile for the ScreenPad userspace tools.
#
# Targets:
#   make            -> build wmi-set (dynamic)
#   make static     -> build wmi-set statically linked (for recovery envs)
#   make install    -> install both tools to $(PREFIX)/bin (default /usr/local)
#   make uninstall
#   make clean

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin

CC          ?= cc
CFLAGS      ?= -O2 -Wall -Wextra -Wpedantic -Wshadow -Wformat=2 \
               -Wstrict-prototypes -Wmissing-prototypes -std=c11
LDFLAGS     ?=

BIN         := wmi-set
SRC         := wmi-set.c

PY_TOOL     := ux435-screenpad

.PHONY: all static install uninstall clean check

all: $(BIN)

$(BIN): $(SRC)
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDFLAGS)

# Static build. Needs a static libc (glibc-static / musl); on Debian:
#   sudo apt install libc6-dev  (dynamic is fine for most cases;
#   for a truly portable static binary, build against musl-gcc).
static:
	$(CC) $(CFLAGS) -static -o $(BIN) $(SRC) $(LDFLAGS)

install: $(BIN)
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(BIN)     $(DESTDIR)$(BINDIR)/$(BIN)
	install -m 0755 $(PY_TOOL) $(DESTDIR)$(BINDIR)/$(PY_TOOL)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(BIN)
	rm -f $(DESTDIR)$(BINDIR)/$(PY_TOOL)

# Quick smoke test: syntax-check the Python and compile-check the C.
check:
	python3 -c "import ast; ast.parse(open('$(PY_TOOL)').read())" && echo "python: ok"
	$(CC) $(CFLAGS) -fsyntax-only $(SRC) && echo "c: syntax ok"

clean:
	rm -f $(BIN) *.o
