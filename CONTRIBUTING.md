# Contributing to PixOS

First off, thank you for considering contributing to PixOS! It's people like you that make PixOS such a valuable tool for everyone in the open source community.

## Code of Conduct

This project and everyone participating in it is governed by the [PixOS Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs
Before creating bug reports, please check the existing issues to see if the problem has already been reported.

When filing a bug, please include:
- Your macOS version (e.g. macOS 14.5 Sonoma, macOS 15.0 Sequoia).
- iPhone model and iOS version.
- Android / Google Pixel model and Android version.
- Whether you connected via USB cable or Wireless ADB.
- Terminal output or App log messages.

### Suggesting Enhancements
Feature requests are tracked as GitHub issues. Please provide:
- A clear explanation of the feature and problem it solves.
- Any relevant device constraints or Edge cases.

### Pull Requests
1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add unit tests in `Tests/TestRunner/main.swift`.
3. Verify that tests pass by running:
   ```bash
   swift run --build-system native test-runner
   ```
4. Verify that the app and DMG build successfully:
   ```bash
   bash scripts/package_dmg.sh
   ```
5. Ensure your code follows standard Swift styling.
6. Open a Pull Request referencing any related issues.

## Project Structure
- `Sources/CoreSyncEngine/`: Shared Swift framework containing device managers, SQLite state, Motion Photo synthesis, and ADB client.
- `Sources/CLI/`: Terminal executable `pixos`.
- `Sources/App/`: Native macOS SwiftUI Desktop Application with Liquid Glass UI.
- `scripts/`: Packaging and build scripts (`build_app.sh`, `package_dmg.sh`).
- `docs/`: GitHub Pages landing page.

Thank you for helping make PixOS better!
