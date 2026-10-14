# Android runtime notices

Unmodified `NOTICE` and `NOTICE.toolchain` from
https://dl.google.com/android/repository/android-ndk-r28b-linux.zip,
whose `source.properties` declares `Pkg.Revision = 28.1.13356709`.
These cover native runtime code linked into the Android binaries (including
libc++, libc++abi and compiler-rt); the complete upstream toolchain inventory is
retained conservatively, not a claim that build tools ship in the APK.

`scripts/pins.sh` records the revision and text hashes. The notice collector
checks both Godot's and the vendor addon's source build configurations against
that revision before packaging; update these original texts when it changes.
