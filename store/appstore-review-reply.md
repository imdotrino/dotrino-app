# Respuesta a App Review (Guideline 2.1 — Information Needed)

Apple rechazó la 0.4.13 (1) el 2026-10-13 pidiendo información, no por un fallo de la app.
Envío `50ae1559-b426-4709-9cf2-54de690b2329`. Se contesta en App Store Connect («Reply to App
Review»), se adjunta la grabación, y el mismo texto se añade al campo Notes de «App Review
Information».

**BORRADOR: sin enviar.** Revisar cada afirmación contra la build que se reenvíe.

## 1. Grabación de pantalla (la hace el dueño, en el iPhone)

En un iPhone físico con el iOS más reciente, empezando por abrir la app:

1. Abrir la app; pestaña Inicio.
2. Pestaña Perfil → botón redondo → «Crear perfil» (el alta: no pide correo ni contraseña).
3. Mismo menú → «Iniciar sesión» con la cuenta de demostración.
4. Pestaña Pedidos: llega un pedido de «Servidor de prueba»; aprobar uno y denegar otro.
5. Pestaña Bóveda: los aparatos de la cuenta.
6. Borrar la cuenta: quitar el perfil del teléfono, con su aviso de confirmación.

## 2–6. Texto de la respuesta

```
Hello,

Thank you for the review. The requested information follows. A screen recording made on a
physical iPhone is attached.

2. PURPOSE AND AUDIENCE
Dotrino is the phone app of the Dotrino ecosystem, a set of open-source (MIT) apps built around
the privacy of the user's data. Its audience is people who keep their passwords and keys in
their own Dotrino vault, a free program they install on their own computer. The problem it
solves: knowing and deciding, from the phone, when a program or device wants to use one of those
keys. The app shows who is asking for what, and only what the user approves is delivered. It
also carries the user's profile and opens the catalog of Dotrino apps.

3. HOW TO ACCESS THE MAIN FEATURES
- Open the Profile tab (2nd), tap the round profile button (top right), choose "Sign in"
  (Iniciar sesion).
- Enter the demo address and password from the Sign-In Information section, check "Remember",
  tap "Sign in".
- Open the Requests tab (4th). The demo account shows a pending request from "Servidor de
  prueba". Tap Approve or Deny. A new sample request arrives about every 3 minutes.
- The Home and Profile tabs work without signing in. The ES / EN buttons switch the language.
The demo account is backed by a demo vault that we keep running during the review.

ACCOUNTS: there is no account with us. A profile is a key pair created on the phone and kept in
the Secure Enclave; creating one asks for no email and no password. A profile is deleted from
the profile menu, which removes it and its keys from the phone. "Sign in" only links the phone
to a vault the user already owns.

4. EXTERNAL SERVICES
- Apple Push Notification service, to tell the phone that a request is waiting. The
  notification carries no content.
- proxy.dotrino.com, our own open-source message relay. Messages are end-to-end encrypted;
  the relay cannot read them.
- dotrino.com, profile.dotrino.com and id.dotrino.com, our own web pages, shown in the Home
  and Profile tabs.
- The user's own vault, running on the user's computer.
No third-party analytics, advertising, payment or AI services. No in-app purchases.

5. REGIONAL DIFFERENCES
None. The app works the same in every region, in Spanish and English.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app is not in a regulated industry and contains no third-party protected
material. All code is our own and published under the MIT license at github.com/imdotrino.
```
