# App Review notes

Paste the text below into App Store Connect after replacing every bracketed
field. Enter review-only credentials directly in App Store Connect, not in this
repository or the public Hexo pages.

---

This is an independently maintained client for the open-source Mumble voice-chat
protocol. It connects to user-selected servers. It supports voice activation,
push-to-talk, text and photo messages, LAN discovery and certificate identities.

## Test connection

- Server: [REVIEW SERVER HOST]
- Port: [REVIEW PORT]
- Username: [REVIEW USERNAME]
- Password: [ENTER PRIVATELY IN APP STORE CONNECT, IF REQUIRED]
- Test channel: [CHANNEL NAME]
- Server availability: [CONFIRM IT WILL REMAIN ONLINE THROUGH REVIEW]

1. Complete the initial welcome/transmission/certificate guide. A certificate
   can be generated on the device; no developer-operated account is needed.
2. On Home, choose Quick Connect and enter the test-server details above.
3. Grant microphone permission to test speech. LAN discovery is optional for
   this internet-hosted test server.
4. Join the test channel. Test voice activation or choose push-to-talk in the
   transmission menu. The microphone and speaker controls mute local speech and
   incoming audio respectively.
5. Open Messages to send text. Use the plus button to select a photo through
   the system photo picker. [DESCRIBE HOW REVIEWERS CAN VERIFY AUDIO/MESSAGES
   WITH A TEST PEER OR OTHER WORKING TEST ARRANGEMENT.]
6. Disconnect from the server menu to end the conversation.

Audio may remain active in the background while connected so an ongoing
conversation continues when the user switches apps or locks the phone. The app
declares the audio background mode for this purpose.

The app can create a registration on a selected Mumble server through
Self-Register when the server permits it. [DESCRIBE THE VERIFIED ACCOUNT/REMOTE
REGISTRATION DELETION FLOW AND SERVER RESPONSIBILITIES.]

Privacy policy: https://www.rubycore.ltd/mumble/privacy/

Support contact: apple@piggy.live

Content safety: [DESCRIBE IMPLEMENTED BLOCKING, REPORTING, MODERATION AND RESPONSE
ARRANGEMENTS. DO NOT CLAIM THE SUPPORT WEB PAGE ALONE IMPLEMENTS THESE FEATURES.]

Publisher: blakebill (confirm the final publishing identity)

Review email: apple@piggy.live

Review contact name and phone: [ENTER IN APP STORE CONNECT]

---

Prefer a review server with a valid publicly trusted TLS certificate to simplify
review. Do not ask reviewers to disable certificate checks. Keep its content
controlled and free of real users' private information.
