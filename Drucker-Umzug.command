#!/bin/bash
# Drucker-Umzug: Drucker, PPDs und Treiber von einem Mac auf einen anderen übertragen.
# Löscht nie etwas und überschreibt nichts. Import ohne --apply ist nur eine Vorschau.
#
#   Doppelklick                        -> Menü
#   sudo ./Drucker-Umzug.command export <ordner>
#   sudo ./Drucker-Umzug.command import <ordner|zip> [--apply]
#   DU_GUI=1 ...                       -> kurze, laienverständliche Ausgabe (für die App)
set -u

CUPS_DIR="${CUPS_DIR:-/private/etc/cups}"
PRINTERS_DIR="${PRINTERS_DIR:-/Library/Printers}"
BACKEND_DIR="${BACKEND_DIR:-/usr/libexec/cups/backend}"
HOST_ARCH="${HOST_ARCH:-$(uname -m)}"
NEED_ROOT="${NEED_ROOT:-1}"   # nur Tests setzen 0
GUI="${DU_GUI:-0}"
NL=$'\n'; TAB=$'\t'
OKCH='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-'
NOEXP="Diese Datei ist kein Drucker-Export. Bitte die Datei Drucker-Export-….zip vom alten Mac wählen."

die() { echo "$*" >&2; exit 1; }
v() { [ "$GUI" = 1 ] || echo "$*"; }    # nur Terminal (ausführlich)
g() { [ "$GUI" != 1 ] || echo "$*"; }   # nur App (kurz)
need_root() {
  if [ "$NEED_ROOT" = 1 ] && [ "$(id -u)" != 0 ]; then die "Bitte mit sudo starten."; fi
}
# scheme://user:pass@host/... -> scheme://***@host/...
mask() {
  case "$1" in *://*@*) ;; *) echo "$1"; return;; esac
  local r="${1#*://}"; local h="${r%%/*}"
  case "$h" in *@*) echo "${1%%://*}://***@${h##*@}${r#"$h"}";; *) echo "$1";; esac
}
valid_name() { case "$1" in ""|-*|*..*|*[!@$OKCH]*) return 1;; esac; }
warns=""
warn() { case "$NL$warns" in *"$NL$1$NL"*) return;; esac; warns="$warns$1$NL"; }
# Anzeigename: Beschreibung (oder Queue-Name), plus Modell
label() { local l="${info:-$name}"; [ "$l" = - ] && l="$name"; [ -n "$mm" ] && [ "$mm" != - ] && l="$l ($mm)"; echo "$l"; }
rosetta() { case "${HAS_ROSETTA:-}" in 1) return 0;; 0) return 1;; esac; /usr/bin/pgrep -q oahd || arch -x86_64 /usr/bin/true 2>/dev/null; }

