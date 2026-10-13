# Respuesta a App Review (Guideline 2.1 — Information Needed)

Apple rechazó la 0.4.13 (1) el 2026-10-13 pidiendo información, no por un fallo de la app.
Envío `50ae1559-b426-4709-9cf2-54de690b2329`. Se contesta en App Store Connect («Reply to App
Review») con el vídeo adjunto, y `notes` se añade al campo Notes de «App Review Information».

## 1. Grabación de pantalla

Se saca sola, en el iPhone conectado a la Mac, con la prueba de interfaz
`ios/DotrinoUITests/ReviewRecordingUITests.swift` (paso `take`): maneja la app ya instalada y
Xcode graba la pantalla. Solo toca lo que ella crea: el perfil «Review Demo» y la cuenta de
demostración. El teléfono tiene que estar desbloqueado.

```
TEST_RUNNER_REVIEW_STEP=take TEST_RUNNER_REVIEW_ADDRESS=apple@6C48-BB6B-4085 \
TEST_RUNNER_DEMO_PASSWORD=… xcodebuild -project Dotrino.xcodeproj -scheme DotrinoUITests \
  -destination 'platform=iOS,name=Dotrino Phone' -resultBundlePath take.xcresult test
xcrun xcresulttool export attachments --path take.xcresult --output-path out   # el .mp4
```

Si una toma se corta a medias, el paso `cleanup` quita el perfil y sale de la demo.

## 2. Respuesta (`reply`)

```
Hello,

Thank you for the review. The requested information follows.

1. SCREEN RECORDING
Attached. It was captured on a physical iPhone 11 running iOS 26.6.1, with the build submitted
for review. It starts by launching the app and shows, in this order:
- Home tab.
- Requests tab before signing in.
- Registration: Profile tab > profile button > "Create profile". A profile is a key pair made on
  the phone; it asks for a name only, no email and no password.
- Login: profile button > "Sign in", with the demo account.
- Requests tab: a request from "Servidor de prueba" is approved.
- Vault tab: the devices of the account in use.
- Account deletion: Profile tab > "Your profiles" > "Delete" > "Yes, delete it". The profile and
  its keys are removed from the phone.
- Requests tab: a second request is denied.
- Sign out: profile button > "Sign out". The demo account leaves the phone.
The app has no paid content and no in-app purchases. It has no feed, chat or posting: a profile
holds the user's own name and details.

2. PURPOSE AND AUDIENCE
Dotrino is the phone app of the Dotrino ecosystem, a set of open-source (MIT) apps built around
the privacy of the user's data. Its audience is people who keep their passwords and keys in
their own Dotrino vault, a free program they install on their own computer. The problem it
solves: knowing and deciding, from the phone, when a program or device wants to use one of those
keys. The app shows who is asking for what, and only what the user approves is delivered. It
also carries the user's profile and opens the catalog of Dotrino apps.

3. HOW TO ACCESS THE MAIN FEATURES
- Open the Profile tab (2nd), tap the round profile button (top right), choose "Sign in".
- Enter the demo address and password from the Sign-In Information section, check "Remember",
  tap "Sign in".
- Open the Requests tab (4th). The demo account shows a pending request from "Servidor de
  prueba". Tap Approve or Deny. A new sample request arrives about every 3 minutes.
- The Home and Profile tabs work without signing in. The ES / EN buttons switch the language.
The demo account is backed by a demo vault that we keep running during the review.

4. EXTERNAL SERVICES
- Apple Push Notification service, to tell the phone that a request is waiting. The
  notification carries no content.
- proxy.dotrino.com, our own open-source message relay. Messages are end-to-end encrypted;
  the relay cannot read them.
- dotrino.com, profile.dotrino.com, vault.dotrino.com, id.dotrino.com and
  reputation.dotrino.com: our own pages and services, shown in the Home, Profile and Vault tabs.
  They count page views with our own self-hosted, cookieless counter.
- The user's own vault, running on the user's computer.
No third-party analytics, advertising, payment or AI services.

5. REGIONAL DIFFERENCES
None. The app works the same in every region, in Spanish and English.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app is not in a regulated industry and contains no protected third-party
material. All code is our own and published under the MIT license at github.com/imdotrino.
```

## 3. Lo que se añade al campo Notes (`notes`)

```
ABOUT THE APP (Guideline 2.1)
Purpose: phone app of the Dotrino ecosystem (open source, MIT), for people who keep their
passwords and keys in their own Dotrino vault, a free program on their own computer. The phone
shows when a program or device wants to use a key, and only what the user approves is delivered.
Accounts: no account with us. A profile is a key pair made on the phone (name only, no email or
password). Create: Profile tab > profile button > "Create profile". Delete: Profile tab > "Your
profiles" > "Delete". "Sign in" links the phone to a vault the user already owns.
External services: Apple Push Notification service (no content in the notification); our own
relay proxy.dotrino.com (end-to-end encrypted); our own pages dotrino.com, profile., vault., id.
and reputation.dotrino.com, with a self-hosted cookieless page counter; the user's own vault.
No third-party analytics, ads, payments or AI. No in-app purchases, no feed, chat or posting.
Regions: same everywhere, Spanish and English. Not a regulated industry; no protected
third-party material. A screen recording on a physical iPhone was sent in the App Review reply.
```
