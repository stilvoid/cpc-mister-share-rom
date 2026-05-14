ASM ?= pasmo

ROM_SRC := rom/m4s_rom.asm
ROM_INC := rom/m4s_protocol.inc
ROM_OUT ?= build/boot.eXX
CORE_DIR ?= ../Amstrad_MiSTer

MISTER_HOST ?= root@mister
MISTER_ROM ?= /media/usb0/games/Amstrad/boot.e09
MISTER_CORE ?= /media/fat/_Computer/Amstrad.rbf
CORE_RBF ?= $(REMOTE_BUILD_OUT)/Amstrad.rbf

REMOTE_HOST ?= admin@35.178.180.27
REMOTE_DIR ?= Amstrad_MiSTer
REMOTE_QUARTUS_IMAGE ?= ghcr.io/raetro/quartus:mister
REMOTE_BUILD_OUT ?= build/remote
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
	scp "$(CORE_RBF)" "$(MISTER_HOST):$(MISTER_CORE)"

remote-sync:
	$(REMOTE_SSH) "$(REMOTE_HOST)" 'mkdir -p "$(REMOTE_DIR)"'
	$(REMOTE_RSYNC) $(REMOTE_RSYNC_EXCLUDES) "$(CORE_DIR)/" "$(REMOTE_HOST):$(REMOTE_DIR)/"

remote-build:
	$(REMOTE_SSH) "$(REMOTE_HOST)" 'cd "$(REMOTE_DIR)" && docker run --rm -v "$$PWD":/build -w /build "$(REMOTE_QUARTUS_IMAGE)" quartus_sh --flow compile Amstrad'

remote-fetch:
	@mkdir -p "$(REMOTE_BUILD_OUT)"
	rsync -az "$(REMOTE_HOST):$(REMOTE_DIR)/output_files/*.rbf" "$(REMOTE_BUILD_OUT)/"

remote-core: remote-sync remote-build remote-fetch

remote-start-ec2:
	$(AWS) ec2 start-instances $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"
	$(AWS) ec2 wait instance-running $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"

remote-stop-ec2:
	$(AWS) ec2 stop-instances $(if $(AWS_REGION),--region "$(AWS_REGION)",) --instance-ids "$(EC2_INSTANCE_ID)"

clean:
	rm -f "$(ROM_OUT)"
