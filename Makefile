ASM ?= pasmo

ROM_SRC := rom/m4s_rom.asm
ROM_INC := rom/m4s_protocol.inc
ROM_OUT ?= build/boot.eXX

MISTER_HOST ?= root@mister
MISTER_ROM ?= /media/usb0/games/Amstrad/boot.e09

.PHONY: all clean install

all: $(ROM_OUT)

$(ROM_OUT): $(ROM_SRC) $(ROM_INC) Makefile
	@mkdir -p "$(@D)"
	cd "$(dir $(ROM_SRC))" && "$(ASM)" "$(notdir $(ROM_SRC))" "$(abspath $(ROM_OUT))"
	@size=$$(wc -c < "$@"); \
	if [ "$$size" -ne 16384 ]; then \
		echo "error: expected 16384-byte ROM, got $$size bytes: $@"; \
		exit 1; \
	fi; \
	echo "built $@ ($$size bytes)"

install: $(ROM_OUT)
	scp "$<" "$(MISTER_HOST):$(MISTER_ROM)"

clean:
	rm -f "$(ROM_OUT)"
