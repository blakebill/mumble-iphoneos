# Mumble for iOS

This application uses [libmumble](https://github.com/mumble-voip/libmumble) through
an application-owned Objective-C++ backend, with native iOS audio. MumbleKit is
no longer a dependency. The existing interface, database and keychain remain
part of this application.

## Requirements

- Apple Silicon Mac, Xcode 27 or newer, iOS 18 or newer.
- CMake 3.24+, Ninja, pkg-config and a bootstrapped vcpkg checkout.
- Internet access for the first dependency build.

Library sources are pinned in `Dependencies/libmumble`; dependency versions are
pinned by its vcpkg manifest. Builds include ARM64 iPhone and ARM64 Simulator.
FMDB remains an upstream submodule; `Scripts/build-libmumble.sh` automatically
applies the checked-in iOS build/linker patch. To prepare FMDB separately, run
`bash Scripts/prepare-fmdb.sh` after cloning recursively.

## Build

Clone this repository recursively to obtain FMDB. Install build tools and
bootstrap the pinned dependency manager:

```sh
brew install cmake ninja pkgconf
git clone https://github.com/microsoft/vcpkg.git /path/to/vcpkg
git -C /path/to/vcpkg checkout e456309491fd875487bf02b8a0dca76c1b1b00cc
/path/to/vcpkg/bootstrap-vcpkg.sh -disableMetrics
export VCPKG_ROOT=/path/to/vcpkg
bash Scripts/build-libmumble.sh
```

The generated `Dependencies/Generated/libmumble.xcframework` contains static
libraries and headers. All dependencies target iOS 18. Third-party notices in
the Legal screen are refreshed from the source licenses. Generated binaries are
ignored by Git. Rebuild the framework after changing library sources/dependencies.

Open `Mumble.xcodeproj`, select **Mumble**, configure your signing team, and build.
For builds without signing:

```sh
xcodebuild -project Mumble.xcodeproj -scheme Mumble -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Mumble.xcodeproj -scheme Mumble -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO build
```

Run the local backend integration tests:

```sh
bash Scripts/test-libmumble.sh
```

`LIBMUMBLE_BUILD_ROOT`, `LIBMUMBLE_TEST_ROOT` and `LIBMUMBLE_BUILD_JOBS` control
build locations and concurrency. Tests run independently of the XCFramework.
See [the backend notes](Source/LibMumble/README.md) for architecture, compatibility,
test coverage and physical-device checks.

The GitHub Actions build uses GitHub's `xcode-27` preview image while Xcode 27
is unavailable on the regular macOS images. The app's deployment target remains
iOS 18; older iOS versions use compatibility paths and a static app icon.

This project originates from the [Mumble iOS application](https://github.com/mumble-voip/mumble-iphoneos).
Mumble is an open-source voice chat application: [mumble.info](https://www.mumble.info/).
