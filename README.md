# PlanTracker

A native macOS menu bar app to track your Claude.ai usage limits in real-time.

**This app is going to be made available on the Mac App Store.**

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2+-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-blue)

## Features

- **Menu Bar Integration** — Always visible usage stats without leaving your workflow
- **5-Hour & 7-Day Limits** — Track both rolling usage windows with color-coded progress bars
- **All Plan Tiers** — Supports Free, Pro, Max, Team, and Enterprise accounts
- **Secure Authentication** — Sign in via Claude.ai with session stored securely in Keychain
- **Auto-Refresh** — Configurable polling interval to keep usage data current
- **Native Experience** — Built with SwiftUI for a lightweight, fast macOS app

## Screenshots

<!-- TODO: Add screenshots -->

## Requirements

- macOS 15.0 (Sequoia) or later
- A Claude.ai account

## Installation

### Download

Download the latest release from the [Releases](../../releases) page.

### Build from Source

> **Note:** The Xcode project file (`project.pbxproj`) is not included in this repository to protect signing credentials. You'll need to configure the project yourself.

1. Clone the repository:
   ```bash
   git clone https://github.com/jpelayo/PlanTracker.git
   cd PlanTracker
   ```

2. Open `PlanTracker.xcodeproj` in Xcode

3. Configure the project:
   - Select the PlanTracker target
   - Go to **Signing & Capabilities**
   - Select your Development Team
   - Xcode will generate the project configuration

4. Build and run (⌘R)

## Usage

1. Launch PlanTracker — it appears in your menu bar
2. Click the icon and sign in with your Claude.ai account
3. View your current usage limits at a glance
4. Configure refresh intervals and display preferences in Settings

### Menu Bar Display

The menu bar shows your usage percentage with color indicators:
- **Green** — Under 50% used
- **Yellow** — 50-80% used
- **Red** — Over 80% used

## Privacy & Security

- Your Claude.ai session is stored locally in the macOS Keychain
- No data is sent to any third-party servers
- Authentication happens directly with Claude.ai via embedded browser

## Disclaimer

This is an unofficial, community-built application. It is **not** endorsed by, affiliated with, or supported by Anthropic (PBC) or Claude.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Inspired by the need to manage Claude.ai usage limits effectively
