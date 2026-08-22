# dotrino-app — la app de Dotrino (Android e iOS)

Cáscara **nativa** (Kotlin) sobre las páginas del ecosistema: abre en `dotrino.com` (el
home) y lleva pestañas a **Perfil** (`profile.dotrino.com`) y **Bóveda**
(`vault.dotrino.com/devices`). El pilar de identidad corre dentro del WebView igual que
en el navegador, así que los perfiles —y el multiperfil— son los mismos.

Lo que aporta ser nativa, y el navegador no da:

1. **Aviso del sistema** que despierta la app cuando tu bóveda tiene un pedido (un cajón
   con aprobación, una firma SSH), con *Aprobar / Denegar* en el propio aviso.
2. **Llave SSH en el llavero del teléfono** (Android Keystore): ni la app puede extraerla.

## Estructura

```
android/   Kotlin · Gradle · WebView + pestañas · push (FCM)
ios/       Swift · WKWebView + pestañas · push (APNs) · XcodeGen (project.yml)
```

Las dos cáscaras cargan **las mismas páginas** y solo difieren en lo nativo (aviso del
sistema, llavero). El `android/` compila en Linux; `ios/` necesita una Mac con Xcode:
`brew install xcodegen && cd ios && xcodegen generate && open Dotrino.xcodeproj`.

## Compilar (Android)

Requisitos: JDK 17, Android SDK (compileSdk 36). El *wrapper* de Gradle (`gradlew`,
`gradle/`) **se recicló del proyecto TWA de `dotrino-wallet`** — es el script genérico de
Gradle 8.11.1, sin nada de wallet dentro.

```sh
cd android && ./gradlew assembleDebug   # app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease      # firmado si existe keystore.properties (gitignoreado)
```

`keystore.properties`: `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Los
instaladores llevan la versión en el nombre (`dotrino-app-<ver>.apk`).

MIT.
