#!/bin/bash
# Testsuite fuer Drucker-Umzug.command. Laeuft mit macOS /bin/bash 3.2.
# Alles in einem Temp-Ordner; echtes /etc/cups, /Library/Printers, lpadmin werden nie angefasst.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/Drucker-Umzug.command"
T="$(mktemp -d "${TMPDIR:-/tmp}/druckertest.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT
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
# lpstat -p NAME: Exit 0 nur wenn NAME in $FAKE_EXISTING steht
[ "$1" = -p ] && grep -Fxq -- "$2" "$FAKE_EXISTING"
EOF
cat > "$STUBS/lpadmin" <<'EOF'
#!/bin/bash
# loggt jeden Aufruf als eine Zeile: \037arg1\037arg2\037
printf '\037%s' "$@" >> "$FAKE_LOG"; printf '\037\n' >> "$FAKE_LOG"
if [ "$1" = -p ]; then
  [ -n "${LPADMIN_FAIL:-}" ] && [ "$2" = "$LPADMIN_FAIL" ] && exit 1
  echo "$2" >> "$FAKE_EXISTING"
fi
exit 0
EOF
chmod +x "$STUBS/lpstat" "$STUBS/lpadmin"

# ---------- Fake-Quelle (alter Mac) ----------
SRC="$T/src"; CUPS="$SRC/cups"; PSRC="$SRC/printers"
mkdir -p "$CUPS/ppd" "$PSRC/Drv/Contents/Filter" "$PSRC/Drv/Contents/Resources"
{
  printf '# Printer configuration file for CUPS\n'
  printf '<DefaultPrinter Office>\n'
  printf 'UUID urn:uuid:1\nInfo HP LaserJet Büro\nLocation Raum 1\nMakeModel HP LaserJet 4000\n'
  printf 'DeviceURI lpd://10.0.0.5/queue\nState Idle\nShared Yes\n</Printer>\n'
  printf '<Class Gruppe>\nInfo Klassen-Info\nLocation Klassen-Ort\nMakeModel Klasse\nDeviceURI file:///dev/null\nShared Yes\n</Class>\n'
  printf '<Printer Empty>\nInfo \nMakeModel Brother X\nDeviceURI ipp://10.0.0.9/ipp/print\nShared No\n</Printer>\n'
  printf '<Printer Usbp>\nInfo USB Gerät\nMakeModel Canon Y\nDeviceURI usb://Canon/Y?serial=1\nShared No\n</Printer>\n'
  printf '<Printer Spaced>\nInfo Mein  Büro Drucker\nLocation EG links\nMakeModel Epson Z\nDeviceURI socket://10.0.0.7:9100\nShared Yes\n</Printer>\n'
} > "$CUPS/printers.conf"
echo "PPD-OFFICE" > "$CUPS/ppd/Office.ppd"
echo "PPD-SPACED" > "$CUPS/ppd/Spaced.ppd"
echo "#!/bin/sh" > "$PSRC/Drv/Contents/Filter/rastertox"; chmod 755 "$PSRC/Drv/Contents/Filter/rastertox"
echo "readme" > "$PSRC/Drv/Contents/Resources/readme.txt"
echo "SOURCE-DIFFERENT" > "$PSRC/Drv/shared.txt"
ln -s Contents "$PSRC/Drv/Current"

snap() { ( cd "$1" 2>/dev/null || exit 0
  find . -exec stat -f '%N %p %z %m' {} \; | sort
  find . -type f -exec shasum {} \; | sort
  find . -type l -exec sh -c 'for l; do echo "$l -> $(readlink "$l")"; done' _ {} + | sort ); }

# Zielverzeichnis frisch bauen: Drv/shared.txt mit anderem Inhalt, plus Ziel-eigene Datei
mk_target() { rm -rf "$1"; mkdir -p "$1/Drv" "$1/Eigen"; echo "TARGET-ORIGINAL" > "$1/Drv/shared.txt"; echo "mine" > "$1/Eigen/x"; }

