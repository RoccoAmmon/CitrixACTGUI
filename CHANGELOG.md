# Changelog

## v1.1.0 (01.07.2026) – Cloud-Anmeldung & Credentials-Validierung

### 🚀 Neu
- **Cloud-Anmeldung direkt in der GUI:** Eingabefelder für Customer ID, Client ID und Secret werden bei Auswahl von „Cloud“ automatisch eingeblendet
- **Auto-Konfiguration `CustomerInfo.yml`:** Beim Ausführen wird die Datei automatisch im korrekten Pfad (`%USERPROFILE%\Documents\Citrix\AutoConfig\`) mit vollständiger YAML-Struktur erstellt
- **Credentials-Validierung:** Prüfung der Anmeldedaten auf Plausibilität vor dem Start (zu kurze/ungültige Werte lösen Warnung aus)
- **Tooltips & Hilfetexte:** Die Cloud-Eingabefelder enthalten Hinweise zum erwarteten Format (UUID, Secret-Länge etc.)
- **Fehlerbehebungs-Tipps:** Direkte Hinweise in der GUI bei Authentifizierungsfehlern

### 🔧 Verbessert
- **`Get-CustomerInfoPath()`** – zentrale Funktion für den Standardpfad statt Rekursion
- **`Test-CustomerInfoValidity()`** – neue Validierungslogik für Customer ID, Client ID und Secret
- **`Write-CustomerInfoYml()`** – generiert jetzt vollständige `CustomerInfo.yml` mit allen ACT-relevanten Feldern (Environment, Locale, Confirm, LogTransactions, OnErrorAction, DisplayLog)
- **ACT-Integration:** `CustomerInfoFileSpec` wird mit exaktem Dateipfad übergeben (Backup & Restore)
- **Log-Ausgaben:** Klarere Meldungen zur CustomerInfo.yml (Erfolg/Fehler/Validierung)

### 📝 Dokumentation
- README.md: Cloud-Features dokumentiert, Warnhinweis „Cloud nicht getestet“ entfernt
- Bedienungsanleitung: Neuer Abschnitt „Cloud-Anmeldung“ mit vollständiger Beschreibung
- Fehlerbehebung: Bearertoken-Fehler und Credentials-Themen ergänzt
- CHANGELOG.md erstellt

---

## v1.0.0 (01.07.2026) – Erste stabile Version

### 🚀 Neu
- Vollständige WPF-GUI mit Backup & Restore-Funktionalität
- Unterstützung für OnPrem (CVAD) und Cloud (DaaS) – automatische Parametererkennung
- 20 ACT-Komponenten als CheckBoxen (UniformGrid mit 5 Spalten)
- Selektive Komponentenauswahl für gezielten Restore
- Auto-Detection: Komponenten aus Backup-Ordner automatisch erkennen
- Zone Mapping: Automatische Generierung der `ZoneMapping.yml` aus `Zone.yml`
- CheckMode (Trockenlauf) für Restore
- Bestätigungsunterdrückung via `$ConfirmPreference` und conditionalem `-Confirm` Parameter
- Echtzeit-Log im GUI-Fenster + Dateilogging nach `C:\ScriptLog`
- Backups werden neueste zuerst sortiert
- „Alle“ / „Keine“ Schnellauswahl-Buttons
- Dynamische Fenstergröße (90 % Höhe, 85 % Breite)
- Versionseinblendung in der Titelleiste

### 🔧 Behoben
- **v1.0.0-beta:** Selective Restore hat alle Komponenten wiederhergestellt statt nur der ausgewählten
  - Ursache: ACT verwendet Switch-Parameter (z. B. `-GroupPolicies $true`), keine String-Arrays
  - Lösung: Foreach-Schleife mit individuellen Switch-Parametern
- **v1.0.0-beta:** Bestätigungsdialoge blockierten die GUI
  - Ursache: `-Confirm` wird nicht von allen ACT-Cmdlets unterstützt
  - Lösung: `$ConfirmPreference='None'` + conditionaler `Confirm`-Parameter
- **v1.0.0-beta:** Zones verursachten Restore-Fehler
  - Ursache: Fehlende ZoneMapping.yml
  - Lösung: Automatische Zone-Mapping-Generierung eingebaut
- **v1.0.0-beta:** Umlaute in Zone.yml wurden korrumpiert
  - Ursache: UTF-8 mit BOM
  - Lösung: Konsistent UTF-8 ohne BOM (`[System.Text.UTF8Encoding]::new($false)`)
- **v1.0.0-beta:** Parameterkonflikt `AdminAddress` vs `DDC`
  - Ursache: Unterschiedliche Parameternamen bei Export/Import
  - Lösung: DDC-Parameter entfernt, Restore arbeitet immer lokal

### 📝 Dokumentation
- Ausführliches README.md mit Badges, Installation, Bedienung, Komponenten
- Umfangreiches Wiki (8 Seiten): Home, Installation, Bedienung, Komponenten, Zone-Mapping, Logging, Fehlerbehebung, Changelog
- .gitignore für PowerShell-Projekte
- GitHub Release v1.0.0 erstellt
