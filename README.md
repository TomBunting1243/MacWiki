# MacWiki

MacWiki is a native macOS Wikipedia client that makes research a pleasure. It combines the depth of Wikipedia with the polish of Apple's best apps, with Readwise integration reserved for a future release.

Wikipedia on the web is cluttered, disconnected from a reader's research workflow, awkward for keyboard-driven work, and poorly suited to comparing articles. MacWiki approaches those problems as a native Mac app:

- **Focuses on content:** A four-column layout—Lists → Directory → Reader → Inspector—puts articles front and center.
- **Prepares for connected workflows:** Local highlights are first-class today; bidirectional Readwise sync is planned, not implemented.
- **Embraces the keyboard:** Navigate the app without reaching for the mouse.
- **Enables comparison:** Tabs and multiple windows support deep research across articles.
- **Keeps work available:** Save articles and reading lists locally for later.

## Design Philosophy

### Apple-native feel

MacWiki should feel like it shipped with macOS. Interactions follow Apple's Human Interface Guidelines, while Liquid Glass gives the interface depth without turning translucency into a gimmick.

### Research first

The app is optimized for deep research sessions rather than casual browsing. Reading lists, annotations, article metadata, references, and connections are treated as first-class parts of the reading experience.

### Keyboard power

Power users can move through the app by keyboard, with standard shortcuts and quick actions that behave as expected on macOS.

### Connected knowledge

Articles do not exist in isolation. The Inspector surfaces metadata, references, highlights, and the context around what you are reading.

### Performance is the product

MacWiki is only worth building if it feels alive in motion. Reader scrolling and table-of-contents navigation should feel fluid enough that the interface disappears and the reading flow remains intact. Safari on the same Mac is the baseline to meet or beat.

## An Experiment in Building with AI

MacWiki is also a record of sustained human–AI collaboration on a real native application. AI agents have helped explore unfamiliar APIs, implement features, investigate regressions, write tests, and maintain the project's technical documentation. Product direction, scope, acceptance criteria, and final judgment remain human-owned.

The interesting part is not that AI produced code. It is the control system around that work:

- Product intent lives in explicit vision and specification documents rather than in chat history.
- Behavioral tests and real-app checks are preferred over assertions about source-code shape.
- Accessibility, persistence safety, and perceived performance are release requirements.
- Experimental changes are recorded as small, inspectable commits instead of one generated code drop.
- Documentation distinguishes current behavior from planned features; Readwise sync, for example, is deliberately described as deferred rather than implemented.
- AI-generated changes are expected to survive build, test, review, and evidence gates before they are treated as complete.

Read [AI_COLLABORATION.md](AI_COLLABORATION.md) for the working method, representative examples, and lessons from the experiment.

## Requirements

- macOS 26.0+
- Xcode 27 (for the official Xcode Tools MCP sign-off and IDE diagnostics)
- Swift 6.2+

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

## Internal Beta Quality Program

The active readiness contract is `INTERNAL_BETA_QUALITY_PROGRAM.md`. It requires
traceable clean candidates, exhaustive interface and journey evidence, isolated
test data, accessibility and Liquid Glass review, and final official Xcode 27 MCP
verification.

Run the CLI-backed gates and create a traceable ad-hoc package with:

```bash
./scripts/internal_beta_preflight.sh
```

This command is a documented fallback, not a substitute for the official Xcode
27 MCP evidence required by the quality program. The former public-beta matrix,
checklist, and release automation are retained only as explicitly retired history.

## Project Structure

```
MacWiki/
├── Sources/MacWiki/
│   ├── App/           # Application entry point
│   ├── Models/        # Data models
│   ├── Services/      # API and persistence
│   ├── Views/         # SwiftUI views
│   └── Utilities/     # Helpers and extensions
└── Tests/             # Unit tests
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
