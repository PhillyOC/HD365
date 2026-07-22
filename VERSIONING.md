# Versioning

HD365 uses [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

## Source of truth

Module version lives in [`HD365.psd1`](HD365.psd1) as `ModuleVersion`.

- Git tags: `vX.Y.Z` (and `vX.Y.Z-beta.N` for pre-releases)
- Installer / zip filenames: `HD365-Setup-X.Y.Z.exe`, `HD365-X.Y.Z.zip`
- Work export zip: `HD365-work-X.Y.Z-YYYYMMDD.zip` (date stamp only; no "work" string in code)

## Current

**0.1.0** — first public release.

## Bumping

1. Update `ModuleVersion` in `HD365.psd1`
2. Update `CHANGELOG.md` (`[Unreleased]` → new section)
3. Commit, tag `vX.Y.Z`, push tag (release workflow builds artifacts)