# run <existing-inhalt> <printers_dir> <args...>   (Log in $LOG, Existing in $EX)
LOG="$T/lpadmin.log"; EX="$T/existing.txt"
run() { local ex="$1" pd="$2"; shift 2
  : > "$LOG"; printf '%s' "$ex" > "$EX"
  env CUPS_DIR="$CUPS" PRINTERS_DIR="$pd" NEED_ROOT=0 PATH="$STUBS:$PATH" \
      FAKE_LOG="$LOG" FAKE_EXISTING="$EX" LPADMIN_FAIL="${FAIL:-}" \
      /bin/bash "$SCRIPT" "$@" </dev/null; }
callline() { grep -F -- "${US}-p${US}$1${US}" "$LOG" | head -1; }
ncalls() { wc -l < "$LOG" | tr -d ' '; }

# ================= EXPORT =================
EXP="$T/export"
SNAP_CUPS_BEFORE="$(snap "$CUPS")"; SNAP_P_BEFORE="$(snap "$PSRC")"
run "" "$PSRC" export "$EXP" > "$T/export.out" 2>&1; RC=$?
chk "Export Exitcode 0" "[ $RC -eq 0 ]"
printf 'Office\tja\tHP LaserJet Büro\tRaum 1\tHP LaserJet 4000\tlpd://10.0.0.5/queue\tja\n'    >  "$T/expected.tsv"
printf 'Empty\tnein\t-\t-\tBrother X\tipp://10.0.0.9/ipp/print\tnein\n'                          >> "$T/expected.tsv"
printf 'Usbp\tnein\tUSB Gerät\t-\tCanon Y\tusb://Canon/Y?serial=1\tnein\n'                       >> "$T/expected.tsv"
printf 'Spaced\tnein\tMein  Büro Drucker\tEG links\tEpson Z\tsocket://10.0.0.7:9100\tja\n'        >> "$T/expected.tsv"
chk "manifest.tsv exakt wie erwartet (Platzhalter '-', Class ignoriert, Default=ja)" "diff '$T/expected.tsv' '$EXP/manifest.tsv'"
chk "Class 'Gruppe' nicht im Manifest" "! grep -q Gruppe '$EXP/manifest.tsv'"
chk "Manifest hat 4 Zeilen" "[ \$(wc -l < '$EXP/manifest.tsv' | tr -d ' ') -eq 4 ]"
chk "PPD Office kopiert" "[ \"\$(cat '$EXP/ppd/Office.ppd')\" = PPD-OFFICE ]"
chk "PPD Spaced kopiert" "[ \"\$(cat '$EXP/ppd/Spaced.ppd')\" = PPD-SPACED ]"
chk "Keine PPD fuer Drucker ohne PPD" "[ ! -e '$EXP/ppd/Empty.ppd' ] && [ ! -e '$EXP/ppd/Usbp.ppd' ]"
chk "cups-original Referenzkopie vorhanden" "[ -f '$EXP/cups-original/printers.conf' ]"
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
run "" "$PSRC" export > "$T/exp3.out" 2>&1; RC=$?
chk "Export ohne Ordner-Argument schlaegt fehl" "[ $RC -ne 0 ]"

# ================= IMPORT: VORSCHAU =================
GONE="$T/nonexistent-printers"
run "" "$GONE" import "$EXP" > "$T/prev1.out" 2>&1; RC=$?
chk "Vorschau Exitcode 0" "[ $RC -eq 0 ]"
chk "Vorschau: lpadmin 0 Aufrufe" "[ \$(ncalls) -eq 0 ]"
chk "Vorschau: nicht existierendes Ziel-PRINTERS_DIR wird nicht angelegt" "[ ! -e '$GONE' ]"
chk "Vorschau nennt sich VORSCHAU" "grep -q VORSCHAU '$T/prev1.out'"

mk_target "$T/tgt"; TB="$(snap "$T/tgt")"
run "" "$T/tgt" import "$EXP" > "$T/prev2.out" 2>&1
chk "Vorschau: bestehendes Ziel-PRINTERS_DIR unveraendert" "[ \"\$TB\" = \"\$(snap '$T/tgt')\" ]"
chk "Vorschau: lpadmin 0 Aufrufe (2. Lauf)" "[ \$(ncalls) -eq 0 ]"
chk "Vorschau listet nur fehlende Treiber" "grep -q '+ Drv/Contents' '$T/prev2.out' && grep -q '+ Drv/Current' '$T/prev2.out' && ! grep -q 'shared.txt' '$T/prev2.out'"
chk "Vorschau: Export-Ordner unveraendert" "[ -f '$EXP/manifest.tsv' ]"

