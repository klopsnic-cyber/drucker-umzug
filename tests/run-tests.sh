#!/bin/bash
# Testsuite fuer Drucker-Umzug.command. Laeuft mit macOS /bin/bash 3.2.
# Alles in einem Temp-Ordner; echtes /etc/cups, /Library/Printers, lpadmin werden nie angefasst.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/Drucker-Umzug.command"
T="$(mktemp -d "${TMPDIR:-/tmp}/druckertest.XXXXXX")" || exit 2
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"' EXIT
US=$'\037'
TAB=$'\t'

PASSN=0; FAILN=0
chk() { # chk "Beschreibung" 'shell-ausdruck'
  if eval "$2" >/dev/null 2>&1; then PASSN=$((PASSN+1)); echo "PASS: $1"
  else FAILN=$((FAILN+1)); echo "FAIL: $1   [$2]"; fi
}

# ---------- Stubs ----------
STUBS="$T/stubs"; mkdir -p "$STUBS"
cat > "$STUBS/lpstat" <<'EOF'
#!/bin/bash
# FAKE_EXISTING: Zeilen "NAME<TAB>URI" (URI optional; Klassen ohne URI); FAKE_DEFAULT: Standarddrucker
case "$1" in
  -p|-c) cut -f1 "$FAKE_EXISTING" | grep -Fxq -- "$2" ;;
  -v) awk -F'\t' 'NF > 1 { print "device for " $1 ": " $2 }' "$FAKE_EXISTING" ;;
  -d) if [ -n "${FAKE_DEFAULT:-}" ]; then echo "system default destination: $FAKE_DEFAULT"
      else echo "no system default destination"; fi ;;
esac
EOF
cat > "$STUBS/lpadmin" <<'EOF'
#!/bin/bash
# loggt jeden Aufruf als eine Zeile: \037arg1\037arg2\037
printf '\037%s' "$@" >> "$FAKE_LOG"; printf '\037\n' >> "$FAKE_LOG"
if [ "$1" = -p ]; then
  [ -n "${LPADMIN_FAIL:-}" ] && [ "$2" = "$LPADMIN_FAIL" ] && exit 1
  uri=""; cls=""; prev=""
  for a in "$@"; do case "$prev" in -v) uri="$a";; -c) cls="$a";; esac; prev="$a"; done
  if [ -n "$cls" ]; then echo "$cls" >> "$FAKE_EXISTING"; else printf '%s\t%s\n' "$2" "$uri" >> "$FAKE_EXISTING"; fi
