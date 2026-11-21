# Windows-Tastatur auf dem Mac

Dieser kleine macOS-Hintergrunddienst schaltet beim Anschließen einer bestimmten deutschen Windows-Tastatur auf **Deutsch – Standard**. Beim Abziehen schaltet er auf dein übliches Mac-Layout zurück. Die rechte Alt-Taste funktioniert dabei wie AltGr, etwa für `@` auf `Q`, `€` auf `E` und `{ [ ] }` auf `7 8 9 0`.

Der Dienst wechselt die aktive Eingabequelle deiner macOS-Sitzung. Solange die externe Tastatur angeschlossen ist, gilt Deutsch – Standard auch für die eingebaute Tastatur. Der Umschalter verwendet IOKit-Gerätebenachrichtigungen und greift ausschließlich auf Geräteinformationen zu.

## Installation

Für eine **Corsair K65 Pro Mini** und **ABC – QWERTZ** als Mac-Layout führst du im Repository aus:

```bash
./install.sh 1b1c:1bd7 com.apple.keylayout.ABC-QWERTZ
```

Du brauchst die Xcode Command Line Tools (`xcode-select --install`, falls `swiftc` fehlt). Das Skript installiert einen LaunchAgent für dein Benutzerkonto und startet ihn sofort. Der Agent startet auch nach der nächsten Anmeldung automatisch. Das Layout **Deutsch – Standard** wird bei Bedarf aktiviert.

Für eine andere Tastatur oder ein anderes Mac-Layout findest du die passenden IDs so:

```bash
swiftc -O KeyboardSwitch.swift -o /tmp/keyboard-switch
/tmp/keyboard-switch devices
/tmp/keyboard-switch current
/tmp/keyboard-switch layouts
```

Führe `current` aus, während dein gewünschtes Mac-Layout aktiv ist. Übergib die Geräte-ID und die Layout-ID an `install.sh`. Als optionales drittes Argument kannst du ein anderes PC-Layout angeben. Bei einem USB-Funkempfänger ist dessen sichtbare HID-Geräteverbindung ausschlaggebend.

## Prüfen

1. Stecke die Windows-Tastatur ein. Im Eingabemenü sollte **Deutsch – Standard** stehen. Probiere rechts Alt + Q für `@` und rechts Alt + 8 für `[`.
2. Zieh die Tastatur ab. Im Eingabemenü sollte wieder dein Mac-Layout erscheinen.

Wenn macOS beim Wechsel zwischen Dokumenten selbst das Layout wechselt, prüfe unter **Systemeinstellungen → Tastatur → Texteingabe → Bearbeiten** die Option zum automatischen Wechsel der Eingabequelle pro Dokument. Wenn `<` und `^` vertauscht sind, prüfe für eine deutsche Tastatur mit hoher Eingabetaste den Tastaturtyp ISO. [Apple zur Auswahl des Tastaturtyps](https://support.apple.com/guide/mac-help/specify-a-keyboard-type-mchlp2886/mac)

Fehler des Dienstes stehen in `~/Library/Logs/io.github.windows-de-keyboard-mac.layout-switch.log`.

## Deinstallation

```bash
./install.sh --uninstall
```

Das Skript beendet den Dienst, stellt das konfigurierte Mac-Layout wieder her und entfernt den LaunchAgent sowie das Programm.
