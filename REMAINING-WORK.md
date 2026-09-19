# Verbleibende Arbeiten — Thread `0504bcb5` / PR #18

Stand: 19.09.2026, Branch `fix/coderabbit-findings-audit` (Abschnitt 1 erledigt mit 553a15e, CI grün).
PR: <https://github.com/kaeferfreund/socket.io-client-swift/pull/18>

## 1. CI rot: Deployment-Floor-Anhebung ist unvollständig

Die Anhebung auf iOS 15 / macOS 12 / tvOS 15 / watchOS 8 wurde nur in
`Package.swift` (platforms), Podspec und Doku umgesetzt. Zwei CI-Jobs auf
PR #18 schlagen seitdem fehl (`Native library and full Socket.IO regression
suite`, `Native framework distribution builds (four Apple SDKs)`):

- [x] **`Package.swift` — swift-tools-version anheben.** Das Manifest steht auf
      `swift-tools-version:5.4`; dort sind `.iOS(.v15)`, `.macOS(.v12)`,
      `.tvOS(.v15)`, `.watchOS(.v8)` nicht verfügbar
      (CI-Fehler: `'v15' is unavailable` unter
      `-package-description-version 5.4.0`). Bump auf mind. 5.5
      (verifizieren, ggf. 5.6) und README-Abschnitt *Installation* mitziehen
      (dort steht noch „Swift tools 5.4 manifest“).
- [x] **Xcode-Projekt — Deployment-Targets anheben.**
      `Socket.IO-Client-Swift.xcodeproj/project.pbxproj` hat 24 Einträge, alle
      noch auf `IPHONEOS_DEPLOYMENT_TARGET = 13.0`, `MACOSX_DEPLOYMENT_TARGET
      = 10.15`, `TVOS_DEPLOYMENT_TARGET = 13.0`, `WATCHOS_DEPLOYMENT_TARGET =
      6.0`. Der Distribution-Build kompiliert deshalb mit
      `-target arm64-apple-macos10.15` und bricht:
      `SocketServerTrustEvaluator.swift:36: 'SecTrustCopyCertificateChain' is
      only available in macOS 12.0 or newer`. Alle vier Targets auf
      15.0 / 12.0 / 15.0 / 8.0 setzen.
- [x] **`scripts/test-native-transport.sh` — eingebettetes Manifest aktualisieren.**
      Zeile 14 erzeugt ein temporäres Manifest mit den alten Floors
      `.iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)` — inkonsistent
      zum neuen Floor und ggf. gleicher Tools-Version-Fehler.
- [x] Danach CI neu laufen lassen und beide Jobs auf grün prüfen.

## 2. PR #18 — Merge-Voraussetzungen

- [x] Beide fehlgeschlagenen Checks auf grün (siehe oben).
- [ ] Review-Entscheidung steht noch aus (`reviewDecision` leer; 1 Review
      vorhanden, aber kein genehmigendes) — Review einholen bzw. abwarten.

## 3. Release-Checkliste (aus `Documentation/NativeWebSocketTransport.md`)

- [ ] **Kein Release-Tag existiert.** Podspec trägt Prerelease-Version
      `17.0.0-native.1` und verweigt noch auf den Moving Branch
      `feat/native-urlsession-transport` (nicht auf `fix/coderabbit-findings-audit`).
      Vor Veröffentlichung: immutable Tag wählen/anlegen, Podspec-`source` auf
      den Tag umstellen, neu validieren.
- [ ] CI-Ergebnisse einem konkreten Commit zuordnen (Doku-Forderung).
- [ ] **Device-/Runtime-Validierung offen**, insbesondere watchOS — ein
      grüner macOS-Suite-Lauf und SDK-Builds belegen keine echte
      Geräte-Abdeckung (README + Doku weisen explizit darauf hin).
- [ ] Konsistenz prüfen: README/Doku nennen als Adopter-Hinweis, dass
      Verbraucher dieses Prerelease auf einen Commit pinnen sollen — nach dem
      Tag-Stich auf aktuellen Stand kontrollieren.

## 4. Optional / Kosmetik

- [ ] Überholte Legacy-TODOs in `Source/SocketIO/Manager/SocketManagerSpec.swift`
      (Zeilen 25, 60) sichten und ggf. erledigen oder entfernen.
- [ ] Prüfen, ob `Cartfile`/`Cartfile.resolved` (Starscream-Legacy) noch
      benötigt werden oder entfernt werden können.

## 5. Offen aus den Review-Runden (19.09.2026)

- [ ] **Gerätetest nach dem Upgrade-Fix (94f9004):** TimeMonkey auf den grünen Head pinnen, `.forceWebsockets(true)` testweise entfernen und prüfen, dass der Polling→WebSocket-Upgrade gegen den Bun-Server hält.
- [ ] **Council-Review der gesamten PR** erst nach ausdrücklicher Freigabe starten.
- [ ] **Ack-Bereinigung bei jedem Close** (JS `_clearAcks()` bei jedem `onclose`, Swift nur beim endgültigen Disconnect) — von Runde 2 bewusst offengelassen, berührt Retry-Queue und Send-Buffer.
- [ ] **Review-Gates R1 (Ressourcen-Policy für Puffer/Queues) und R5 (Geräte-/Runtime-Validierung, Thread Sanitizer, Swift-6-Modus)** aus `Documentation/ProtocolParityReview.md`.
- [ ] **Test-Inventar:** 57 `engine.io-client`- und 7 `socket.io-parser`-Deklarationen weiterhin `unmapped` (URI-Parsing, Cookies, Close-Details, Binär über Polling/WS, Blob/ArrayBuffer-Encoder).
- [ ] Swift-6-Sprachmodus / `swift-tools-version:6.x` als eigene Runde nach der Concurrency-Aufräumarbeit.
