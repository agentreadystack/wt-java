# Contributing to wt-java

Thanks for helping! wt-java is deliberately small: one portable Bash script, no runtime dependencies beyond git.

## Dev setup

```bash
git clone https://github.com/agentreadystack/wt-java && cd wt-java
./test/test.sh                       # core tests, no services needed
shellcheck bin/wt-java install.sh test/test.sh
```

Integration tests need Postgres and Redis (see the README "Tests" section for one-line Docker commands).

## Guidelines

- Keep it Bash 3.2 compatible (macOS default): no associative arrays, no `${var,,}`, no `mapfile`.
- `shellcheck` must pass with no findings.
- Every behavior change needs a test in `test/test.sh`.
- Never make a missing or unreachable Postgres/Redis fatal. Warn and continue.
- Never execute `.wt-java.conf`. It's parsed, and only known keys are accepted.
- Update the README and `CHANGELOG.md` when you add a flag or config key.

## Pull requests

1. Open an issue first for anything bigger than a bug fix.
2. One focused change per PR, with a clear description and test output.
3. CI must be green.

By contributing you agree your contribution is licensed under the MIT License.
