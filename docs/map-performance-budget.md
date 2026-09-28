# Map performance budget

"The map works flawlessly" is an opinion. This file is the number it has to stand for.

## What is measured

One frame of the flat map: the coastline casing pass, then a fill and an interior border for
every country. `Canvas` hands exactly these calls to Core Graphics, so rasterising the same
`CGPath`s into a bitmap context measures the same work without needing a running view or a
frame rate to watch.

The geometry is the real bundled geometry, built through `FlatMapShapeCache` in both variants:

| Variant | Where it is used | What it is |
| --- | --- | --- |
| `.light` | the dashboard card, the onboarding welcome screen | simplified rings |
| `.full` | the map screen | full rings |

Canvas is 1200 × 1200 px, which is roughly a full-screen map; 20 frames are timed after one
untimed warm-up frame, and the average is reported.

## The measurement machine

**iPhone 17 Pro simulator, iOS 26.1, on an Apple silicon Mac.**

This is not a device measurement, and it should not be read as one. A simulator rasterises on
the host CPU and shares that CPU with whatever else is building at the time. What the numbers
are good for is comparison: the same workload, measured the same way, before and after a
change. What they are not good for is predicting a frame rate on an iPhone.

A real device number is still missing and is worth taking once there is hardware to take it on:
run the same suite with `-destination 'platform=iOS,name=<device>'` and record the result here
as a second row rather than replacing this one.

## The budget

| Measurement | Measured | Enforced ceiling | Constant |
| --- | --- | --- | --- |
| `.full` frame | 60–65 ms | 130 ms | `MapPerformanceBudget.fullFrameMilliseconds` |
| `.light` frame | 11–13 ms | 26 ms | `MapPerformanceBudget.previewFrameMilliseconds` |
| `.light` ÷ `.full` | 0.18–0.20 | 0.30 | `MapPerformanceBudget.previewCostShare` |

The two absolute ceilings sit at twice the measured value on purpose. They are there to catch a
change that costs an order of magnitude — a stroke that leaves the hairline fast path, a pass
that runs per country instead of once — not to fail on a Mac that happens to be busy. The ratio
is the tight one: it is two measurements taken seconds apart on the same machine, so noise
cancels out of it, and it is the number that actually protects the dashboard.

The `.full` figure is a worst case the interactive map never draws. It renders the whole world
at once; on screen the camera is zoomed in, and `ScaledPathCache` and clipping keep most of that
geometry out of the pass.

## The preview stays on `.light`

`MapDetailRequest` carries the three switches that decide the level of detail — selection,
interaction, labels — and resolves them: all three off means `.light`, anything on means
`.full`. The dashboard and the onboarding screen name `MapDetailRequest.preview`, the map screen
names `MapDetailRequest.interactive`, and no call site spells the switches out any more.

That is what makes the rule testable rather than merely intended.
`MapPerformanceBudgetTests` asserts that `.preview` leaves all three switches off and resolves
to `.light`, that each switch on its own forces `.full`, and that the light geometry carries
less than half the path segments of the full geometry. A ticket that wants labels on the
dashboard has to change `MapDetailRequest.preview`, which fails those tests on the same commit —
which is the moment somebody reads this file.

## Repeating the measurement

From the `Countries/` directory:

```bash
xcodebuild -scheme Countries -project Countries.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CountriesTests/MapPerformanceBudgetTests
```

The suite prints its measurements, which is what gets pasted into a ticket:

```
MAPBUDGET full measured=59.58ms budget=130.0ms
MAPBUDGET light measured=11.04ms budget=26.0ms
MAPBUDGET share measured=0.1778 budget=0.3
```

Run it on an otherwise idle machine. A parallel build in another window moves the absolute
numbers by tens of percent; the share barely moves at all, which is the other reason it is the
assertion worth trusting.

## The rule for map tickets

Every ticket that touches `App/Map/` records two blocks in its pull request: the three
`MAPBUDGET` lines from before the change, and the three from after. Unchanged numbers are a
result and are worth writing down — most map work should not move them, and a ticket that moves
them without saying why is the case this budget exists to catch.

A ticket that legitimately makes the map more expensive raises the ceiling in
`MapPerformanceBudget` **in that ticket**, with the new measurement in the commit message. The
constant moving is the record that a trade was made deliberately.
