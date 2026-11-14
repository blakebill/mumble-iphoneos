# Privacy and encryption worksheet

Reviewed against the source on 2026-11-13. Recheck the final archive and any
publisher-operated services before entering declarations. This is a factual
worksheet, not a completed export classification or an assurance of approval.

## Data flows

| Data / operation | Current behavior | Source evidence |
| --- | --- | --- |
| Live voice | Microphone input is processed on-device, encoded as Opus and sent to the selected Mumble server. No app voice-recording feature was found. The server and recipients can receive/record it. | `Source/LibMumble/MLAudio.mm`, `MLConnection.mm` |
| Text and images | Sent through the selected server. The conversation uses a temporary local SQLite database; its cleanup depends on the conversation object being released and OS temporary-file handling. It is not a permanent message-history service. | `Source/Classes/MUMessagesDatabase.m` |
| Connection identity | Server receives username, protocol/client version, network address and certificate identity when used. A supplied password or access token is sent to that server for authentication. | `Source/LibMumble/MLConnection.mm` |
| Favourites / Recent / trust | Server addresses, usernames, recent connections and accepted certificate fingerprints are stored locally. | `Source/Classes/MUDatabase.m` |
| Passwords / access tokens | Current writes use non-synchronizing device-only Keychain storage. Migration retains old database entries if secure migration cannot complete. Keychain items may outlive app removal. | `MUCredentialStore.m`, `MUDatabase.m` |
| Certificate private keys | Stored through iOS Keychain and used locally. Exporting a PKCS#12 identity produces a sensitive copy; it is not sent as a private key during normal server authentication. | `MUCertificateController.m`, `MLCertificate.mm` |
| Public directory | The app refreshes `https://publist.mumble.info/v1/list`; the operator can receive ordinary request metadata, including IP address. The app also pings server entries shown in browser lists. | `MLModels.mm`, `MUPublicServerList.m`, `MLServerPinger.mm` |
| LAN | Bonjour finds `_mumble._tcp` services and local connections exchange network traffic. | `MULanServerListController.m`, `Source/Info.plist` |
| Support / diagnostics | Publisher support email and website have their own handling. No custom advertising, analytics or crash-upload SDK was found in the app source. Apple diagnostic sharing is separate. | Source search; verify the final dependency archive and actual support services |

## App privacy answers to resolve

- The current manifest declares no tracking, no collected data types and the
  UserDefaults required-reason API. It is a starting point, not proof that the
  App Store privacy answers can be "Data Not Collected."
- Determine whether the publisher or partners retain any voice, text, images,
  usernames/identifiers, IP addresses, diagnostics or usage information. Review
  the directory service and any demonstration/production server the publisher
  operates or contracts with.
- Apple treats collection as off-device transmission that permits access for
  longer than needed to service the request in real time. Local-only storage
  and qualifying real-time processing need separate consideration; receiving a
  permission prompt does not by itself determine the label.
- Evaluate optional disclosure for voluntary support messages using Apple's
  actual criteria. Do not assume every support email or server log is exempt.
- Explain to users that selected server operators are separate recipients and
  can set retention/recording policies. Do not promise zero collection by all
  servers, automatic erasure of remote messages, or end-to-end encryption.
- Generate Xcode's privacy report from the final archive and audit required-
  reason API use across the app and all statically linked dependencies.
- Confirm the published contact, retention practices and regional privacy
  request handling match the public policy.

## Encryption facts for the questionnaire

- TLS uses linked OpenSSL/libmumble, not exclusively Apple's operating-system
  encryption implementation.
- Voice packets use the Mumble OCB-AES128 transport implementation; TCP voice
  fallback travels through TLS.
- Certificate identities/private keys and Keychain storage are also used.
- Encryption protects the connection to the server. The server handles the
  content; this is not an end-to-end encrypted messenger.
- `ITSAppUsesNonExemptEncryption` is currently absent. Determine the correct
  classification and documentation in App Store Connect before setting this
  value. Do not insert `false` merely to avoid the questionnaire.
- Keep any required Apple approval/code and supporting documentation with
  private release records. France and other selected territories may affect
  the required documentation.

## Account and content-safety review

`Self-Register` sends a registration request to the selected server. The current
UI does not provide a corresponding general remote-account deletion action.
Resolve the applicable deletion/request flow before claiming the account-
deletion requirement is satisfied.

The client has local user muting. No independent user-report flow was found in
this audit. Document actual safeguards for voice, text, images and public server
discovery and complete necessary product work before submission. A privacy
policy or reporting mailbox does not replace required in-app safeguards.

## Sources

- [Apple privacy labels](https://developer.apple.com/app-store/app-privacy-details/)
- [Privacy policy and data handling guidelines](https://developer.apple.com/app-store/review/guidelines/#privacy)
- [Account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [User-generated content](https://developer.apple.com/app-store/review/guidelines/#user-generated-content)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)
