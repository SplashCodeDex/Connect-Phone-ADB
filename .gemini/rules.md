# DeX — Project Rules

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
- Verify script syntax and AST correctness.
- Re-pack MSIX package using `PackMSIX.ps1`.
- Re-sign MSIX package using `SignMSIX.ps1`.
- Perform local execution verification to ensure zero runtime regressions.

## 4. Git Commit & Release Protocol
- Update `CHANGELOG.md` with handwritten, precise notes.
- Git commit with standardized tag prefixes (`[fix]`, `[minor]`, or `[major]`).
- Push changes to remote repository (`git push`).
