# CVAD ACT Backup & Restore Manager

![Version](https://img.shields.io/badge/Version-1.1.0-1D4ED8?style=for-the-badge)
![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Citrix ACT](https://img.shields.io/badge/Citrix%20ACT-3.0.122.0-00A1E0?style=for-the-badge&logo=citrix&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![.NET](https://img.shields.io/badge/.NET-WPF-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**Autor:** Rocco Ammon  
**Stand:** 01.07.2026  
**Version:** 1.1.0  
**Sprache:** PowerShell 5.0+ / WPF (.NET)

---

## Übersicht

Graphische Oberfläche (WPF) für **Backup & Restore** einer **Citrix CVAD** (OnPrem) oder **Citrix DaaS** (Cloud) Umgebung über das **Automated Configuration Tool (ACT)**.

Das Skript ist als **Single-File-PowerShell-Skript** konzipiert – die gesamte GUI (XAML) ist direkt eingebettet. Keine zusätzlichen Dateien nötig.

---

## Features

- **Backup** – vollständige oder selektive Komponenten einer Citrix-Site sichern
- **Restore** – einzelne Komponenten aus einem Backup gezielt wiederherstellen
- **CheckMode (Trockenlauf)** – Änderungen nur anzeigen, ohne sie anzuwenden
- **OnPrem & Cloud** – unterstützt beide Umgebungen (automatische Parametererkennung)
- **Cloud-Anmeldung** – GUI-Eingabefelder für Customer ID, Client ID und Secret
- **Cloud-Validierung** – Prüfung der Anmeldedaten vor Ausführung (Warnung bei ungültigen Werten)
- **Auto-Konfiguration** – automatisches Schreiben der `CustomerInfo.yml` mit vollständiger YAML-Struktur
- **Auto-Detection** – erkennt automatisch, welche Komponenten im Backup-Ordner vorhanden sind
- **Zone Mapping** – automatische Generierung der `ZoneMapping.yml` aus der `Zone.yml`
- **Selektive Komponentenauswahl** – 20 Komponenten als CheckBoxen, via UniformGrid mit 5 Spalten
- **Schnellauswahl** – „Alle“ / „Keine“ Buttons
- **GUI-Log** – Echtzeit-Protokoll im Fenster + Dateilogging nach `C:\ScriptLog`
- **Bestätigungsunterdrückung** – automatisierte Ausführung ohne manuelle Eingriffe

---

## Systemvoraussetzungen

| Komponente | Anforderung |
|---|---|
| **Betriebssystem** | Windows Server 2016 / 2019 / 2022 oder Windows 10 / 11 |
| **PowerShell** | 5.0 oder höher |
| **Citrix ACT** | Automated Configuration Tool v3.0.122.0 (ab Version 3.0) |
| **.NET Framework** | 4.7.2 oder höher (für WPF) |
| **Bildschirmauflösung** | Mindestens 1024 × 768 (optimiert für Full-HD) |

---

## Installation

1. **Citrix ACT installieren** (falls nicht vorhanden):
   - Download: https://www.citrix.com/downloads/citrix-cloud/product-software/automated-configuration.html
   - Die ACT-Cmdlets werden als PowerShell-SnapIn oder Modul installiert.

2. **Skript herunterladen**:
   - `CitrixACTGui.ps1` in ein beliebiges Verzeichnis kopieren.

3. **Ausführung erlauben** (falls eingeschränkt):
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

4. **Skript starten**:
   ```powershell
   .\CitrixACTGui.ps1
   ```

---

## Bedienung

### 1) Aktion
- **Backup erstellen** – sichert die konfigurierten Komponenten in einen Ordner
- **Restore durchführen** – stellt Komponenten aus einem bestehenden Backup wieder her
- **Trockenlauf (CheckMode)** – führt einen Durchlauf ohne echte Änderungen durch (nur Restore)

### 2) Umgebung
- **OnPrem** – für lokale Citrix CVAD-Installationen (keine DDC-Angabe nötig, arbeitet immer lokal)
- **Cloud** – für Citrix DaaS (Citrix Cloud). Zeigt Eingabefelder für Customer ID, Client ID und Secret an.

### 3) Cloud-Anmeldung (nur Cloud-Modus)
Sobald „Cloud“ ausgewählt wird, erscheint eine GroupBox mit drei Eingabefeldern:
- **Customer ID** – Ihre Citrix Cloud-Kundennummer (z. B. `markhof123`)
- **Client ID** – UUID des Secure Clients (Format: `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`)
- **Secret** – geheimer Schlüssel des Secure Clients (verschlüsselter String, 20+ Zeichen)

Beim Klick auf **Ausführen** werden die Daten validiert und automatisch in die `CustomerInfo.yml` geschrieben:
```
C:\Users\[Username]\Documents\Citrix\AutoConfig\CustomerInfo.yml
```

Die generierte Datei enthält automatisch alle erforderlichen Felder (Environment, Locale, LogTransactions, uvm.) im korrekten YAML-Format.

> ⚠️ **Validierung:** Zu kurze oder ungültig aussehende Credentials lösen eine Warnung aus, die bestätigt werden muss.

### 3) Backup-Ordner & Komponenten
- **Ordner** – Basisverzeichnis für Backups (Standard: `C:\CvadBackups`)
- **Verfügbare Backups** – Listet alle vorhandenen Backup-Ordner auf (neueste zuerst)
- **Komponenten** – 20 CheckBoxen zur Auswahl der zu sichernden/wiederherstellenden Komponenten
- **Zone Mapping** – generiert automatisch eine `ZoneMapping.yml` aus dem ausgewählten Backup

### Buttons
| Button | Funktion |
|---|---|
| ▶ **Ausführen** | Startet Backup oder Restore |
| ✖ **Schließen** | Beendet die Anwendung |
| ✓ **Alle** | Alle Komponenten auswählen |
| ✗ **Keine** | Alle Komponenten abwählen |
| 🗺️ **Zone Mapping** | ZoneMapping.yml aus Zone.yml generieren |

---

## Komponentenübersicht

Das ACT-Tool unterscheidet 20 Komponenten, die einzeln gesichert und wiederhergestellt werden können:

| # | Komponente | Beschreibung |
|---|---|---|
| 1 | **Zones** | Citrix-Zonen – definieren die geografische oder logische Aufteilung der Site (z. B. Primäre Zone, Sekundäre Zone) |
| 2 | **Tags** | Tags zur Kennzeichnung und Filterung von Objekten (Maschinen, Kataloge, Delivery Groups etc.) |
| 3 | **AdminRoles** | Administratorrollen – Berechtigungsvorlagen für die Verwaltung der Site |
| 4 | **AdminScopes** | Admin-Geltungsbereiche – definieren, auf welche Objekte sich eine Rolle bezieht |
| 5 | **HostConnections** | Hostverbindungen – Verbindungen zu Hypervisoren (VMware, Hyper-V, XenServer, Nutanix etc.) |
| 6 | **MachineCatalogs** | Maschinenkataloge – Pools von virtuellen oder physischen Maschinen |
| 7 | **PolicySets** | Richtliniensätze – Konfiguration von Citrix-Richtlinien (z. B. USB-Redirection, Drucken) |
| 8 | **Storefronts** | StoreFront-Konfiguration (Authentifizierung, Stores, Beacons) |
| 9 | **DeliveryGroups** | Liefergruppen – verknüpfen Maschinenkataloge mit Benutzern/Anwendungen |
| 10 | **ApplicationGroups** | Anwendungsgruppen – Gruppierung von Anwendungen für die Zuweisung |
| 11 | **ApplicationFolders** | Anwendungsordner – Ordnerstruktur für Anwendungen im Citrix-Store |
| 12 | **Applications** | Einzelanwendungen – veröffentlichte Anwendungen (Dateisystem-Pfad, Argumente, Icons) |
| 13 | **AppLibPackageDiscovery** | AppLib-Paketerkennung – automatische Suche nach App-V- oder MSIX-Paketen |
| 14 | **AdminAdministrators** | Administratoren – Benutzer und Gruppen mit Administratorrechten auf die Site |
| 15 | **AdminFolders** | Admin-Ordner – Ordnerstruktur zur Organisation der Administrationsobjekte |
| 16 | **GroupPolicies** | Gruppenrichtlinien – Citrix-spezifische Gruppenrichtlinieneinstellungen |
| 17 | **SiteData** | Siteweite Daten – globale Einstellungen der Citrix-Site (Lizenzserver, Datenbankverbindung etc.) |
| 18 | **UserZonePreferences** | Benutzer-Zonenpräferenzen – bevorzugte Zonen für Benutzer (für die Standortsteuerung) |
| 19 | **AppVIsolationGroups** | App-V-Isolationsgruppen – Konfiguration von App-V-Isolationsumgebungen |
| 20 | **BackupSchedules** | Backup-Zeitpläne – geplante automatische Sicherungen innerhalb des ACT-Tools |

---

## Logging

- **GUI-Protokollfenster** – zeigt die ACT-Ausgabe in Echtzeit an
- **Dateilog** – wird automatisch nach `C:\ScriptLog\CVAD-ACT-GUI_{Zeitstempel}.log` geschrieben
- **ACT-eigenes Log** – wird vom ACT-Tool automatisch im Backup-Ordner unter `History.log` erstellt

---

## Zone Mapping

Beim Restore über Zonengrenzen hinweg (z. B. lokales Backup → anderer DDC) kann eine **ZoneMapping.yml** erforderlich sein.

Der Button **„🗺️ Zone Mapping“** erzeugt automatisch eine 1:1-Zuordnung aus der `Zone.yml` des ausgewählten Backups:

```
---
Primäre: Primäre
Sekundäre: Sekundäre
```

Die generierte Datei wird im Backup-Ordner gespeichert.

---

## Fehlerbehebung

| Problem | Ursache / Lösung |
|---|---|
| **„Import-CvadAcToSite nicht gefunden“** | ACT ist nicht installiert oder das PowerShell-SnapIn nicht geladen. ACT installieren und PowerShell neu starten. |
| **„CustomerInfo.yml nicht gefunden“** | Im Cloud-Modus muss die `CustomerInfo.yml` im Benutzerprofil liegen. Wird automatisch aus den GUI-Eingabefeldern generiert. |
| **Bearertoken-Fehler (Cloud)** | Ungültige Customer ID, Client ID oder Secret. Credentials im Citrix Cloud Admin Portal prüfen. Siehe Abschnitt **Cloud-Anmeldung**. |
| **Restore macht keine Änderungen** | Prüfen, ob die richtigen Komponenten angehakt sind und ob `CheckMode` deaktiviert ist. |
| **Zone.yml nicht gefunden** | Das Backup enthält keine Zonen-Komponente. Zone Mapping ist dann nicht nötig. |
| **Umlaute werden falsch dargestellt** | Encoding-Problem – die Dateien werden jetzt automatisch als UTF-8 ohne BOM gespeichert. |

---

## Lizenz

Dieses Skript wird ohne Gewähr und ohne Support bereitgestellt.  
Nutzung auf eigene Verantwortung. Änderungen und Weiterentwicklung erwünscht.
