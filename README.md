# PlanTracker Workspace

This repository now contains two separate app variants.

## Repository Layout

- `PlanTrackerForClaude/`
  - Claude-focused version
  - Xcode project: `PlanTrackerForClaude/PlanTracker/PlanTracker.xcodeproj`
- `PlanTrackerForCodex/`
  - Codex/ChatGPT-focused version
  - Xcode project: `PlanTrackerForCodex/PlanTracker/PlanTracker for Codex.xcodeproj`

Each variant has its own:
- source code
- assets
- App Store marketing/review material (`Appstore/`)

## Quick Start

### Build Claude Variant

```bash
open "PlanTrackerForClaude/PlanTracker/PlanTracker.xcodeproj"
```

or

```bash
xcodebuild -project "PlanTrackerForClaude/PlanTracker/PlanTracker.xcodeproj" \
  -scheme "PlanTracker" \
  -destination 'platform=macOS' build
```

### Build Codex Variant

```bash
open "PlanTrackerForCodex/PlanTracker/PlanTracker for Codex.xcodeproj"
```

or

```bash
xcodebuild -project "PlanTrackerForCodex/PlanTracker/PlanTracker for Codex.xcodeproj" \
  -scheme "PlanTracker for Codex" \
  -destination 'platform=macOS' build
```

## Notes

- The repository root is now a workspace container.
- Day-to-day development should happen inside `PlanTrackerForClaude/` or `PlanTrackerForCodex/`.
- Keep App Store submission assets in each variant's own `Appstore/` directory.