do_export() {
  out="$1"; need_root
  if [ -e "$out" ] || [ -L "$out" ] || [ -e "$out.zip" ] || [ -L "$out.zip" ]; then
    die "„${out##*/}“ gibt es schon. Bitte einen anderen Namen wählen."
  fi
  grep -qE '^<(Default)?Printer ' "$CUPS_DIR/printers.conf" 2>/dev/null ||
    die "Auf diesem Mac sind keine Drucker eingerichtet – es gibt nichts zu exportieren."

  # Erst in einem root-eigenen Temp-Ordner bauen, erst am Ende an den Zielort schieben
  work=$(mktemp -d /private/tmp/drucker-umzug.XXXXXX) || die "Kein Platz für temporäre Dateien."
  trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work" 2>/dev/null' EXIT   # Treiberordner sind oft 555
  e="$work/${out##*/}"
  mkdir -p "$e/ppd" || die "Kein Platz für temporäre Dateien."

  # printers.conf -> manifest.tsv (+ options.tsv); leere Felder als "-", sonst verschluckt read sie.
  # Nur diese Auswertung wandert in den Export, nie cupsd.conf, ssl/ oder Kennwortdateien.
  : > "$e/options.tsv"
  awk -v OFS='\t' -v opt="$e/options.tsv" '
    function f(v) { return v == "" ? "-" : v }
    /^<(Default)?Printer / { name = $2; sub(/>$/, "", name); def = ($1 == "<DefaultPrinter") ? "ja" : "nein"
                             info = loc = mm = uri = auth = ""; shared = stopped = "nein"; inp = 1; next }
    /^<\/Printer>/         { if (inp) print name, def, f(info), f(loc), f(mm), f(uri), shared, f(auth), stopped; inp = 0; next }
    !inp                   { next }
    /^Info /               { info = substr($0, 6) }
    /^Location /           { loc  = substr($0, 10) }
    /^MakeModel /          { mm   = substr($0, 11) }
    /^DeviceURI /          { uri  = substr($0, 11) }
    /^AuthInfoRequired /   { auth = $2 }
    /^Shared Yes/          { shared = "ja" }
    /^State Stopped/       { stopped = "ja" }
    /^Option /             { print name, $2, substr($0, length($2) + 9) > opt }
  ' "$CUPS_DIR/printers.conf" > "$e/manifest.tsv"
  # classes.conf -> classes.tsv (Klasse<TAB>Mitglied)
  [ -f "$CUPS_DIR/classes.conf" ] && awk -v OFS='\t' '
    /^<(Default)?Class / { c = $2; sub(/>$/, "", c); next }
    /^<\/Class>/         { c = ""; next }
    c != "" && /^Printer / { print c, $2 }
  ' "$CUPS_DIR/classes.conf" > "$e/classes.tsv"
  echo "macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))" > "$e/quelle.txt"
  pkgutil --pkgs 2>/dev/null | grep -iE 'brother|canon|epson|hp|hewlett|kyocera|ricoh|konica|minolta|xerox|lexmark|sharp|toshiba|oki|samsung|printer' |
    grep -v '^com\.apple\.' > "$e/pakete.txt"

  count=0
  while IFS="$TAB" read -r name def info loc mm uri rest; do
    count=$((count + 1))
    v "  Drucker: $name  ($mm)  $(mask "$uri")"
    g "• $(label)"
    [ -f "$CUPS_DIR/ppd/$name.ppd" ] && cp "$CUPS_DIR/ppd/$name.ppd" "$e/ppd/"
  done < "$e/manifest.tsv"

  if [ -d "$PRINTERS_DIR" ]; then
    v "  Kopiere Treiber aus $PRINTERS_DIR ..."
    ditto "$PRINTERS_DIR" "$e/Library-Printers" || echo "Achtung: Treiber konnten nicht vollständig gesichert werden."
  fi
  # Zip für den Transport: USB-Sticks mit FAT/exFAT verlieren sonst Symlinks in Treiber-Bundles
  ditto -c -k --sequesterRsrc --keepParent "$e" "$e.zip" || die "Die Zip-Datei konnte nicht erstellt werden."
  owner="${SUDO_USER:-${EXPORT_OWNER:-}}"   # EXPORT_OWNER setzt die App (Admin-Rechte ohne sudo)
  [ -n "$owner" ] && chown -R "$owner" "$e" "$e.zip" 2>/dev/null
  if [ -e "$out" ] || [ -L "$out" ] || [ -e "$out.zip" ] || [ -L "$out.zip" ]; then
    die "„${out##*/}“ ist inzwischen aufgetaucht. Bitte den Export erneut starten."
  fi
  { mv "$e" "$out" && mv "$e.zip" "$out.zip"; } || die "Der Export konnte nicht gespeichert werden."

  echo
  v "Export fertig: $count Drucker in $out"
  v "Bitte die Datei $out.zip auf den neuen Mac bringen und dort Import starten."
  g "Export fertig: $count Drucker gesichert."
  g "Bitte die Datei „${out##*/}.zip“ auf den neuen Mac bringen und dort „Import“ wählen."
}

# Kopiert aus $1 nach $2 nur Einträge, die ganz fehlen. In vorhandene Ordner wird nur
# hinabgestiegen, wenn sie kein Bundle sind (Name ohne Punkt, z. B. "Brother", "PPDs"),
# damit nie Dateien in ein vorhandenes, signiertes Bundle gemischt werden.
copy_missing() {
  local s="$1" d="$2" e
  for e in "$s"/* "$s"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    local name="${e##*/}" t="$d/${e##*/}"
    if [ ! -e "$t" ] && [ ! -L "$t" ]; then
      v "  + ${t#"$PRINTERS_DIR"/}"; added=$((added + 1))
      if [ "$apply" = 1 ]; then
        mkdir -p "$d"
        # cp -R: Symlinks bleiben Links, xattrs/Signaturen bleiben; ohne -p gehören neue
        # Dateien root (cupsd verlangt das für Filter). ditto würde Symlinks auflösen.
        if ! cp -R "$e" "$t"; then
          v "    WARNUNG: konnte nicht kopiert werden."; warn "Ein Treiberteil konnte nicht kopiert werden – Herstellertreiber installieren."
        elif ! xattr -drs com.apple.quarantine "$t" 2>/dev/null; then
          v "    WARNUNG: Quarantäne-Markierung nicht entfernt."
          warn "Bei einem Treiber ließ sich die Download-Sperre nicht entfernen – falls Drucken scheitert, Herstellertreiber neu installieren."
        fi
      fi
    elif [ -d "$e" ] && [ ! -L "$e" ] && [ -d "$t" ] && [ ! -L "$t" ] && [ "${name%.*}" = "$name" ]; then
      copy_missing "$e" "$t"
    fi
  done
}

