# Connect Phone ADB — Project Rules

## 1. Minimalist Execution (`/ponytail`)
- **Always enforce `/ponytail` ladder**:
  1. Does this need to exist at all? (YAGNI)
  2. Already in codebase? (Reuse helper/util/pattern)
  3. Standard library / Native platform feature?
  4. Shortest diff that solves root cause.
- No unrequested abstractions, zero bloat, no unused speculative code or placeholders.

## 2. Deep Edge-Case Reasoning & Investigation
- After every edit, auto-reason and evaluate all potential edge cases (e.g. disconnections, null targets, missing binaries, focus loss, threading, UI responsiveness).
- Resolve all identified edge cases until zero edge cases remain.

## 3. Automated Verification & MSIX Build Protocol
- **Version Bump (before build):** Bump `Version` in [`AppxManifest.xml`](file:///w:/CodeDeX/Connect-Phone-ADB/MSIX_Source/AppxManifest.xml) based on what was implemented:
  - **Patch** (`X.Y.Z+1.0`) — bug fixes, minor tweaks.
  - **Minor** (`X.Y+1.0.0`) — new features, UI additions.
  - **Major** (`X+1.0.0.0`) — breaking changes, architecture overhauls.
  - `PackMSIX.ps1` auto-syncs this version to `ConnectPhoneADB.appinstaller`.
- Verify script syntax and AST correctness.
- Re-pack MSIX package using `PackMSIX.ps1`.
- Re-sign MSIX package using `SignMSIX.ps1`.
- Perform local execution verification to ensure zero runtime regressions.

## 4. Git Commit & Release Protocol
- Update `CHANGELOG.md` with handwritten, precise notes.
- Git commit with standardized tag prefixes (`[fix]`, `[minor]`, or `[major]`).
- Push changes to remote repository (`git push`).

## 5. Bleeding Edge Dependency Protocol
- Always prefer the absolutely latest modern versions of frameworks/libraries (e.g. Ktor 3.x+ over Ktor 2.x).
- Auto-trigger the `/stale-knowledge-research` protocol proactively whenever introducing a dependency or making architectural decisions to ensure you aren't referencing deprecated APIs.
