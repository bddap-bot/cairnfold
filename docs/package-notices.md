# Package notices

Cairnfold's own code and authored assets are MIT OR Apache-2.0; the two project
license files accompany this document. Third-party material retains its upstream
terms. Godot's `COPYRIGHT.txt` contains the component inventory and full license
texts, supplemented by the upstream license, notice, author and readme files.
These are a conservative source inventory, including optional components absent
from some binaries. The engine's OpenXR implementation is covered there.

The Frame archive contains `notices/` next to the launcher. The Quest APK contains
`assets/notices/`, readable with any ZIP reader without running the game. No game
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

Steam's Frame bundle contains no vendor addon or Meta SDK, so those SDK-specific
restrictions do not attach to that bundle. Selling on Steam does not itself
require Meta attribution. A future Steam build incorporating SDK material would
need the approved-product restriction and other SDK terms reassessed.

The agreement also governs privacy/data handling, platform behavior and
experimental features (§§1.2, 1.4, 1.6). Notices alone do not establish store
approval or compliance with those behavioral requirements. SDK use is subject
to the agreement's update provisions (§7.1).

## Building and checking

`scripts/pins.sh` is the source of download versions and hashes. Both builders
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

Both builders compare every expected notice byte-for-byte against the completed
archive, after APK signing. `scripts/test.sh` also tests rejection of missing and
truncated notices in both archive formats. To check an existing release, collect
its expected notices from the matching revision and run
`scripts/notices.py check PACKAGE EXPECTED_DIRECTORY`; for APKs the expected tree
also includes the build's generated Android dependency notices.
