# TV Remote voor Telenet

Een iOS-app (SwiftUI) die je iPhone verandert in een afstandsbediening voor je **Telenet TV-box**.

## Wat kan de app?

- Volledige afstandsbediening: aan/uit, pijltjes + OK (of **touchpad met veeggebaren**), terug, menu, gids, info, opties
- Zender +/−, cijferklavier, teletekst, ondertitels
- Afspelen/pauze, terugspoelen, vooruitspoelen, stop, **opnemen**
- Rode, groene, gele en blauwe toets
- **Zenderlijst** met logo's en zoekfunctie: tik op een zender om er rechtstreeks naartoe te schakelen; veeg voor favorieten
- Toont of de box aan/stand-by staat en welke zender er speelt
- Meerdere TV-boxen in huis? Kies bovenaan welke box je bedient
- Werkt via de Telenet-cloud: je iPhone hoeft niet op hetzelfde wifi-netwerk te zitten

## Hoe werkt het?

De Telenet TV-box (EOS/Horizon-platform van Liberty Global: Arris DCX960 of Humax 2008C)
wordt bediend via een MQTT-berichtendienst in de cloud, dezelfde die de officiële
Telenet TV-app gebruikt voor "Bekijk op TV".

1. Je meldt je aan op de officiële telenet.tv-website (in de app). De app onthoudt enkel het
   **refresh token** in de iOS Keychain — nooit je wachtwoord.
2. Met dat token haalt de app een access token, je huishouden-ID en je gekoppelde TV-boxen op
   (`spark-prod-be.gnp.cloud.telenet.tv`).
3. De app verbindt via een beveiligde WebSocket met de MQTT-broker en stuurt toetsaanslagen
   als `CPE.KeyEvent`-berichten naar `{huishouden}/{box-id}`.

De MQTT-client is zelf geschreven (geen externe libraries nodig).

## Installeren op je iPhone

Je hebt een Mac met **Xcode 15 of nieuwer** nodig.

```bash
brew install xcodegen      # eenmalig
git clone <deze repo>
cd Telenettv-remote
xcodegen generate          # maakt TelenetRemote.xcodeproj
open TelenetRemote.xcodeproj
```

In Xcode:

1. Selecteer het target **TelenetRemote** → *Signing & Capabilities* → kies je **Team**
   (een gratis Apple ID volstaat; de app is dan 7 dagen geldig, met een betaald
   developer-account een jaar).
2. Pas eventueel de *Bundle Identifier* aan (moet uniek zijn, bv. `be.jouwnaam.tvremote`).
3. Sluit je iPhone aan, kies hem als bestemming en druk op ▶︎ (Run).
4. Op de iPhone: *Instellingen → Algemeen → VPN en apparaatbeheer* → vertrouw je
   ontwikkelaarscertificaat (alleen de eerste keer). Op iOS 16+ moet je ook
   *Instellingen → Privacy en beveiliging → Ontwikkelaarsmodus* aanzetten.

## Aanmelden

- **Aanmelden met Telenet**: opent telenet.tv. Meld je aan met je Telenet-login; zodra de site
  ingelogd is, sluit het venster vanzelf en verbindt de app met je TV-box.
- **Token handmatig invoeren** (als het automatische aanmelden niet lukt):
  1. Ga op je computer naar <https://www.telenet.tv> en meld je aan.
  2. Open de ontwikkelaarstools (F12) → tab *Netwerk* en herlaad de pagina.
  3. Zoek het verzoek `authorization/refresh` (of `authorization`) en kopieer de waarde
     van `refreshToken` uit het antwoord.
  4. Plak die in de app.

## Beperkingen

- **Volume** wordt door je TV/soundbar geregeld, niet door de TV-box. Die toetsen zitten dus
  niet in de app.
- Werkt met de Telenet TV-box op het EOS/Horizon-platform. Oudere Digicorders of boxen op
  Android TV worden niet ondersteund.
- Dit is geen officiële Telenet-app. De gebruikte cloud-API is niet publiek gedocumenteerd en
  kan door Telenet gewijzigd worden.

## Projectstructuur

```
project.yml                     XcodeGen-projectdefinitie
TelenetRemote/
  App/TelenetRemoteApp.swift    App-ingang + routering tussen schermen
  Services/HorizonAPI.swift     REST: authenticatie, configuratie, boxen, zenders
  Services/MQTTClient.swift     Lichtgewicht MQTT 3.1.1 over WebSocket
  Services/RemoteController.swift  App-state, toetsen versturen, status ontvangen
  Services/Keychain.swift       Veilige opslag van het refresh token
  Models/                       Toetsen, boxen, zenders
  Views/                        SwiftUI-schermen (login, afstandsbediening, zenders, ...)
```

Met dank aan het open-source project [lghorizon](https://pypi.org/project/lghorizon/)
(gebruikt door Home Assistant) voor het in kaart brengen van het protocol.
