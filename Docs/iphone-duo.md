# iPhone Duo adaptation

The conversation adapts to the current window and safe area instead of checking a device name, screen size, or interface idiom. Build with Xcode 27.1 to enable the native arrangement APIs. The deployment target remains iOS 18; earlier systems retain the single-pane Server/Messages interface.

References: Apple's [Duo design guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), [Duo preparation guide](https://developer.apple.com/iphone-duo/prepare/) and [adaptive layout tech talk](https://developer.apple.com/videos/play/tech-talks/111463/).

## Conversation layout

The initial arrangement is resolved in `viewIsAppearing:` using the scene's installed traits, safe area and reserved regions. Layout updates remain enabled during presentation, so entering a server does not briefly show the compact interface before adapting. The fixture checks this before the presentation animation finishes.

On iOS 27.1, one `UIArrangementViewController` owns the existing channel and message controllers throughout the connection. `UISplitArrangement` supports horizontal and vertical arrangements and uses system division regions to keep panes clear of an active fold.

- Without an active division, at least 720 points of usable width and 280 points of height enables channels and messages side by side.
- With a horizontal division, Server shows channels above the fold and the conversation below it when there are at least 360 points of usable width and 260 points on each side. Voice controls remain in the shared lower-right rail.
- With a vertical division (book posture), Server remains in the leading pane and Messages in the trailing pane, with native equal regions around the fold. Voice controls remain in the scene-level right rail. Admission uses the same 280/320-point leading/trailing width minima as the native split and at least 280 points of usable height. The reading order follows the interface language.
- Smaller windows show the selected Server or Messages pane across the available area. Native placement dimensions collapse the other pane without transferring its controller to a different parent.
- Side-by-side layouts show accessible, Dynamic Type pane headings instead of a shared Server/Messages selector over the fold. The selector remains available in compact and tabletop layouts. Selecting Messages shows the conversation in a native pane clear of the division; its composer stays inside that pane and above the system keyboard. Returning to Server restores the split channel/message layout. An active message field remains selected when folding. The keyboard reduces the usable height for both unfolded and book splits; typing alone does not collapse book posture when both panes still fit. Dismissing the keyboard restores the split if it had to collapse.
- The connection, server model, recipient, draft text, and pending image are reused. Layout changes do not start or restart audio capture. An active message field keeps its focus when the layout changes.
- A pane with zero area skips channel-tree refreshes and message insertion animations. Channels catch up when their pane expands again.

Navigation and tab bars remain UIKit controls, including their system-managed vertical placement. On iOS 27.1 server actions use the navigation item's native overflow menu. The Server heading and summary measure and constrain against their own safe area, including when system controls occupy the leading side. The native split axis is explicit for book/tabletop and the resolved posture participates in layout invalidation. Portrait and both landscape orientations are supported. The obsolete orientation-only iPad welcome wrapper was removed; Home uses the same adaptive table implementation in every window.

## Controls and presentation

Voice buttons use SF Symbols without Mic/Audio captions on every device; accessibility labels and muted-state announcements remain available. Ordinary iPhone layouts retain their floating controls and wide PTT bar.

The side rail uses 44-by-44-point buttons with 20-point symbols, 12 points between buttons, and 10 points of container padding. This keeps their scale consistent with nearby navigation controls while preserving a full touch target. Ordinary floating controls use 22-point symbols.

Duo-size and native vertical-bar windows use one scene-level rail at the lower right in closed, open, tabletop and book layouts. The same two native glass buttons reuse Self-Mute/Self-Deafen and server restrictions. In PTT mode the microphone becomes a hold-to-speak target; release, cancellation and geometry changes end transmission. Switching to Messages keeps these controls available. The rail stays clear of the keyboard, active fold and system occlusion regions, including the outer camera and Dynamic Island after rotation. It reserves content space when UIKit does not already reserve a right-hand bar. On the inner portrait display, the server menu uses a native glass menu button in the upper right rail; vertical system bars retain their native overflow menu. The rail is not attached to either conversation pane and does not create another audio owner.

The message composer is centered with a maximum width of 720 points and follows the enclosing navigation controller's keyboard guide. Short windows put a 44-point image thumbnail beside the text instead of a 96-point preview above it. Text scrolls when it exceeds the remaining height, and message reflow preserves the reader's visible history anchor.

