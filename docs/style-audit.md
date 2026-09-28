# Style audit

`swift-general-rules.md` has been binding since 2026-09-26. This is what the codebase looks
like against it, re-run on 2026-09-28 across all 91 Swift files.

The approach A-05 sets is deliberate and unchanged: **a file is brought in line when another
ticket touches it anyway.** A style sweep across every file, with the test coverage this
project had when the rule was written, is exactly how working code breaks. What is fixed
immediately, independently of other tickets, are the two categories that are real defect
sources rather than matters of form.

## The two defect categories: both clean

### Force-unwrap, force-cast, force-try

**None left.** No `try!`, no `as!`, and no postfix `!` on a value anywhere in the app target.

Three implicitly unwrapped optionals remain, and all three are the case the rules exempt —
a programmatically created view assigned once during setup and never nil afterwards. Each
one carries a doc comment saying so:

| Declaration | Assigned in |
| --- | --- |
| `MapViewController.mapHost` | `setUpMapHost()` |
| `MapSheetCoordinator.bottomSheetAnchorView` | `attach()` |
| `MapSheetCoordinator.bottomSheetAnchorCenterXConstraint` | `attach()` |

One `fatalError` remains, in `MapViewController.init(coder:)`, which is the form Apple
prescribes for a controller that is only ever created programmatically.

### Escaping closures capturing `self`

**Clean.** All twelve escaping closures that capture `self` use `[weak self]` and rebind it
as `guard let strong = self`, never re-shadowing `self`:

| File | Closures |
| --- | --- |
| `MapSheetCoordinator.swift` | 11 |
| `MapViewController.swift` | 1 |
| `TripDeletionCoordinator.swift` | 1 |

## The 2026-09-26 findings, revisited

Four findings were named when the rule was adopted. Three of them no longer exist, and it is
worth saying why rather than quietly ticking them off:

| Finding | Status |
| --- | --- |
| `PreferenceDerivationService.swift:92, :104` — `allCases.last!` / `.first!` | **File gone.** `Common/Services/Recommendations/` was removed with the recommendation stack. |
| `WikimediaService.swift:89`, `UnsplashService.swift:87` — rebind `[weak self]` as `self`, `defer` holds a strong reference | **Files gone.** `Common/Services/API/` was removed with the photo stack. |
| `FlatPathBuilder.swift:274` — force-unwrap | **Fixed.** No force-unwrap remains in the file. |
| `MapViewController.swift:74, 99, 100` — implicitly unwrapped optionals dereferenced in `viewDidLayoutSubviews` | **Moved, still IUOs.** Two of the three now live in `MapSheetCoordinator` after M-02. They are the exempt case and are documented as such; the dereference in the layout pass happens after `attach()` has run. |

## What is left, per file

Nothing below is a defect. These are the matters of form that the A-05 approach brings in
line as other tickets touch the files.

### Comments not in English — 1

| File | Line |
| --- | --- |
| `Common/SwiftData/CountrySeeder.swift` | 11 — `// JSON-DTO: Data Transfer Object um die items aus der JSON eins zu eins zu übertragen` |

This is the last German comment in the codebase. It records nothing measured, so it can be
rewritten in English rather than translated carefully.

### Primary type without a doc comment — 6

| File | Type |
| --- | --- |
| `App/Map/Flat/FlatPathBuilder.swift` | `FlatPathBuilder` |
| `Common/SwiftData/Country.swift` | `Country` |
| `Common/SwiftData/Country+Enums.swift` | `CountryStatus` |
| `Common/SwiftData/CountryIndex.swift` | `CountryIndex` |
| `Common/SwiftData/CountrySeeder.swift` | `CountryJSON` |
| `Common/Utils/CircularStrokeGaugeStyle.swift` | `CircularStrokeGaugeStyle` |

`Country` is the one that matters: it is the identity the whole app is keyed on, its `iso2`
is stored uppercase but looked up lowercased by the map layers, and its localized names live
in JSON rather than in a relationship. None of that is written down on the type.

### Lines over 120 characters — 3

| File | Line | Length |
| --- | --- | --- |
| `Common/Utils/VisitedWithdrawalConfirmation.swift` | 50 | 166 |
| `App/Settings/SettingsScreen.swift` | 105 | 125 |
| `App/Onboarding/OnboardingWelcomeView.swift` | 60 | 122 |

### Trailing whitespace — 172 lines in 6 files

| File | Lines |
| --- | --- |
| `App/Map/Flat/FlatPathBuilder.swift` | 93 |
| `App/Map/Flat/FlatMapCamera.swift` | 36 |
| `App/Map/Flat/FlatMapView.swift` | 18 |
| `Common/SwiftData/Country.swift` | 11 |
| `Common/SwiftData/CountryIndex.swift` | 8 |
| `Common/SwiftData/CountrySeeder.swift` | 6 |

All six are files that predate the rule. `FlatMapCamera.swift` is also the one file still
written without the blank-line-after-signature spacing the rest of the map code uses.

## How this file is kept honest

Re-run the scans rather than trusting the table:

```bash
# force operations and implicitly unwrapped optionals
grep -rnE 'try!|\bas! ' --include="*.swift" Countries/

# weak-self rebinding
grep -rn "weak self" --include="*.swift" -A2 Countries/ | grep -E "guard let"

# lines over 120 characters
find Countries -name "*.swift" -exec awk 'length>120 {print FILENAME":"FNR" ("length")"}' {} \;

# trailing whitespace
grep -rnE ' +$' --include="*.swift" Countries/
```
