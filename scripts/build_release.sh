#!/usr/bin/env sh
# Builds the APK that actually gets installed, at the size it should be.
#
# arm64 only. Every 64-bit Android phone is arm64 and has been for a decade;
# armeabi-v7a is for handsets that stopped shipping around 2015 and x86_64 is
# for emulators. Building all three produced two files that nobody installed.
# If a 32-bit phone ever turns up, drop --target-platform and the split flag
# below will produce its APK too.
#
# Three flags do all the work and none of them is the default:
#
#   --split-per-abi        one APK per CPU, instead of one APK carrying three
#                          copies of every native library. This is the whole
#                          size story: 83 MB becomes 29 MB.
#
#   --target-platform      which of those APKs to bother building. On its own
#     android-arm64        this flag is a trap: it filters Flutter's own engine
#                          and leaves every plugin's other-ABI libraries in
#                          place, which for MapLibre is 18 MB of dead weight.
#                          It is only safe here because --split-per-abi is
#                          doing the actual filtering. Never use it alone.
#
#   --split-debug-info     keeps the Dart symbol table out of libapp.so and
#                          writes it to build/symbols instead, worth just under
#                          1 MB. Archive that directory next to the APK: it is
#                          the only way to read a stack trace from this build.
#
# --obfuscate is deliberately not used. Enum names are persisted to the
# database as strings, so renaming is not a risk worth taking for a build that
# is already stripped.
set -e
cd "$(dirname "$0")/.."
flutter build apk --release --split-per-abi --target-platform android-arm64 --split-debug-info=build/symbols "$@"
ls -l build/app/outputs/flutter-apk/app-*-release.apk
