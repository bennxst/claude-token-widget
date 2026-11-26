# Token-Zähler für Claude Code

Zeigt, wie viele Tokens du mit Claude Code auf deinem Mac verbraucht hast – als kleines Desktop-Widget und als Terminal-Skripte.
Alles läuft lokal: Gezählt werden nur die Verläufe in `~/.claude/projects`, es wird nichts ins Internet geschickt.

## Desktop-Widget

Kleines Widget (160 × 160) mit Milchglas-Hintergrund, zeigt die Gesamtzahl gekürzt („1,58 Milliarden“) und genau. Aktualisiert sich alle 30 Sekunden.

- **Installieren:** `Token-Widget.app` in den Programme-Ordner ziehen und starten.
  Da die App nicht von Apple beglaubigt ist, beim ersten Start: Rechtsklick → **Öffnen** → **Öffnen**
  (oder Systemeinstellungen → Datenschutz & Sicherheit → **Dennoch öffnen**).
- **Verschieben:** Einfach mit der Maus ziehen, die Position wird gemerkt.
- **Beenden / Aktualisieren:** Rechtsklick auf das Widget.
- **Autostart:** Systemeinstellungen → Allgemein → Anmeldeobjekte → **+** → `Token-Widget.app`.
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
