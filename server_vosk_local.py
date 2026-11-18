#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Server WebSocket Vosk Lokal untuk Ekstensi Browser Side Panel
Menyediakan endpoint ws://localhost:2700 agar ekstensi browser
dapat mentranskripsi secara 100% offline tanpa internet.
"""

import os
import sys
import json
import time
import asyncio
import subprocess

def release_port(port=2700):
    """
    Memastikan port 2700 tidak terblokir oleh instance server sebelumnya (zombie/orphaned process).
    Otomatis membebaskan port jika proses lama masih menggantung.
    """
    current_pid = os.getpid()
    try:
        out = subprocess.check_output(f'netstat -ano | findstr :{port}', shell=True, text=True, stderr=subprocess.DEVNULL)
        for line in out.strip().splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[1].endswith(f':{port}') and parts[3] == 'LISTENING':
                old_pid = int(parts[4])
                if old_pid != current_pid and old_pid > 0:
                    print(f"[*] Port {port} sedang dipakai oleh instance lama (PID: {old_pid}). Membersihkan...", flush=True)
                    subprocess.run(f"taskkill /PID {old_pid} /F", shell=True, capture_output=True)
                    time.sleep(1)
    except Exception:
        pass

try:
    import websockets
except ImportError:
    print("[*] Memasang modul websockets...", flush=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "websockets", "--quiet"])
    import websockets

try:
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
except ImportError:
    print("[*] Memasang modul vosk...", flush=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "vosk", "--quiet"])
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.join(ROOT_DIR, "models")

# Cache model Vosk dalam memori
models = {}

def is_valid_vosk_model(path):
    if not path or not os.path.exists(path) or not os.path.isdir(path):
        return False
    # Model Vosk valid wajib memiliki folder 'am' atau 'conf' di dalamnya
    has_am = os.path.exists(os.path.join(path, "am"))
    has_conf = os.path.exists(os.path.join(path, "conf"))
    return has_am or has_conf

def get_model(lang_code):
    if lang_code in models:
        return models[lang_code]

    lc = lang_code.lower()
    if "ja" in lc or "jp" in lc:
        target = "ja"
    elif "id" in lc or "in" in lc:
        target = "id"
    elif "en" in lc:
        target = "en"
    else:
        target = "cn"

    possible = [
        os.path.join(MODELS_DIR, target),
        os.path.join(MODELS_DIR, f"vosk-model-small-{target}-0.4"),
        os.path.join(MODELS_DIR, f"vosk-model-small-{target}-0.22"),
        os.path.join(MODELS_DIR, f"vosk-model-small-{target}-0.15"),
        target
    ]
    for p in possible:
        if is_valid_vosk_model(p):
            try:
                print(f"[✓] Memuat model Vosk {target} dari: {p}", flush=True)
                models[lang_code] = Model(p)
                return models[lang_code]
            except Exception as e:
                print(f"[!] Gagal memuat model Vosk dari {p}: {e}", flush=True)

    # Cari subfolder di folder models
    if os.path.exists(MODELS_DIR):
        for item in os.listdir(MODELS_DIR):
            p = os.path.join(MODELS_DIR, item)
            if os.path.isdir(p) and target in item.lower() and is_valid_vosk_model(p):
                try:
                    print(f"[✓] Memuat model Vosk {target} dari: {p}", flush=True)
                    models[lang_code] = Model(p)
                    return models[lang_code]
                except Exception as e:
                    print(f"[!] Gagal memuat model Vosk dari {p}: {e}", flush=True)

    return None

async def handler(websocket, *args):
    print(f"\n[+] Klien terhubung dari browser side panel.", flush=True)
    recognizer = None
    sample_rate = 16000.0
    lang = "id-ID"

    try:
        async for message in websocket:
            # Jika pesan berupa JSON konfigurasi
            if isinstance(message, str):
                try:
                    data = json.loads(message)
                    if "config" in data:
                        lang = data["config"].get("lang", "id-ID")
                        sample_rate = float(data["config"].get("sample_rate", 16000.0))
                        m = get_model(lang)
                        if m:
                            recognizer = KaldiRecognizer(m, sample_rate)
                            recognizer.SetWords(True)
                            await websocket.send(json.dumps({"status": "ready", "lang": lang}))
                        else:
                            await websocket.send(json.dumps({"error": f"Model untuk {lang} belum terpasang di folder 'models/'."}))
                except Exception as e:
                    await websocket.send(json.dumps({"error": str(e)}))

            # Jika pesan berupa byte data audio mentah PCM
            elif isinstance(message, bytes):
                if recognizer is None:
                    m = get_model(lang)
                    if m:
                        recognizer = KaldiRecognizer(m, sample_rate)
                        recognizer.SetWords(True)
                    else:
                        await websocket.send(json.dumps({"error": "Model Vosk offline belum ditemukan!"}))
                        continue

                if recognizer.AcceptWaveform(message):
                    res = recognizer.Result()
                    await websocket.send(res)
                else:
                    partial = recognizer.PartialResult()
                    await websocket.send(partial)

    except websockets.exceptions.ConnectionClosed:
        print("[-] Koneksi klien browser terputus.", flush=True)
    finally:
        if recognizer:
            final_res = recognizer.FinalResult()
            try:
                await websocket.send(final_res)
            except Exception:
                pass

def process_request(connection, request):
    """
    Jika endpoint diakses via browser biasa (HTTP), tampilkan dashboard status visual yang informatif.
    Jika diakses via WebSocket, izinkan upgrade koneksi.
    """
    try:
        connection_hdr = request.headers.get("Connection", "").lower()
        upgrade_hdr = request.headers.get("Upgrade", "").lower()
        if "upgrade" not in connection_hdr or upgrade_hdr != "websocket":
            from websockets.http11 import Response
            from websockets.datastructures import Headers
            html = b"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Server Vosk Lokal - Aktif</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #f8fafc; padding: 30px; line-height: 1.6;">
  <div style="max-width: 650px; margin: 0 auto; background: #1e293b; border-radius: 12px; padding: 24px; box-shadow: 0 10px 25px rgba(0,0,0,0.3); border: 1px solid #334155;">
    <h2 style="margin-top: 0; color: #38bdf8;">&#128640; Server Vosk Offline WebSocket Aktif</h2>
    <p>Status Server: <span style="background: #065f46; color: #34d399; padding: 4px 12px; border-radius: 20px; font-weight: bold; font-size: 13px;">&#10003; BERJALAN NORMAL</span></p>
    <p>Endpoint WebSocket: <code style="background: #0f172a; padding: 4px 8px; border-radius: 6px; color: #f43f5e; font-size: 14px;">ws://localhost:2700</code></p>
    <hr style="border: 0; border-top: 1px solid #334155; margin: 18px 0;">
    <p style="font-size: 13px; color: #94a3b8;">
      Server ini menyediakan transkripsi suara 100% offline langsung dari mesin lokal tanpa koneksi internet.
      Ekstensi browser Chrome / Edge (Side Panel) akan otomatis terhubung ke endpoint ini.
    </p>
  </div>
</body>
</html>"""
            headers = Headers([
                ("Content-Type", "text/html; charset=utf-8"),
                ("Content-Length", str(len(html))),
                ("Connection", "close")
            ])
            return Response(200, "OK", headers, html)
    except Exception:
        pass
    return None

