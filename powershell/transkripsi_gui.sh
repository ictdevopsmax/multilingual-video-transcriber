#!/usr/bin/env bash
# ==============================================================================
# Aplikasi Transkripsi Video Offline - Shell Script GUI (Zenity/Yad)
# Menggunakan mesin Vosk & FFmpeg Streaming Audio on-the-fly.
# Mendukung Bahasa Indonesia & Bahasa Mandarin (China).
# ==============================================================================

# Cek dependensi GUI (zenity atau dialog)
if ! command -v zenity &> /dev/null; then
    echo "[Perhatian] zenity tidak ditemukan. Mohon install zenity: sudo apt install zenity"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$ROOT_DIR/models"

# 1. Buka File Video (.mp4/.mkv) secara interaktif
VIDEO_PATH=$(zenity --file-selection \
    --title="Pilih File Video Berdurasi Panjang" \
    --file-filter="Video Files (*.mp4 *.mkv *.avi *.mov *.webm) | *.mp4 *.mkv *.avi *.mov *.webm *.flv" \
    --file-filter="Semua File | *.*" 2>/dev/null)

if [ -z "$VIDEO_PATH" ]; then
    echo "Pemilihan file dibatalkan."
    exit 0
fi

# Tentukan file nota catatan teks output dan subtitle .srt
DIR_NAME="$(dirname "$VIDEO_PATH")"
BASE_NAME="$(basename "$VIDEO_PATH" | cut -f 1 -d '.')"
OUTPUT_TXT="$DIR_NAME/${BASE_NAME}_transkripsi.txt"
OUTPUT_SRT="$DIR_NAME/${BASE_NAME}_subtitle.srt"

# 2. Pilihan Bahasa (Indonesia / Mandarin)
LANG_CHOICE=$(zenity --list \
    --title="Pilihan Bahasa Transkripsi" \
    --text="Pilih bahasa video yang akan ditranskripsi:" \
    --radiolist \
    --column="Pilih" --column="Bahasa" \
    TRUE "Bahasa Indonesia" \
    FALSE "Bahasa Mandarin (China)" 2>/dev/null)

if [ -z "$LANG_CHOICE" ]; then
    echo "Pemilihan bahasa dibatalkan."
    exit 0
fi

if [[ "$LANG_CHOICE" == *"Indonesia"* ]]; then
    LANG_CODE="id"
else
    LANG_CODE="cn"
fi

# Deteksi folder model Vosk
MODEL_PATH=""
if [ -d "$MODELS_DIR/$LANG_CODE" ]; then
    MODEL_PATH="$MODELS_DIR/$LANG_CODE"
else
    # Cari di subfolder models
    MATCH=$(find "$MODELS_DIR" -maxdepth 2 -type d -name "*$LANG_CODE*" | head -n 1)
    if [ -n "$MATCH" ]; then
        MODEL_PATH="$MATCH"
    fi
fi

if [ -z "$MODEL_PATH" ] || [ ! -d "$MODEL_PATH" ]; then
    zenity --error --text="Model Vosk offline untuk $LANG_CHOICE belum ditemukan!\nSilakan unduh dan letakkan di: $MODELS_DIR/$LANG_CODE" 2>/dev/null
    exit 1
fi

# Inisialisasi file nota dan subtitle
cat << EOF > "$OUTPUT_TXT"
=== NOTA CATATAN TRANSKRIPSI VIDEO (Shell Script) ===
File Video : $VIDEO_PATH
Bahasa     : $LANG_CHOICE
Model Vosk : $MODEL_PATH
-----------------------------------------------------

EOF
> "$OUTPUT_SRT"

# 3. Proses Transkripsi Streaming On-The-Fly via FFmpeg Pipe
(
    python3 -c "
import sys, os, json, subprocess
from vosk import Model, KaldiRecognizer, SetLogLevel

SetLogLevel(-1)
video = sys.argv[1]
model_path = sys.argv[2]
out_txt = sys.argv[3]
out_srt = sys.argv[4]

def format_srt_time(sec):
    if sec is None or sec < 0: sec = 0.0
    h, m, s = int(sec // 3600), int((sec % 3600) // 60), int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms >= 1000: ms = 999
    return f'{h:02d}:{m:02d}:{s:02d},{ms:03d}'

model = Model(model_path)
rec = KaldiRecognizer(model, 16000.0)
rec.SetWords(True)

cmd = ['ffmpeg', '-loglevel', 'quiet', '-i', video, '-ar', '16000', '-ac', '1', '-f', 's16le', '-']
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=4000)

total_bytes = 0
srt_idx = 1

while True:
    data = p.stdout.read(4000)
    if len(data) == 0:
        break
    total_bytes += len(data)
    cur_sec = total_bytes / 32000.0
    if rec.AcceptWaveform(data):
        res = json.loads(rec.Result())
        txt = res.get('text', '').strip()
        if txt:
            st_sec = max(0.0, cur_sec - 3.5)
            words = res.get('result', [])
            if words and 'start' in words[0] and 'end' in words[-1]:
                st_sec = words[0]['start']
                cur_sec = words[-1]['end']
            print(txt, flush=True)
            with open(out_txt, 'a', encoding='utf-8') as f:
                f.write(txt + '\n')
            with open(out_srt, 'a', encoding='utf-8') as f:
                f.write(f'{srt_idx}\n{format_srt_time(st_sec)} --> {format_srt_time(cur_sec)}\n{txt}\n\n')
            srt_idx += 1

final_res = json.loads(rec.FinalResult())
final_txt = final_res.get('text', '').strip()
if final_txt:
    cur_sec = total_bytes / 32000.0
    st_sec = max(0.0, cur_sec - 3.0)
    print(final_txt, flush=True)
    with open(out_txt, 'a', encoding='utf-8') as f:
        f.write(final_txt + '\n')
    with open(out_srt, 'a', encoding='utf-8') as f:
        f.write(f'{srt_idx}\n{format_srt_time(st_sec)} --> {format_srt_time(cur_sec)}\n{final_txt}\n\n')
    srt_idx += 1
" "$VIDEO_PATH" "$MODEL_PATH" "$OUTPUT_TXT" "$OUTPUT_SRT"
) | zenity --text-info \
    --title="Transkripsi Video Streaming: $BASE_NAME" \
    --width=750 --height=500 \
    --ok-label="Selesai" \
    --cancel-label="Hentikan" 2>/dev/null

# 4. Fitur Baca Nota & Subtitle
ACTION=$(zenity --list \
    --title="Transkripsi Selesai" \
    --text="Transkripsi selesai!\n1. Nota: $OUTPUT_TXT\n2. Subtitle: $OUTPUT_SRT\n\nPilih file yang ingin dibuka:" \
    --column="Aksi" \
    "Buka Subtitle (.SRT)" \
    "Buka Nota (.TXT)" \
    "Tutup" 2>/dev/null)

if [ "$ACTION" == "Buka Subtitle (.SRT)" ]; then
    if command -v xdg-open &> /dev/null; then xdg-open "$OUTPUT_SRT"; elif command -v open &> /dev/null; then open "$OUTPUT_SRT"; fi
elif [ "$ACTION" == "Buka Nota (.TXT)" ]; then
    if command -v xdg-open &> /dev/null; then xdg-open "$OUTPUT_TXT"; elif command -v open &> /dev/null; then open "$OUTPUT_TXT"; fi
fi

