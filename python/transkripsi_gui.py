#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Aplikasi Transkripsi Video Hybrid (Offline & Online) - Python GUI
- Mode Offline : Menggunakan engine lokal Vosk (tanpa internet).
- Mode Online  : Menggunakan Google Web Speech Recognition (gratis, tanpa API key) / Cloud API.
Streaming on-the-fly via FFmpeg pipe (tanpa file audio terpisah di disk).
Mendukung Bahasa Indonesia & Bahasa Mandarin (China) serta penanda waktu [HH:MM:SS].
"""

import os
import sys
import json
import io
import wave
import shutil
import subprocess
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox, scrolledtext

# Paksa encoding UTF-8 untuk stdout & stderr di Windows
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass

class TranskripsiApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Transkripsi Video Hybrid (Offline & Online) - Python GUI")
        self.root.geometry("880x720")
        self.root.minsize(740, 560)

        self.video_path = ""
        self.output_txt_path = ""
        self.output_srt_path = ""
        self.is_transcribing = False
        self.process = None

        self.base_dir = os.path.dirname(os.path.abspath(__file__))
        self.project_root = os.path.dirname(self.base_dir)
        self.models_dir = os.path.join(self.project_root, "models")
        self.tools_dir = os.path.join(self.project_root, "tools")

        self.setup_ui()

    def setup_ui(self):
        style = ttk.Style()
        style.theme_use("clam")

        # Frame Pengaturan Utama
        top_frame = ttk.LabelFrame(self.root, text=" Pengaturan Transkripsi Video ", padding=12)
        top_frame.pack(fill=tk.X, padx=14, pady=8)

        # 1. Pemilihan Mode Mesin (Offline vs Online)
        lbl_mode = ttk.Label(top_frame, text="Mode Mesin:", font=("Segoe UI", 9, "bold"))
        lbl_mode.grid(row=0, column=0, sticky=tk.W, pady=4)

        mode_frame = ttk.Frame(top_frame)
        mode_frame.grid(row=0, column=1, sticky=tk.W, padx=6, pady=4)

        # Mode default cerdas: Online untuk Bahasa Indonesia (karena akurasi tinggi & gratis), Offline jika model lokal ada
        has_id_model = os.path.exists(os.path.join(self.models_dir, "id")) and os.path.exists(os.path.join(self.models_dir, "id", "am"))
        self.mode_var = tk.StringVar(value="offline" if has_id_model else "online")
        r_off = ttk.Radiobutton(mode_frame, text="🔒 Offline (Vosk Lokal - Tanpa Internet)", variable=self.mode_var, value="offline", command=self.on_mode_change)
        r_off.pack(side=tk.LEFT, padx=(0, 15))

        r_on = ttk.Radiobutton(mode_frame, text="🌐 Online (Google Speech API - Gratis / Akurasi Tinggi)", variable=self.mode_var, value="online", command=self.on_mode_change)
        r_on.pack(side=tk.LEFT)

        # 2. File Video (Buka File)
        lbl_video = ttk.Label(top_frame, text="File Video (.mp4/.mkv):")
        lbl_video.grid(row=1, column=0, sticky=tk.W, pady=4)

        self.entry_video = ttk.Entry(top_frame, width=58)
        self.entry_video.grid(row=1, column=1, padx=6, pady=4, sticky=tk.EW)

        btn_browse = ttk.Button(top_frame, text="📁 Buka File", command=self.browse_video)
        btn_browse.grid(row=1, column=2, padx=4, pady=4)

        # 3. Pilihan Bahasa
        lbl_lang = ttk.Label(top_frame, text="Pilihan Bahasa:")
        lbl_lang.grid(row=2, column=0, sticky=tk.W, pady=4)

        self.lang_var = tk.StringVar(value="Bahasa Indonesia")
        self.combo_lang = ttk.Combobox(
            top_frame, 
            textvariable=self.lang_var, 
            values=["Bahasa Indonesia", "Bahasa Mandarin (China)", "Bahasa Jepang (Japan)"],
            state="readonly",
            width=28
        )
        self.combo_lang.grid(row=2, column=1, sticky=tk.W, padx=6, pady=4)

        self.btn_model = ttk.Button(top_frame, text="⚙️ Folder Model (Offline)", command=self.browse_model_folder)
        self.btn_model.grid(row=2, column=2, padx=4, pady=4)
        self.custom_model_path = ""

        # Opsi Timestamp
        self.var_timestamp = tk.BooleanVar(value=True)
        chk_time = ttk.Checkbutton(top_frame, text="Sertakan Penanda Waktu Jam [HH:MM:SS]", variable=self.var_timestamp)
        chk_time.grid(row=3, column=1, sticky=tk.W, padx=6, pady=2)

        # Tombol Aksi
        btn_frame = ttk.Frame(top_frame)
        btn_frame.grid(row=4, column=0, columnspan=3, pady=10)

        self.btn_start = ttk.Button(btn_frame, text="▶️ Mulai Transkripsi", command=self.toggle_transcription)
        self.btn_start.pack(side=tk.LEFT, padx=6)

        self.btn_read_note = ttk.Button(btn_frame, text="📝 Baca Nota (TXT)", command=self.read_note)
        self.btn_read_note.pack(side=tk.LEFT, padx=6)

        self.btn_read_srt = ttk.Button(btn_frame, text="🎬 Baca Subtitle (.SRT)", command=self.read_srt)
        self.btn_read_srt.pack(side=tk.LEFT, padx=6)

        self.btn_clear = ttk.Button(btn_frame, text="🗑️ Hapus Layar", command=self.clear_display)
        self.btn_clear.pack(side=tk.LEFT, padx=6)

        # Indikator Status & Progress Bar
        self.status_var = tk.StringVar(value="Status: Siap. Pilih file video dan mode (Offline/Online).")
        self.lbl_status = ttk.Label(self.root, textvariable=self.status_var, font=("Segoe UI", 9, "italic"))
        self.lbl_status.pack(anchor=tk.W, padx=16, pady=2)

        self.progress = ttk.Progressbar(self.root, mode="indeterminate")
        self.progress.pack(fill=tk.X, padx=16, pady=2)

        # Area Teks Hasil Transkripsi
        text_frame = ttk.LabelFrame(self.root, text=" Hasil Transkripsi (Streaming On-The-Fly Langsung) ", padding=8)
        text_frame.pack(fill=tk.BOTH, expand=True, padx=14, pady=6)

        self.txt_display = scrolledtext.ScrolledText(text_frame, wrap=tk.WORD, font=("Consolas", 10))
        self.txt_display.pack(fill=tk.BOTH, expand=True)

        top_frame.columnconfigure(1, weight=1)

    def on_mode_change(self):
        mode = self.mode_var.get()
        if mode == "online":
            self.btn_model.config(state="disabled")
            self.status_var.set("Mode Online aktif: Menggunakan koneksi internet & Google Speech API (Tanpa butuh model lokal).")
        else:
            self.btn_model.config(state="normal")
            self.status_var.set("Mode Offline aktif: Memproses secara lokal dengan mesin Vosk (100% tanpa internet).")

    def find_ffmpeg_executable(self):
        # 1. Cek di PATH sistem
        ffmpeg_bin = shutil.which("ffmpeg")
        if ffmpeg_bin:
            return ffmpeg_bin

        # 2. Cek di folder lokal project (tools/ atau root)
        local_candidates = [
            os.path.join(self.tools_dir, "ffmpeg.exe"),
            os.path.join(self.tools_dir, "bin", "ffmpeg.exe"),
            os.path.join(self.project_root, "ffmpeg.exe"),
            r"C:\ffmpeg\bin\ffmpeg.exe",
            r"C:\Program Files\FFmpeg\bin\ffmpeg.exe"
        ]
        for c in local_candidates:
            if os.path.exists(c):
                return c

        # 3. Cek di folder WinGet Packages jika baru diinstall lewat winget
        local_app_data = os.environ.get("LOCALAPPDATA", "")
        if local_app_data:
            winget_dir = os.path.join(local_app_data, "Microsoft", "WinGet", "Packages")
            if os.path.exists(winget_dir):
                for root_dir, dirs, files in os.walk(winget_dir):
                    if "ffmpeg.exe" in files:
                        return os.path.join(root_dir, "ffmpeg.exe")

        return None

    def format_time(self, seconds):
        if seconds is None or seconds < 0:
            seconds = 0.0
        hrs = int(seconds // 3600)
        mins = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        return f"[{hrs:02d}:{mins:02d}:{secs:02d}]"

    def format_srt_time(self, seconds):
        if seconds is None or seconds < 0:
            seconds = 0.0
        hrs = int(seconds // 3600)
        mins = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        millis = int(round((seconds - int(seconds)) * 1000))
        if millis >= 1000:
            millis = 999
        return f"{hrs:02d}:{mins:02d}:{secs:02d},{millis:03d}"

    def browse_video(self):
        file_path = filedialog.askopenfilename(
            title="Pilih File Video Berdurasi Panjang",
            filetypes=[
                ("Video Files", "*.mp4;*.mkv;*.avi;*.mov;*.flv;*.webm;*.ts"),
                ("MP4 Video", "*.mp4"),
                ("MKV Video", "*.mkv"),
                ("Semua File", "*.*")
            ]
        )
        if file_path:
            self.video_path = file_path
            self.entry_video.delete(0, tk.END)
            self.entry_video.insert(0, file_path)
            
            dir_name = os.path.dirname(file_path)
            base_name = os.path.splitext(os.path.basename(file_path))[0]
            self.output_txt_path = os.path.join(dir_name, f"{base_name}_transkripsi.txt")
            self.output_srt_path = os.path.join(dir_name, f"{base_name}_subtitle.srt")
            self.status_var.set(f"File dipilih. Nota (.txt) & Subtitle (.srt) siap dibuat.")

    def browse_model_folder(self):
        folder = filedialog.askdirectory(title="Pilih Folder Model Vosk Offline")
        if folder:
            self.custom_model_path = folder
            messagebox.showinfo("Model Terpilih", f"Menggunakan model kustom:\n{folder}")

    def get_model_path(self):
        if self.custom_model_path and os.path.exists(self.custom_model_path):
            return self.custom_model_path

        lang = self.lang_var.get()
        if "Indonesia" in lang:
            target_name = "id"
        elif "Jepang" in lang or "Japan" in lang:
            target_name = "ja"
        else:
            target_name = "cn"

        possible_paths = [
            os.path.join(self.models_dir, target_name),
            os.path.join(self.models_dir, f"vosk-model-small-{target_name}-0.4" if target_name == "id" else f"vosk-model-small-{target_name}-0.22"),
            os.path.join(self.project_root, target_name),
            os.path.join(self.base_dir, target_name)
        ]

        if os.path.exists(self.models_dir):
            for item in os.listdir(self.models_dir):
                item_path = os.path.join(self.models_dir, item)
                if os.path.isdir(item_path) and target_name in item.lower():
                    return item_path

        for p in possible_paths:
            if os.path.exists(p):
                return p

        return None

    def toggle_transcription(self):
        if self.is_transcribing:
            if self.process:
                self.process.terminate()
            self.is_transcribing = False
            self.btn_start.config(text="▶️ Mulai Transkripsi")
            self.progress.stop()
            self.status_var.set("Transkripsi dihentikan pengguna.")
            return

        self.video_path = self.entry_video.get().strip()
        if not self.video_path or not os.path.exists(self.video_path):
            messagebox.showerror("Error", "File video tidak ditemukan! Silakan klik 'Buka File'.")
            return

        mode = self.mode_var.get()
        model_path = None

        if mode == "offline":
            model_path = self.get_model_path()
            if not model_path:
                if "Indonesia" in self.lang_var.get():
                    resp = messagebox.askyesno(
                        "Beralih ke Mode Online",
                        "Model offline Vosk resmi untuk Bahasa Indonesia tidak tersedia di server Vosk.\n\n"
                        "Namun Anda dapat menggunakan 'Mode Online (Google Speech API)' secara GRATIS & berakurasi tinggi tanpa perlu API key.\n\n"
                        "Apakah Anda ingin langsung beralih ke Mode Online sekarang?"
                    )
                    if resp:
                        self.mode_var.set("online")
                        self.on_mode_change()
                        mode = "online"
                    else:
                        return
                else:
                    messagebox.showerror(
                        "Model Tidak Ditemukan",
                        f"Model offline Vosk untuk {self.lang_var.get()} belum ditemukan.\n\n"
                        f"Silakan unduh model Vosk lewat skrip 'Pasang_Model_Otomatis.bat'\n"
                        f"atau beralih ke 'Mode Online'."
                    )
                    return

        self.is_transcribing = True
        self.btn_start.config(text="⏹️ Hentikan Transkripsi")
        self.progress.start(10)
        self.txt_display.delete("1.0", tk.END)
        self.txt_display.insert(tk.END, f"=== MEMULAI TRANSKRIPSI VIDEO ({mode.upper()}) DARI DETIK KE-0 SAMPAI SELESAI ===\n")
        self.txt_display.insert(tk.END, f"File Video : {self.video_path}\n")
        self.txt_display.insert(tk.END, f"Bahasa     : {self.lang_var.get()}\n")
        self.txt_display.insert(tk.END, f"Mode Mesin : {'🔒 Offline (Vosk)' if mode == 'offline' else '🌐 Online (Google Speech API)'}\n")
        self.txt_display.insert(tk.END, f"File Nota     : {self.output_txt_path}\n")
        self.txt_display.insert(tk.END, f"File Subtitle : {self.output_srt_path}\n")
        self.txt_display.insert(tk.END, f"Metode        : Streaming audio on-the-fly via RAM Buffer (tanpa file audio terpisah di disk)\n\n")

        if mode == "offline":
            thread = threading.Thread(target=self.run_offline_transcription, args=(model_path,), daemon=True)
        else:
            thread = threading.Thread(target=self.run_online_transcription, daemon=True)
        thread.start()

    def run_offline_transcription(self, model_path):
        try:
            from vosk import Model, KaldiRecognizer, SetLogLevel
            SetLogLevel(-1)
        except ImportError:
            self.root.after(0, lambda: messagebox.showerror(
                "Dependensi Hilang",
                "Library 'vosk' belum terpasang.\nJalankan: pip install vosk"
            ))
            self.stop_processing("Gagal: vosk belum terinstall.")
            return

        ffmpeg_bin = self.find_ffmpeg_executable()
        if not ffmpeg_bin:
            self.root.after(0, lambda: messagebox.showerror(
                "FFmpeg Belum Terpasang",
                "Program 'FFmpeg' belum ditemukan di komputer Anda.\n\n"
                "FFmpeg diperlukan untuk memutar dan mengekstrak audio video secara langsung.\n\n"
                "Solusi Mudah:\n"
                "Jalankan file 'Pasang_FFmpeg_Otomatis.bat' di folder aplikasi ini,\n"
                "lalu ulangi klik 'Mulai Transkripsi'."
            ))
            self.stop_processing("Gagal: FFmpeg belum terpasang.")
            return

        try:
            self.status_var.set("Memuat model Vosk offline ke memori...")
            model = Model(model_path)
            rec = KaldiRecognizer(model, 16000.0)
            rec.SetWords(True)

            self.status_var.set("Streaming audio langsung dari video secara offline...")

            ffmpeg_cmd = [
                ffmpeg_bin,
                "-loglevel", "quiet",
                "-i", self.video_path,
                "-ar", "16000",
                "-ac", "1",
                "-f", "s16le",
                "-"
            ]

            with open(self.output_txt_path, "w", encoding="utf-8") as f_out:
                f_out.write(f"=== NOTA CATATAN TRANSKRIPSI VIDEO (OFFLINE) ===\n")
                f_out.write(f"File Video: {self.video_path}\n")
                f_out.write(f"Bahasa: {self.lang_var.get()}\n")
                f_out.write(f"-----------------------------------------\n\n")

            with open(self.output_srt_path, "w", encoding="utf-8") as f_srt:
                pass
            srt_index = 1

            self.process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=4000
            )

            total_bytes = 0
            while self.is_transcribing:
                data = self.process.stdout.read(4000)
                if len(data) == 0:
                    break

                total_bytes += len(data)
                current_sec = total_bytes / 32000.0

                if rec.AcceptWaveform(data):
                    res = json.loads(rec.Result())
                    text = res.get("text", "").strip()
                    if text:
                        words = res.get("result", [])
                        if words and "start" in words[0] and "end" in words[-1]:
                            start_sec = words[0]["start"]
                            end_sec = words[-1]["end"]
                            timestamp = self.format_time(start_sec)
                        else:
                            start_sec = max(0.0, current_sec - 3.5)
                            end_sec = current_sec
                            timestamp = self.format_time(current_sec)

                        formatted_line = f"{timestamp} {text}" if self.var_timestamp.get() else text
                        self.append_text(formatted_line + "\n")
                        with open(self.output_txt_path, "a", encoding="utf-8") as f_out:
                            f_out.write(formatted_line + "\n")

                        # Simpan ke format SubRip Subtitle (.SRT)
                        srt_block = f"{srt_index}\n{self.format_srt_time(start_sec)} --> {self.format_srt_time(end_sec)}\n{text}\n\n"
                        with open(self.output_srt_path, "a", encoding="utf-8") as f_srt:
                            f_srt.write(srt_block)
                        srt_index += 1

            final_res = json.loads(rec.FinalResult())
            final_text = final_res.get("text", "").strip()
            if final_text:
                final_end = total_bytes / 32000.0
                final_start = max(0.0, final_end - 3.0)
                final_timestamp = self.format_time(final_end)
                formatted_line = f"{final_timestamp} {final_text}" if self.var_timestamp.get() else final_text
                self.append_text(formatted_line + "\n")
                with open(self.output_txt_path, "a", encoding="utf-8") as f_out:
                    f_out.write(formatted_line + "\n")

                srt_block = f"{srt_index}\n{self.format_srt_time(final_start)} --> {self.format_srt_time(final_end)}\n{final_text}\n\n"
                with open(self.output_srt_path, "a", encoding="utf-8") as f_srt:
                    f_srt.write(srt_block)
                srt_index += 1

            if self.is_transcribing:
                self.append_text("\n=== TRANSKRIPSI OFFLINE SELESAI DENGAN SUKSES ===\n")
                self.status_var.set(f"Selesai! Nota & Subtitle (.srt) tersimpan.")
                self.root.after(0, lambda: messagebox.showinfo(
                    "Selesai",
                    f"Transkripsi video offline selesai!\n\n"
                    f"1. Nota TXT: {self.output_txt_path}\n"
                    f"2. Subtitle SRT: {self.output_srt_path}\n\n"
                    f"Klik 'Baca Subtitle (.SRT)' atau 'Baca Nota' untuk melihat."
                ))
        except Exception as e:
            self.append_text(f"\n[Terjadi Kesalahan]: {str(e)}\n")
            self.status_var.set(f"Error: {str(e)}")
        finally:
            self.stop_processing()

    def run_online_transcription(self):
        """
        Mode Online: Streaming chunk audio (10-15 detik) on-the-fly di dalam RAM (BytesIO)
        tanpa pernah menyimpan file audio sementara ke disk, lalu mengirim ke Google Speech API.
        """
        try:
            import speech_recognition as sr
        except ImportError:
            # Install speech_recognition otomatis jika belum ada
            subprocess.run([sys.executable, "-m", "pip", "install", "SpeechRecognition", "--quiet"])
            try:
                import speech_recognition as sr
            except Exception:
                self.root.after(0, lambda: messagebox.showerror(
                    "Dependensi Online Hilang",
                    "Library 'SpeechRecognition' belum terpasang.\nJalankan: pip install SpeechRecognition"
                ))
                self.stop_processing("Gagal: SpeechRecognition belum terpasang.")
                return

        ffmpeg_bin = self.find_ffmpeg_executable()
        if not ffmpeg_bin:
            self.root.after(0, lambda: messagebox.showerror(
                "FFmpeg Belum Terpasang",
                "Program 'FFmpeg' belum ditemukan di komputer Anda.\n\n"
                "FFmpeg diperlukan untuk memutar dan mengekstrak audio video secara langsung.\n\n"
                "Solusi Mudah:\n"
                "Jalankan file 'Pasang_FFmpeg_Otomatis.bat' di folder aplikasi ini,\n"
                "lalu ulangi klik 'Mulai Transkripsi'."
            ))
            self.stop_processing("Gagal: FFmpeg belum terpasang.")
            return
        recognizer = sr.Recognizer()

        # Kode bahasa Google Speech Recognition
        lang_str = self.lang_var.get()
        if "Indonesia" in lang_str:
            lang_code = "id-ID"
        elif "Jepang" in lang_str or "Japan" in lang_str:
            lang_code = "ja-JP"
        else:
            lang_code = "zh-CN"

        try:
            self.status_var.set("Menghubungkan ke layanan online streaming audio...")

            with open(self.output_txt_path, "w", encoding="utf-8") as f_out:
                f_out.write(f"=== NOTA CATATAN TRANSKRIPSI VIDEO (ONLINE GOOGLE SPEECH) ===\n")
                f_out.write(f"File Video: {self.video_path}\n")
                f_out.write(f"Bahasa: {self.lang_var.get()} ({lang_code})\n")
                f_out.write(f"-----------------------------------------------------------\n\n")

            with open(self.output_srt_path, "w", encoding="utf-8") as f_srt:
                pass
            srt_index = 1

            ffmpeg_cmd = [
                ffmpeg_bin,
                "-loglevel", "quiet",
                "-i", self.video_path,
                "-ar", "16000",
                "-ac", "1",
                "-f", "s16le",
                "-"
            ]

            self.process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                bufsize=32000
            )

            # 16000 sample/sec * 2 byte = 32000 bytes/sec
            # Ambil chunk per 10 detik = 320,000 bytes di memori RAM
            chunk_seconds = 10
            bytes_per_chunk = 32000 * chunk_seconds
            total_bytes = 0

            while self.is_transcribing:
                raw_chunk = self.process.stdout.read(bytes_per_chunk)
                if not raw_chunk or len(raw_chunk) == 0:
                    break

                chunk_start_sec = total_bytes / 32000.0
                chunk_len_sec = len(raw_chunk) / 32000.0
                chunk_end_sec = chunk_start_sec + chunk_len_sec
                total_bytes += len(raw_chunk)
                timestamp = self.format_time(chunk_start_sec)

                # Konversi raw PCM byte langsung di RAM ke format AudioData SpeechRecognition
                audio_data = sr.AudioData(raw_chunk, 16000, 2)

                try:
                    self.status_var.set(f"Mentranskripsikan online {timestamp}...")
                    # Google Web Speech Recognition (Free online API)
                    text = recognizer.recognize_google(audio_data, language=lang_code).strip()
                    if text:
                        formatted_line = f"{timestamp} {text}" if self.var_timestamp.get() else text
                        self.append_text(formatted_line + "\n")
                        with open(self.output_txt_path, "a", encoding="utf-8") as f_out:
                            f_out.write(formatted_line + "\n")

                        # Simpan ke format SubRip Subtitle (.SRT)
                        srt_block = f"{srt_index}\n{self.format_srt_time(chunk_start_sec)} --> {self.format_srt_time(chunk_end_sec)}\n{text}\n\n"
                        with open(self.output_srt_path, "a", encoding="utf-8") as f_srt:
                            f_srt.write(srt_block)
                        srt_index += 1
                except sr.UnknownValueError:
                    # Hening atau tidak ada kata terdeteksi pada potongan ini (skip)
                    pass
                except sr.RequestError as e:
                    self.append_text(f"{timestamp} [Koneksi Internet Terganggu]: {str(e)}\n")

            if self.is_transcribing:
                self.append_text("\n=== TRANSKRIPSI ONLINE SELESAI DENGAN SUKSES ===\n")
                self.status_var.set(f"Selesai! Nota & Subtitle (.srt) tersimpan.")
                self.root.after(0, lambda: messagebox.showinfo(
                    "Selesai",
                    f"Transkripsi video online selesai!\n\n"
                    f"1. Nota TXT: {self.output_txt_path}\n"
                    f"2. Subtitle SRT: {self.output_srt_path}\n\n"
                    f"Klik 'Baca Subtitle (.SRT)' atau 'Baca Nota' untuk melihat."
                ))
        except Exception as e:
            self.append_text(f"\n[Terjadi Kesalahan Online]: {str(e)}\n")
            self.status_var.set(f"Error: {str(e)}")
        finally:
            self.stop_processing()

    def append_text(self, text):
        def _update():
            self.txt_display.insert(tk.END, text)
            self.txt_display.see(tk.END)
        self.root.after(0, _update)

    def stop_processing(self, status_msg=None):
        def _stop():
            self.is_transcribing = False
            self.btn_start.config(text="▶️ Mulai Transkripsi")
            self.progress.stop()
            if status_msg:
                self.status_var.set(status_msg)
        self.root.after(0, _stop)

    def read_note(self):
        target_path = self.output_txt_path if self.output_txt_path else ""
        if not target_path or not os.path.exists(target_path):
            target_path = filedialog.askopenfilename(
                title="Pilih File Nota Catatan Transkripsi (.txt)",
                filetypes=[("Text File", "*.txt"), ("Semua File", "*.*")]
            )

        if target_path and os.path.exists(target_path):
            try:
                if sys.platform.startswith("win"):
                    os.startfile(target_path)
                elif sys.platform.startswith("darwin"):
                    subprocess.Popen(["open", target_path])
                else:
                    subprocess.Popen(["xdg-open", target_path])
            except Exception:
                self.show_note_window(target_path)
        else:
            messagebox.showwarning("Nota Belum Ada", "File nota belum tersedia. Silakan jalankan transkripsi terlebih dahulu atau pilih file nota yang ada.")

    def read_srt(self):
        target_path = self.output_srt_path if self.output_srt_path else ""
        if not target_path or not os.path.exists(target_path):
            target_path = filedialog.askopenfilename(
                title="Pilih File Subtitle Video (.srt)",
                filetypes=[("Subtitle SubRip", "*.srt"), ("Semua File", "*.*")]
            )

        if target_path and os.path.exists(target_path):
            try:
                if sys.platform.startswith("win"):
                    os.startfile(target_path)
                elif sys.platform.startswith("darwin"):
                    subprocess.Popen(["open", target_path])
                else:
                    subprocess.Popen(["xdg-open", target_path])
            except Exception:
                self.show_note_window(target_path)
        else:
            messagebox.showwarning("Subtitle Belum Ada", "File subtitle (.srt) belum tersedia. Silakan jalankan transkripsi terlebih dahulu atau pilih file subtitle yang ada.")

    def clear_display(self):
        if messagebox.askyesno("Konfirmasi Hapus", "Bersihkan seluruh teks hasil transkripsi di layar?"):
            self.txt_display.delete("1.0", tk.END)
            self.status_var.set("Layar transkripsi telah dibersihkan.")

    def show_note_window(self, file_path):
        note_win = tk.Toplevel(self.root)
        note_win.title(f"Baca Nota: {os.path.basename(file_path)}")
        note_win.geometry("650x500")

        txt = scrolledtext.ScrolledText(note_win, wrap=tk.WORD, font=("Consolas", 10))
        txt.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            txt.insert(tk.END, f.read())

if __name__ == "__main__":
    root = tk.Tk()
    app = TranskripsiApp(root)
    root.mainloop()
