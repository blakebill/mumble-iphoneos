---
title: "Mumble (new) Privacy Policy"
date: 2026-11-14 00:00:00
updated: 2026-11-14 00:00:00
layout: page
comments: false
header: false
lang: en
permalink: mumble/privacy/
---

# Mumble (new) Privacy Policy

Effective date: 2026-11-14

[Contact support](mailto:apple@piggy.live)

blakebill publishes this independently maintained iOS client for
Mumble servers. This policy explains how the app handles information. The
client is based on the [open-source Mumble iOS project](https://github.com/blakebill/mumble-iphoneos) and is
not an official release from the Mumble project.

## Voice, messages and server connections

When you speak, the app captures microphone audio, processes it on your device,
and sends encoded voice to the Mumble server you connect to. Text messages and
photos you choose to send also pass through that server to the selected channel
or recipients. The app does not provide an automatic voice-recording service.

The server receives information needed to establish and maintain the connection,
such as your network address, username, client/protocol version, and certificate
identity when one is used. Passwords and access tokens you supply are sent to
that server for authentication or access control. Certificate private keys are
used locally for authentication and are not sent to the server as private keys.

Connections use transport encryption. **This is not end-to-end encryption:**
server operators handle the content, and operators or other participants may
retain messages, record audio or keep connection logs. Their access rules,
privacy policies and retention practices apply to their services. Only connect
to servers you trust. No policy here promises that all Mumble servers delete or
avoid collecting information.

## Information stored on your device

- Preferences, favourite servers, recent connections, remembered usernames and
  accepted server-certificate fingerprints are stored locally.
- Saved server passwords and access tokens use iOS Keychain. Current credential
  writes do not synchronize through iCloud Keychain. During an upgrade, older
  database credentials are removed only after secure migration succeeds.
- Certificate identities and private keys are held using iOS Keychain. If you
  choose to export an identity, protect the exported file because it can contain
  the private key.
- Conversation text and received images may be held in memory and temporary
  local storage for display and previews. The app is not a permanent message-
  history or cloud-backup service. Temporary files are normally removed when
  the conversation storage is released; unexpected termination and operating-
  system cleanup can affect when temporary files disappear.

Device backups and operating-system services follow your device settings and
Apple's policies. We do not promise that uninstalling the app removes Keychain
items or copies that you exported, backed up or shared.

## Public servers and local discovery

The app can refresh its public-server directory from
`https://publist.mumble.info/v1/list`. That service receives ordinary network
request information, such as your IP address. Server browsers can also send
status queries to servers to display their availability and connection details.
Directory and server operators are responsible for their own services.

With local-network permission, the app uses Bonjour to discover Mumble servers
and exchanges network traffic with local servers. The directory refresh and
server discovery are separate from sending a voice or text message.

## Permissions and your choices

- **Microphone:** used for live voice chat and microphone-level setup. You can
  mute, disconnect, or revoke permission in iOS Settings. Microphone activity
  may continue in the background during a connected voice session.
- **Local network:** used to discover and connect to LAN servers. You can manage
  permission in iOS Settings.
- **Photos and files:** the system picker gives the app the items you select.
  Selected content is sent when you choose to send it. Importing or exporting
  a certificate uses the file location you choose.

You can delete favourite servers, remove Recent entries, edit or remove saved
access tokens, and remove certificate identities using the corresponding app
controls. Deleting a favourite removes its saved password. Deleting a local
message only affects the local copy; it does not recall messages from servers
or other recipients. Contact us if you need help with local data not covered by
these controls.

The app does not require a central account operated by the publisher. A server
may allow **Self-Register**, which creates a registration on that server. Contact
that server's administrator about deleting the registration or server-held
information. Removing a local certificate does not itself delete that remote
registration.

## Advertising, diagnostics and support

This client does not include advertising or cross-app tracking, and does not
include a custom analytics or automatic crash-upload SDK. Apple may provide
diagnostic information under its own settings and policies. You may choose to
send us a problem description, diagnostic log or screenshot for support; check
it for passwords, private messages, server details and other sensitive content
before sending.

If you email us, we process your address and the information you provide to
answer the request, investigate problems or handle privacy and safety reports.
We retain correspondence only as needed for those purposes and applicable
recordkeeping obligations. You can request deletion of support correspondence;
we will explain any information that must be retained. Mail, hosting and issue-
tracking providers process information under their own applicable terms.

GitHub issues are public. Do not post credentials, private messages, certificate
private keys or personal information there. Use email for private reports.
This policy covers the app; separately configured website analytics, cookies or
hosting logs, if any, are governed by the website's own practices.

## Privacy requests and changes

For questions, access/correction/deletion requests relating to information we
hold, or a private safety report, email
[apple@piggy.live](mailto:apple@piggy.live). We may ask for information needed
to verify and understand the request. We cannot erase records held by unrelated
server operators or other participants, but can explain how to contact them.

We update this page when these practices change and show the effective date
above. The app's minimum age and server participation rules are described by
its App Store rating and the rules of the servers you use.