async def main():
    port = 2700
    print("=" * 65, flush=True)
    print("  🚀 SERVER VOSK OFFLINE WEBSOCKET (EKSTENSI SIDE PANEL)", flush=True)
    print(f"  📡 Mendengarkan koneksi di: ws://localhost:{port}", flush=True)
    print("  💡 Ekstensi browser mode offline akan otomatis terhubung ke sini.", flush=True)
    print("  Tekan Ctrl+C untuk menghentikan server.", flush=True)
    print("=" * 65, flush=True)

    # 1. Bersihkan zombie process di port 2700 jika ada
    release_port(port)

    # 2. Pra-muat model offline yang tersedia
    m_cn = get_model("zh-CN")
    if m_cn:
        print("[✓] Model Vosk Mandarin siap digunakan (100% Offline).", flush=True)

    m_ja = get_model("ja-JP")
    if m_ja:
        print("[✓] Model Vosk Jepang siap digunakan (100% Offline).", flush=True)

    m_id = get_model("id-ID")
    if m_id:
        print("[✓] Model Vosk Bahasa Indonesia siap digunakan (Offline).", flush=True)
    else:
        print("[i] Model offline Bahasa Indonesia belum terpasang di 'models/id'.", flush=True)
        print("    Transkripsi Bahasa Indonesia otomatis diarahkan ke Google Speech Online.", flush=True)

    # 3. Jalankan server WebSocket
    try:
        async with websockets.serve(handler, "localhost", port, process_request=process_request):
            print(f"\n[✓] Server berhasil berjalan di port {port}. Siap menerima audio!", flush=True)
            await asyncio.Future() # Berjalan selamanya
    except OSError:
        # Fallback eksplisit ke 127.0.0.1 jika localhost resolusi bermasalah di OS
        async with websockets.serve(handler, "127.0.0.1", port, process_request=process_request):
            print(f"\n[✓] Server berhasil berjalan di 127.0.0.1:{port}. Siap menerima audio!", flush=True)
            await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[!] Server dihentikan oleh pengguna.", flush=True)
    except Exception as e:
        print(f"\n[!] Terjadi kesalahan pada server: {e}", flush=True)
