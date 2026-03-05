# MacWiki and Open Source

MacWiki is open source so people can clone it, learn from it, and build their own variants.

There is no strict contribution process right now. If you want to experiment, fork it and run with it.

## Quick local run

```bash
swift build
swift test
.build/debug/MacWiki
```

## If you want to share changes back

You can open an issue or PR, but it is optional and informal for now.

Useful validation commands before sharing:

```bash
swift build
swift test
```

## Local-only files

The repository intentionally excludes local machine and agent files:

- `.agent/`
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `ANTIGRAVITY.md`
- `.build/`, `.swiftpm/`, cache/profiler outputs

## Conduct

Please be respectful and collaborative. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
