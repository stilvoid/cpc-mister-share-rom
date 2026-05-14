# Remote MiSTer Core Build

Use this when developing on an ARM machine and compiling the Amstrad MiSTer
core on a temporary x86_64 EC2 builder.

## EC2 builder assumptions

- x86_64 instance, not Graviton/ARM.
- Docker installed and working for your SSH user.
- At least 100GB free disk, preferably 150GB.
- The Quartus environment runs in Docker; do not install Quartus directly.

Verify the remote host:

```sh
uname -m
docker --version
docker run --rm hello-world
```

`uname -m` must print `x86_64`.

## Install build image

On the EC2 builder:

```sh
docker pull ghcr.io/raetro/quartus:mister
```

The image is large. Keeping the EC2 instance stopped, rather than terminated,
keeps this download cached on the EBS volume.

## Sync the core to EC2

The scaffold Makefile can drive the remote build. From `mister-cpc-m4`, set
`REMOTE_HOST` to the EC2 SSH target if the default in the Makefile is not
current:

```sh
make remote-start-ec2
make remote-core REMOTE_HOST=debian@HOST
make remote-stop-ec2
```

Use `admin@HOST` if the Debian AMI uses `admin` as its default user.

The fetched `.rbf` is copied to:

```text
build/remote/
```

The rest of this document shows the equivalent manual commands.

From the local workspace root, replace `debian@HOST` with the EC2 SSH target:

```sh
rsync -az --delete \
  --exclude '.git/' \
  --exclude 'output_files/' \
  --exclude 'incremental_db/' \
  --exclude 'db/' \
  --exclude 'build_id.v' \
  Amstrad_MiSTer/ debian@HOST:Amstrad_MiSTer/
```

Use `admin@HOST` if the Debian AMI uses `admin` as its default user.

## Build

On the EC2 builder:

```sh
cd ~/Amstrad_MiSTer
docker run --rm -v "$PWD":/build -w /build ghcr.io/raetro/quartus:mister \
  quartus_sh --flow compile Amstrad
```

The expected output is under:

```text
~/Amstrad_MiSTer/output_files/
```

## Fetch artifacts

From the local workspace root:

```sh
mkdir -p build/remote
rsync -az debian@HOST:Amstrad_MiSTer/output_files/*.rbf build/remote/
```

## Cost control

Stop the EC2 instance after fetching artifacts. Do not terminate it unless you
are happy to lose the Docker image, Quartus cache, checkout, and build outputs.

If the AWS CLI is configured locally, the Makefile can start and stop the
instance:

```sh
make remote-start-ec2 EC2_INSTANCE_ID=i-0123456789abcdef0 AWS_REGION=eu-west-2
make remote-stop-ec2 EC2_INSTANCE_ID=i-0123456789abcdef0 AWS_REGION=eu-west-2
```
