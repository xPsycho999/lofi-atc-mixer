#!/bin/bash

# Prüfen ob socat installiert ist
if ! command -v socat &> /dev/null; then
    echo "❌ Fehler: 'socat' fehlt. Bitte mit 'sudo pacman -S socat' installieren."
    exit 1
fi

# ==========================================
# STREAM DATENBANK
# ==========================================
declare -A MUSIC_STREAMS=(
    ["🎧 Lofi Girl (Klassiker)"]="https://www.youtube.com/watch?v=jfKfPfyJRdk"
    ["🌃 Synthwave / Retrowave"]="https://www.youtube.com/watch?v=4xDzrJKXOOY"
    ["🎷 Chillhop Radio"]="https://www.youtube.com/watch?v=5yx6BWlEVcY"
    ["☕ Jazz / Bossa Nova"]="https://www.youtube.com/watch?v=HuFYqnbVbzY"
)

declare -A AMBIENCE_STREAMS=(
    ["🚫 Keine (Stumm)"]="NONE"
    ["🌧️ Sanfter Regen"]="https://www.youtube.com/watch?v=PhDPj2sfKm0"
    ["✈️ Flugzeug Kabine"]="https://www.youtube.com/watch?v=co7KgV2edGk"
)

declare -A ATC_STREAMS=(
    ["🇺🇸 Los Angeles (LAX Tower)"]="http://d.liveatc.net/klax_twr"
    ["🇺🇸 New York (JFK Tower)"]="http://d.liveatc.net/kjfk_twr"
    ["🇺🇸 Chicago (ORD Tower)"]="http://d.liveatc.net/kord_twr"
    ["🇺🇸 Atlanta (ATL Tower)"]="http://d.liveatc.net/katl_twr"
    ["🇺🇸 San Francisco (SFO Tower)"]="http://d.liveatc.net/ksfo_twr"
    ["🇨🇦 Toronto (YYZ Tower)"]="http://d.liveatc.net/cyyz_twr"
    ["🇦🇺 Sydney (SYD Tower)"]="http://d.liveatc.net/yssy_twr"
    ["🇮🇪 Dublin (DUB Tower)"]="http://d.liveatc.net/eidw_twr"
)

# ==========================================
# SYSTEM SETUP & FUNKTIONEN
# ==========================================
SOCK_MUSIC="/tmp/lofi-atc-music.sock"
SOCK_AMB="/tmp/lofi-atc-amb.sock"
SOCK_ATC="/tmp/lofi-atc-atc.sock"

# Cava & Status Setup
FIFO_CAVA="/tmp/lofi-cava.fifo"
FILE_CAVA="/tmp/lofi-cava.state"
CONF_CAVA="/tmp/lofi-cava.conf"
FILE_STATUS="/tmp/lofi-status.env"

