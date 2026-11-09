# Licences

Settings > About > Open source licences lists what the app bundles, in four groups:
App packages, Core crates, Fonts and Icons.

## Where each group comes from

- **App packages** (Dart and Flutter): Flutter's `LicenseRegistry`, as collected by the build.
- **Fonts**: `registerFontLicences` (`lib/src/app_licences.dart`) adds the OFL texts in
  `assets/fonts/licenses`.
- **Icons**: Lucide's entry in the registry.
- **Core crates**: the Rust crates compiled into the native library, the embedded
  BubblePaw Core included. `registerCrateLicences` reads a generated file at startup and
  adds one `CrateLicenceEntry` per crate and licence text to the registry, so they show in
  the same page. The page keeps a crate and a package of the same name as two rows.
  A row shows the crate version and the licence the crate declares (for example
  `Apache-2.0 OR MIT`).

## The generated files

`tool/licences.sh` runs `cargo about generate` (pinned: cargo-about 0.9.3) on
`native/Cargo.lock` and `tool/licences.py` condenses the result (each distinct licence text
once, then per crate its name, version, declared licence and text indexes):

| File | Config | Used by |
|---|---|---|
| `assets/licences/core-crates.json` | `native/about.toml` (targets: Linux and Windows x86_64) | the desktop app |
| `assets/licences/phone-crates.json` | `native/about-phone.toml` (`--no-default-features`, target: arm64 Android) | the phone app |

The phone app builds the crate without the embedded host, so its list is shorter and is
generated separately; `main_phone.dart` registers the phone file. Dev dependencies are left
out; build dependencies stay in. The phone list is derived from the cargo metadata of the
crate's own dependency graph, so it can include a crate that only a feature unified by a
dev dependency pulls in; it is a superset of what ships, never a subset.

The files are committed, so the app build does not need cargo-about.

## Keeping them current

- The `licences` job in `.github/workflows/ci.yml` regenerates both files and fails when
  they differ from the committed ones, so a change to `native/Cargo.lock` cannot merge
  without updated licences.
- To update: run `tool/licences.sh` where cargo-about 0.9.3 is installed, or run the `ci`
  workflow by hand (workflow_dispatch) and `git apply licences.patch` from the
  `licences-patch` artifact.
- `accepted` in the two config files is the list of allowed licences. A crate under any
  other licence fails the job; adding one to the list is a decision to make, not a fix.
  The BubblePaw Core crates are accepted as AGPL-3.0-only, their own licence and the one
  of this app.
