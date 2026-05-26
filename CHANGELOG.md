# Changelog

All notable changes to ForensicKit follow [Conventional Commits](https://www.conventionalcommits.org/).

---

## [Unreleased]

---

## [Phase 0] — 2026-05-26

### Added
- `Package.swift` — multi-target SPM manifest (ForensicKit · ForensicKitCLI · ForensicKitTests)
- `Sources/ForensicKit/ForensicKit.swift` — scaffold library placeholder (v0.0.0-scaffold)
- `Sources/ForensicKitCLI/main.swift` — CLI entry point placeholder
- `Tests/ForensicKitTests/ForensicKitTests.swift` — Swift Testing smoke test
- `specs/00-project-overview.yaml` — project-level spec index
- `specs/phase-0.yaml` — Phase 0 spec (REQ-000)
- `specs/tools/spec-verify.sh` — offline spec validator (yamllint + traceability check)
- `.gitignore` — SPM-appropriate ignores
- `README.md` — SPM build/test/validate documentation

### Spec Delta
- `specs/phase-0.yaml` status: `draft` → `verified`

### Commit
```
chore(phase-0): spm scaffold + spec tooling
```
