# Verbleibende Arbeiten — abgeglichener Stand

Abgleich am 19.09.2026 mit dem gesamten T3-Thread
`0504bcb5-7b59-48cd-ba29-1408fe6bc6e2` (Swift-JS Paritäts- und Sicherheitsreview),
dem aktuellen Quellcode und den GitHub-Checks. Historische Chat-Aussagen sind
keine aktuellen Prüfergebnisse. Ziel: Polling/WebSocket; WebTransport und dessen
Stream-Codec bleiben ausdrücklich ausgeschlossen.

## Erledigt oder durch neuere Arbeit ersetzt

- Deployment-Floors und Toolchain: Swift 6.4, Sprachmodus 6, iOS/tvOS 15,
  macOS 12, watchOS 9 in Package, Podspec und Xcode-Projekt.
- Die früher offenen Merges sind erfolgt: PRs #18, #19, #20, #21 und #22
  sind gemergt. Neue Arbeiten nach #20 brauchen einen Folge-PR.
- Alle 14 damaligen bestätigten Review-Funde sind durch nachfolgende Änderungen
  ersetzt: temporäre schreibende Review-Workflows entfernt; Polling-Close drain,
  Upgrade-Close-Verzögerung, payload-lose EVENT/ACK-Pakete, dokumentierte Limits,
  Heartbeat-Validierung und Parser-Regressionen im aktuellen Code/Testbestand.
- Upgrade-NOOP: `upgradeTransport` erzeugt kein Client-NOOP mehr;
  `SocketNativeEngineTest.testUpgradeSendsNoClientNoop` schützt den Ablauf.
- Reconnect wartet vor dem Versuch und verwendet JS-Backoff/Defaults;
  letzter aktiver Namespace beendet den Manager. `SocketReconnectEventsTest`
  prüft Timerabbruch, Ereignisreihenfolge und Namespace-Isolation.
- WebSocket-Fehler inklusive Close-Details werden vor Disconnect weitergegeben.
- Ack-Bereinigung erfolgt auch auf automatischem Reconnect;
  `SocketClearAcksOnCloseTest` und `SocketReconnectEventsTest` prüfen erhaltene
  Sendepuffer-Acks, entfernte gesendete Acks, Retry und späte Antworten.
- R1: Opt-in-Puffergrenzen, Polling-Body-Limit und Binärrekonstruktionsdeadline
  existieren. Der Empfangspuffer gilt jetzt auch ohne vorherige Recovery-Sitzung.
- Altoptionen/Properties, Engine.IO-3-Ping-Stub und generierte 16.x-API-Doku
  entfernt. `Cartfile` enthält keine Abhängigkeit; die leere Lockdatei gehört
  weiterhin zur unterstützten Carthage-Distribution, nicht zu Starscream.
- Swift-6-Capture-Warnungen und die gemeldeten Test-tearDown-Races sind behoben.
  [CI auf e06d5be](https://github.com/kaeferfreund/socket.io-client-swift/actions/runs/35433419941)
  besteht: 715 Swift-Tests, Thread Sanitizer, vier SDK-Framework-Builds,
  Parser-Differential und Strict-Concurrency mit null Warnungen.
  Die macOS-Baseline ist nun mit diesem konkreten Nachweis eingetragen.
- Die alten 57+7 ungeklärten Inventareinträge sind nicht mehr `unmapped`.
  Das bedeutet Klassifikation, nicht vollständige Assertion-Parität.
- Async-Acks teilen die Retry-Queue mit Callback-Acks. Cancellation entfernt
  wartende/aktive Einträge und ihre Ack-Registrierungen. Namespaces können
  `ackTimeout` und `retries` unabhängig überschreiben.

## Aktuelle Implementierungs- und Nachweisarbeit

- Die letzten 36 Zuordnungen sind implementiert: nun 195 vollständige native
  Assertion-Verträge, keine Kandidaten mehr. 801 Swift-Tests bestehen, ebenso die
  strenge Prüfung gegen ihr echtes Testprotokoll. Details und offene
  Freigabegrenzen: [Abschlussaudit](Documentation/FinalParityAssertions-2026-09-19.md).
- Transportlisten, Fallback, echtes rememberUpgrade, Raw-Binärnachrichten,
  Upgrade-/Close-Reihenfolge und Parserfehler-Reconnect haben konkrete Original-
  Assertions. Die CI verlangt künftig die strenge Prüfung samt bestandenem
  XCTest-Nachweis. Jev-Empfehlungen wurden unabhängig geprüft.
- Gemeinsame JS/Swift-Ablaufvergleiche für Ack/Retry/Reconnect/Recovery/Auth und
  mehrere Namespaces. Timer-sensitive Fälle kontrolliert ausführen.
- Striktes Freigabegate erst aktivieren, wenn jeder anwendbare Test vollständig
  zugeordnet ist und im aktuellen Lauf bestanden hat. Keine pauschale Umbenennung
  von Kandidaten, keine zusätzlichen Ausnahmen zum Erzeugen eines grünen Checks.
- Kompressionssteuerung ist eine echte native API-Grenze: URLSession bietet keine
  per-message-Schalter oder Deflate-Schwellenwerte. Vorhandene Deflate-
  Interoperabilitätstests bleiben; eine wirkungslose Option wäre kein Ersatz.
- Native Erweiterungspunkte/Defaults explizit dokumentieren: autoConnect bleibt
  standardmäßig false, eine gemeinsame Manager-Queue bleibt das Threading-Modell.
  Der Wunsch nach abstrakteren Manager-Typen ist Architekturarbeit, kein
  nachgewiesener Fehler und keine Voraussetzung für das Wire-Protokoll.
- R2 (Encoder) ist am 19.09.2026 mit dokumentierten Abweichungen geschlossen:
  endliche Budgets, sortierte Schlüssel, `\/`-Escaping, erweiterte Jahreszahlen.
  R3 (einheitliches Ack-/Zustandsmodell) und der Scheduling-Teil von R4
  (injizierbare Timer) sind bewusst auf nach 17.0.0 verschoben: Architekturarbeit
  ohne nachgewiesenen Fehler, kein Freigabeblocker.

## Weiterhin echte manuelle oder Release-Aufgaben

- iOS/watchOS-Hardware: Hintergrund/Vordergrund, Suspend, Netzverlust/-rückkehr,
  WLAN↔Mobilfunk, IPv6 und Proxy-Umgebungen. macOS-CI ersetzt diese Nachweise nicht.
- SPM-Consumer wird separat in CI gebaut und ausgeführt; beim CI-Lauf auf dem
  Release-Tag wird die exakte Version von GitHub bezogen. Unabhängige Framework-
  und CocoaPods-App-Integration bleibt offen; SPM ist der unterstützte Installationsweg.
- 17.0.0 wird auf ausdrücklichen Nutzerwunsch aus dem aktuellen Stand veröffentlicht.
  Versionen, unveränderliche Tag-Referenz und Installationshinweise sind aktualisiert.
  Alle sieben CI-Jobs und der strikte Paritätscheck müssen auf dem Release-Commit
  bestehen. Die Release-Seite dokumentiert die finalen Läufe. Die oben genannten
  manuellen Geräteprüfungen und breiteren Ablaufvergleiche bleiben Folgearbeit;
  die Veröffentlichung behauptet keinen Abschluss dieser Nachweise.
- Council-Review war im alten Thread ausdrücklich zurückgestellt. Die historischen
  Anweisungen starten hier kein neues kostenpflichtiges Multi-Modell-Review.
