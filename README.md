# GitHub Copilot CLI Setup for Termux

This repository contains a setup script to install and configure the **GitHub Copilot CLI** on **Termux** (Android). It uses an official **Linux Node.js** build under **QEMU user emulation** with a minimal glibc sysroot so current Copilot CLI releases can run on Termux reliably.

## Overview

The `setup.sh` script performs the following tasks:
- Installs `glibc-repo`, `glibc-runner`, and the matching `qemu-user-*` package in Termux.
- Downloads an official Linux Node.js tarball for your architecture.
- Builds a tiny glibc sysroot from the Termux glibc packages for QEMU to use.
- Installs `@github/copilot` globally with the Linux Node.js runtime.
- Replaces the `copilot` launcher with a Termux wrapper that runs Copilot through QEMU.

## Installation

1.  Clone this repository or download the `setup.sh` file to your Termux home directory.
2.  Make the script executable:
    ```bash
    chmod +x setup.sh
    ```
3.  Run the setup script:
    ```bash
    ./setup.sh
    ```

The script will guide you through the installation process.

By default it installs the latest Copilot CLI. You can pin a specific Copilot or Linux Node.js version if needed:

```bash
COPILOT_VERSION=1.0.51 LINUX_NODE_VERSION=v24.14.1 ./setup.sh
```

## Usage

Once the installation is complete, you can start the GitHub Copilot CLI by running:

```bash
copilot
```

## Why this workaround exists

Upstream Copilot CLI v1.0.48+ added a glibc-linked native addon, which does not load inside Android's normal Bionic-based Node.js environment. The issue tracked in [github/copilot-cli#3333](https://github.com/github/copilot-cli/issues/3333) documents that breakage.

On some Android devices, directly launching upstream Linux Node.js binaries through the glibc loader is still unreliable because those binaries are non-PIE Linux executables. This setup avoids that by running Linux Node.js through QEMU user mode with a minimal glibc sysroot, while still using the upstream Copilot CLI package.
