ASM ?= pasmo

ROM_SRC := rom/m4s_rom.asm
ROM_INC := rom/m4s_protocol.inc
ROM_OUT ?= build/boot.eXX
CORE_DIR ?= ../Amstrad_MiSTer

MISTER_HOST ?= root@mister
MISTER_ROM ?= /media/usb0/games/Amstrad/boot.e09
MISTER_CORE ?= /media/fat/_Computer/Amstrad.rbf
CORE_RBF ?= $(REMOTE_BUILD_OUT)/Amstrad.rbf
CORE_INPUTS := $(shell find "$(CORE_DIR)" -type f \( \
	-name '*.sv' -o \
	-name '*.v' -o \
	-name '*.vhd' -o \
	-name '*.qip' -o \
	-name '*.qsf' -o \
	-name '*.qpf' -o \
	-name '*.sdc' -o \
	-name '*.tcl' -o \
	-name '*.mif' -o \
	-name '*.hex' \) \
	-not -path '*/.git/*' \
	-not -path '*/output_files/*' \
	-not -path '*/incremental_db/*' \
	-not -path '*/db/*' \
	-not -name 'build_id.v')

REMOTE_USER ?= admin
# Recursive on purpose: AWS is queried only when a remote target expands
# REMOTE_HOST, not when doing a ROM-only build such as `make build/boot.eXX`.
REMOTE_IP = $(shell $(AWS) ec2 describe-instances $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
REMOTE_HOST ?= $(REMOTE_USER)@$(REMOTE_IP)
REMOTE_DIR ?= Amstrad_MiSTer
REMOTE_QUARTUS_IMAGE ?= ghcr.io/raetro/quartus:mister
REMOTE_BUILD_OUT ?= build/remote
REMOTE_STOP_AFTER_BUILD ?= 1
REMOTE_SSH ?= ssh
REMOTE_RSYNC ?= rsync -az --delete
REMOTE_RSYNC_EXCLUDES := \
	--exclude '.git/' \
	--exclude 'output_files/' \
	--exclude 'incremental_db/' \
	--exclude 'db/' \
	--exclude 'build_id.v'

EC2_INSTANCE_ID ?= i-0b7b18909edecdb55
AWS_REGION ?= eu-west-2
AWS ?= aws

.PHONY: all clean install remote-sync remote-build remote-fetch remote-core remote-start-ec2 remote-stop-ec2

all: $(ROM_OUT) $(CORE_RBF)

$(ROM_OUT): $(ROM_SRC) $(ROM_INC) Makefile
	@mkdir -p "$(@D)"
	cd "$(dir $(ROM_SRC))" && "$(ASM)" "$(notdir $(ROM_SRC))" "$(abspath $(ROM_OUT))"
	@size=$$(wc -c < "$@"); \
	if [ "$$size" -ne 16384 ]; then \
		echo "error: expected 16384-byte ROM, got $$size bytes: $@"; \
		exit 1; \
	fi; \
	echo "built $@ ($$size bytes)"

install: $(ROM_OUT) $(CORE_RBF)
	scp "$(ROM_OUT)" "$(MISTER_HOST):$(MISTER_ROM)"
	scp "$(CORE_RBF)" "$(MISTER_HOST):$(MISTER_CORE)"

remote-sync:
	@test "$(REMOTE_IP)" != "None" && test -n "$(REMOTE_IP)" || { echo "error: no public IP for $(EC2_INSTANCE_ID); run remote-start-ec2 or remote-core"; exit 1; }
	$(REMOTE_SSH) "$(REMOTE_HOST)" 'mkdir -p "$(REMOTE_DIR)"'
	$(REMOTE_RSYNC) $(REMOTE_RSYNC_EXCLUDES) "$(CORE_DIR)/" "$(REMOTE_HOST):$(REMOTE_DIR)/"

remote-build:
	$(REMOTE_SSH) "$(REMOTE_HOST)" 'cd "$(REMOTE_DIR)" && docker run --rm -v "$$PWD":/build -w /build "$(REMOTE_QUARTUS_IMAGE)" quartus_sh --flow compile Amstrad'

remote-fetch:
	@mkdir -p "$(dir $(CORE_RBF))"
	rsync -az "$(REMOTE_HOST):$(REMOTE_DIR)/output_files/Amstrad.rbf" "$(CORE_RBF)"

remote-start-ec2:
	$(AWS) ec2 start-instances $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"
	$(AWS) ec2 wait instance-running $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"

remote-core: remote-start-ec2
	$(MAKE) remote-sync
	$(MAKE) remote-build
	$(MAKE) remote-fetch
	@if [ "$(REMOTE_STOP_AFTER_BUILD)" = "1" ]; then $(MAKE) remote-stop-ec2; fi

$(CORE_RBF): $(CORE_INPUTS)
	$(MAKE) remote-core

remote-stop-ec2:
	$(AWS) ec2 stop-instances $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"

clean:
	rm -f "$(ROM_OUT)" "$(CORE_RBF)"