SPIN_CHARS=('/' '-' '\' '|')
LOOP_COUNT=0

# Funktion zum sauberen Beenden
cleanup_streams() {
    [[ -n "$PID_MUSIC" ]] && kill "$PID_MUSIC" 2>/dev/null
    [[ -n "$PID_AMB" ]] && kill "$PID_AMB" 2>/dev/null
    [[ -n "$PID_ATC" ]] && kill "$PID_ATC" 2>/dev/null
    [[ -n "$PID_CAVA" ]] && kill "$PID_CAVA" 2>/dev/null
    [[ -n "$PID_READER" ]] && kill "$PID_READER" 2>/dev/null
    [[ -n "$PID_STAT" ]] && kill "$PID_STAT" 2>/dev/null
    rm -f "$SOCK_MUSIC" "$SOCK_AMB" "$SOCK_ATC" "$FIFO_CAVA" "$FILE_CAVA" "$CONF_CAVA" "$FILE_STATUS"
}

trap 'cleanup_streams; clear; echo -e "\n👋 Ciao! Guten Flug!"; exit' EXIT

# Diese Funktion wird nur vom Hintergrund-Worker gerufen (verhindert Lag!)
get_status_raw() {
    local sock="$1"
    if [[ ! -S "$sock" ]]; then
        echo -en "\e[1;31m[FAIL]\e[0m"
        return
    fi
    local res
    res=$(timeout 0.2 socat - "$sock" <<< '{ "command": ["get_property", "core-idle"] }' 2>/dev/null)
    if [[ -z "$res" ]]; then
        echo -en "\e[1;31m[FAIL]\e[0m"
    elif [[ "$res" == *'"data":false'* ]]; then
        echo -en "\e[1;32m[LIVE]\e[0m"
    else
        echo -en "\e[1;33m[LOAD_SPIN]\e[0m" # Platzhalter für den schnellen UI-Spinner
    fi
}

draw_ui() {
    LOOP_COUNT=$(( (LOOP_COUNT + 1) % 1000 ))
    local spin_idx=$(( (LOOP_COUNT / 4) % 4 ))
    local spin_char="${SPIN_CHARS[$spin_idx]}"

    # Status aus der Temp-Datei laden (Blockiert nicht = ultra flüssig!)
    local stat_music="\e[1;33m[LOAD_SPIN]\e[0m"
    local stat_atc="\e[1;33m[LOAD_SPIN]\e[0m"
    local stat_amb="\e[1;33m[LOAD_SPIN]\e[0m"
    if [[ -f "$FILE_STATUS" ]]; then
        source "$FILE_STATUS" 2>/dev/null
    fi

    # Platzhalter mit animiertem Spinner ersetzen
    stat_music="${STAT_MUSIC//LOAD_SPIN/LOAD $spin_char}"
    stat_atc="${STAT_ATC//LOAD_SPIN/LOAD $spin_char}"
    stat_amb="${STAT_AMB//LOAD_SPIN/LOAD $spin_char}"

    # Cava Visualizer auslesen und umwandeln
    local vis_str="   (Visualizer startet...)"
    if [[ -n "$PID_CAVA" && -f "$FILE_CAVA" ]]; then
        local raw_data=$(< "$FILE_CAVA")
        IFS=';' read -ra bars <<< "$raw_data"
        vis_str=""
        # Präzise Unicode Blöcke (0 bis 7)
        local chars=(' ' '▂' '▃' '▄' '▅' '▆' '▇' '█')
        for b in "${bars[@]}"; do
            [[ "$b" =~ ^[0-7]$ ]] && vis_str+="${chars[$b]}"
        done
        vis_str=$(printf "%-36s" "$vis_str")
    elif ! command -v cava &> /dev/null; then
        vis_str="   (cava nicht installiert)"
    fi

    # ATC String (Check auf Mute)
    local atc_str="${VOL_ATC}%"
    if [ "$MUTE_ATC" -eq 1 ]; then
        atc_str="\e[1;31m[MUTED]\e[0m"
    fi

    # Musik Filter String
    local filter_str=""
    if [ "$FILTER_ON" -eq 1 ]; then
        filter_str=" \e[1;33m[VHF]\e[0m"
    fi

    local amb_vol_str
    if [[ "$AMB_URL" != "NONE" ]]; then
        amb_vol_str=$(printf "%3d%%" "$VOL_AMB")
    else
        stat_amb="\e[1;30m[OFF]\e[0m"
        amb_vol_str="---%"
    fi

    # UI Zeichnen (1 Zeile hoch, Visualizer schreiben, dann Status schreiben)
    printf "\r\e[1A\e[K %b %s \e[0m\n\e[K${C_MAIN}>> Status:\e[0m  🎵 Musik: \e[1;32m%3d%%\e[0m %b%b  |  🌧️ Ambience: \e[1;34m%s\e[0m %b  |  ✈️ ATC: \e[1;32m%-15b\e[0m %b" \
        "${C_SEC}" "$vis_str" "$VOL_MUSIC" "$stat_music" "$filter_str" "$amb_vol_str" "$stat_amb" "$atc_str" "$stat_atc"
}

# ==========================================
# HAUPTSCHLEIFE (Main Loop)
# ==========================================
while true; do
    # 1. Auswahl Musik
    MUSIC_CHOICE=$(printf "%s\n" "${!MUSIC_STREAMS[@]}" | sort | fzf --prompt="🎵 Wähle deinen Vibe (ESC zum Beenden): " --border=rounded --height=30% --color=bg+:#2e3440,fg+:#d8dee9,hl+:#88c0d0,prompt:#b48ead,pointer:#bf616a)
    [[ -z "$MUSIC_CHOICE" ]] && break
    MUSIC_URL="${MUSIC_STREAMS[$MUSIC_CHOICE]}"

    # Dynamische Farbpalette
    case "$MUSIC_CHOICE" in
        *"Synthwave"*)
            C_MAIN="\e[38;5;201m" # Neon Pink
            C_SEC="\e[38;5;51m"   # Cyan
            ;;
        *"Lofi"*)
            C_MAIN="\e[38;5;150m" # Pastel Green
            C_SEC="\e[38;5;183m"  # Pastel Purple
            ;;
        *"Chillhop"*)
            C_MAIN="\e[38;5;214m" # Orange
            C_SEC="\e[38;5;220m"  # Yellow
            ;;
        *"Jazz"*)
            C_MAIN="\e[38;5;137m" # Brown
            C_SEC="\e[38;5;178m"  # Gold
            ;;
        *)
            C_MAIN="\e[1;36m"
            C_SEC="\e[1;35m"
            ;;
    esac
    C_RST="\e[0m"

    # 2. Auswahl Ambience
    AMB_CHOICE=$(printf "%s\n" "${!AMBIENCE_STREAMS[@]}" | sort | fzf --prompt="🌧️ Wähle deine Ambience (ESC zum Beenden): " --border=rounded --height=30% --color=bg+:#2e3440,fg+:#d8dee9,hl+:#81a1c1,prompt:#81a1c1,pointer:#bf616a)
    [[ -z "$AMB_CHOICE" ]] && break
    AMB_URL="${AMBIENCE_STREAMS[$AMB_CHOICE]}"

    # 3. Auswahl ATC
    ATC_CHOICE=$(printf "%s\n" "${!ATC_STREAMS[@]}" | sort | fzf --prompt="✈️  Wähle deinen Tower (ESC zum Beenden): " --border=rounded --height=40% --color=bg+:#2e3440,fg+:#d8dee9,hl+:#88c0d0,prompt:#a3be8c,pointer:#bf616a)
    [[ -z "$ATC_CHOICE" ]] && break
    ATC_URL="${ATC_STREAMS[$ATC_CHOICE]}"

    # Reset Variablen
    VOL_MUSIC=50
    VOL_AMB=50
    VOL_ATC=80
    MUTE_ATC=0
    FILTER_ON=0
    cleanup_streams

    # ==========================================
    # CAVA TUNING & SETUP
    # ==========================================
    if command -v cava &> /dev/null; then
        rm -f "$FIFO_CAVA" "$FILE_CAVA"
        mkfifo "$FIFO_CAVA"

        # Generiere dynamische Cava-Config für hohe FPS & Genauigkeit
        cat <<EOF > "$CONF_CAVA"
[general]
framerate = 40
bars = 36
sensitivity = 120
[smoothing]
monstercat = 1
noise_reduction = 0.5
[output]
method = raw
raw_target = $FIFO_CAVA
data_format = ascii
ascii_max_range = 7
bar_delimiter = 59
EOF

        # Starte Cava unsichtbar im Hintergrund
        cava -p "$CONF_CAVA" >/dev/null 2>&1 &
        PID_CAVA=$!

        # Subshell liest den Cava-Output super schnell ein
        (
            while read -r line; do
                echo "$line" > "$FILE_CAVA"
            done < "$FIFO_CAVA"
        ) &
        PID_READER=$!
    fi

    clear
    # ASCII Art & Theming
    echo -e "${C_SEC}           __|__${C_RST}"
    echo -e "${C_MAIN}  --@--@--(_)--@--@--${C_RST}"
    echo -e "${C_MAIN}======================================${C_RST}"
    echo -e " 🎵 ${C_SEC}$MUSIC_CHOICE${C_RST}"
    echo -e " 🌧️ ${C_SEC}$AMB_CHOICE${C_RST}"
    echo -e " ✈️  ${C_SEC}$ATC_CHOICE${C_RST}"
    echo -e "${C_MAIN}======================================${C_RST}"
    echo -e " \e[1mSTEUERUNG:\e[0m"
    echo -e " [\e[1;33mW / S\e[0m] Musik lauter/leiser"
    echo -e " [\e[1;33mE / D\e[0m] Ambience lauter/leiser"
    echo -e " [\e[1;33m↑ / ↓\e[0m] ATC lauter/leiser"
    echo -e " [\e[1;35m  F  \e[0m] Musik-VHF-Filter (Radio-Effekt) an/aus"
    echo -e " [\e[1;31m  M  \e[0m] ATC stumm schalten (Mute)"
    echo -e " [\e[1;31m  Q  \e[0m] Zurück zum Menü"
    echo -e "${C_MAIN}======================================${C_RST}"
    echo "" # Platzhalter für Visualizer
    echo "" # Platzhalter für Status

    # Streams starten
    mpv --no-video --volume=$VOL_MUSIC --input-ipc-server="$SOCK_MUSIC" "$MUSIC_URL" > /dev/null 2>&1 &
    PID_MUSIC=$!

    if [[ "$AMB_URL" != "NONE" ]]; then
        mpv --no-video --volume=$VOL_AMB --input-ipc-server="$SOCK_AMB" "$AMB_URL" > /dev/null 2>&1 &
        PID_AMB=$!
    fi

    mpv --no-video --volume=$VOL_ATC --input-ipc-server="$SOCK_ATC" "$ATC_URL" > /dev/null 2>&1 &
    PID_ATC=$!

    # Status-Worker im Hintergrund (Verhindert, dass das Zeichnen laggt!)
    echo "STAT_MUSIC='\e[1;33m[LOAD_SPIN]\e[0m'; STAT_ATC='\e[1;33m[LOAD_SPIN]\e[0m'; STAT_AMB='\e[1;33m[LOAD_SPIN]\e[0m'" > "$FILE_STATUS"
    (
        while true; do
            s_m=$(get_status_raw "$SOCK_MUSIC")
            s_a=$(get_status_raw "$SOCK_ATC")
            s_amb="\e[1;30m[OFF]\e[0m"
            if [[ "$AMB_URL" != "NONE" ]]; then
                s_amb=$(get_status_raw "$SOCK_AMB")
            fi
            # Schreibe Variablen in Env-Datei für den Haupt-Thread
            cat <<EOF > "$FILE_STATUS"
STAT_MUSIC="$s_m"
STAT_ATC="$s_a"
STAT_AMB="$s_amb"
EOF
            sleep 1
        done
    ) &
    PID_STAT=$!

    # ==========================================
    # LIVE-KONTROLLSCHLEIFE (Player Loop)
    # ==========================================
    while true; do
        # Timeout auf 0.03 reduziert -> ~33 FPS UI Refresh Rate!
        if read -rsn1 -t 0.03 key; then
            case "$key" in
                $'\x1b') # Pfeiltasten
                    read -rsn2 -t 0.1 rest
                    case "$rest" in
                        '[A') # Hoch (ATC)
                            ((VOL_ATC < 130)) && VOL_ATC=$((VOL_ATC + 5))
                            echo "{ \"command\": [\"set_property\", \"volume\", $VOL_ATC] }" | socat - "$SOCK_ATC" >/dev/null 2>&1
                            ;;
                        '[B') # Runter (ATC)
                            ((VOL_ATC > 0)) && VOL_ATC=$((VOL_ATC - 5))
                            echo "{ \"command\": [\"set_property\", \"volume\", $VOL_ATC] }" | socat - "$SOCK_ATC" >/dev/null 2>&1
                            ;;
                    esac
                    ;;
                w|W) # Hoch (Musik)
                    ((VOL_MUSIC < 130)) && VOL_MUSIC=$((VOL_MUSIC + 5))
                    echo "{ \"command\": [\"set_property\", \"volume\", $VOL_MUSIC] }" | socat - "$SOCK_MUSIC" >/dev/null 2>&1
                    ;;
                s|S) # Runter (Musik)
                    ((VOL_MUSIC > 0)) && VOL_MUSIC=$((VOL_MUSIC - 5))
                    echo "{ \"command\": [\"set_property\", \"volume\", $VOL_MUSIC] }" | socat - "$SOCK_MUSIC" >/dev/null 2>&1
                    ;;
                e|E) # Hoch (Ambience)
                    if [[ "$AMB_URL" != "NONE" ]]; then
                        ((VOL_AMB < 130)) && VOL_AMB=$((VOL_AMB + 5))
                        echo "{ \"command\": [\"set_property\", \"volume\", $VOL_AMB] }" | socat - "$SOCK_AMB" >/dev/null 2>&1
                    fi
                    ;;
                d|D) # Runter (Ambience)
                    if [[ "$AMB_URL" != "NONE" ]]; then
                        ((VOL_AMB > 0)) && VOL_AMB=$((VOL_AMB - 5))
                        echo "{ \"command\": [\"set_property\", \"volume\", $VOL_AMB] }" | socat - "$SOCK_AMB" >/dev/null 2>&1
                    fi
                    ;;
                f|F) # VHF Filter für Musik On/Off
                    if [ "$FILTER_ON" -eq 0 ]; then
                        FILTER_ON=1
                        echo '{ "command": ["set_property", "af", "highpass=f=400,lowpass=f=3000"] }' | socat - "$SOCK_MUSIC" >/dev/null 2>&1
                    else
                        FILTER_ON=0
                        echo '{ "command": ["set_property", "af", ""] }' | socat - "$SOCK_MUSIC" >/dev/null 2>&1
                    fi
                    ;;
                m|M) # Mute (ATC)
                    if [ "$MUTE_ATC" -eq 0 ]; then
                        MUTE_ATC=1
                        echo '{ "command": ["set_property", "mute", true] }' | socat - "$SOCK_ATC" >/dev/null 2>&1
                    else
                        MUTE_ATC=0
                        echo '{ "command": ["set_property", "mute", false] }' | socat - "$SOCK_ATC" >/dev/null 2>&1
                    fi
                    ;;
                q|Q) # Zurück zum Menü
                    cleanup_streams
                    break
                    ;;
            esac
        fi

        # Zeichnen passiert jetzt ~33 mal pro Sekunde für perfekte Cava-Animation
        draw_ui
    done
done
