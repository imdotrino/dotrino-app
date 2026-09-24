# dotrino-app — la app de Dotrino (Android e iOS)

Cáscara **nativa** (Kotlin) sobre las páginas del ecosistema: abre en `dotrino.com` (el
home) y lleva pestañas a **Perfil** (`profile.dotrino.com`) y **Bóveda**
(`vault.dotrino.com/vault`). El pilar de identidad corre dentro del WebView igual que
en el navegador, así que los perfiles —y el multiperfil— son los mismos.

Lo que aporta ser nativa, y el navegador no da:

1. **Aviso del sistema** que despierta la app cuando tu bóveda tiene un pedido (un cajón
   con aprobación, una firma SSH), con *Aprobar / Denegar* en el propio aviso.
2. **Llave SSH en el llavero del teléfono** (Android Keystore): ni la app puede extraerla.

## Pedidos nativos (0.2.0)

La pestaña **Pedidos** es nativa: no pasa por el WebView. Cada cuenta en la que el teléfono
aprueba tiene **su propia llave en el Android Keystore** (firma ECDSA + cifrado ECDH P-256,
no extraíbles), y es un aparato más del acta de esa cuenta con `+aprueba`.

- **Multicuenta:** una sección por cuenta con su nombre, en orden fijo. Cada una mantiene una
  conexión al proxio mientras la pantalla está a la vista, así que un pedido llega en vivo
  (~0,5 s tras el aviso de la bóveda). El sondeo de 15 s es solo la red de seguridad.
- **Qué pide:** «pide tus claves de…» con el comando y la carpeta, o «quiere guardar
  variables en…» con los nombres. Los dos llegan sellados a la llave del teléfono y se abren
  aquí.
- **Alta:** Pedidos → *Añadir cuenta* abre `vault.dotrino.com/d?native=1`. Ahí se pega o
  escanea la invitación de la bóveda y se teclea el código en la bóveda, como siempre.
  Después, en la bóveda: `dotrino-vault caps <ID> +aprueba`. El puente de alta
  (`DotrinoNativeKeys`) solo lo ve esa página (se filtra por origen), y la llave solo firma
  su propio `enroll`.
- **Quitar** una cuenta del teléfono: pulsación larga sobre su nombre. Sus llaves se borran
  aquí; en la bóveda se quita como cualquier aparato.

La cripto y el cable viven en el módulo **`dotrino-native`** (ver su README), no en la app.

## Estructura

```
android/   Kotlin · Gradle · WebView + pestañas · push (FCM) · Pedidos nativos
  dotrino-native/   la librería: canónico, firma, sobres, proxio, bóveda (puerto mínimo del pilar JS)
ios/       Swift · WKWebView + pestañas · push (APNs) · XcodeGen (project.yml)
```

Las dos cáscaras cargan **las mismas páginas** y solo difieren en lo nativo (aviso del
sistema, llavero). El `android/` compila en Linux; `ios/` necesita una Mac con Xcode:
`brew install xcodegen && cd ios && xcodegen generate && open Dotrino.xcodeproj`.

## Push

El proxio manda por FCM un **timbre sin contenido** (`{ type: 'ring' }`) cuando la bóveda
tiene un pedido para este aparato; la app muestra el aviso del sistema y al tocarlo abre
*Pedidos*, que baja el detalle por el proxio. El token de FCM lo registra la página bajo la
llave del aparato (`id.registerPush`), no la app: así el proxio solo conoce pubkey → token.

## Compilar (Android)

Requisitos: JDK 17, Android SDK (compileSdk 36). El *wrapper* de Gradle (`gradlew`,
`gradle/`) **se recicló del proyecto TWA de `dotrino-wallet`** — es el script genérico de
Gradle 8.11.1, sin nada de wallet dentro.

```sh
cd android && ./gradlew assembleDebug   # app/build/outputs/apk/debug/app-debug.apk
# Google Play: AAB firmado con la llave de SUBIDA, que vive en la bóveda (cajón `claude`)
dotrino-env run --ns claude -- ./gradlew --no-daemon :app:bundleRelease
```

Hace falta `android/app/google-services.json` (proyecto Firebase `dotrino-app`, app
`com.dotrino.app`; gitignoreado) para el push.

**La llave de subida a Play no está en ningún archivo.** `dotrino-env` la entrega por el
entorno (`ANDROID_UPLOAD_KEYSTORE_B64`, `_STORE_PASSWORD`, `_KEY_ALIAS`, `_KEY_PASSWORD`),
Gradle la escribe en `$XDG_RUNTIME_DIR` (memoria) y se borra al terminar. Sin esas variables
el release sale sin firmar. Es la llave de *subida*: con Play App Signing la que firma lo que
se instala la guarda Google, y la de subida se puede cambiar si se pierde.

Los instaladores llevan la versión en el nombre (`dotrino-app-<ver>.apk` / `.aab`).

MIT.
