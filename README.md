# Drucker-Umzug

Überträgt Drucker-Einstellungen und Treiber von einem alten auf einen neuen Mac.

## Was es macht

Das Skript `Drucker-Umzug.command` liest auf dem alten Mac alle eingerichteten Drucker aus, sichert deren Treiber (PPD-Dateien und Treiberordner) und legt sie auf dem neuen Mac wieder an. Es löscht nichts und überschreibt nichts.

## Schritt für Schritt

**Auf dem alten Mac**

1. `Drucker-Umzug.command` doppelklicken.
2. Im Menü die **1** eingeben und Enter drücken.
3. Das Administrator-Passwort eingeben.
4. Es entsteht der Ordner **Drucker-Export** auf dem Schreibtisch.
5. Den Ordner per USB-Stick oder AirDrop auf den neuen Mac bringen.

**Auf dem neuen Mac**

1. `Drucker-Umzug.command` doppelklicken.
2. **2** eingeben (Vorschau). Die Vorschau zeigt, was passieren würde, und ändert nichts. Den Ordner dazu ins Fenster ziehen und Enter drücken.
3. Wenn die Vorschau passt: **3** eingeben (ausführen) und das Administrator-Passwort eingeben.
4. Eine Testseite pro Drucker drucken (Systemeinstellungen > Drucker & Scanner).

## Falls macOS den Start blockiert

Die Datei stammt aus dem Internet, deshalb kann macOS den Start verweigern. So geht es:

- **Rechtsklick** auf die Datei, dann **Öffnen** wählen.
- Oder: **Systemeinstellungen > Datenschutz & Sicherheit**, unten auf **„Dennoch öffnen“** klicken.
- Alternative im Terminal:
  `xattr -d com.apple.quarantine Drucker-Umzug.command`

## Für Profis

Kommandozeile (im Ordner der Datei):

```
sudo ./Drucker-Umzug.command export <ordner>
sudo ./Drucker-Umzug.command import <ordner>            # Vorschau
sudo ./Drucker-Umzug.command import <ordner> --apply    # ausführen
```

## Garantien

- Es wird nichts gelöscht.
- Vorhandene Dateien werden nie überschrieben. Treiber werden nur ergänzt, wenn sie fehlen.
- Die Vorschau (`import` ohne `--apply`) ändert nichts.
- Existiert der Export-Ordner schon, bricht der Export ab. Im Menü bekommt er dann einen Zeitstempel.
- Hat ein Drucker auf dem neuen Mac schon denselben Namen, wird der neue mit Suffix `-migriert` angelegt (bzw. `-migriert2`, `-migriert3`, ...).

## Grenzen

- Drucker mit eigenen Herstellertreibern und Hintergrunddiensten: Bitte den Installer des Herstellers verwenden. Das Skript kann diese nicht vollständig übertragen.
- Drucker ohne PPD-Datei werden nur übernommen, wenn sie IPP/AirPrint unterstützen (`ipp://`, `ipps://`, `dnssd://`). Alle anderen werden übersprungen.
- USB-Drucker müssen beim Import angeschlossen sein.
- Druckvoreinstellungen (Presets, z. B. Duplex oder Papierformat) werden nicht übernommen.
- Der Standarddrucker wird nicht automatisch gesetzt.
