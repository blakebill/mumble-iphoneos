# Audio session lifecycle regression tests

Build the Debug Simulator app, boot an arm64 iOS 27 Simulator, then run:

```sh
bash Scripts/test-audio-lifecycle.sh /path/to/Debug-iphonesimulator/Mumble.app
```

The runner copies the application into a separate bundle and loads a test-only
library. It exercises the application's compiled MLAudio implementation, replacing
AVAudioSession with delayed callbacks and engine creation/resumption with test
counters. It
does not connect to a server or use a microphone. No test code is loaded by the
normal app.

Checks include duplicate starts, stop during activation, restart during activation,
start during deactivation, interruptions with and without permission to resume,
activation failure, configuration failure, late permission grants, and deactivation
failure, engine stops after hardware configuration changes, off-main recovery
without session reactivation, duplicate and stale recovery events, bounded repeated
failures, callbacks that do not retain retiring engines, sustained idle capture
intent, transient input-format startup failures, and cancellation of a pending
startup retry. Configuration and synchronous
session calls must never run on the main thread. On iOS 27 the asynchronous system
API must be used. Callback completion is deliberately delivered from a background
queue. The script prints results and fails if a check fails or times out.

To exercise the compiled compatibility branch on the same Simulator, build into a
separate derived data directory with these additional build settings:

```sh
'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) __IPHONE_OS_VERSION_MIN_REQUIRED=180000 __IPHONE_OS_VERSION_MAX_ALLOWED=260200'
```

Then pass `legacy` as the second argument to the runner. In this mode the fake
synchronous APIs block the session queue until the test releases them, ensuring
that the main thread remains available and ordering is preserved. This also
checks that the older-SDK preprocessor guards compile without the new APIs.

The runner requires an iOS 27 Simulator; it does not validate physical audio
hardware, routes, or a real older-iOS runtime.
