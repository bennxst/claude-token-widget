# Token-Zähler für Claude Code

Zeigt, wie viele Tokens du mit Claude Code auf deinem Mac verbraucht hast – als kleines Desktop-Widget und als Terminal-Skripte.
Gezählt werden die Verläufe in `~/.claude/projects` auf deinem Mac.

## Desktop-Widget

Quadratisches Widget (158 × 158, so groß wie ein kleines macOS-Widget) mit Milchglas-Hintergrund. Aktualisiert sich alle 30 Sekunden und zeigt:

- **Gesamtverbrauch** gekürzt („1,58 Milliarden“), die genaue Zahl klein oben rechts.
- **5-Stunden-Limit und Wochen-Limit** mit Balken, Prozent und Reset-Zeit, wenn du in Claude Code angemeldet bist.
  Dafür liest das Widget deinen eigenen Claude-Code-Login aus dem Schlüsselbund und fragt damit alle 2 Minuten `api.anthropic.com` ab.
  Der Login verlässt deinen Mac nur in Richtung Anthropic und wird nirgends gespeichert.
  Die Schnittstelle ist **inoffiziell** und kann sich jederzeit ändern.
- **Login abgelaufen?** Dann erneuert das Widget ihn selbst, indem es Claude Code einmal kurz startet
  (Modell Haiku, ohne gespeicherten Verlauf, höchstens alle 30 Minuten, kostet jeweils ein paar Tokens).
  Voraussetzung: Claude Code ist installiert und du warst dort mindestens einmal angemeldet (`claude auth login`).
  Anthropic verlangt trotzdem ab und zu eine neue Anmeldung, dann einmal `claude auth login` ausführen.
- **Ohne gültigen Login** rechnet das Widget selbst: Tokens im aktuellen
  5-Stunden-Fenster mit geschätzter Reset-Zeit und Verbrauch der letzten 7 Tage. Prozente gibt es dann nicht,
  weil Anthropic die Grenzen der Tarife nicht veröffentlicht.

- **Installieren:** `Token-Widget.app` in den Programme-Ordner ziehen und starten.
  Da die App nicht von Apple beglaubigt ist, beim ersten Start: Rechtsklick → **Öffnen** → **Öffnen**
  (oder Systemeinstellungen → Datenschutz & Sicherheit → **Dennoch öffnen**).
- **Verschieben:** Einfach mit der Maus ziehen, die Position wird gemerkt.
- **Beenden / Aktualisieren:** Rechtsklick auf das Widget.
- **Automatisch:** Beim ersten Öffnen trägt sich das Widget als Anmeldeobjekt ein und startet danach mit dem Mac.
  Sichtbar ist es nur, solange die Claude-Desktop-App offen ist. Abschalten: Systemeinstellungen → Allgemein → Anmeldeobjekte.
- **Balken immer blau** (ohne Orange/Rot): `defaults write local.benni.tokenwidget NurBlau -bool true`, dann Widget neu starten.
- **Selbst bauen:** `Widget/build.sh` (braucht die Xcode Command Line Tools: `xcode-select --install`).

## Terminal-Skripte (Python 3)

| Skript | Zeigt |
|---|---|
| `tokens.py` | Gesamtzahl, Aufteilung nach Modell, letzte 7 Tage |
| `chats.py` | Pro Chat: Cache-Verbrauch und Kontextgröße, mit Hinweis wann ein neuer Chat lohnt |
| `warnung.py` | Hook für Claude Code: warnt ab 150.000 Tokens Kontext (siehe Kommentar in der Datei) |

## Was die Zahl bedeutet

Gezählt werden Eingabe, Ausgabe, Cache-Schreiben und Cache-Lesen. Der größte Teil ist Cache-Lesen: Bei jeder Nachricht liest Claude den bisherigen Chat erneut. Kürzere Chats = weniger Tokens.
Nicht enthalten: Chats auf claude.ai, in der Claude-App ohne Claude Code oder auf anderen Geräten.