# Prüft in der PPD referenzierte absolute Pfade (nach dem geplanten Treiberkopieren) und
# x86_64-only-Filter auf Apple-Chip ohne Rosetta. Nur Warnungen.
check_ppd() {
  local key p t x
  while IFS="$TAB" read -r key p; do
    case "$p" in
      /Library/Printers/*) t="$PRINTERS_DIR/${p#/Library/Printers/}"; x="$src/Library-Printers/${p#/Library/Printers/}";;
      *) t="$p"; x="";;
    esac
    # Vorschau: was der Treiberkopiervorgang ergänzen würde, zählt als vorhanden
    [ ! -e "$t" ] && [ "$apply" = 0 ] && [ -n "$x" ] && [ -e "$x" ] && t="$x"
    if [ ! -e "$t" ]; then warn "Drucker „${who}“: Treiberteil fehlt – Herstellertreiber installieren."; continue; fi
    case "$key" in cupsFilter*) ;; *) continue;; esac
    case "$(file -b "$t" 2>/dev/null)" in
      *Mach-O*arm64*) ;;
      *Mach-O*) [ "$HOST_ARCH" = arm64 ] && ! rosetta &&
                warn "Drucker „${who}“: Rosetta nötig – im Terminal: softwareupdate --install-rosetta";;
    esac
  done < <(awk '/^\*(cupsFilter2?|APDialogExtension|APPrinterIconPath|APPrinterUtilityPath)[ :]/ {
      k = substr($1, 2); sub(/:.*/, "", k)
      p = $0; sub(/^[^"]*"/, "", p); sub(/".*/, "", p)
      if (substr(p, 1, 1) != "/") { i = index(p, " /"); if (!i) next; p = substr(p, i + 1) }
      print k "\t" p }' "$1")
}

# Drucker übersprungen: $1 = Terminaltext, $2 = Kurztext für die App
skipped() { v "  ÜBERSPRUNGEN: $1"; g "• $(label) – $2"; skip=$((skip + 1)); }

