# ForensicKit

> macOS forensic data collection framework & CLI tool — built with Swift Package Manager.

## Requirements
- **Swift 6.3+** (check: `swift --version`)
- **macOS 13 Ventura** or later
- **No Xcode required**

## Build

```bash
# Resolve dependencies and build
swift build

# Run CLI (placeholder until Phase 5)
swift run forensic-kit

# Run all tests
swift test
```

## Project Structure

```
forensic-kit/
├── Package.swift                  # SPM manifest
├── Sources/
│   ├── ForensicKit/               # Core library (phases 1-4)
│   └── ForensicKitCLI/           # CLI executable (phase 5)
├── Tests/
│   └── ForensicKitTests/          # Swift Testing suite
├── specs/
│   ├── 00-project-overview.yaml
│   ├── phase-0.yaml  ✅
│   ├── phase-1.yaml  (draft)
│   └── tools/
│       └── spec-verify.sh         # Local spec validator
└── CHANGELOG.md
```

## Spec Validation

```bash
# Validate a phase spec (requires: brew install yamllint)
bash specs/tools/spec-verify.sh specs/phase-1.yaml --dir Sources/
```

## Git Workflow

```
feat/phase-N  →  dev  →  main
```

Commit format: `<type>(<scope>): <message>`  
Examples: `feat(process): add ProcessTreeService`, `fix(memory): correct checkpoint interval`

## Git Tag Signing (optional)

To use signed tags, configure GPG:
```bash
git config --global user.signingkey <YOUR_KEY_ID>
git tag -s v0.1.0-alpha -m "Phase 1 complete"
```

Without signing: `git tag v0.1.0-alpha -m "Phase 1 complete"`

## License

MIT
