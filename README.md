# Integrity Control for Proxmox VE QEMU VMs

`pve-integrity-control` is a start-time integrity-control system for QEMU
virtual machines managed by Proxmox VE. It records a cryptographic baseline
for selected VM objects and prevents an enabled VM from starting when a later
check detects a change.

It is intended to detect unauthorized or unexpected changes to important
guest files, VM configuration, and legacy boot records before the guest runs.

## How it works

1. Enable integrity control for a VM. The project assigns a Proxmox hook
   script to the VM.
2. Select the objects to protect while the VM is stopped.
3. The project reads the selected objects and stores their GOST
   `md_gost12_256` hashes as the VM's baseline.
4. At the VM's `pre-start` hook, the checker reads the objects again and
   compares their hashes with the baseline.
5. A mismatch makes the hook fail, and Proxmox VE aborts the VM start.

Guest files and boot records are read through libguestfs in read-only mode.
Baseline data is stored in the Proxmox cluster filesystem under the node that
owns the VM:

```
/etc/pve/nodes/<node>/qemu-server/integrity-control/<vmid>.conf
```

## Protected objects

The `ic set-objects` command can add any combination of:

- The rendered Proxmox VE VM configuration (`--config`). The transient VM
  `lock` property is excluded from its hash.
- Individual guest files (`--files`), identified as
  `<partition>:<absolute-path>`.
- The master boot record and/or volume boot record (`--bootloader`).

For example:

```sh
ic set-objects 101 --config \
  --files '/dev/sda1:/etc/passwd;/dev/sda1:/etc/ssh/sshd_config'
```

## Requirements

- Proxmox VE with the required `pve-qemu-server` and `pve-cluster` integration
  patches described below.
- A Proxmox storage configured with the `snippets` content type, used to store
  `ic-hookscript.pl`.
- Perl dependencies: `libdata-printer-perl`, `libguestfs-perl`,
  `liblog-log4perl-perl`, `libengine-gost-openssl`, and
  `liblogfile-rotate-perl`.
- A stopped VM when adding integrity objects.

The helper scripts install the dependencies and fetch the matching patched
Proxmox components:

```sh
make deps-install
make patches-install
make install
```

`make full-install` runs all three steps. These installation commands modify
the Proxmox host and require administrative privileges. Review the scripts
before running them in production.

## Required Proxmox VE integration patches

Integrity control extends two Proxmox VE components. A compatible installation
must include the following changes.

| Component | Required changes | Why IC needs them |
| --- | --- | --- |
| `pve-qemu-server` | Define the boolean VM configuration option `integrity_control`; allow it as a fast VM configuration update. | `ic enable` records that integrity control is enabled in the VM configuration. |
| `pve-cluster` | Create and expose `nodes/<node>/qemu-server/integrity-control` in pmxcfs, including its convenience symlink. | IC stores each VM's baseline database in the Proxmox cluster filesystem. |
| `pve-cluster` | Permit the integrity-control directory as a cluster configuration path and include its `<vmid>.conf` files in configuration version handling. | IC registers, reads, writes, and synchronizes baseline data safely through the cluster filesystem. |

The current `make patches-install` helper obtains these changes from the
project's `pve-ic-support` branches. Those branches are historical component
snapshots, not version-checked minimal patches.

## Typical workflow

Install the hook script, enable integrity control, and create a baseline:

```sh
make install_hookscript
ic enable 101
ic set-objects 101 --config \
  --files '/dev/sda1:/etc/passwd;/dev/sda1:/etc/ssh/sshd_config'
ic status 101
```

After an authorized change to a protected file, reset that object's baseline
while the VM is stopped:

```sh
ic unset-objects 101 --files '/dev/sda1:/etc/ssh/sshd_config'
ic set-objects 101 --files '/dev/sda1:/etc/ssh/sshd_config'
```

For an enabled VM that will run on another cluster node, copy its node-specific
baseline first:

```sh
ic sync-db pve-node2 --vmid 101
```

## CLI commands

| Command | Purpose |
| --- | --- |
| `ic status <vmid>` | Show whether integrity control is enabled. |
| `ic enable <vmid>` / `ic disable <vmid>` | Attach or remove the integrity hook. |
| `ic set-objects <vmid> ...` | Add and hash protected objects. |
| `ic unset-objects <vmid> ...` | Remove protected objects from the baseline. |
| `ic get-db <vmid>` | Print the VM's baseline database. |
| `ic sync-db <target> --vmid <vmid>` | Copy the baseline to another node. |
| `ic open-journal` | Open the integrity-control journal. |
| `ic start-new-journal` | Rotate the journal. |

The journal is written to `/var/log/pve-integrity-control/journal.log`.

## Limitations and security model

- The current implementation supports VMs with one boot disk.
- Boot-record checks support MBR (`msdos`) partition tables only. GPT boot
  structures are not checked.
- Integrity control checks selected file contents, not file metadata,
  directories, non-selected files, or the entire guest filesystem.
- The baseline is not signed or externally attested. A fully privileged actor
  who can modify both the guest disks and the Proxmox cluster filesystem can
  alter the baseline. This project is a start-time change detector, not a
  defense against a compromised Proxmox host or cluster administrator.

## Documentation

The documentation sources are:

- [`docs/ic.adoc`](docs/ic.adoc): `ic(1)` manual and operational guide.
- [`docs/generated/ic.1-synopsis.adoc`](docs/generated/ic.1-synopsis.adoc):
  CLI command reference.
- [`docs/README.md`](docs/README.md): local build and `pve-docs` integration
  guidance.

Install the standard `asciidoctor` command and build the standalone
documentation without a `pve-docs` checkout:

```sh
make docs
```

This creates `docs/build/ic.1` and `docs/build/ic.html`. To stage the generated
manpage, HTML guide, and AsciiDoc sources for installation, run:

```sh
make install-docs DESTDIR=/package/staging/root
```

The sources also supplement the Proxmox VE `pve-docs` build; see
[`docs/README.md`](docs/README.md) for that integration workflow.