do_import() {
  src="$1"; apply="$2"
  case "$src" in
    *.zip) [ -f "$src" ] || die "Die Datei wurde nicht gefunden."
           tmp=$(mktemp -d) || die "Kein Platz für temporäre Dateien."
           trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp" 2>/dev/null' EXIT
           ditto -x -k "$src" "$tmp" 2>/dev/null || die "Die Zip-Datei konnte nicht entpackt werden. Ist sie vollständig kopiert?"
           for d in "$tmp"/*/manifest.tsv; do src="${d%/manifest.tsv}"; done
           case "$src" in "$tmp"/*) ;; *) die "$NOEXP";; esac
           [ -L "$src" ] && die "$NOEXP" ;;
  esac
  { [ -f "$src/manifest.tsv" ] && [ ! -L "$src/manifest.tsv" ]; } || die "$NOEXP"
  [ "$apply" = 1 ] && need_root
  if [ "$apply" = 1 ]; then v "== IMPORT (Änderungen werden ausgeführt) =="; g "Ergebnis:"
  else v "== VORSCHAU (es wird nichts geändert) =="; g "Vorschau – es wird noch nichts geändert."; fi
  [ -s "$src/quelle.txt" ] && echo "Alter Mac: $(head -1 "$src/quelle.txt")"

  # 1. Treiber: nur ganz fehlende Bundles/Dateien kopieren, vorhandene bleiben unangetastet
  added=0
  if [ -d "$src/Library-Printers" ] && [ ! -L "$src/Library-Printers" ]; then
    v "Treiber, die auf diesem Mac fehlen und ergänzt werden:"
    copy_missing "$src/Library-Printers" "$PRINTERS_DIR"
    [ $added = 0 ] && v "  (keine – alle Treiber sind schon vorhanden)"
    w="Treiberpakete"; [ $added = 1 ] && w="Treiberpaket"
    if [ $added = 0 ]; then g "Alle Treiber sind schon vorhanden."
    elif [ "$apply" = 1 ]; then g "$added $w ergänzt."
    else g "$added $w werden ergänzt."; fi
  fi
  if [ -s "$src/pakete.txt" ]; then
    miss=$(grep -Fvx -f <(pkgutil --pkgs 2>/dev/null) "$src/pakete.txt")
    miss=$(echo $miss)   # Zeilen -> eine Zeile
    [ -n "$miss" ] && warn "Auf dem alten Mac war Herstellersoftware installiert, die hier fehlt: ${miss// /, }"
  fi

  # Stand des neuen Macs vor dem Anlegen
  have_uris=$(lpstat -v 2>/dev/null | sed 's/^[^:]*: //')
  case "$(lpstat -d 2>/dev/null)" in *": "*) have_def=1;; *) have_def=0;; esac

  # 2. Druckerwarteschlangen anlegen
  g ""; g "Drucker:"
  ok=0; fail=0; skip=0; map=""; def_who=""; def_done=0
  while IFS="$TAB" read -r name def info loc mm uri shared auth stopped; do
    [ "$info" = - ] && info=""; [ "$loc" = - ] && loc=""; [ "$auth" = - ] && auth=""
    who="${info:-$name}"
    [ "$def" = ja ] && def_who="$who"
    v ""; v "Drucker: $name  ($mm)"
    if ! valid_name "$name"; then skipped "ungültiger Name." "übersprungen (ungültiger Name)"; continue; fi
    if [ "$uri" = - ]; then skipped "keine Geräteadresse." "übersprungen (keine Geräteadresse)"; continue; fi
    if printf '%s\n' "$have_uris" | grep -Fxq -- "$uri"; then
      skipped "gleiche Geräteadresse ist hier schon eingerichtet." "schon vorhanden, übersprungen"; continue
    fi

    target=$name; n=1
    while lpstat -p "$target" >/dev/null 2>&1; do
      target="$name-migriert"; [ $n -gt 1 ] && target="$target$n"; n=$((n + 1))
    done
    [ "$target" != "$name" ] && v "  Name schon vorhanden, lege an als: $target"

    ppd="$src/ppd/$name.ppd"
    if [ -f "$ppd" ] && [ ! -L "$ppd" ]; then
      drv="-P"; drvarg="$ppd"; v "  Treiber: PPD vom alten Mac"
    else
      case "$uri" in
        ipp://*|ipps://*|dnssd://*) drv="-m"; drvarg="everywhere"; v "  Treiber: driverless (AirPrint/IPP Everywhere)";;
        *) skipped "keine PPD und kein IPP-Drucker." "übersprungen (kein passender Treiber – Herstellertreiber installieren)"; continue;;
      esac
    fi

    sh=false; [ "$shared" = ja ] && sh=true
    opts=(-o "printer-is-shared=$sh")
    pw=0; case "$uri" in smb://*) pw=1;; esac
    [ -n "$auth" ] && [ "$auth" != none ] && { pw=1; opts+=(-o "auth-info-required=$auth"); }
    [ $pw = 1 ] && warn "Drucker „${who}“ braucht ein Kennwort – beim ersten Druck eingeben."
    if [ -f "$src/options.tsv" ]; then
      while IFS="$TAB" read -r on okey oval; do
        [ "$on" = "$name" ] || continue
        case "$okey" in ""|-*|*[!$OKCH]*) continue;; esac
        opts+=(-o "$okey=$oval")
      done < "$src/options.tsv"
    fi
    [ -e "$BACKEND_DIR/${uri%%:*}" ] || warn "Drucker „${who}“: Anschlussart „${uri%%:*}“ fehlt auf diesem Mac – Herstellertreiber installieren."
    [ "$drv" = -P ] && check_ppd "$ppd"
    v "  lpadmin -p $target -E -v $(mask "$uri") $drv $drvarg -D \"$info\" -L \"$loc\" ${opts[*]}"

    if [ "$apply" = 1 ]; then
      if lpadmin -p "$target" -E -v "$uri" "$drv" "$drvarg" -D "$info" -L "$loc" "${opts[@]}"; then
        v "  OK"; ok=$((ok + 1))
      else
        v "  FEHLGESCHLAGEN (Drucker erreichbar? Bei -m everywhere muss er eingeschaltet sein)"; fail=$((fail + 1))
        g "• $(label) – Einrichten fehlgeschlagen (Drucker eingeschaltet und im Netz?)"
        continue
      fi
    fi
    map="$map$name$TAB$target$NL"

    st="eingerichtet"; [ "$target" != "$name" ] && st="als „${target}“ eingerichtet"
    [ "$apply" = 1 ] || st="wird $st"
    if [ "$stopped" = ja ]; then
      st="$st (pausiert wie auf dem alten Mac)"; v "  cupsdisable $target  (war auf dem alten Mac pausiert)"
      [ "$apply" = 1 ] && { cupsdisable "$target" || warn "Drucker „${who}“ ließ sich nicht pausieren."; }
    fi
    if [ "$def" = ja ] && [ $have_def = 0 ]; then
      def_done=1; st="$st, Standarddrucker"; v "  lpadmin -d $target  (Standarddrucker)"
      [ "$apply" = 1 ] && { lpadmin -d "$target" || def_done=0; }
    fi
    g "• $(label) – $st"
  done < "$src/manifest.tsv"
  [ -n "$def_who" ] && [ $def_done = 0 ] && warn "Standarddrucker war „${def_who}“ – bei Bedarf in Drucker & Scanner festlegen."

  # 3. Klassen (Druckergruppen): nur neu angelegte Drucker, nur wenn die Klasse hier noch fehlt
  if [ -f "$src/classes.tsv" ] && [ ! -L "$src/classes.tsv" ]; then
    last=""; cls_ok=0
    while IFS="$TAB" read -r cls mem; do
      new=$(printf '%s' "$map" | awk -F'\t' -v n="$mem" '$1 == n { print $2; exit }')
      [ -n "$new" ] || continue
      if [ "$cls" != "$last" ]; then
        last="$cls"; cls_ok=0
        if ! valid_name "$cls"; then :
        elif lpstat -c "$cls" >/dev/null 2>&1; then warn "Druckergruppe „${cls}“ gibt es hier schon – Drucker bei Bedarf selbst hinzufügen."
        else cls_ok=1; v ""; v "Klasse: $cls"
             if [ "$apply" = 1 ]; then g "• Druckergruppe „${cls}“ angelegt"; else g "• Druckergruppe „${cls}“ wird angelegt"; fi
        fi
      fi
      [ $cls_ok = 1 ] || continue
      v "  lpadmin -p $new -c $cls"
      [ "$apply" = 1 ] && { lpadmin -p "$new" -c "$cls" || warn "Drucker „${new}“ konnte nicht zur Druckergruppe „${cls}“ hinzugefügt werden."; }
    done < "$src/classes.tsv"
  fi

  echo
  if [ "$apply" = 1 ]; then
    echo "Fertig: $ok angelegt, $fail fehlgeschlagen, $skip übersprungen."
    echo "Bitte jeden Drucker mit einer Testseite prüfen (Systemeinstellungen > Drucker & Scanner)."
  else
    echo "Nur eigene Exporte importieren – Treiber werden mit Administratorrechten installiert."
    v "Vorschau fertig ($skip würden übersprungen). Zum Ausführen: „Jetzt einrichten“ in der App bzw. --apply / Menüpunkt 3."
    g "Zum Einrichten auf „Jetzt einrichten“ klicken."
  fi
  if [ -n "$warns" ]; then
    echo; echo "Bitte danach prüfen:"
    printf '%s' "$warns" | sed 's/^/• /'
  fi
}

ask_dir() {
  default=$(ls -td "$HOME"/Desktop/Drucker-Export*.zip "$HOME"/Desktop/Drucker-Export* 2>/dev/null | head -1)
  echo "Export (Zip oder Ordner) ins Fenster ziehen und Enter drücken (leer = ${default:-nichts gefunden}):" >&2
  read -r p
  p="${p%"${p##*[! ]}"}"; p="${p//\\/}"; p="${p#\'}"; p="${p%\'}"   # Drag&Drop-Escapes entfernen
  echo "${p:-$default}"
}

menu() {
  me="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  echo "Drucker-Umzug"
  echo "  1) Export   (auf dem ALTEN Mac)"
  echo "  2) Import – Vorschau   (auf dem NEUEN Mac, ändert nichts)"
  echo "  3) Import – ausführen  (auf dem NEUEN Mac)"
  printf "Auswahl: "; read -r c
  case "$c" in
    1) out="$HOME/Desktop/Drucker-Export"; [ -e "$out" ] && out="$out-$(date +%Y%m%d-%H%M%S)"
       echo "Das Administrator-Passwort wird abgefragt."; sudo "$me" export "$out" ;;
    2) "$me" import "$(ask_dir)" ;;
    3) d="$(ask_dir)"; echo "Das Administrator-Passwort wird abgefragt."; sudo "$me" import "$d" --apply ;;
    *) echo "Abgebrochen." ;;
  esac
  echo; echo "Fenster kann geschlossen werden."
}

case "${1:-}" in
  export) [ $# -ge 2 ] || die "Ordner fehlt: export <ordner>"; do_export "$2" ;;
  import) [ $# -ge 2 ] || die "Ordner fehlt: import <ordner> [--apply]"
          a=0; [ "${3:-}" = --apply ] && a=1; do_import "$2" "$a" ;;
  "")     menu ;;
  *)      die "Unbekannt: $1 (export | import)" ;;
esac
