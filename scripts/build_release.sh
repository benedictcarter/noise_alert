#!/usr/bin/env sh
# Builds the APKs that actually get installed, at the size they should be.
#
# Two flags do all the work and neither is the default:
#
#   --split-per-abi        one APK per CPU, instead of one APK carrying three
#                          copies of every native library. This is the whole
#                          size story: 83 MB becomes 29 MB. Note that the
#                          similar-looking --target-platform android-arm64 does
#                          NOT do this. It filters Flutter's own engine and
#                          leaves every plugin's other-ABI libraries in place,
#                          which for MapLibre is 18 MB of dead weight.
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
flutter build apk --release --split-per-abi --split-debug-info=build/symbols "$@"
ls -l build/app/outputs/flutter-apk/app-*-release.apk
