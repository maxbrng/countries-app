# One feature, three platforms

A feature is not done until it works on iPhone, iPad and Mac. This file is what "works"
means, so that a ticket can be checked against something rather than against an opinion.

Every feature pull request copies the block at the bottom into its body and fills it in.
A ticket that covers one platform and leaves the others for later is not finished; it is
split, and the remaining platforms get their own ticket.

## Why this is a rule and not a habit

The three platforms fail differently, and two of the three failures are invisible on the
one being developed on:

- **iPhone** is where everything is written, so it is the one that is never wrong.
- **iPad** breaks on *size*, not on API. A layout that is correct at 402 pt wide is often
  merely stretched at 820 pt, and a Split View at a third of the screen puts an iPad back
  into the compact size class mid-session, while the app is running.
- **Mac** breaks on *input and idiom*. There is no touch, no sheet chain, no tab bar, and
  an empty menu bar is the clearest sign of a ported iPad app. It also compiles code that
  iOS accepts but should not: see the note on default isolation below.

## What to check

### 1. It builds for all three

```bash
xcodebuild -scheme Countries -project Countries.xcodeproj -destination 'generic/platform=iOS Simulator' build
```

For a file that is not in the Mac target yet, a standalone type-check is enough and is
much faster than a full build:

```bash
xcrun swiftc -typecheck -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macosx26.0 -swift-version 6 -default-isolation MainActor <files>
```

`-default-isolation MainActor` is not optional. The app target sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and leaving it out of the probe produces a
misleading `Animatable` conformance error instead of the real problem. This check is how
`PlatformColor`'s helpers were found to be inheriting main-actor isolation while being
called from a `@Sendable` colour provider — a genuine concurrency bug that the iOS build
compiles without complaint, because UIKit's own provider is not declared `@Sendable`.

### 2. It runs on all three

| Platform | Minimum pass |
| --- | --- |
| iPhone | portrait and landscape, both orientations reached by rotating while the feature is on screen |
| iPad | full screen in both orientations, **and** Split View at one third width |
| Mac | window at its smallest allowed size and at full screen, and a resize in between |

Rotating and resizing *while the feature is on screen* is the part that finds things. A
feature that is correct when entered fresh in each configuration can still be wrong when
the configuration changes under it — the map's sheet chain has regressed that way more
than once, which is why `MapSheetChainUITests` drives rotation rather than trusting it.

### 3. Input works on all three

- Touch: tap, drag, pinch, long press.
- Pointer: click, scroll wheel, trackpad pinch, hover where hover means something.
- Keyboard: every action reachable by shortcut has a menu item that shows the shortcut.

Shared input goes through a protocol with one implementation per platform, not through
`#if` inside a view. `MapGestureSurface` is the pattern: `MapGestureHandlers` carries the
nine closures, `TouchMapGestureSurface` and `PointerMapGestureSurface` implement them, and
`PlatformMapGestureSurface` picks one. The call site names neither platform.

### 4. Platform differences are resolved in one place

There is a small set of files whose whole job is to answer "what is this called here":

- `PlatformColor`, `PlatformFont` — `UIColor`/`NSColor`, `UIFont`/`NSFont`
- `PlatformDisplayLink` — `CADisplayLink` vs `NSScreen.displayLink`
- `MemoryPressureSignals` — which notifications mean "give memory back"
- `MapGestureSurface` — touch versus pointer

A new difference belongs in a file like these, not in a `#if` in a view. If a view needs
to know which platform it is on, that is usually a sign the difference is a *layout*
decision, and layout decisions belong in one view with different numbers — not in two
views. See H-02: "no third code path: one view, different layout decisions."

### 5. Nothing regressed

- The full test suite passes: unit tests plus `CountriesUITests`.
- A feature that touches `App/Map/` records its `MAPBUDGET` numbers before and after, per
  `docs/map-performance-budget.md`.

## What does not count

- "It compiles for macOS" is not "it runs on macOS".
- "It looks fine on the iPad simulator in landscape" is not iPad coverage without Split
  View, which is where the size class actually changes.
- A screenshot of the feature working is not a check that the *other* two platforms still
  work; that is what the test suite is for.

## The block to paste into a pull request

```markdown
### Platforms

- [ ] iPhone — portrait, landscape, rotated while on screen
- [ ] iPad — full screen both orientations, Split View at one third width
- [ ] Mac — smallest window, full screen, resized in between
- [ ] Pointer and keyboard paths work, and every shortcut has a menu item
- [ ] Full test suite passes
- [ ] MAPBUDGET before/after recorded (map tickets only)

Not covered, and why:
```

The last line is not decoration. A platform left out is a fact about the ticket, and
writing it down is what turns it into the next ticket instead of into a surprise.