Resizing the channel pane, switching the selected pane, or deactivating its scene releases PTT. These actions do not stop a connected voice-activated conversation. Certificate alerts and queued server notices use their originating controller and scene instead of searching globally for a key window.

## Verification

The interactive fixture uses an isolated Simulator bundle and a synthetic channel tree. It presents the server controller with the same full-screen animation used by a real connection, waits for presentation completion, and observes layout without forcing periodic layout passes. Initial half-fold presentation must work without rotating the device. The controller reconciles layout after presentation completes, because intermediate layout passes may run while its transition coordinator is active. It never connects to a server or opens the microphone. Generated applications, injected libraries, screenshots, and result files are outside the repository. Its observation timer exists only in the injected test library.

Build the isolated host:

```sh
xcodebuild -project Mumble.xcodeproj -scheme Mumble -configuration Debug \
  -sdk iphonesimulator -derivedDataPath /tmp/mumble-duo-sim \
  PRODUCT_BUNDLE_IDENTIFIER=com.blakebill.mumble.audio-lifecycle-tests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

Run against a booted Duo Simulator, specifying its identifier when more than one Simulator is booted:

```sh
MU_TEST_DEVICE="<Duo Simulator identifier>" bash Scripts/test-duo-layout.sh \
  /tmp/mumble-duo-sim/Build/Products/Debug-iphonesimulator/Mumble.app
```

The script prints the fixture's Documents directory. Writing one of `server`, `draft`, `keyboard`, `dismissKeyboard`, `messages`, `vad`, `ptt`, `hold`, `rtl`, `ltr`, or `hiddenUpdate` to `duo-command.txt` triggers that test action. `hiddenUpdate` adds a channel while the channel pane is collapsed. Use Device Hub to change posture and orientation, and enable its software keyboard before validating keyboard avoidance. A first responder alone does not prove that the software keyboard is visible; the fixture requires a system keyboard-frame event as well. Inspect `duo-state.json` after each transition; `failures` must be empty. `duo-layout.png` records the corresponding app layout, while Device Hub's live display is needed to inspect the system keyboard. Stop the test bundle after inspection to end the observation timer.

Validated on the iOS 27.1 Duo Simulator:

- Closed and open layouts, with text and image drafts preserved.
- Keyboard focus across closing/opening, with voice controls above the keyboard.
- Book posture keeps Server in the leading pane and Messages in the trailing pane, with voice controls at the lower right, with both titles clear of the hinge and side bars. Tabletop keeps channels above and messages/voice controls below; the composer and footer must not overlap. Explicit Messages selection and returning to Server are checked separately.
- First connection without rotating, both landscape directions, keyboard-visible book layout, reading-direction changes, and native overflow menu availability.
- Held PTT released after a geometry change.
- Closed landscape controls avoid the camera and status region when they move to the lower right. The inner portrait server menu remains in the right rail without a duplicate navigation overflow button.
- Original connection/model identity and no audio start from layout changes.
- Hidden channel updates deferred until the pane becomes visible, then reflected in the table.
- Both portrait and landscape compact chat fill the usable display.
- A real software keyboard with a photo draft remains clear of the send button during closed-landscape, open, and partial-fold transitions. Short-height thumbnail layout and restoration of the shared message/control surface after returning to Server were inspected in Device Hub and checked against system keyboard-frame events.

Ordinary iPhone interface, channel-list, and audio lifecycle regression scripts accept the same `MU_TEST_DEVICE` selector. The compatibility audio test requires a separate build; passing `legacy` to the runner alone does not select that compiled branch. For an SDK-branch test with the current SDK, use a temporary prefix header that imports UIKit, then undefines `__IPHONE_OS_VERSION_MAX_ALLOWED` and defines it as `260000`. Pass its absolute path as `GCC_PREFIX_HEADER` with `GCC_PRECOMPILE_PREFIX_HEADER=NO`. Defining only a command-line macro is insufficient because imported SDK modules can restore the current version. This tests compiled fallback logic, not an actual older SDK or runtime.

Debug Simulator, compatibility-branch, and unsigned iPhone Release builds are checked separately. Simulator layout tests do not validate Duo microphone routing, real network continuity, power consumption, or physical fold behavior. Those require a Duo device. Multiple simultaneous app scenes remain disabled because the application still has one shared connection and audio owner.
