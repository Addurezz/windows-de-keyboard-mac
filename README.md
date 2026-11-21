# Tastatur-Layout-Umschalter für macOS

Dieser Hintergrunddienst wechselt beim Anschließen einer externen Tastatur die macOS-Eingabequelle und stellt beim Abziehen dein gewohntes Layout wieder her. Standardmäßig verwendet er für externe Tastaturen **Deutsch – Standard**, etwa für AltGr + Q (`@`) und AltGr + 8 (`[`) auf deutschen Windows-Tastaturen. Du kannst für beide Zustände ein beliebiges installiertes macOS-Tastaturlayout auswählen.

Der Dienst wechselt die aktive Eingabequelle für die gesamte macOS-Sitzung. Das gewählte Layout gilt daher auch für die eingebaute Tastatur, solange die externe angeschlossen ist. Der Dienst prüft den Verbindungsstatus in IOKit.

## Einrichten

Schließe die Tastatur an oder kopple sie per Bluetooth. Du brauchst die Xcode Command Line Tools (`xcode-select --install`, falls `swiftc` fehlt).

```bash
./install.sh
```

1. Wähle die Geräte-ID aus der Liste. Alternativ gib `--any-external` ein, um alle von macOS erkannten externen USB- und Bluetooth-HID-Tastaturen einzubeziehen.
2. Bestätige dein derzeit aktives Mac-Layout mit Enter oder gib seine Layout-ID ein. Bei einer erneuten Einrichtung wird dein bisher eingestelltes Mac-Layout vorgeschlagen.
3. Bestätige **Deutsch – Standard** für die externe Tastatur mit Enter oder gib eine andere Layout-ID ein.

Der LaunchAgent läuft sofort und startet bei der nächsten Anmeldung automatisch.

### IDs anzeigen und direkt installieren

```bash
./install.sh --list
```

`--list` zeigt die angeschlossenen Geräte und die verfügbaren Layouts mit ihren IDs. Beispiel für alle externen Tastaturen mit dem normalen Mac-Layout **Deutsch** als Rückfall:

```bash
./install.sh --any-external com.apple.keylayout.German
```

Für eine bestimmte Tastatur gib anstelle von `--any-external` ihre Geräte-ID ein. Ein optionales drittes Argument legt das externe Layout fest, etwa `com.apple.keylayout.US` für eine entsprechend beschriftete US-Tastatur.

## Verhalten bei mehreren Geräten

Im Modus `--any-external` bleibt das externe Layout aktiv, solange mindestens eine externe USB- oder Bluetooth-Tastatur verbunden ist. USB-Funkempfänger können macOS eine Tastaturschnittstelle melden, solange der Empfänger steckt. Der Dienst erkennt in diesem Fall die Verbindung des Empfängers. Wähle bei Bedarf eine bestimmte Geräte-ID, um andere Empfänger auszuschließen. Geräte desselben Modells mit identischer Geräte-ID werden gemeinsam berücksichtigt.

## Prüfen

Stecke die Tastatur ein und prüfe das Layout im macOS-Eingabemenü. Zieh sie wieder ab und prüfe, ob dein Mac-Layout zurückkehrt.

Wenn macOS beim Wechsel zwischen Dokumenten selbst das Layout wechselt, prüfe unter **Systemeinstellungen → Tastatur → Texteingabe → Bearbeiten** die Option zum automatischen Wechsel der Eingabequelle pro Dokument. Wenn `<` und `^` vertauscht sind, prüfe den Tastaturtyp ISO für eine deutsche Tastatur mit hoher Eingabetaste. [Apple zur Auswahl des Tastaturtyps](https://support.apple.com/guide/mac-help/specify-a-keyboard-type-mchlp2886/mac)

Fehler des Dienstes stehen in `~/Library/Logs/io.github.windows-de-keyboard-mac.layout-switch.log`.

## Deinstallieren

```bash
./install.sh --uninstall
```

Das Skript beendet den Dienst, stellt das konfigurierte Mac-Layout wieder her und entfernt den LaunchAgent sowie das Programm.
