# dotrino-native

Lo mínimo del ecosistema que una app **nativa** necesita para hablar con la bóveda sin
WebView. Es un **puerto** de piezas de `@dotrino/identity` y del cable de
`@dotrino/proxy-client`, así que no decide nada propio: si el pilar JS cambia un formato,
esto tiene que seguirlo.

| Archivo | Qué es | Original en JS |
|---|---|---|
| `Canonical.kt` | JSON canónico (lo que se firma) | `vault/core.js` `canonicalStringify` |
| `Crypto.kt` | JWK, firma P1363, `openWrap` / `decryptWithCek` | `vault/capabilities.js`, `vault/content.js` |
| `Delegation.kt` | `pubkeyId`, `keyLabel`, cuerpo y comprobación del papel | `vault/keyid.js`, `delegationBody` |
| `KeystoreKeys.kt` | las dos llaves de una cuenta en el Android Keystore | — |
| `ProxyConnection.kt` | `connected` / `identify` / `push-subscribe` / mensaje por pubkey | `proxy-client/src/client.js` |
| `VaultClient.kt` | `approvals` / `approve` / `deny` / `grants` / `renew` | `vault/remote.js` `vaultRpc` |
| `AccountStore.kt` | las cuentas en disco, cifradas con una llave del Keystore | — |

**No hace el emparejamiento.** El alta la hace el pilar JS de siempre (en la consola, con
`enrollDevice` y un firmador externo, identity ≥ 0.102.0), firmando con la llave del
Keystore. Así no hay que portar el parseo de invitaciones ni la verificación del acta.

## Pruebas

```sh
node dotrino-native/test-vectors/gen.mjs          # regenera los vectores desde el pilar JS
./gradlew :dotrino-native:testDebugUnitTest       # vectores de oro (JVM)
./gradlew :dotrino-native:connectedDebugAndroidTest   # el Keystore de verdad (emulador o teléfono)

# contra un proxio y una bóveda REALES (los repos hermanos):
node dotrino-native/test-vectors/e2e-vault.mjs /tmp/e2e.json &
DOTRINO_E2E=/tmp/e2e.json ./gradlew :dotrino-native:testDebugUnitTest
```

`test-vectors/e2e-live.mjs` es para probar la app a mano: dos bóvedas de usar y tirar en el
proxio de producción, con invitaciones `?native=1` y disparadores para crear pedidos (ver su
cabecera).
