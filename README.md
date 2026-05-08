# lofi-atc-mixer
Terminal-TUI für Lofi, Live-ATC & Ambient Sounds. Features: Native fzf-Menüs, asynchrone Statusleiste, integrierter Cava-Visualizer und dynamische VHF-Radio-Filter.

## ✨ Features
* **Multi-Layer Audio:** Steuere Lofi-Beats, Tower-Funk und Ambient-Sounds (Regen, Café) unabhängig voneinander.
* **Dynamisches TUI:** Elegante, farbcodierte `fzf`-Menüs für blitzschnelle Navigation.
* **Integrierter Visualizer:** Nativer `cava` Audio-Visualizer, der direkt im Terminal läuft.
* **Asynchrone Statusleiste:** Flüssige UI-Updates mit Live-Verbindungsstatus (`[LIVE]`, `[LOAD]`, `[FAIL]`).
* **VHF-Radio-Filter:** Lege auf Knopfdruck einen authentischen Highpass/Lowpass-Filter über die Musik.

## 🛠️ Voraussetzungen (Dependencies)
Das Skript nutzt leichtgewichtige CLI-Tools. Stelle sicher, dass folgende Pakete installiert sind:

Auf **Arch Linux / CachyOS**:
```bash
sudo pacman -S mpv yt-dlp fzf socat cava
```
## 🚀 Installation & Nutzung
```
git clone [https://github.com/DEIN-GITHUB-NAME/lofi-atc-mixer.git](https://github.com/DEIN-GITHUB-NAME/lofi-atc-mixer.git)
cd lofi-atc-mixer
chmod +x lofi-atc.sh
./lofi-atc.sh
