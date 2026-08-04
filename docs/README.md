# Proxmox VE documentation supplement

This directory contains the documentation maintained by
`pve-integrity-control`. It supplements the upstream
[`pve-docs`](https://git.proxmox.com/?p=pve-docs.git) documentation with the
`ic(1)` manual and its command reference.

## Contents

```text
docs/
├── ic.adoc                     # narrative source for the ic(1) manual
├── generated/
│   └── ic.1-synopsis.adoc       # CLI command reference snapshot
└── README.md                    # this guide
```

`ic.adoc` documents the integrity-control workflow, examples, operational
constraints, and security model. `generated/ic.1-synopsis.adoc` contains the
CLI reference generated from the command/API schema in a Proxmox VE build
environment.

## Local documentation build

Install the standard `asciidoctor` command, then build the standalone manual
and HTML guide without a `pve-docs` checkout:

```sh
make docs
```

This generates:

```text
docs/build/ic.1
docs/build/ic.html
```

View the generated manual with `man -l docs/build/ic.1`. Run
`make install-docs` to build these artifacts and install the manpage,
HTML guide, and AsciiDoc sources. The target honors `DESTDIR` and does not copy
README files.

## Upstream pve-docs integration

When integrating this manual into a `pve-docs` checkout, place the files at
the equivalent paths relative to that checkout's root:

```text
pve-docs/
├── ic.adoc
└── generated/
    └── ic.1-synopsis.adoc
```

Register `ic` as a section-1 manual source in the `pve-doc-generator` metadata
used by the `pve-docs` build. That causes the normal PVE documentation pipeline
to generate and package `ic(1)`, its HTML rendering, and index entries.

## Updating the command reference

After changing `PVE::CLI::ic` or its API schema, regenerate the reference in a
PVE documentation build environment. From the root of a `pve-docs` checkout:

```sh
make generated/ic.1-synopsis.adoc
```

Review the generated file and copy it back to
`docs/generated/ic.1-synopsis.adoc` in this repository. The checked-in
snapshot lets documentation changes be reviewed together with CLI changes.

To retain the generated synopsis in this repository, copy and review it
explicitly:

```sh
cp "$PVE_DOCS_DIR/generated/ic.1-synopsis.adoc" \
  docs/generated/ic.1-synopsis.adoc
```