fi
exit 0
EOF
cat > "$STUBS/cupsdisable" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG.disable"
EOF
cat > "$STUBS/pkgutil" <<'EOF'
#!/bin/bash
[ "$1" = --pkgs ] && cat "${FAKE_PKGS:-/dev/null}"
EOF
cat > "$STUBS/file" <<'EOF'
#!/bin/bash
for f; do :; done
if grep -q X86ONLY "$f" 2>/dev/null; then echo "Mach-O 64-bit executable x86_64"; else exec /usr/bin/file "$@"; fi
EOF
cat > "$STUBS/xattr" <<'EOF'
#!/bin/bash
[ -n "${XATTR_FAIL:-}" ] && exit 1
exec /usr/bin/xattr "$@"
EOF
chmod +x "$STUBS"/*

# ---------- Fake-Quelle (alter Mac) ----------
SRC="$T/src"; CUPS="$SRC/cups"; PSRC="$SRC/printers"
mkdir -p "$CUPS/ppd" "$CUPS/ssl" "$PSRC/Drv/Contents/Filter" "$PSRC/Drv/Contents/Resources"
{
  printf '# Printer configuration file for CUPS\n'
  printf '<DefaultPrinter Office>\n'
  printf 'UUID urn:uuid:1\nInfo HP LaserJet Büro\nLocation Raum 1\nMakeModel HP LaserJet 4000\n'
  printf 'DeviceURI lpd://10.0.0.5/queue\nState Idle\nShared Yes\n'
  printf 'Option finishings-default 3\nOption custom-note Hallo  Welt\n</Printer>\n'
  printf '<Class Gruppe>\nInfo Klassen-Info\nLocation Klassen-Ort\nMakeModel Klasse\nDeviceURI file:///dev/null\nShared Yes\n</Class>\n'
  printf '<Printer Empty>\nInfo \nMakeModel Brother X\nDeviceURI ipp://10.0.0.9/ipp/print\nShared No\n</Printer>\n'
  printf '<Printer Usbp>\nInfo USB Gerät\nMakeModel Canon Y\nDeviceURI usb://Canon/Y?serial=1\nShared No\n</Printer>\n'
  printf '<Printer Spaced>\nInfo Mein  Büro Drucker\nLocation EG links\nMakeModel Epson Z\nDeviceURI socket://10.0.0.7:9100\nShared Yes\n</Printer>\n'
  printf '<Printer Secure>\nInfo Secure Drucker\nMakeModel Ricoh S\nDeviceURI smb://user:geheim@server/Drucker\n'
  printf 'AuthInfoRequired username,password\nState Stopped\nShared No\n</Printer>\n'
} > "$CUPS/printers.conf"
printf '<DefaultClass Team>\nInfo Team\nPrinter Office\nPrinter Spaced\nPrinter Usbp\n</Class>\n<Class Alt>\nPrinter Spaced\n</Class>\n' > "$CUPS/classes.conf"
{ echo '*PPD-Adobe: "4.3"'; echo '*cupsFilter: "application/vnd.cups-raster 0 /Library/Printers/Drv/Contents/Filter/rastertox"'
  echo '*cupsFilter2: "application/pdf application/vnd.cups-raster 10 /Library/Printers/Drv/Contents/Filter/x86filter"'; } > "$CUPS/ppd/Office.ppd"
{ echo '*PPD-Adobe: "4.3"'; echo '*APDialogExtension: "/Library/Printers/Fehlt/Mein PDE.plugin"'; } > "$CUPS/ppd/Spaced.ppd"
echo '*PPD-Adobe: "4.3"' > "$CUPS/ppd/Secure.ppd"
echo "Listen 631" > "$CUPS/cupsd.conf"; echo "secret" > "$CUPS/passwords.md5"; echo "KEY" > "$CUPS/ssl/server.key"
echo "#!/bin/sh" > "$PSRC/Drv/Contents/Filter/rastertox"; chmod 755 "$PSRC/Drv/Contents/Filter/rastertox"
echo "X86ONLY" > "$PSRC/Drv/Contents/Filter/x86filter"; chmod 755 "$PSRC/Drv/Contents/Filter/x86filter"
echo "readme" > "$PSRC/Drv/Contents/Resources/readme.txt"
echo "SOURCE-DIFFERENT" > "$PSRC/Drv/shared.txt"
ln -s Contents "$PSRC/Drv/Current"
printf 'com.brother.driver\ncom.apple.pkg.Printer\ncom.example.other\njp.co.canon.x\n' > "$T/srcpkgs"
BK="$T/backend"; mkdir -p "$BK"; for b in lpd ipp ipps dnssd socket usb smb; do touch "$BK/$b"; done

snap() { ( cd "$1" 2>/dev/null || exit 0
  find . -exec stat -f '%N %p %z %m' {} \; | sort
  find . -type f -exec shasum {} \; | sort
  find . -type l -exec sh -c 'for l; do echo "$l -> $(readlink "$l")"; done' _ {} + | sort ); }

# Zielverzeichnis frisch bauen: Drv/shared.txt mit anderem Inhalt, plus Ziel-eigene Datei
mk_target() { rm -rf "$1"; mkdir -p "$1/Drv" "$1/Eigen"; echo "TARGET-ORIGINAL" > "$1/Drv/shared.txt"; echo "mine" > "$1/Eigen/x"; }

# run <existing-inhalt> <printers_dir> <args...>   (Log in $LOG, Existing in $EX)
# Optionale Variablen: FAIL DEFAULT PKGS ARCH ROSETTA BACKEND GUI XFAIL TMPD CUPSD
LOG="$T/lpadmin.log"; EX="$T/existing.txt"
run() { local ex="$1" pd="$2"; shift 2
  : > "$LOG"; : > "$LOG.disable"; printf '%s' "$ex" > "$EX"
  env CUPS_DIR="${CUPSD:-$CUPS}" PRINTERS_DIR="$pd" NEED_ROOT=0 PATH="$STUBS:$PATH" \
      FAKE_LOG="$LOG" FAKE_EXISTING="$EX" LPADMIN_FAIL="${FAIL:-}" FAKE_DEFAULT="${DEFAULT:-}" \
      FAKE_PKGS="${PKGS:-/dev/null}" HOST_ARCH="${ARCH:-x86_64}" HAS_ROSETTA="${ROSETTA:-1}" \
      BACKEND_DIR="${BACKEND:-$BK}" DU_GUI="${GUI:-0}" XATTR_FAIL="${XFAIL:-}" TMPDIR="${TMPD:-${TMPDIR:-/tmp}}" \
      /bin/bash "$SCRIPT" "$@" </dev/null; }
callline() { grep -F -- "${US}-p${US}$1${US}" "$LOG" | head -1; }
ncalls() { wc -l < "$LOG" | tr -d ' '; }
ncreate() { grep -cF -- "${US}-E${US}" "$LOG"; }   # nur Anlege-Aufrufe

# ================= EXPORT =================
EXP="$T/export"
SNAP_CUPS_BEFORE="$(snap "$CUPS")"; SNAP_P_BEFORE="$(snap "$PSRC")"
NTMP_BEFORE=$(ls -d /private/tmp/drucker-umzug.* 2>/dev/null | wc -l)
PKGS="$T/srcpkgs" run "" "$PSRC" export "$EXP" > "$T/export.out" 2>&1; RC=$?
chk "Export Exitcode 0" "[ $RC -eq 0 ]"
printf 'Office\tja\tHP LaserJet Büro\tRaum 1\tHP LaserJet 4000\tlpd://10.0.0.5/queue\tja\t-\tnein\n'      >  "$T/expected.tsv"
printf 'Empty\tnein\t-\t-\tBrother X\tipp://10.0.0.9/ipp/print\tnein\t-\tnein\n'                            >> "$T/expected.tsv"
printf 'Usbp\tnein\tUSB Gerät\t-\tCanon Y\tusb://Canon/Y?serial=1\tnein\t-\tnein\n'                         >> "$T/expected.tsv"
printf 'Spaced\tnein\tMein  Büro Drucker\tEG links\tEpson Z\tsocket://10.0.0.7:9100\tja\t-\tnein\n'          >> "$T/expected.tsv"
printf 'Secure\tnein\tSecure Drucker\t-\tRicoh S\tsmb://user:geheim@server/Drucker\tnein\tusername,password\tja\n' >> "$T/expected.tsv"
chk "manifest.tsv exakt wie erwartet (Platzhalter '-', Class ignoriert, Default=ja, Auth, Stopped)" "diff '$T/expected.tsv' '$EXP/manifest.tsv'"
chk "Class 'Gruppe' nicht im Manifest" "! grep -q Gruppe '$EXP/manifest.tsv'"
chk "Manifest hat 5 Zeilen" "[ \$(wc -l < '$EXP/manifest.tsv' | tr -d ' ') -eq 5 ]"
chk "PPD Office kopiert" "diff '$CUPS/ppd/Office.ppd' '$EXP/ppd/Office.ppd'"
chk "PPD Spaced kopiert" "diff '$CUPS/ppd/Spaced.ppd' '$EXP/ppd/Spaced.ppd'"
chk "Keine PPD fuer Drucker ohne PPD" "[ ! -e '$EXP/ppd/Empty.ppd' ] && [ ! -e '$EXP/ppd/Usbp.ppd' ]"
chk "Sicherheit: kein cups-original/ssl/cupsd.conf/passwords.md5 im Export" "[ ! -e '$EXP/cups-original' ] && ! find '$EXP' -name ssl -o -name cupsd.conf -o -name passwords.md5 -o -name server.key | grep -q ."
chk "Sicherheit: Zip enthaelt keine ssl/Kennwortdateien" "! unzip -l '$EXP.zip' | grep -qE 'ssl/|server.key|passwords.md5|cupsd.conf'"
printf 'Office\tfinishings-default\t3\nOffice\tcustom-note\tHallo  Welt\n' > "$T/expected-opt.tsv"
chk "options.tsv mit Optionen (Leerzeichen erhalten)" "diff '$T/expected-opt.tsv' '$EXP/options.tsv'"
printf 'Team\tOffice\nTeam\tSpaced\nTeam\tUsbp\nAlt\tSpaced\n' > "$T/expected-cls.tsv"
chk "classes.tsv aus classes.conf" "diff '$T/expected-cls.tsv' '$EXP/classes.tsv'"
chk "quelle.txt mit macOS-Version und Architektur" "grep -qE '^macOS [0-9].* \\((arm64|x86_64)\\)\$' '$EXP/quelle.txt'"
printf 'com.brother.driver\njp.co.canon.x\n' > "$T/expected-pkgs.txt"
chk "pakete.txt: nur Herstellerpakete, kein com.apple" "diff '$T/expected-pkgs.txt' '$EXP/pakete.txt'"
chk "Export-Ausgabe maskiert Zugangsdaten" "grep -qF 'smb://***@server/Drucker' '$T/export.out' && ! grep -q geheim '$T/export.out'"
chk "Export: kein Temp-Ordner bleibt liegen, kein Temp-Pfad in Ausgabe" "[ \$(ls -d /private/tmp/drucker-umzug.* 2>/dev/null | wc -l) -eq $NTMP_BEFORE ] && ! grep -q 'drucker-umzug\\.' '$T/export.out'"
chk "Treiber nach Library-Printers kopiert" "[ -f '$EXP/Library-Printers/Drv/Contents/Resources/readme.txt' ]"
chk "Export: Symlink bleibt Symlink" "[ -L '$EXP/Library-Printers/Drv/Current' ]"
chk "Export: Executable-Bit erhalten" "[ -x '$EXP/Library-Printers/Drv/Contents/Filter/rastertox' ]"
chk "Export: Quelle CUPS_DIR unveraendert" "[ \"\$SNAP_CUPS_BEFORE\" = \"\$(snap '$CUPS')\" ]"
chk "Export: Quelle PRINTERS_DIR unveraendert" "[ \"\$SNAP_P_BEFORE\" = \"\$(snap '$PSRC')\" ]"
chk "Export ruft lpadmin nie auf" "[ \$(ncalls) -eq 0 ]"

mkdir "$T/exists"; echo keep > "$T/exists/f"
run "" "$PSRC" export "$T/exists" > "$T/exp2.out" 2>&1; RC=$?
chk "Export lehnt existierenden Zielordner ab (Exit != 0)" "[ $RC -ne 0 ]"
chk "Export in existierenden Ordner schreibt nichts hinein" "[ \$(ls '$T/exists' | wc -l | tr -d ' ') -eq 1 ] && [ \"\$(cat '$T/exists/f')\" = keep ]"
chk "Fehlermeldung ohne 'FEHLER:'-Praefix" "[ -s '$T/exp2.out' ] && ! grep -q 'FEHLER' '$T/exp2.out'"
ln -s "$T/exists" "$T/link"
run "" "$PSRC" export "$T/link" > /dev/null 2>&1; RC=$?
chk "Export lehnt Symlink als Ziel ab" "[ $RC -ne 0 ] && [ \$(ls '$T/exists' | wc -l | tr -d ' ') -eq 1 ]"
ln -s "$T/exists/f" "$T/link2.zip"
run "" "$PSRC" export "$T/link2" > /dev/null 2>&1; RC=$?
chk "Export lehnt vorhandenes/Symlink-Zip als Ziel ab" "[ $RC -ne 0 ] && [ ! -e '$T/link2' ] && [ \"\$(cat '$T/exists/f')\" = keep ]"
run "" "$PSRC" export > "$T/exp3.out" 2>&1; RC=$?
chk "Export ohne Ordner-Argument schlaegt fehl" "[ $RC -ne 0 ]"
mkdir -p "$T/leer-cups"; printf '<Class X>\nPrinter A\n</Class>\n' > "$T/leer-cups/printers.conf"
CUPSD="$T/leer-cups" run "" "$PSRC" export "$T/exp-leer" > "$T/exp4.out" 2>&1; RC=$?
chk "Export ohne Drucker: laienverstaendliche Meldung, Exit 1, nichts angelegt" "[ $RC -eq 1 ] && grep -qx 'Auf diesem Mac sind keine Drucker eingerichtet – es gibt nichts zu exportieren.' '$T/exp4.out' && [ ! -e '$T/exp-leer' ]"
CUPSD="$T/gibts-nicht" run "" "$PSRC" export "$T/exp-leer" > "$T/exp5.out" 2>&1; RC=$?
chk "Export ohne printers.conf: gleiche Meldung" "[ $RC -eq 1 ] && grep -q 'keine Drucker eingerichtet' '$T/exp5.out'"
GUI=1 run "" "$PSRC" export "$T/exportG" > "$T/exportG.out" 2>&1
chk "GUI-Export: eine Zeile je Drucker, kein Pfad/URI" "grep -qx '• HP LaserJet Büro (HP LaserJet 4000)' '$T/exportG.out' && ! grep -qE '$T|/tmp|://' '$T/exportG.out' && grep -q 'exportG.zip' '$T/exportG.out'"

# ================= IMPORT: VORSCHAU =================
GONE="$T/nonexistent-printers"
run "" "$GONE" import "$EXP" > "$T/prev1.out" 2>&1; RC=$?
chk "Vorschau Exitcode 0" "[ $RC -eq 0 ]"
chk "Vorschau: lpadmin 0 Aufrufe" "[ \$(ncalls) -eq 0 ]"
chk "Vorschau: cupsdisable 0 Aufrufe" "[ ! -s '$LOG.disable' ]"
chk "Vorschau: nicht existierendes Ziel-PRINTERS_DIR wird nicht angelegt" "[ ! -e '$GONE' ]"
chk "Vorschau nennt sich VORSCHAU" "grep -q VORSCHAU '$T/prev1.out'"
chk "Vorschau: Hinweis 'Nur eigene Exporte importieren'" "grep -q 'Nur eigene Exporte importieren – Treiber werden mit Administratorrechten installiert.' '$T/prev1.out'"
chk "Vorschau: Quellsystem angezeigt" "grep -q '^Alter Mac: macOS' '$T/prev1.out'"
chk "Vorschau: Abschnitt 'Bitte danach prüfen:'" "grep -qx 'Bitte danach prüfen:' '$T/prev1.out'"
chk "Vorschau: Treiberteil fehlt (APDialogExtension) fuer Spaced" "grep -qF '• Drucker „Mein  Büro Drucker“: Treiberteil fehlt – Herstellertreiber installieren.' '$T/prev1.out'"
chk "Vorschau: Pfade, die das Treiberkopieren ergaenzt, gelten als vorhanden" "! grep -qF '„HP LaserJet Büro“: Treiberteil fehlt' '$T/prev1.out'"
chk "Vorschau: Kennwort-Hinweis fuer smb/AuthInfoRequired" "grep -qF 'Drucker „Secure Drucker“ braucht ein Kennwort – beim ersten Druck eingeben.' '$T/prev1.out'"
chk "Vorschau: Credentials maskiert" "grep -qF 'smb://***@server/Drucker' '$T/prev1.out' && ! grep -q geheim '$T/prev1.out'"
chk "Vorschau: fehlende Herstellerpakete als Hinweis" "grep -qF 'Herstellersoftware installiert, die hier fehlt: com.brother.driver, jp.co.canon.x' '$T/prev1.out'"
PKGS="$T/srcpkgs" run "" "$GONE" import "$EXP" > "$T/prevP.out" 2>&1
chk "Vorschau: kein Paket-Hinweis, wenn Pakete vorhanden" "! grep -q Herstellersoftware '$T/prevP.out'"
chk "Vorschau: ohne Rosetta-Bedarf kein Rosetta-Hinweis (x86_64)" "! grep -q Rosetta '$T/prev1.out'"
ARCH=arm64 ROSETTA=0 run "" "$GONE" import "$EXP" > "$T/prevR.out" 2>&1
chk "Vorschau: x86_64-Filter auf arm64 ohne Rosetta -> Hinweis" "grep -qF '„HP LaserJet Büro“: Rosetta nötig – im Terminal: softwareupdate --install-rosetta' '$T/prevR.out'"
ARCH=arm64 ROSETTA=1 run "" "$GONE" import "$EXP" > "$T/prevR2.out" 2>&1
chk "Vorschau: arm64 mit Rosetta -> kein Hinweis" "! grep -q Rosetta '$T/prevR2.out'"
mkdir -p "$T/bk2"; touch "$T/bk2/lpd" "$T/bk2/ipp" "$T/bk2/smb"
BACKEND="$T/bk2" run "" "$GONE" import "$EXP" > "$T/prevB.out" 2>&1
chk "Vorschau: fehlendes Backend -> Warnung" "grep -qF 'Anschlussart „socket“ fehlt auf diesem Mac' '$T/prevB.out' && ! grep -qF 'Anschlussart „lpd“' '$T/prevB.out'"
chk "Vorschau: Standarddrucker wuerde gesetzt (kein Default vorhanden)" "grep -qF 'lpadmin -d Office' '$T/prev1.out'"

mk_target "$T/tgt"; TB="$(snap "$T/tgt")"
run "" "$T/tgt" import "$EXP" > "$T/prev2.out" 2>&1
chk "Vorschau: bestehendes Ziel-PRINTERS_DIR unveraendert" "[ \"\$TB\" = \"\$(snap '$T/tgt')\" ]"
chk "Vorschau: lpadmin 0 Aufrufe (2. Lauf)" "[ \$(ncalls) -eq 0 ]"
chk "Vorschau listet nur fehlende Treiber" "grep -q '+ Drv/Contents' '$T/prev2.out' && grep -q '+ Drv/Current' '$T/prev2.out' && ! grep -q 'shared.txt' '$T/prev2.out'"
chk "Vorschau: Export-Ordner unveraendert" "[ -f '$EXP/manifest.tsv' ]"

run "" "$T/tgt" import "$T/nichtda" > "$T/prev3.out" 2>&1; RC=$?
chk "Import aus Nicht-Export-Ordner schlaegt fehl" "[ $RC -ne 0 ]"
chk "Nicht-Export: laienverstaendliche Meldung ohne FEHLER/Pfad" "grep -qx 'Diese Datei ist kein Drucker-Export. Bitte die Datei Drucker-Export-….zip vom alten Mac wählen.' '$T/prev3.out' && [ \$(wc -l < '$T/prev3.out') -eq 1 ]"
mkdir -p "$T/nozip/x"; echo hallo > "$T/nozip/x/a.txt"; ditto -c -k "$T/nozip" "$T/nozip.zip"
mkdir -p "$T/tmpd"; TMPD="$T/tmpd" run "" "$T/tgt" import "$T/nozip.zip" > "$T/prev4.out" 2>&1; RC=$?
chk "Zip ohne Manifest: Meldung ohne Temp-Pfad, Temp aufgeraeumt" "[ $RC -eq 1 ] && ! grep -qE 'tmp|/var/' '$T/prev4.out' && [ -z \"\$(ls -A '$T/tmpd')\" ]"
mkdir -p "$T/evil"; ln -s "$EXP" "$T/evil/x"; ditto -c -k "$T/evil" "$T/evil.zip"
TMPD="$T/tmpd" run "" "$T/tgt" import "$T/evil.zip" > "$T/prev5.out" 2>&1; RC=$?
chk "Zip mit Symlink-Ordner wird abgelehnt" "[ $RC -eq 1 ] && [ \$(ncalls) -eq 0 ] && grep -q 'kein Drucker-Export' '$T/prev5.out'"

# GUI-Vorschau
DEFAULT=Anderer GUI=1 run "Office${TAB}ipp://anders/
" "$T/tgt" import "$EXP" > "$T/prevG.out" 2>&1
chk "GUI-Vorschau: keine Fachbegriffe/Befehle/Temp-Pfade" "! grep -qE 'lpadmin|PPD|dnssd|cupsdisable|driverless|$T|/tmp|/var/folders|FEHLER|ÜBERSPRUNGEN' '$T/prevG.out'"
chk "GUI-Vorschau: Umbenennung als eine Zeile" "grep -qx '• HP LaserJet Büro (HP LaserJet 4000) – wird als „Office-migriert“ eingerichtet' '$T/prevG.out'"
chk "GUI-Vorschau: normaler Drucker 'wird eingerichtet'" "grep -qx '• Mein  Büro Drucker (Epson Z) – wird eingerichtet' '$T/prevG.out'"
chk "GUI-Vorschau: Treiber nur als Anzahl" "grep -qE '^[0-9]+ Treiberpakete? werden ergänzt\\.\$' '$T/prevG.out' && ! grep -q '+ Drv' '$T/prevG.out'"
chk "GUI-Vorschau: Warnungsabschnitt am Ende" "[ \"\$(grep -n 'Bitte danach prüfen:' '$T/prevG.out' | cut -d: -f1)\" -gt \"\$(grep -n 'Jetzt einrichten' '$T/prevG.out' | cut -d: -f1)\" ]"
chk "GUI-Vorschau: lpadmin 0 Aufrufe" "[ \$(ncalls) -eq 0 ]"

# ================= IMPORT: APPLY =================
# Quarantaene-xattr auf Export-Kopie setzen (wie bei AirDrop/Download)
Q="0083;5f000000;Safari;"
for f in "$EXP/manifest.tsv" "$EXP/ppd/Office.ppd" "$EXP/Library-Printers/Drv/Contents/Filter/rastertox" \
         "$EXP/Library-Printers/Drv/Contents/Resources/readme.txt" "$EXP/Library-Printers/Drv"; do
  xattr -w com.apple.quarantine "$Q" "$f"
done
chk "Test-Setup: Quarantaene-xattr gesetzt" "xattr -p com.apple.quarantine '$EXP/Library-Printers/Drv/Contents/Filter/rastertox'"

# A: Namenskonflikt Office (anderes Geraet), Klasse Alt existiert schon
mk_target "$T/tgtA"
run "Office
Alt
" "$T/tgtA" import "$EXP" --apply > "$T/applyA.out" 2>&1; RC=$?
cp "$EX" "$T/existingA.txt"
chk "Apply Exitcode 0 (mit Quarantaene-xattr)" "[ $RC -eq 0 ]"
chk "Apply: Konflikt -> Office-migriert" "[ -n \"\$(callline Office-migriert)\" ]"
chk "Apply: Konflikt -> nie unter Originalnamen Office angelegt" "[ -z \"\$(callline Office)\" ]"
chk "Apply: Empty/Spaced/Secure unter Originalnamen" "[ -n \"\$(callline Empty)\" ] && [ -n \"\$(callline Spaced)\" ] && [ -n \"\$(callline Secure)\" ]"
chk "Apply: usb:// ohne PPD uebersprungen" "[ -z \"\$(callline Usbp)\" ] && grep -q 'ÜBERSPRUNGEN: keine PPD' '$T/applyA.out'"
chk "Apply: genau 4 Anlege-Aufrufe" "[ \$(ncreate) -eq 4 ]"
chk "Apply: lpadmin nie mit -x" "! grep -qF -- '${US}-x${US}' '$LOG'"
chk "Apply: Office nutzt -P mit PPD-Pfad, kein -m" "callline Office-migriert | grep -qF '${US}-P${US}$EXP/ppd/Office.ppd${US}' && ! callline Office-migriert | grep -qF '${US}-m${US}'"
chk "Apply: Empty (ipp, keine PPD) nutzt -m everywhere" "callline Empty | grep -qF '${US}-m${US}everywhere${US}'"
chk "Apply: Empty ohne Info -> leeres -D Argument" "callline Empty | grep -qF '${US}-D${US}${US}-L${US}${US}'"
chk "Apply: Info mit Leerzeichen als EIN Argument" "callline Spaced | grep -qF '${US}-D${US}Mein  Büro Drucker${US}-L${US}EG links${US}'"
chk "Apply: Shared Yes -> printer-is-shared=true" "callline Office-migriert | grep -qF '${US}printer-is-shared=true${US}'"
chk "Apply: Shared No -> printer-is-shared=false" "callline Empty | grep -qF '${US}printer-is-shared=false${US}'"
chk "Apply: URI uebergeben" "callline Spaced | grep -qF '${US}-v${US}socket://10.0.0.7:9100${US}'"
chk "Apply: Optionen als -o key=value (Leerzeichen erhalten)" "callline Office-migriert | grep -qF '${US}-o${US}finishings-default=3${US}-o${US}custom-note=Hallo  Welt${US}'"
chk "Apply: Optionen nur beim eigenen Drucker" "! callline Spaced | grep -qF 'finishings-default'"
chk "Apply: echte smb-URI an lpadmin, aber maskiert in Ausgabe" "callline Secure | grep -qF '${US}-v${US}smb://user:geheim@server/Drucker${US}' && ! grep -q geheim '$T/applyA.out'"
chk "Apply: auth-info-required aus AuthInfoRequired" "callline Secure | grep -qF '${US}-o${US}auth-info-required=username,password${US}'"
chk "Apply: Stopped -> cupsdisable nur fuer Secure" "[ \"\$(cat '$LOG.disable')\" = Secure ]"
chk "Apply: Standarddrucker gesetzt (kein Default vorhanden)" "grep -qxF '${US}-d${US}Office-migriert${US}' '$LOG'"
chk "Apply: Klasse Team mit neuen Namen, ohne uebersprungenen Usbp" "grep -qxF '${US}-p${US}Office-migriert${US}-c${US}Team${US}' '$LOG' && grep -qxF '${US}-p${US}Spaced${US}-c${US}Team${US}' '$LOG' && ! grep -qF '${US}Usbp${US}' '$LOG'"
chk "Apply: vorhandene Klasse Alt nicht angefasst + Hinweis" "! grep -qF '${US}-c${US}Alt${US}' '$LOG' && grep -qF 'Druckergruppe „Alt“ gibt es hier schon' '$T/applyA.out'"
chk "Apply: Existing-Datei behielt Original (Stub fuegt nur hinzu)" "grep -qx Office '$EX'"
chk "Apply: Abschnitt 'Bitte danach prüfen:' am Ende" "[ \"\$(tail -n +\$(grep -n 'Bitte danach prüfen:' '$T/applyA.out' | cut -d: -f1) '$T/applyA.out' | grep -c '^• ')\" -ge 2 ]"

# Treiber
chk "Treiber: vorhandene Datei NICHT ueberschrieben" "[ \"\$(cat '$T/tgtA/Drv/shared.txt')\" = TARGET-ORIGINAL ]"
chk "Treiber: Ziel-eigene Datei noch da" "[ \"\$(cat '$T/tgtA/Eigen/x')\" = mine ]"
chk "Treiber: fehlende Dateien kopiert (readme)" "[ \"\$(cat '$T/tgtA/Drv/Contents/Resources/readme.txt')\" = readme ]"
chk "Treiber: Symlink als Symlink erhalten" "[ -L '$T/tgtA/Drv/Current' ] && [ \"\$(readlink '$T/tgtA/Drv/Current')\" = Contents ]"
chk "Treiber: Executable-Bit erhalten" "[ -x '$T/tgtA/Drv/Contents/Filter/rastertox' ]"
chk "Treiber: Quarantaene-xattr nicht im Ziel" "! xattr -p com.apple.quarantine '$T/tgtA/Drv/Contents/Filter/rastertox'"
chk "Treiber: ohne xattr-Fehler keine Download-Sperre-Warnung" "! grep -q 'Download-Sperre' '$T/applyA.out'"
chk "Apply nennt Summe 4 angelegt, 0 fehlgeschlagen, 1 uebersprungen" "grep -q 'Fertig: 4 angelegt, 0 fehlgeschlagen, 1 übersprungen' '$T/applyA.out'"

# Wiederholter Import: gleiche Geraeteadressen -> keine Duplikate
run "$(cat "$T/existingA.txt")
" "$T/tgtA" import "$EXP" --apply > "$T/applyA2.out" 2>&1
chk "Wiederholung: keine Anlege-Aufrufe, keine Klassen, kein -d" "[ \$(ncalls) -eq 0 ] && [ ! -s '$LOG.disable' ]"
chk "Wiederholung: 'schon vorhanden' + Summe 0 angelegt" "grep -q 'gleiche Geräteadresse' '$T/applyA2.out' && grep -q 'Fertig: 0 angelegt, 0 fehlgeschlagen, 5 übersprungen' '$T/applyA2.out'"
GUI=1 run "Andere${TAB}socket://10.0.0.7:9100
" "$T/tgtA" import "$EXP" > "$T/prevD.out" 2>&1
chk "GUI: gleiche URI unter anderem Namen -> 'schon vorhanden, übersprungen'" "grep -qx '• Mein  Büro Drucker (Epson Z) – schon vorhanden, übersprungen' '$T/prevD.out'"

# Standarddrucker schon gesetzt -> kein -d, Hinweis
mk_target "$T/tgtD"; DEFAULT=Anderer run "" "$T/tgtD" import "$EXP" --apply > "$T/applyD.out" 2>&1
chk "Default vorhanden: kein lpadmin -d" "! grep -qF '${US}-d${US}' '$LOG'"
chk "Default vorhanden: Hinweis 'Standarddrucker war'" "grep -qF 'Standarddrucker war „HP LaserJet Büro“' '$T/applyD.out'"

# xattr-Fehler -> Warnung statt stumm
mk_target "$T/tgtX"; XFAIL=1 run "" "$T/tgtX" import "$EXP" --apply > "$T/applyX.out" 2>&1
chk "xattr-Fehler: Warnung im Abschluss" "grep -q 'Download-Sperre nicht entfernen' '$T/applyX.out'"

# Apply auf nicht existierendes Ziel-PRINTERS_DIR: wird angelegt, Treiber komplett
run "" "$T/neu-printers" import "$EXP" --apply > "$T/applyN.out" 2>&1
chk "Apply: fehlendes PRINTERS_DIR wird angelegt + befuellt" "[ -x '$T/neu-printers/Drv/Contents/Filter/rastertox' ] && [ -L '$T/neu-printers/Drv/Current' ] && [ \"\$(cat '$T/neu-printers/Drv/shared.txt')\" = SOURCE-DIFFERENT ]"

# Apply wiederholt: zweiter Lauf, alles vorhanden -> Treiber unveraendert
mk_target "$T/tgtR"; run "" "$T/tgtR" import "$EXP" --apply >/dev/null 2>&1
TR="$(snap "$T/tgtR")"; run "" "$T/tgtR" import "$EXP" --apply > "$T/applyR.out" 2>&1
chk "Apply 2x: Treiberdateien beim zweiten Lauf unveraendert" "[ \"\$TR\" = \"\$(snap '$T/tgtR')\" ] && ! grep -q '^  + ' '$T/applyR.out'"

# GUI-Apply
mk_target "$T/tgtG"; GUI=1 run "" "$T/tgtG" import "$EXP" --apply > "$T/applyG.out" 2>&1
chk "GUI-Apply: keine Fachbegriffe/Befehle/Temp-Pfade" "! grep -qE 'lpadmin|PPD|dnssd|cupsdisable|$T|/tmp|FEHLER' '$T/applyG.out'"
chk "GUI-Apply: Zeile je Drucker inkl. pausiert/Standarddrucker" "grep -qx '• Secure Drucker (Ricoh S) – eingerichtet (pausiert wie auf dem alten Mac)' '$T/applyG.out' && grep -qx '• HP LaserJet Büro (HP LaserJet 4000) – eingerichtet, Standarddrucker' '$T/applyG.out'"
chk "GUI-Apply: Treiberanzahl + Summe" "grep -qE '^[0-9]+ Treiberpakete? ergänzt\\.\$' '$T/applyG.out' && grep -q 'Fertig: 4 angelegt' '$T/applyG.out'"

# B: zweiter Konflikt
mk_target "$T/tgtB"
run "Office
Office-migriert
" "$T/tgtB" import "$EXP" --apply > "$T/applyB.out" 2>&1
chk "Apply: zweiter Konflikt -> Office-migriert2" "[ -n \"\$(callline Office-migriert2)\" ]"
chk "Apply: dritter Namen Office-migriert/Office nicht angelegt" "[ -z \"\$(callline Office-migriert)\" ] && [ -z \"\$(callline Office)\" ]"

# B2: dritter Konflikt (Zusatz)
run "Office
Office-migriert
Office-migriert2
" "$T/tgtB" import "$EXP" --apply > "$T/applyB2.out" 2>&1
chk "Apply: dritter Konflikt -> Office-migriert3" "[ -n \"\$(callline Office-migriert3)\" ]"

# C: Fehlschlag eines lpadmin-Aufrufs bricht nicht ab
mk_target "$T/tgtC"
FAIL=Office run "" "$T/tgtC" import "$EXP" --apply > "$T/applyC.out" 2>&1; RC=$?
chk "Fehlschlag: Script laeuft weiter (Exit 0)" "[ $RC -eq 0 ]"
chk "Fehlschlag: Office wurde versucht" "[ -n \"\$(callline Office)\" ]"
chk "Fehlschlag: Empty und Spaced danach trotzdem aufgerufen" "[ -n \"\$(callline Empty)\" ] && [ -n \"\$(callline Spaced)\" ]"
chk "Fehlschlag: Summenzeile 3 angelegt, 1 fehlgeschlagen" "grep -q 'Fertig: 3 angelegt, 1 fehlgeschlagen, 1 übersprungen' '$T/applyC.out'"
chk "Fehlschlag: nie -x" "! grep -qF -- '${US}-x${US}' '$LOG'"
chk "Fehlschlag: kein Default, nicht in Klasse, Hinweis" "! grep -qF '${US}-d${US}' '$LOG' && ! grep -qF '${US}-p${US}Office${US}-c' '$LOG' && grep -q 'Standarddrucker war' '$T/applyC.out'"
chk "Fehlschlag: Treiber trotzdem kopiert, Original unberuehrt" "[ -x '$T/tgtC/Drv/Contents/Filter/rastertox' ] && [ \"\$(cat '$T/tgtC/Drv/shared.txt')\" = TARGET-ORIGINAL ]"

# Import selbst veraendert den Export-Ordner nicht (Manifest/PPDs)
chk "Import laesst Manifest unveraendert" "diff '$T/expected.tsv' '$EXP/manifest.tsv'"

# Namensvalidierung + Options-Keys aus manipuliertem Manifest
cp -R "$EXP" "$T/expV"
printf -- '-evil\tnein\t-\t-\tX\tipp://1.2.3.4/\tnein\t-\tnein\n../up\tnein\t-\t-\tX\tipp://1.2.3.5/\tnein\t-\tnein\nbad/n\tnein\t-\t-\tX\tipp://1.2.3.6/\tnein\t-\tnein\n' >> "$T/expV/manifest.tsv"
printf 'Empty\t-x\tboese\n' >> "$T/expV/options.tsv"
run "" "$T/tgt" import "$T/expV" --apply > "$T/applyV.out" 2>&1
chk "Ungueltige Namen uebersprungen" "[ \$(grep -c 'ÜBERSPRUNGEN: ungültiger Name' '$T/applyV.out') -eq 3 ] && ! grep -qF '1.2.3.' '$LOG'"
chk "Ungueltiger Options-Key verworfen" "! grep -qF 'boese' '$LOG'"

# Bundle-Schutz: in ein vorhandenes Bundle (Name mit Punkt) wird nichts gemischt
cp -R "$EXP" "$T/expB"; mkdir -p "$T/expB/Library-Printers/Foo.plugin" "$T/tgtP/Foo.plugin"
echo a > "$T/expB/Library-Printers/Foo.plugin/a"; echo b > "$T/expB/Library-Printers/Foo.plugin/b"
echo a-neu > "$T/tgtP/Foo.plugin/a"
run "" "$T/tgtP" import "$T/expB" --apply > "$T/applyP.out" 2>&1
chk "Bundle: nichts in vorhandenes Bundle gemischt" "[ ! -e '$T/tgtP/Foo.plugin/b' ] && [ \"\$(cat '$T/tgtP/Foo.plugin/a')\" = a-neu ]"

# Import direkt aus dem Zip des Exports
chk "Export: Zip erzeugt" "[ -f '$EXP.zip' ]"
mk_target "$T/tgtZ"; TMPD="$T/tmpd" run "" "$T/tgtZ" import "$EXP.zip" --apply > "$T/applyZ.out" 2>&1
chk "Zip-Import: Symlink + Executable im Ziel" "[ -L '$T/tgtZ/Drv/Current' ] && [ -x '$T/tgtZ/Drv/Contents/Filter/rastertox' ]"
chk "Zip-Import: Drucker angelegt" "grep -q 'Fertig: ' '$T/applyZ.out' && [ \$(ncalls) -gt 0 ]"
chk "Zip-Import: Temp-Ordner aufgeraeumt" "[ -z \"\$(ls -A '$T/tmpd')\" ]"


# Schreibgeschützte Treiberordner (555, wie in /Library/Printers): Vorschau räumt still auf
cp -R "$EXP" "$T/expRO"; chmod 555 "$T/expRO/Library-Printers/Drv"; (cd "$T" && ditto -c -k --keepParent expRO expRO.zip)
run "" "$T/tgt" import "$T/expRO.zip" > "$T/prevRO.out" 2>&1; RC=$?
chk "555-Ordner: Vorschau ohne rm-Fehler, Exit 0" "[ $RC -eq 0 ] && ! grep -q 'Permission denied' '$T/prevRO.out'"
chmod -R u+w "$T/expRO"

echo
echo "Gesamt: $PASSN PASS, $FAILN FAIL (von $((PASSN+FAILN)))"
[ "$FAILN" -eq 0 ]