run "" "$T/tgt" import "$T/nichtda" > "$T/prev3.out" 2>&1; RC=$?
chk "Import aus Nicht-Export-Ordner schlaegt fehl" "[ $RC -ne 0 ]"

# ================= IMPORT: APPLY =================
# Quarantaene-xattr auf Export-Kopie setzen (wie bei AirDrop/Download)
Q="0083;5f000000;Safari;"
for f in "$EXP/manifest.tsv" "$EXP/ppd/Office.ppd" "$EXP/Library-Printers/Drv/Contents/Filter/rastertox" \
         "$EXP/Library-Printers/Drv/Contents/Resources/readme.txt" "$EXP/Library-Printers/Drv"; do
  xattr -w com.apple.quarantine "$Q" "$f"
done
chk "Test-Setup: Quarantaene-xattr gesetzt" "xattr -p com.apple.quarantine '$EXP/Library-Printers/Drv/Contents/Filter/rastertox'"

# A: Namenskonflikt Office
mk_target "$T/tgtA"
run "Office
" "$T/tgtA" import "$EXP" --apply > "$T/applyA.out" 2>&1; RC=$?
chk "Apply Exitcode 0 (mit Quarantaene-xattr)" "[ $RC -eq 0 ]"
chk "Apply: Konflikt -> Office-migriert" "[ -n \"\$(callline Office-migriert)\" ]"
chk "Apply: Konflikt -> nie unter Originalnamen Office angelegt" "[ -z \"\$(callline Office)\" ]"
chk "Apply: Empty/Spaced unter Originalnamen" "[ -n \"\$(callline Empty)\" ] && [ -n \"\$(callline Spaced)\" ]"
chk "Apply: usb:// ohne PPD uebersprungen" "[ -z \"\$(callline Usbp)\" ] && grep -q 'ÜBERSPRUNGEN: keine PPD' '$T/applyA.out'"
chk "Apply: genau 3 lpadmin-Aufrufe" "[ \$(ncalls) -eq 3 ]"
chk "Apply: lpadmin nie mit -x" "! grep -qF -- '${US}-x${US}' '$LOG'"
chk "Apply: Office nutzt -P mit PPD-Pfad, kein -m" "callline Office-migriert | grep -qF '${US}-P${US}$EXP/ppd/Office.ppd${US}' && ! callline Office-migriert | grep -qF '${US}-m${US}'"
chk "Apply: Empty (ipp, keine PPD) nutzt -m everywhere" "callline Empty | grep -qF '${US}-m${US}everywhere${US}'"
chk "Apply: Empty ohne Info -> leeres -D Argument" "callline Empty | grep -qF '${US}-D${US}${US}-L${US}${US}'"
chk "Apply: Info mit Leerzeichen als EIN Argument" "callline Spaced | grep -qF '${US}-D${US}Mein  Büro Drucker${US}-L${US}EG links${US}'"
chk "Apply: Shared Yes -> printer-is-shared=true" "callline Office-migriert | grep -qF '${US}printer-is-shared=true${US}'"
chk "Apply: Shared No -> printer-is-shared=false" "callline Empty | grep -qF '${US}printer-is-shared=false${US}'"
chk "Apply: URI uebergeben" "callline Spaced | grep -qF '${US}-v${US}socket://10.0.0.7:9100${US}'"
chk "Apply: Existing-Datei behielt Original (Stub fuegt nur hinzu)" "grep -qx Office '$EX'"

# Treiber
chk "Treiber: vorhandene Datei NICHT ueberschrieben" "[ \"\$(cat '$T/tgtA/Drv/shared.txt')\" = TARGET-ORIGINAL ]"
chk "Treiber: Ziel-eigene Datei noch da" "[ \"\$(cat '$T/tgtA/Eigen/x')\" = mine ]"
chk "Treiber: fehlende Dateien kopiert (readme)" "[ \"\$(cat '$T/tgtA/Drv/Contents/Resources/readme.txt')\" = readme ]"
chk "Treiber: Symlink als Symlink erhalten" "[ -L '$T/tgtA/Drv/Current' ] && [ \"\$(readlink '$T/tgtA/Drv/Current')\" = Contents ]"
chk "Treiber: Executable-Bit erhalten" "[ -x '$T/tgtA/Drv/Contents/Filter/rastertox' ]"
chk "Treiber: Quarantaene-xattr nicht im Ziel" "! xattr -p com.apple.quarantine '$T/tgtA/Drv/Contents/Filter/rastertox'"
chk "Apply nennt IMPORT und Summe 3 angelegt, 0 fehlgeschlagen, 1 uebersprungen" "grep -q 'Fertig: 3 angelegt, 0 fehlgeschlagen, 1 übersprungen' '$T/applyA.out'"

