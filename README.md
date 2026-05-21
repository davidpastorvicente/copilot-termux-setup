# GitHub Copilot CLI Setup for Termux

This repository contains a setup script to install and configure the **GitHub Copilot CLI** on **Termux** (Android). It uses Termux's **glibc-runner** plus an official **Linux Node.js** build so current Copilot CLI releases can run with the upstream Linux binaries.

## Overview

The `setup.sh` script performs the following tasks:
- Installs `glibc-repo` and `glibc-runner` in Termux.
- Downloads an official Linux Node.js tarball for your architecture.
- Installs `@github/copilot` plus the matching `@github/copilot-linux-*` package under glibc.
- Replaces the `copilot` launcher with a Termux wrapper that runs Copilot under glibc.

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

Upstream Copilot CLI v1.0.48+ added a glibc-linked native addon, which does not load inside Android's normal Bionic-based Node.js environment. The workaround tracked in [github/copilot-cli#3333](https://github.com/github/copilot-cli/issues/3333) is to run Copilot with a Linux Node.js binary under Termux's glibc support, so the standard upstream `linux-arm64` / `linux-x64` packages can be used unchanged.
