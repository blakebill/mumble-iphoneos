# App Store release preparation

This folder contains release materials for the current iOS client. Public web
pages are in English and Simplified Chinese; submission notes are in English.
The documents describe the current code, not unimplemented features.

## Files

- [Store listing](metadata.md): English and Simplified Chinese copy.
- [Review notes](review-notes.md): reviewer instructions and a private-information checklist.
- [Privacy and encryption worksheet](privacy-and-encryption.md): facts to verify before answering App Store Connect questionnaires.
- [Hexo pages](hexo/README.md): generate the English privacy policy for your existing Hexo website.

## Before submission

- [ ] Confirm the public app name, publisher name, branding rights and release territories.
- [ ] Register the production Bundle ID and create the App Store Connect record.
- [ ] Use the paid developer team consistently. The project currently contains two Team IDs and development-signing overrides; validate the final distribution archive.
- [ ] Increment the build number for each uploaded build and confirm the version in the archive.
- [ ] Use an Apple-supported production Xcode/SDK combination accepted by App Store Connect at upload time.
- [ ] Generate and deploy the Hexo pages. Open both URLs on an unauthenticated device and check every contact link.
- [ ] Add a working privacy-policy entry inside the app. About links to the publisher's repository and issue tracker; a separate support website is not part of this privacy-only deployment.
- [ ] Complete the privacy, encryption, age-rating and regional questionnaires using the final binary and actual service arrangements.
- [ ] Resolve reporting/blocking/moderation requirements for voice, text and images. A web contact page alone does not implement these safeguards.
- [ ] Review the server **Self-Register** flow and the applicable account-deletion requirements. Describe remote-server responsibilities accurately; do not claim that registration is absent.
- [ ] Review the licenses in `Resources/Legal.html` against the archived dependencies and retain required notices.
- [ ] Provide the required screenshots of the actual release UI; remove private servers, usernames and messages from them.
- [ ] Run Release archive validation and the existing build/regression checks. Test real microphone quality, interruptions, background audio, reconnect, certificate trust and photo messages on an iPhone.
- [ ] Resolve or document the outstanding cough/transient-distortion investigation. Synthetic signal tests have not established the cause on the physical microphone.
- [ ] Supply an online review server and working test instructions in App Store Connect. Keep credentials out of Git and public web pages.
- [ ] Choose availability, pricing and manual/automatic release. Complete any applicable EU trader or China mainland filing requirements.

TestFlight is recommended before the first release. It is not a prerequisite
for submitting an App Store version.

## Scope

Preparing these files does not change app behavior, signing, privacy labels,
export declarations or distribution settings. No App Store submission is
performed by the page generator.

Apple's live forms are authoritative and may change. Check the linked sources
again when submitting:

- [Create an app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Submit for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
