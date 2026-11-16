-- Drucker-Umzug: Oberfläche mit zwei Knöpfen. Die eigentliche Arbeit macht
-- Resources/Drucker-Umzug.command (getestet über tests/run-tests.sh).
property appVersion : "__VERSION__"
property repo : "klopsnic-cyber/drucker-umzug"

on run
	checkUpdate()
	set engine to quoted form of (POSIX path of (path to resource "Drucker-Umzug.command"))
	set choice to button returned of (display dialog "Drucker, Treiber und Einstellungen von einem Mac auf einen anderen übertragen." & return & return & "Export: auf dem ALTEN Mac" & return & "Import: auf dem NEUEN Mac" & return & return & "Es wird nie ein Drucker gelöscht oder etwas überschrieben." buttons {"Abbrechen", "Import", "Export"} cancel button "Abbrechen" with title "Drucker-Umzug " & appVersion with icon note)
	try
		if choice is "Export" then
			doExport(engine)
		else
			doImport(engine)
		end if
	on error msg number n
		if n is not -128 then display dialog "Fehler:" & return & msg buttons {"OK"} default button "OK" with title "Drucker-Umzug" with icon stop
	end try
end run

on doExport(engine)
	set stamp to do shell script "date +%Y%m%d-%H%M%S"
	set out to (POSIX path of (path to desktop)) & "Drucker-Export-" & stamp
	set me_ to short user name of (system info)
	set res to do shell script "EXPORT_OWNER=" & quoted form of me_ & " " & engine & " export " & quoted form of out & " 2>&1" with administrator privileges
	display dialog res buttons {"Im Finder zeigen", "OK"} default button "OK" with title "Export fertig"
	if button returned of result is "Im Finder zeigen" then do shell script "open -R " & quoted form of (out & ".zip")
end doExport

on doImport(engine)
	set f to POSIX path of (choose file with prompt "Die Export-Datei (Drucker-Export-….zip) vom alten Mac auswählen:" of type {"zip", "public.zip-archive"} default location (path to desktop))
	-- Vorschau ohne Admin-Rechte, ändert nichts
	set preview to do shell script engine & " import " & quoted form of f & " 2>&1"
	display dialog preview buttons {"Abbrechen", "Drucker anlegen"} cancel button "Abbrechen" default button "Drucker anlegen" with title "Vorschau – noch wurde nichts geändert"
	set res to do shell script engine & " import " & quoted form of f & " --apply 2>&1" with administrator privileges
	display dialog res buttons {"Drucker & Scanner öffnen", "OK"} default button "OK" with title "Import fertig"
	if button returned of result is not "OK" then do shell script "open 'x-apple.systempreferences:com.apple.Print-Scanner-Settings.extension'"
end doImport

-- Updater: VERSION-Datei im Repo vergleichen, neue App aus dem letzten Release laden und ersetzen.
on checkUpdate()
	try
		set latest to do shell script "curl -fsSL --max-time 5 https://raw.githubusercontent.com/" & repo & "/main/VERSION"
	on error
		return -- offline oder GitHub nicht erreichbar: einfach weiter
	end try
	considering numeric strings
		if latest ≤ appVersion then return
	end considering
	set b to button returned of (display dialog "Version " & latest & " ist verfügbar (installiert: " & appVersion & ")." buttons {"Später", "Jetzt aktualisieren"} default button "Jetzt aktualisieren" with title "Update" with icon note)
	if b is "Später" then return
	set appPath to POSIX path of (path to me)
	if appPath ends with "/" then set appPath to text 1 thru -2 of appPath
	set cmd to "set -e; t=$(mktemp -d); curl -fsSL -o \"$t/u.zip\" https://github.com/" & repo & "/releases/latest/download/Drucker-Umzug.zip; ditto -x -k \"$t/u.zip\" \"$t/x\"; n=$(find \"$t/x\" -maxdepth 2 -name 'Drucker-Umzug.app' | head -1); test -d \"$n\"; mv " & quoted form of appPath & " \"$t/alt.app\"; mv \"$n\" " & quoted form of appPath
	try
		do shell script cmd
	on error
		do shell script cmd with administrator privileges -- z. B. in /Applications ohne Schreibrecht
	end try
	do shell script "open -n " & quoted form of appPath
	error number -128 -- diese (alte) Instanz beenden
end checkUpdate