# Apply auf nicht existierendes Ziel-PRINTERS_DIR: wird angelegt, Treiber komplett
run "" "$T/neu-printers" import "$EXP" --apply > "$T/applyN.out" 2>&1
chk "Apply: fehlendes PRINTERS_DIR wird angelegt + befuellt" "[ -x '$T/neu-printers/Drv/Contents/Filter/rastertox' ] && [ -L '$T/neu-printers/Drv/Current' ] && [ \"\$(cat '$T/neu-printers/Drv/shared.txt')\" = SOURCE-DIFFERENT ]"

# Apply wiederholt: zweiter Lauf, alles vorhanden -> Treiber unveraendert
mk_target "$T/tgtR"; run "" "$T/tgtR" import "$EXP" --apply >/dev/null 2>&1
TR="$(snap "$T/tgtR")"; run "" "$T/tgtR" import "$EXP" --apply > "$T/applyR.out" 2>&1
chk "Apply 2x: Treiberdateien beim zweiten Lauf unveraendert" "[ \"\$TR\" = \"\$(snap '$T/tgtR')\" ] && ! grep -q '^  + ' '$T/applyR.out'"

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
chk "Fehlschlag: Summenzeile 2 angelegt, 1 fehlgeschlagen" "grep -q 'Fertig: 2 angelegt, 1 fehlgeschlagen, 1 übersprungen' '$T/applyC.out'"
chk "Fehlschlag: nie -x" "! grep -qF -- '${US}-x${US}' '$LOG'"
chk "Fehlschlag: Treiber trotzdem kopiert, Original unberuehrt" "[ -x '$T/tgtC/Drv/Contents/Filter/rastertox' ] && [ \"\$(cat '$T/tgtC/Drv/shared.txt')\" = TARGET-ORIGINAL ]"

# Import selbst veraendert den Export-Ordner nicht (Manifest/PPDs)
chk "Import laesst Manifest unveraendert" "diff '$T/expected.tsv' '$EXP/manifest.tsv'"


# Bundle-Schutz: in ein vorhandenes Bundle (Name mit Punkt) wird nichts gemischt
cp -R "$EXP" "$T/expB"; mkdir -p "$T/expB/Library-Printers/Foo.plugin" "$T/tgtP/Foo.plugin"
echo a > "$T/expB/Library-Printers/Foo.plugin/a"; echo b > "$T/expB/Library-Printers/Foo.plugin/b"
echo a-neu > "$T/tgtP/Foo.plugin/a"
run "" "$T/tgtP" import "$T/expB" --apply > "$T/applyP.out" 2>&1
chk "Bundle: nichts in vorhandenes Bundle gemischt" "[ ! -e '$T/tgtP/Foo.plugin/b' ] && [ \"\$(cat '$T/tgtP/Foo.plugin/a')\" = a-neu ]"

# Import direkt aus dem Zip des Exports
chk "Export: Zip erzeugt" "[ -f '$EXP.zip' ]"
mk_target "$T/tgtZ"; run "" "$T/tgtZ" import "$EXP.zip" --apply > "$T/applyZ.out" 2>&1
chk "Zip-Import: Symlink + Executable im Ziel" "[ -L '$T/tgtZ/Drv/Current' ] && [ -x '$T/tgtZ/Drv/Contents/Filter/rastertox' ]"
chk "Zip-Import: Drucker angelegt" "grep -q 'Fertig: ' '$T/applyZ.out' && [ \$(ncalls) -gt 0 ]"

echo
echo "Gesamt: $PASSN PASS, $FAILN FAIL (von $((PASSN+FAILN)))"
[ "$FAILN" -eq 0 ]
