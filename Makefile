ASM ?= pasmo

ROM_SRC := rom/cpc_mister_share_rom.asm
ROM_INC := rom/cpc_mister_share_protocol.inc
VERSION_INC := build/cpc_mister_share_version.inc
ROM_OUT ?= build/boot.eXX
GIT_VERSION ?= $(shell git describe --tags --dirty --always 2>/dev/null || echo unknown)

.PHONY: all clean force-version

all: $(ROM_OUT)

$(VERSION_INC): force-version
	@mkdir -p "$(@D)"
	@tmp="$@.tmp"; \
	printf '        db "%s"\n' "$(GIT_VERSION)" > "$$tmp"; \
	if ! cmp -s "$$tmp" "$@"; then mv "$$tmp" "$@"; else rm "$$tmp"; fi

$(ROM_OUT): $(ROM_SRC) $(ROM_INC) $(VERSION_INC) Makefile
	@mkdir -p "$(@D)"
	cd "$(dir $(ROM_SRC))" && "$(ASM)" "$(notdir $(ROM_SRC))" "$(abspath $(ROM_OUT))"
	@size=$$(wc -c < "$@"); \
	if [ "$$size" -ne 16384 ]; then \
		echo "error: expected 16384-byte ROM, got $$size bytes: $@"; \
		exit 1; \
	fi; \
	echo "built $@ ($$size bytes)"

clean:
	rm -f "$(ROM_OUT)" "$(VERSION_INC)"
