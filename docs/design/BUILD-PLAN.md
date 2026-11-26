# Building the Race Day · Track design

The design is on the canvas: https://claude.ai/artifact/LamBcR6W76sUgBGoQqtjHj
(page "App screens"). Tokens, components and decisions: [DESIGN.md](DESIGN.md).

Each step is one branch and one pull request, stacked on the one before
(the first on #19). Every step leaves the app working, and CI (Linux core
tests and the unsigned iOS build) is green before the next step starts.

| # | Step | Branch | Status |
|---|------|--------|--------|
| 1 | Foundation: fonts, colours, buttons, the track, light look | `design/1-foundation` | done (#20) |
| 2 | Four-tab shell: Today, Runs, Lock, Settings | `design/2-tabs` | done (#21) |
| 3 | Today: track hero and its states, start row, chips, buddy | `design/3-today` | done (#22) |
| 4 | Live run: tall track, intervals, treadmill, Nice try, hold to finish | `design/4-live-run` | done (#23) |
| 5 | After the run: unlocked, summary, share card styles, reel | `design/5-after-run` | done (#24) |
| 6 | Runs: month view, run detail, your month | `design/6-runs` | done (#25) |
| 7 | Lock: lock tab, websites, borrow sheet, buddy, time on apps | `design/7-lock` | done (#26) |
| 8 | Plan and settings: plan, Couch to 5K, settings, shoes | `design/8-plan-settings` | done (#27) |
| 9 | Onboarding: welcome, apps, distance, permissions, ready | `design/9-onboarding` | done (#28) |
| 10 | Outside the app: shields and the Live Activity | `design/10-outside` | done (#29) |

Status words: `to do`, `in progress`, `done (#PR)`.
