# MacWiki

A native macOS Wikipedia client featuring Liquid Glass design and a powerful four-column research interface.
## Project Overview

MacWiki reimagines Wikipedia reading on macOS with:
- **Four-column layout**: Lists → Directory → Reader → Inspector
- **Readwise sync (planned)**: Highlight text and sync directly to your Readwise library
- **Tab support**: Browse multiple articles with browser-like tabs
- **Keyboard-first**: Full navigation without touching the mouse
- **Offline reading**: Save articles for later

## Requirements

- macOS 26.0+
- Xcode 26+ (optional, for debugging)
- Swift 6.2+
- Apple Developer account (for App Store distribution)

MacWiki intentionally targets macOS 26 and newer so the app can lean on the current SwiftUI, AppKit, and Liquid Glass system behavior without carrying older-system compatibility branches.

## Quick Start

```bash
# Open in Xcode (SPM)
xed .

# Build from command line
swift build

# Run the app
.build/debug/MacWiki
```

## Project Structure

```
MacWiki/
├── Sources/MacWiki/
│   ├── App/           # Application entry point
│   ├── Models/        # Data models
│   ├── Services/      # API and persistence
│   ├── Views/         # SwiftUI views
│   └── Utilities/     # Helpers and extensions
└── Tests/             # Unit and UI tests
```

## Open Source

MacWiki is open source primarily so people can clone it, modify it, and build their own versions.

- Hacking guide: `CONTRIBUTING.md`
- Conduct: `CODE_OF_CONDUCT.md`
- Security reporting: `SECURITY.md`

## License

Apache-2.0. See `LICENSE`.

## Trademark

The MacWiki name and logo are trademarks. See `TRADEMARK.md`.
