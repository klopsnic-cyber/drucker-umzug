-- Drucker-Umzug: Oberfläche mit zwei Knöpfen. Die eigentliche Arbeit macht
-- Resources/Drucker-Umzug.command (getestet über tests/run-tests.sh).
use AppleScript version "2.4" -- macOS 10.10+, nötig für das native Startfenster
use framework "AppKit"
use scripting additions
property appVersion : "__VERSION__"
property engineSha : "__ENGINE_SHA__"
property repo : "klopsnic-cyber/drucker-umzug"

on run
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	checkUpdate()
	set choice to startDialog() -- Abbrechen hier: still beenden
	try
		if choice is "Export" then
			doExport()
		else
			doImport()
		end if
	on error msg number n
		if n is -128 then
			display dialog "Abgebrochen – es wurde nichts verändert." buttons {"OK"} default button "OK" with title "Drucker-Umzug" with icon (path to resource "applet.icns")
		else
			if msg is "" then set msg to "Unbekannter Fehler."
			if length of msg > 1500 then set msg to (text 1 thru 1500 of msg) & "…"
			display dialog msg buttons {"OK"} default button "OK" with title "Drucker-Umzug" with icon stop
		end if
	end try
	end timeout
end run

-- Natives Startfenster (NSAlert): Logo, Erklärung, oranger kursiver Hinweis.
on startDialog()
	set ca to current application
	set a to ca's NSAlert's alloc()'s init()
	a's setMessageText:("Drucker-Umzug")
	a's setInformativeText:("Nehmen Sie Ihre Drucker mit auf den neuen Mac – samt Treibern und Einstellungen." & return & return & "Auf dem alten Mac: „Exportieren“ sichert alles in eine Datei." & return & "Auf dem neuen Mac: „Importieren“ richtet die Drucker aus dieser Datei ein." & return & return & "Die App wird auf beiden Macs gebraucht." & return & return & "Version " & appVersion)
	a's setIcon:(ca's NSImage's alloc()'s initWithContentsOfFile:(POSIX path of (path to resource "applet.icns")))
	a's addButtonWithTitle:"Exportieren"
	a's addButtonWithTitle:"Importieren"
	((a's addButtonWithTitle:"Abbrechen")'s setKeyEquivalent:(character id 27))
	set f to ca's NSFontManager's sharedFontManager()'s convertFont:(ca's NSFont's systemFontOfSize:12) toHaveTrait:(ca's NSItalicFontMask)
	set attrs to ca's NSDictionary's dictionaryWithObjects:{f, ca's NSColor's systemOrangeColor()} forKeys:{ca's NSFontAttributeName, ca's NSForegroundColorAttributeName}
	set lbl to ca's NSTextField's wrappingLabelWithString:""
	lbl's setAttributedStringValue:(ca's NSAttributedString's alloc()'s initWithString:"Ihre vorhandenen Drucker bleiben unangetastet – es wird nichts gelöscht und nichts überschrieben." attributes:attrs)
	lbl's setPreferredMaxLayoutWidth:330
	lbl's setFrameSize:{330, height of (lbl's fittingSize() as record)}
	a's setAccessoryView:lbl
	ca's NSApp's activateIgnoringOtherApps:true
	-- auf dem Bildschirm mit dem Mauszeiger zentrieren (sonst landet es evtl. auf einem anderen Monitor)
	a's layout()
	set w to a's |window|()
	set m to ca's NSEvent's mouseLocation()
	set wf to (w's frame()) as list
	repeat with s in (ca's NSScreen's screens()) as list
		set f to (s's frame()) as list
		set {sx, sy, sw, sh} to {item 1 of item 1 of f, item 2 of item 1 of f, item 1 of item 2 of f, item 2 of item 2 of f}
		if (x of m) ≥ sx and (x of m) < sx + sw and (y of m) ≥ sy and (y of m) < sy + sh then
			w's setFrameOrigin:{sx + (sw - (item 1 of item 2 of wf)) / 2, sy + (sh - (item 2 of item 2 of wf)) * 0.6}
		end if
	end repeat
	set r to (a's runModal()) as integer
	if r is 1000 then return "Export"
	if r is 1001 then return "Import"
	error number -128
end startDialog

on doExport()
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set nm to "Drucker-Export-" & (do shell script "date +%Y%m%d-%H%M%S")
	set out to (POSIX path of (path to desktop)) & nm
	set res to runEngine("EXPORT_OWNER=" & quoted form of (short user name of (system info)) & " ", "export " & quoted form of out, true, "Drucker werden gesichert …")
	set b to show("Fertig! Die Datei " & nm & ".zip liegt auf dem Schreibtisch. Bringen Sie sie per USB-Stick oder AirDrop auf den neuen Mac und klicken Sie dort auf Import." & return & return & res, "Export fertig", {"OK", "Im Finder zeigen"})
	if b is "Im Finder zeigen" then do shell script "open -R " & quoted form of (out & ".zip")
	end timeout
end doExport

on doImport()
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set f to POSIX path of (choose file with prompt "Die Export-Datei (Drucker-Export-….zip) vom alten Mac auswählen:" of type {"zip", "public.zip-archive"} default location (path to desktop))
	-- Vorschau ohne Admin-Rechte, ändert nichts
	set preview to runEngine("", "import " & quoted form of f, false, "Export-Datei wird gelesen …")
	show(preview, "Vorschau – es wurde noch nichts verändert", {"Abbrechen", "Jetzt einrichten"})
	set res to runEngine("", "import " & quoted form of f & " --apply", true, "Drucker werden eingerichtet …")
	set b to show(res, "Import fertig", {"OK", "Drucker & Scanner öffnen"})
	if b is "Drucker & Scanner öffnen" then do shell script "open 'x-apple.systempreferences:com.apple.Print-Scanner-Settings.extension'"
	end timeout
end doImport

-- Engine prüfen (Hash aus dem Build) und mit Fortschrittsanzeige starten. Fehler: Engine-Meldung im Fehlertext.
on runEngine(pre, args, admin, desc)
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set e to quoted form of (POSIX path of (path to resource "Drucker-Umzug.command"))
	if (do shell script "shasum -a 256 " & e & " | cut -d' ' -f1") is not engineSha then error "Die App ist beschädigt oder verändert – bitte neu herunterladen." number 1
	set cmd to "DU_GUI=1 " & pre & e & " " & args & " 2>&1"
	set progress total steps to 1
	set progress completed steps to 0
	set progress description to desc
	set progress additional description to "Das kann einige Minuten dauern."
	try
		if admin then
			set r to do shell script cmd with administrator privileges
		else
			set r to do shell script cmd
		end if
	on error msg number n
		resetProgress()
		error msg number n
	end try
	resetProgress()
	return r
	end timeout
end runEngine

on resetProgress()
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set progress total steps to 0
	set progress completed steps to 0
	set progress description to ""
	set progress additional description to ""
	end timeout
end resetProgress

-- Text anzeigen; ab 25 Zeilen gekürzt + Knopf "Bericht öffnen" (volle Ausgabe im Texteditor).
-- bl = {links, rechts(Standard)}; "Abbrechen" links beendet mit -128. Gibt den Knopfnamen zurück.
on show(txt, ttl, bl)
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set shown to txt
	if (count of paragraphs of txt) > 25 then
		set AppleScript's text item delimiters to return
		set shown to ((items 1 thru 20 of (paragraphs of txt)) as text) & return & "… (vollständiger Bericht im Texteditor)"
		set AppleScript's text item delimiters to ""
		set bl to {item 1 of bl, "Bericht öffnen", item 2 of bl}
	end if
	repeat
		set b to button returned of (display dialog shown buttons bl default button (item -1 of bl) with title ttl with icon (path to resource "applet.icns"))
		if b is "Bericht öffnen" then
			set p to (do shell script "mktemp -d") & "/Drucker-Umzug-Bericht.txt"
			do shell script "printf '%s\\n' " & quoted form of txt & " > " & quoted form of p & " && open -e " & quoted form of p
		else
			if b is "Abbrechen" then error number -128
			return b
		end if
	end repeat
	end timeout
end show

-- Updater: VERSION im Repo vergleichen, Zip laden, SHA256 + Version prüfen, mit Rollback austauschen.
on checkUpdate()
	with timeout of 86400 seconds -- Dialoge dürfen beliebig lange offen bleiben (Standard: 2 Min. → Fehler -1712)
	set raw to "https://raw.githubusercontent.com/" & repo & "/main/"
	try
		set latest to do shell script "curl -fsSL --max-time 5 " & raw & "VERSION"
		do shell script "case " & quoted form of latest & " in ''|*[!0-9.]*|.*|*.|*..*) exit 1;; esac" -- nur Ziffern und Punkte (^[0-9]+(\\.[0-9]+)*$)
	on error
		return -- offline, GitHub nicht erreichbar oder Unsinn: einfach weiter
	end try
	considering numeric strings
		if latest ≤ appVersion then return -- nie ein Downgrade
	end considering
	set appPath to POSIX path of (path to me)
	if appPath ends with "/" then set appPath to text 1 thru -2 of appPath
	if appPath contains "/AppTranslocation/" then return -- schreibgeschützt gestartet, Update sinnlos
	set b to button returned of (display dialog "Version " & latest & " ist verfügbar (installiert: " & appVersion & ")." buttons {"Später", "Jetzt aktualisieren"} default button "Jetzt aktualisieren" with title "Update" with icon (path to resource "applet.icns"))
	if b is "Später" then return
	-- Phase 1 ohne Admin-Rechte: laden, Prüfsumme und Version prüfen, entpacken
	set dl to "set -e; t=$(mktemp -d); trap 'rc=$?; [ $rc -eq 0 ] || rm -rf \"$t\"' EXIT; " & ¬
		"curl -fsSL --max-time 120 -o \"$t/u.zip\" https://github.com/" & repo & "/releases/latest/download/Drucker-Umzug.zip; " & ¬
		"want=$(curl -fsSL --max-time 10 " & raw & "SHA256 | head -c 64); " & ¬
		"[ \"$(shasum -a 256 \"$t/u.zip\" | cut -d' ' -f1)\" = \"$want\" ] || exit 2; " & ¬
		"ditto -x -k \"$t/u.zip\" \"$t/x\"; n=$(find \"$t/x\" -maxdepth 2 -name Drucker-Umzug.app | head -1); [ -d \"$n\" ] || exit 2; " & ¬
		"[ \"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \"$n/Contents/Info.plist\")\" = " & quoted form of latest & " ] || exit 2; " & ¬
		"codesign -v \"$n\" || exit 2; printf '%s\\n%s' \"$t\" \"$n\""
	try
		set r to do shell script dl
	on error
		display dialog "Update konnte nicht geladen werden. Die App startet normal weiter." buttons {"OK"} default button "OK" with title "Update" with icon caution
		return
	end try
	set t to paragraph 1 of r
	set n to paragraph 2 of r
	-- Phase 2: austauschen mit Rollback; Admin-Rechte nur, wenn der Ordner nicht beschreibbar ist
	set sw to "set -e; t=" & quoted form of t & "; trap 'rm -rf \"$t\"' EXIT; a=" & quoted form of appPath & "; mv \"$a\" \"$t/alt.app\"; mv " & quoted form of n & " \"$a\" || { rm -rf \"$a\"; mv \"$t/alt.app\" \"$a\"; exit 1; }"
	try
		do shell script "test -w " & quoted form of (do shell script "dirname " & quoted form of appPath)
		set adm to false
	on error
		set adm to true
	end try
	try
		if adm then
			do shell script sw with administrator privileges
		else
			do shell script sw
		end if
	on error msg number en
		do shell script "rm -rf " & quoted form of t
		if en is not -128 then display dialog "Update konnte nicht installiert werden. Die bisherige App bleibt erhalten." buttons {"OK"} default button "OK" with title "Update" with icon caution
		return
	end try
	display dialog "Update installiert – die App wird neu gestartet." buttons {"OK"} default button "OK" with title "Update" giving up after 4
	do shell script "open -n " & quoted form of appPath
	error number -128 -- diese (alte) Instanz beenden
	end timeout
end checkUpdate
