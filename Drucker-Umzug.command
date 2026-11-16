#!/bin/bash
# Drucker-Umzug: Drucker, PPDs und Treiber von einem Mac auf einen anderen übertragen.
# Löscht nie etwas und überschreibt nichts. Import ohne --apply ist nur eine Vorschau.
#
#   Doppelklick                        -> Menü
#   sudo ./Drucker-Umzug.command export <ordner>
#   sudo ./Drucker-Umzug.command import <ordner> [--apply]
set -u

CUPS_DIR="${CUPS_DIR:-/private/etc/cups}"
PRINTERS_DIR="${PRINTERS_DIR:-/Library/Printers}"
NEED_ROOT="${NEED_ROOT:-1}"   # nur Tests setzen 0

die() { echo "FEHLER: $*" >&2; exit 1; }
need_root() {
  if [ "$NEED_ROOT" = 1 ] && [ "$(id -u)" != 0 ]; then die "Bitte mit sudo starten."; fi
}

do_export() {
  out="$1"; need_root
  [ -e "$out" ] && die "$out existiert schon. Bitte einen neuen Ordnernamen angeben."
  [ -r "$CUPS_DIR/printers.conf" ] || die "$CUPS_DIR/printers.conf nicht lesbar (keine Drucker eingerichtet?)."
  mkdir -p "$out/ppd" || die "Kann $out nicht anlegen."

  # printers.conf -> manifest.tsv; leere Felder als "-", sonst verschluckt read sie
  awk -v OFS='\t' '
    function f(v) { return v == "" ? "-" : v }
    /^<(Default)?Printer / { name = $2; sub(/>$/, "", name); def = ($1 == "<DefaultPrinter") ? "ja" : "nein"
                             info = loc = mm = uri = ""; shared = "nein"; inp = 1; next }
    /^<\/Printer>/         { if (inp) print name, def, f(info), f(loc), f(mm), f(uri), shared; inp = 0; next }
    !inp                   { next }
    /^Info /               { info = substr($0, 6) }
    /^Location /           { loc  = substr($0, 10) }
    /^MakeModel /          { mm   = substr($0, 11) }
    /^DeviceURI /          { uri  = substr($0, 11) }
    /^Shared Yes/          { shared = "ja" }
  ' "$CUPS_DIR/printers.conf" > "$out/manifest.tsv"

  count=0
  while IFS=$'\t' read -r name def info loc mm uri shared; do
    count=$((count + 1))
    echo "  Drucker: $name  ($mm)  $uri"
    [ -f "$CUPS_DIR/ppd/$name.ppd" ] && cp "$CUPS_DIR/ppd/$name.ppd" "$out/ppd/"
  done < "$out/manifest.tsv"

  cp -R "$CUPS_DIR" "$out/cups-original"          # nur als Referenz, wird nie zurückgespielt
  if [ -d "$PRINTERS_DIR" ]; then
    echo "  Kopiere Treiber aus $PRINTERS_DIR ..."
    ditto "$PRINTERS_DIR" "$out/Library-Printers" || echo "  WARNUNG: Treiber nicht vollständig kopiert."
  fi
  # Ordner dem Benutzer geben, damit er ihn auf Stick/AirDrop kopieren kann
  [ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER" "$out"

  echo
  echo "Export fertig: $count Drucker in $out"
  echo "Diesen Ordner auf den neuen Mac bringen und dort Import starten."
}

do_import() {
  src="$1"; apply="$2"
  [ -f "$src/manifest.tsv" ] || die "$src/manifest.tsv fehlt. Ist das ein Export-Ordner?"
  [ "$apply" = 1 ] && need_root
  if [ "$apply" = 1 ]; then echo "== IMPORT (Änderungen werden ausgeführt) =="; else echo "== VORSCHAU (es wird nichts geändert) =="; fi

  # 1. Treiber: nur fehlende Dateien kopieren
  if [ -d "$src/Library-Printers" ]; then
    missing=$(cd "$src/Library-Printers" && find . \( -type f -o -type l \) | while read -r f; do
      [ -e "$PRINTERS_DIR/$f" ] || [ -L "$PRINTERS_DIR/$f" ] || echo "$f"; done | wc -l | tr -d ' ')
    echo "Treiber: $missing Dateien fehlen auf diesem Mac und werden ergänzt (vorhandene bleiben unangetastet)."
    if [ "$apply" = 1 ] && [ "$missing" != 0 ]; then
      xattr -dr com.apple.quarantine "$src/Library-Printers" 2>/dev/null
      mkdir -p "$PRINTERS_DIR"
      # -n: nie überschreiben; ohne -p: neue Dateien gehören root (cupsd verlangt das für Filter)
      cp -Rn "$src/Library-Printers/" "$PRINTERS_DIR" || echo "  WARNUNG: Nicht alle Treiberdateien konnten kopiert werden."
    fi
  fi

  # 2. Druckerwarteschlangen anlegen
  ok=0; fail=0; skip=0
  while IFS=$'\t' read -r name def info loc mm uri shared; do
    [ "$info" = - ] && info=""; [ "$loc" = - ] && loc=""
    echo
    echo "Drucker: $name  ($mm)"
    if [ "$uri" = - ]; then echo "  ÜBERSPRUNGEN: keine Geräteadresse."; skip=$((skip + 1)); continue; fi

    target=$name; n=1
    while lpstat -p "$target" >/dev/null 2>&1; do
      target="$name-migriert"; [ $n -gt 1 ] && target="$target$n"; n=$((n + 1))
    done
    [ "$target" != "$name" ] && echo "  Name schon vorhanden, lege an als: $target"

    if [ -f "$src/ppd/$name.ppd" ]; then
      drv="-P"; drvarg="$src/ppd/$name.ppd"; echo "  Treiber: PPD vom alten Mac"
    else
      case "$uri" in
        ipp://*|ipps://*|dnssd://*) drv="-m"; drvarg="everywhere"; echo "  Treiber: driverless (AirPrint/IPP Everywhere)";;
        *) echo "  ÜBERSPRUNGEN: keine PPD und kein IPP-Drucker."; skip=$((skip + 1)); continue;;
      esac
    fi
    sh=false; [ "$shared" = ja ] && sh=true
    echo "  lpadmin -p $target -E -v $uri $drv $drvarg -D \"$info\" -L \"$loc\" -o printer-is-shared=$sh"

    if [ "$apply" = 1 ]; then
      if lpadmin -p "$target" -E -v "$uri" "$drv" "$drvarg" -D "$info" -L "$loc" -o printer-is-shared=$sh; then
        echo "  OK"; ok=$((ok + 1))
      else
        echo "  FEHLGESCHLAGEN (Drucker erreichbar? Bei -m everywhere muss er eingeschaltet sein)"; fail=$((fail + 1))
      fi
    fi
  done < "$src/manifest.tsv"

  echo
  if [ "$apply" = 1 ]; then
    echo "Fertig: $ok angelegt, $fail fehlgeschlagen, $skip übersprungen."
    echo "Bitte jeden Drucker mit einer Testseite prüfen (Systemeinstellungen > Drucker & Scanner)."
  else
    echo "Vorschau fertig ($skip würden übersprungen). Zum Ausführen: Import mit --apply bzw. Menüpunkt 3."
  fi
}

ask_dir() {
  default="$HOME/Desktop/Drucker-Export"
  echo "Export-Ordner ins Fenster ziehen und Enter drücken (leer = $default):" >&2
  read -r p
  p="${p//\\ / }"; p="${p%"${p##*[! ]}"}"; p="${p#\'}"; p="${p%\'}"   # Drag&Drop-Escapes entfernen
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
