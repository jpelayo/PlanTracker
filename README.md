# PlanTracker

A native macOS menu bar app to track AI usage limits in real-time.

**This workspace now contains two app variants:**

- `PlanTrackerForClaude/` — Claude.ai-focused tracker
- `PlanTrackerForCodex/` — Codex/ChatGPT-focused tracker

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.2+-orange)

## Features

- **Multi-Model Usage Tracking** — Separate tracking for major usage windows and model/credit limits when available
  - 5-hour style limits (where applicable)
  - 7-day style limits (where applicable)
  - Additional model/credit windows when exposed by the backend
- **Menu Bar Integration** — Always visible usage stats without leaving your workflow
- **Color-Coded Progress Bars** — Green → Yellow → Red indicators for each limit
- **Secure Authentication** — Sign in via service web flow with session stored securely in Keychain
- **Auto-Refresh** — Configurable polling interval (3-60 minutes) to keep usage data current
- **Bilingual Support** — English and Spanish interface
- **Native Experience** — Built with SwiftUI for a lightweight, fast macOS app

## Screenshots

<!-- TODO: Add screenshots -->

## Requirements

- macOS 15.0 (Sequoia) or later
- Account depending on variant:
  - Claude.ai account (Claude variant)
  - ChatGPT/Codex account (Codex variant)

## Installation

### Option 1: Download Pre-Built Binary (Recommended)

**Ready-to-use `.dmg` may be available in releases.** Download the latest release from the [Releases](../../releases) page.

1. Download the corresponding DMG from [Releases](../../releases)
2. Open the DMG and drag the app to your Applications folder
3. **Important:** Right-click the app and select "Open" (first launch only)
   - This is required if the build is not notarized
   - macOS Gatekeeper may block double-click launch
4. Click "Open" in the security dialog
5. Grant Keychain access when prompted (click "Always Allow")

After the first launch, you can open the app normally from Applications or Spotlight.

### Option 2: Build from Source

1. Clone the repository:

```bash
git clone https://github.com/jpelayo/PlanTracker.git
cd PlanTracker
```

2. Open the variant project you want in Xcode:

```bash
open "PlanTrackerForClaude/PlanTracker/PlanTracker.xcodeproj"
```

or

```bash
open "PlanTrackerForCodex/PlanTracker/PlanTracker for Codex.xcodeproj"
```

3. Configure the project in Xcode:
   - Select the target
   - Go to **Signing & Capabilities**
   - Select your Development Team

4. Build and run (⌘R)

## Usage

1. Launch PlanTracker — it appears in your menu bar
2. Click the icon and sign in
3. View your current usage limits at a glance
4. Configure refresh intervals and display preferences in Settings

### Menu Bar Display

The menu bar shows usage percentage with color indicators:

- **Green** — Under 50% used
- **Yellow** — 50-80% used
- **Red** — Over 80% used

## Privacy & Security

- Session data is stored locally in the macOS Keychain
- No data is sent to third-party telemetry endpoints by default
- Authentication happens directly with the target service via embedded browser flow

## Disclaimer

This is an unofficial, community-built application. It is **not** endorsed by, affiliated with, or supported by the tracked services.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project uses Apache License 2.0. See variant license files:

- `PlanTrackerForClaude/PlanTracker/LICENSE`
- `PlanTrackerForCodex/PlanTracker/LICENSE`

## Pro Tips

- **Optimize model usage:** Reserve stronger models for complex tasks
- **Monitor weekly windows:** Keep an eye on high-impact limits to avoid interruptions
- **Set update interval:** 5-10 minutes provides a good balance between freshness and API load
- **Plan model selection:** Use lighter models for quick tasks and stronger ones for deep tasks

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Inspired by the need to manage AI usage limits effectively
