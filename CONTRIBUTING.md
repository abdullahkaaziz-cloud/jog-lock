# Working on Jog Lock

This is how changes are made in this repo. It follows the
[agent-skills](https://github.com/addyosmani/agent-skills) workflow: define, plan, build in small steps with tests, verify, review, ship.

## Branches and commits

- `main` always builds and passes its tests. Nothing is committed to it directly.
- Each task gets a short-lived branch off `main`, named by kind:
  `feature/…`, `fix/…`, `refactor/…`, `chore/…`, `docs/…`, `test/…`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org):
  `feat(engine): …`, `fix(ui): …`, `test(tools): …`. The body says *why*.
- One concern per commit. Formatting-only changes go in their own commit.
- When branches depend on each other, their pull requests are stacked: each one targets the branch before it. Merge them in order, oldest first. GitHub retargets the next one to `main` when the previous branch is deleted.

## Checks to run before pushing

| What | Command |
|---|---|
| Swift unit tests | `cd Packages/JogLockCore && swift test` |
| Python mirror tests | `python3 Tools/test_engine.py` |
| Python lint and format | `ruff check Tools && ruff format --check Tools` |
| App build | Build the `JogLockTracker` scheme in Xcode, or let CI do it |

CI runs all of these on every pull request. The macOS build uses paid-for macOS minutes, so a newer push cancels the older run.

## Definition of Done

A change is done when its own acceptance criteria are met **and** all of this holds:

**Correctness**
- New behaviour is covered by tests that fail without the change. A bug fix starts with a test that shows the bug.
- Existing tests pass, including the real-run fixture in `Tools/fixtures/`, which both test suites replay.
- Logic that doesn't need an iPhone lives in `Packages/JogLockCore`, so it can be tested with `swift test`. The app keeps only the iPhone parts (location, motion, screens).
- A change to a distance rule is made in the Swift engine **and** in the Python mirror (`Tools/replay.py`). Both test suites check the same expected numbers.
- Anything that touches tracking is checked on a phone before a release (a jog, a walk, or a treadmill run as relevant).

**Quality**
- Lint and format pass. No dead code, debug prints or commented-out blocks.
- The change stays inside its task. Other things noticed go in the pull request's "didn't touch" list.

**Integration**
- New iPhone permissions have a usage string in `Config/Info.plist`, and `PrivacyInfo.xcprivacy` is updated if a new API category is used.
- Old run logs still replay. New log fields are optional.

**Documentation**
- README, CHANGELOG and ADRs (`docs/adr/`) are updated where relevant, describing how things are now rather than the history.

**Ship-readiness**
- No real GPS tracks or personal data are committed. Run `Tools/anonymize_log.py` on a log before using it as a fixture.
- No secrets in the repo. Signing keys and App Store credentials live in GitHub secrets, added by the repo owner.
- The repo owner has reviewed and approved the pull request before it's merged.
