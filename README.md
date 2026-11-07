[![Build and Test](https://github.com/irkhin/dextra-commander/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/irkhin/dextra-commander/actions/workflows/build.yml)
[![Nightly Build](https://github.com/irkhin/dextra-commander/actions/workflows/nightly.yml/badge.svg?branch=main)](https://github.com/irkhin/dextra-commander/actions/workflows/nightly.yml)

# Dextra Commander
![](Docs/nc.png)
Dextra Commander is a free dual-pane file manager for macOS, designed with a focus on speed, keyboard-based navigation, and flexibility.  
The project's aim is to blend the user experience of classic file managers from the '80s-'90s with the modern look and feel of Mac computers.  
Dextra Commander is a fork of [Nimble Commander](https://github.com/mikekazakov/nimble-commander) by Michael Kazakov.  

## What's Different
On top of everything Nimble Commander offers, Dextra Commander adds:

- **Open With picker.** Press `Esc` in a file panel to open the selected items with any application, right from the keyboard: pick one of the recently used applications or type to search through all installed ones.
- **Custom ports for network shares.** Connect to SMB servers listening on a non-standard port by entering the server as `host:port`, e.g. `nas.local:4455`.

See [WHATS_NEW.md](WHATS_NEW.md) for the full list of changes and [Help.md](Docs/Help.md) for details.

# Getting Dextra Commander

## Nightly Builds
You can download the latest nightly build of the app from [GitHub Actions](https://github.com/irkhin/dextra-commander/actions/workflows/nightly.yml).  
Go to the most recent integration and select the `dextra-commander-nightly` in the `Artifacts` section (a GitHub account is required).

## Current Release
Download the latest release from [GitHub Releases](https://github.com/irkhin/dextra-commander/releases/latest).  

## Past Releases
Access all previous releases at https://github.com/irkhin/dextra-commander/releases.  
Releases of the original Nimble Commander are available at https://github.com/mikekazakov/nimble-commander-releases.

# Documentation
The user guide can be found here: [Help.md](Docs/Help.md).

# Changelog
Details about each released version can be found in the [WHATS_NEW.md](WHATS_NEW.md) file.

# Building from Source
For build instructions and an overview of the source code, please refer to the [Building.md](Docs/Building.md) document.

# Contributing to the Project
Your contributions are welcome and greatly appreciated! For guidelines on how to contribute, including reporting bugs, suggesting features, and submitting code changes, please see the [CONTRIBUTING.md](CONTRIBUTING.md) file.

# Support the Project
Dextra Commander is free and open source, and it will stay that way.
Keeping it up to date with every new macOS release, fixing bugs, and building new features takes a lot of time, as do the costs of code signing and notarization.

If Dextra Commander is part of your daily workflow, please consider supporting its development:

- **Become a sponsor** on [GitHub Sponsors](https://github.com/sponsors/irkhin). One-time and monthly sponsorships are both welcome.
- **Spread the word.** Star the repository, tell your colleagues, or write about it.
- **Contribute.** Report bugs, suggest features, help other users in [Discussions](https://github.com/irkhin/dextra-commander/discussions), or send a pull request.

You can also find `Support Dextra Commander...` in the app's `Help` menu.
Thank you, your support keeps the project alive!

# License
Copyright (C) 2013-2026 Michael Kazakov (mike.kazakov@gmail.com)  
Copyright (C) 2026 Alexey Irkhin (modifications in Dextra Commander)  
The source code is distributed under GNU General Public License version 3.
