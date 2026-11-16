# Drucker-Umzug

Überträgt Drucker-Einstellungen und Treiber von einem alten auf einen neuen Mac.

> **Start blockiert?** Die App ist nicht von Apple beglaubigt. Beim ersten Start: **Systemeinstellungen > Datenschutz & Sicherheit**, unten bei „Drucker-Umzug“ auf **„Dennoch öffnen“** klicken (ältere macOS: Rechtsklick > Öffnen; Terminal: `xattr -dr com.apple.quarantine Drucker-Umzug.app`).

## Was es macht

Die App liest auf dem alten Mac alle eingerichteten Drucker aus, sichert deren Treiber (PPD-Dateien und Treiberordner) und legt sie auf dem neuen Mac wieder an. Es löscht nichts und überschreibt nichts.

## Schritt für Schritt

Download: [Drucker-Umzug.zip](https://github.com/klopsnic-cyber/drucker-umzug/releases/latest/download/Drucker-Umzug.zip) – entpacken, auf beiden Macs dasselbe Programm.

**Auf dem alten Mac**

1. **Drucker-Umzug.app** öffnen und auf **Export** klicken.
2. Das Administrator-Passwort eingeben.
3. Auf dem Schreibtisch entsteht **Drucker-Export-<Datum>.zip**.
4. Diese Zip-Datei per USB-Stick, AirDrop oder Netzwerk auf den neuen Mac bringen.

**Wichtig:** Der Export kann Druckerkennwörter enthalten. Die Zip-Datei nach dem Umzug auf beiden Macs löschen.

**Auf dem neuen Mac**

1. **Drucker-Umzug.app** öffnen und auf **Import** klicken.
2. Die Zip-Datei auswählen. Es erscheint eine **Vorschau** – dabei wird noch nichts geändert.
3. **Jetzt einrichten** klicken und das Administrator-Passwort eingeben.
4. Die Liste „Bitte danach prüfen“ abarbeiten und pro Drucker eine Testseite drucken (Systemeinstellungen > Drucker & Scanner).

## Updates

Beim Start prüft die App, ob es eine neue Version gibt, und bietet sie an („Jetzt aktualisieren“). Vor der Installation werden Prüfsumme und Version kontrolliert; schlägt etwas fehl, bleibt die alte App erhalten. Ohne Internet startet sie einfach normal.

## Für Profis

Ohne App, per Kommandozeile mit `Drucker-Umzug.command` (liegt mit im Zip, läuft auf jedem macOS):

```
sudo ./Drucker-Umzug.command export <ordner>
sudo ./Drucker-Umzug.command import <ordner>            # Vorschau
sudo ./Drucker-Umzug.command import <ordner> --apply    # ausführen
```

## Garantien

- Es wird nichts gelöscht.
- Vorhandene Dateien werden nie überschrieben. Treiber werden nur ergänzt, wenn sie fehlen.
- Die Vorschau (`import` ohne `--apply`) ändert nichts.
- Hat ein Drucker auf dem neuen Mac schon denselben Namen, wird der neue mit Suffix `-migriert` angelegt (bzw. `-migriert2`, `-migriert3`, ...).

## Grenzen

- Drucker mit eigenen Herstellertreibern und Hintergrunddiensten: Bitte den Installer des Herstellers verwenden. Das Skript kann diese nicht vollständig übertragen.
- Drucker ohne PPD-Datei werden nur übernommen, wenn sie IPP/AirPrint unterstützen (`ipp://`, `ipps://`, `dnssd://`). Alle anderen werden übersprungen.
- USB-Drucker müssen beim Import angeschlossen sein.
- Druckvoreinstellungen aus dem Druckdialog (Presets, z. B. Duplex oder Papierformat) werden nicht übernommen. Die Druckeroptionen aus der Druckerkonfiguration schon.
- Der Standarddrucker wird gesetzt, wenn auf dem neuen Mac noch keiner gesetzt ist.
- Druckerklassen werden übernommen. Ein wiederholter Import erzeugt keine Duplikate.
- Alles, was nach dem Import von Hand geprüft werden sollte, steht am Ende in der Liste „Bitte danach prüfen“.
