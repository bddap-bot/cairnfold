# Package notices

Cairnfold's own code and authored assets are MIT OR Apache-2.0; the two project
license files accompany this document. Third-party material retains its upstream
terms. Godot's `COPYRIGHT.txt` contains the component inventory and full license
texts, supplemented by the upstream license, notice, author and readme files.
These are a conservative source inventory, including optional components absent
from some binaries. The engine's OpenXR implementation is covered there.

Each desktop package (`scripts/package.sh`: Windows, Linux x86_64 and the Frame's
Linux arm64) contains `notices/` next to the game binary. The Quest APK and the
Frame's Android APK (`scripts/android.sh lepton`) contain `assets/notices/`,
readable with any ZIP reader without running the game. No game
screen is needed. Cinzel's OFL is included for the Steam artwork; the font binary
is not shipped and OFL does not impose its font redistribution terms on images
rendered with it.

## Quest vendor terms

The [Meta SDK agreement](https://developers.meta.com/vr/licenses/oculussdk/)
permits application distribution with designated SDK materials for approved
products (§1.1). Quest is the intended target. Preserve terms, links, and copyright
notices (§§1.2.7, 1.3); the package includes the original SDK notice and link plus
the required Meta copyright attribution. This does not relicense SDK material
under Cairnfold's licenses (§1.2.8). Third-party open-source terms control their
components (§3.2): the addon’s Meta flavor actually bundles the Khronos loader
under Apache-2.0. Its license and the addon/bindings licenses are included.

The desktop packages, the Frame's Linux export among them, contain no vendor addon or Meta SDK, so those SDK-specific
restrictions do not attach to them. Selling on Steam does not itself
require Meta attribution. A future Steam build incorporating SDK material would
need the approved-product restriction and other SDK terms reassessed.

The agreement also governs privacy/data handling, platform behavior and
experimental features (§§1.2, 1.4, 1.6). Notices alone do not establish store
approval or compliance with those behavioral requirements. SDK use is subject
to the agreement's update provisions (§7.1).

## Horizon Store package

`scripts/android.sh quest OUT store` builds the Quest APK the Horizon Store gets, which `scripts/release.sh` uploads to
its ALPHA channel. It adds the Godot Meta Toolkit GDExtension (MIT, its license in `notices/godot-meta-toolkit/`) and
the Meta Platform SDK loader it carries, SDK material under the same Meta SDK agreement as the vendor addon above. The
build fetches the toolkit's release at the version and hash pinned in `scripts/pins.sh`. The Quest APK published
elsewhere carries neither.

## Frame Android package

The Lepton APK uses the addon's Khronos flavor: its Android library carries only
the Khronos OpenXR loader (Apache-2.0) and the addon's own GDExtension, built from
the MIT addon sources against Khronos headers. The build deletes every other
vendor's Android library before export and refuses a manifest naming Meta, so the Meta SDK agreement does not attach to this package. It ships the
Godot, Android dependency and NDK runtime notices, the addon and godot-cpp licenses,
and the Khronos loader license in `openxr-vendors/khronos/LICENSE`.

## Steam packages

`scripts/package.sh TARGET OUT steam` and `scripts/android.sh lepton OUT steam` add the
GodotSteam GDExtension (MIT, its license in `notices/godotsteam/`) and the `steam_api` library for that platform, which
Valve's [Steamworks SDK Access Agreement](https://partner.steamgames.com/documentation/sdk_access_agreement)
lets a game redistribute "along with the Licensee Software in object code form" (§1.1(b)).
The same agreement licenses the rest of the SDK, its headers included, only to "use and
locally reproduce", so this repository holds neither: the build fetches GodotSteam's release
at the version and hash pinned in `scripts/pins.sh`, and `game/addons/godotsteam/` is
ignored by git. Packages built without `steam`, and every Quest APK, carry no Steam code at all. The agreement's
§5 ("No Exclusivity") leaves the game free to ship the same code elsewhere; Steamworks'
[key rules](https://partner.steamgames.com/doc/features/keys) govern Steam keys sold
elsewhere, not builds.

## Engine

Every package, desktop and Android, runs an engine `scripts/engine.sh` builds from the pinned Godot source with
`scripts/engine.patch` applied, with the official template's build flags less AccessKit's static library and, on
Windows, ANGLE and the Direct3D 12 driver. Linux builds use Godot's own buildroot SDKs, Windows llvm-mingw
(`toolchains.nix`, pinned in `scripts/pins.sh`), Android the NDK revision of the official template. The patch modifies
MIT-licensed Godot sources only and adds no component, so the source notices above cover the binaries; it is part of
this repository's source under its licenses. `SOURCES.txt` records the source and the patch's SHA256.

Linux templates link only components in Godot's source tree, so `COPYRIGHT.txt` and the extracted upstream files cover
them; Godot's embedded OpenXR loader is among them. The Windows template is built without the Direct3D 12 driver, so
it links no Mesa NIR, WinPixEventRuntime or Agility SDK, and statically links two components outside that tree from
the llvm-mingw toolchain it was built with: the MinGW-w64 runtime and LLVM's C++ runtime, whose license texts the
Windows package adds under `notices/windows/`. Both APKs carry Godot's official Android release library at the pinned
version with that engine as its `libgodot_android.so`.

## Building and checking

`scripts/pins.sh` is the source of download versions and hashes. Every builder
call `scripts/notices.sh`, which extracts original upstream text from the matching
source releases and verified addon ZIP. A changed version with an old hash fails
closed. When updating the addon, update its godot-cpp submodule license pin too.
`SOURCES.txt` records provenance without build-machine paths. Full upstream texts
retain their authorship and copyright years unchanged.

Android's Gradle task resolves the actual release runtime dependencies and
collects their embedded notices and source copyright headers, with the complete
Apache-2.0 text. It fails if a dependency's sources or notices cannot be obtained.
`android/DEPENDENCIES.txt` records the resolved coordinates. The NDK runtime notices cover native support
code linked into Android binaries. Their pinned revision must match both upstream
build configurations. Build tools are not included in the Maven runtime inventory. Review changed dependency licenses on upgrades.

Every builder compares every expected notice byte-for-byte against the completed
archive, after APK signing. `scripts/test.sh` also tests rejection of missing and
truncated notices in every archive format. To check an existing release, collect
its expected notices from the matching revision and run
`scripts/notices.py check PACKAGE EXPECTED_DIRECTORY`; for APKs the expected tree
also includes the build's generated Android dependency notices.

## Human-recorded motion

`LICENSE-CMU` ships in every package through the existing `LICENSE-*`
collection. It records the CMU Graphics Lab source, commercial-product terms,
the requested acknowledgment, and each trial used: 141_16, “Wave Hello”, and the
single frames of trials 140_01, 140_03, 140_08, 82_05 and 14_31 that avatars lie
and sit in, with every original file's hash. The original ASF/AMC inputs are in
`third_party/cmu/`; `scripts/mocap.gd` converts them without authoring motion.
The data is not covered by the game’s code licenses.

A pose lying on the front propped on the elbows was looked for and not found:
CMU's lying and getting-up trials (140_01–04, 140_08–09, 77_16–18, 111_06,
114_11) hold push-ups and lying back on the elbows but not that pose, and
MakeHuman's CC0 pose packs (poses01–05) hold a yoga cobra on straight arms, a
push-up and a prostrate kneel. A player lying so shows the front pose, with the
head and hands where they are tracked.

VRoid’s official VRMA_02 Greeting was also checked at
https://vroid.booth.pm/items/5512385. Its commercial license requires attribution
and prohibits redistributing extractable motion or alterations, so it was not
selected for this source repository. CMU’s terms explicitly permit inclusion in
commercially sold products and prohibit selling the data itself.

Avatar Workshop's portable expression and spring components are pinned in
`game/addons/avatar_workshop/source.json`, with a SHA256 for every vendored file.
`LICENSE-avatar-workshop` carries its MIT and Apache-2.0 grants and the retained
godot-vrm MIT notice for the spring solver. The packaging scripts include this
file with the other root license notices on every target.
