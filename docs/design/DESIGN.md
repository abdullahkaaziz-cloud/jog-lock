# Race Day · Track

Jog Lock's look: warm paper, ink and track red, with your progress drawn round
a 400 m running track. Chosen on 25 November 2026 from three directions and
five Race Day variations (canvas page "Directions"). All 32 screens are on the
canvas page "App screens": https://claude.ai/artifact/LamBcR6W76sUgBGoQqtjHj

## Decisions

- Light look only (`UIUserInterfaceStyle` Light). The paper and ink are the brand.
- Four tabs: Today, Runs, Lock, Settings. The plan opens from the "3 km a day"
  button on Today.
- Card layout: rounded cards and chips on paper.
- The receipt idea lives where it fits: the weekly time on apps report (PAID
  stamp) and a Receipt style for share cards.

## Tokens (`JogLockTracker/Design/Theme.swift`)

| Name | Hex | Use |
|---|---|---|
| `JL.paper` | #F3EFE6 | screen background |
| `JL.card` | #FFFDF8 | cards, lists, sheets |
| `JL.sand` | #E7E1D5 | chips, quiet buttons |
| `JL.infield` | #E9E2D3 | inside the track |
| `JL.line` | #CFC6B6 | hairlines, dashed rules |
| `JL.ink` | #17140F | text, progress, ink buttons |
| `JL.ink2` | #5E584F | secondary text |
| `JL.red` | #C8321A | the track, primary buttons |
| `JL.redText` | #A82A14 | red words on paper |
| `JL.redOnInk` | #E0482C | red marks on ink |

Type: Archivo cut into three fixed fonts (`JogLockTracker/Fonts`, made by
`Tools/fonts/make_fonts.py` from Google's variable Archivo, SIL Open Font
License). `Font.jlDisplay` (black, 122% width) for big numbers,
`Font.jlDisplayItalic` for the unlock moment, `Font.jlHeading` (extra bold,
112% width) for headings and button labels in capitals. Everything else is the
system font (SF Pro). Numbers use tabular digits.

## The track (`JogLockTracker/Design/Track.swift`)

A stadium: red lanes with two thin white lane lines, an infield, and your
progress drawn in ink round the inner lane, clockwise from the white
start/finish line, with a runner dot at the head. Horizontal on Today, tall
during a run. Styles: `track` (red), `done` (full loop, ink infield),
`rest` (sand, dashed lines), `paused` (sand, grey progress), `intervals`
(ink infield, progress as usual, for the 5K plan's runs and walks). The geometry
(`TrackGeometry` in JogLockCore) is tested on Linux.

## Components (`JogLockTracker/Design/`)

- Buttons: `.jlPrimary` (red pill, 58 high, capitals), `.jlInk`,
  `.jlOutline`, `.jlChip` (sand, two lines), `.jlSmall`.
- `JLCard`, `SectionLabel`, `JLListRow`, `AppTiles` (icons of the chosen apps
  from Screen Time), `WeekBars`.
- Tab bar, toolbars and sheets are the system ones: Liquid Glass on iOS 26 and
  later, the classic look on iOS 18.

## After a run

The run screen covers the tabs until the run is saved. A run that unlocked
the apps then shows the unlock moment (red, UNLOCKED in italics, the run's
day, distance and time), otherwise its summary: the route on a muted map,
how it was counted, the shoes, Share card and Make a reel. Share cards come
in three styles, Track, Route and Receipt; the reel is drawn on a paper map
and only opens the lock if the run met its target.

## Behaviour the design adds

Onboarding · hold to finish a run · Receipt share card · red shield with
Jog Lock's own icon · run-only switch on the Lock tab · "Run more" on an
unlocked day.
