# 🎙️ Aplikasi Transkripsi Video Hybrid (Offline & Online)

Aplikasi desktop lengkap dengan **antarmuka grafis (GUI)** sederhana untuk mentranskripsi file video berdurasi panjang dari detik/jam ke-0 sampai selesai dengan dua pilihan mode:
1. 🔒 **Mode Offline**: Menggunakan mesin **Vosk Lokal** (100% tanpa internet, tanpa OpenAI, tanpa API berbayar).
2. 🌐 **Mode Online**: Menggunakan layanan **Google Speech Recognition** (gratis, akurasi tinggi, tanpa perlu download model lokal).

Tersedia dalam **6 bahasa pemrograman / scripting**:
1. 🐍 **Python** (`Tkinter GUI` - Mendukung Offline & Online)
2. ⚡ **C++** (`Win32 Native GUI` + Vosk C API)
3. 🐚 **PowerShell & Bash Script** (`Windows Forms GUI` & `Zenity GUI` - Mendukung Offline & Online)
4. ☕ **Java** (`Java Swing GUI`)
5. 🔷 **C# (.NET)** (`WinForms GUI`)
6. 🍏 **Swift & Objective-C** (`macOS Cocoa / AppKit GUI`)

---

## 🌟 Fitur Utama & Kepatuhan Ketentuan

| Fitur | Keterangan |
| :--- | :--- |
| **Pilihan Mode (Offline / Online)** | Pilih fleksibel antara **Offline** (hemat kuota, privasi penuh) atau **Online** (Google Speech API gratis berakurasi tinggi). |
| **GUI Interaktif "Buka File"** | Tombol Browse bawaan untuk memilih file video (`.mp4`, `.mkv`, `.avi`, `.mov`, `.webm`, dll.). |
| **Streaming On-The-Fly (Tanpa File Audio Terpisah)** | Menggunakan pipa langsung (`pipe`) dari FFmpeg ke buffer memori RAM. **Tidak membuat file `.wav`/`.mp3` perantara di harddisk**, sehingga menghemat ruang penyimpanan untuk video berdurasi berjam-jam (zero disk bloat). |
| **Pilihan Bahasa** | Mendukung **Bahasa Indonesia** dan **Bahasa Mandarin (China)**. |
| **Penanda Waktu Jam `[HH:MM:SS]`** | Setiap baris kalimat dilengkapi penanda waktu video dari jam ke-0 sampai selesai. |
| **Ekspor Subtitle (.SRT) Standar** | Otomatis menghasilkan subtitle berformat SubRip (`.srt`) lengkap dengan penomoran urut dan rentang waktu milidetik (`00:00:01,200 --> 00:00:04,500`), siap dipakai di pemutar video seperti VLC, YouTube, dan Windows Media Player. |
| **Baca Nota & Simpan Otomatis** | Hasil langsung tampil secara streaming real-time pada layar aplikasi, otomatis tersimpan ke file catatan teks (`<nama_video>_transkripsi.txt`) dan subtitle (`<nama_video>_subtitle.srt`), serta dilengkapi tombol interaktif **"📝 Baca Nota (.TXT)"** dan **"🎬 Baca Subtitle (.SRT)"**. |

---

```

---

## 🚀 Cara Menjalankan

### 1. Mode Online (Tanpa Perlu Unduh Model)
Jika Anda memilih **Mode Online**, Anda tidak perlu mengunduh model offline sebesar 40MB:
1. Klik ganda [`Jalankan_Python.bat`](file:///c:/Jalankan_PowerShell.bat).
2. Pilih opsi **"🌐 Online (Google Speech API)"**.
3. Klik **"📁 Buka File"** untuk memilih video `.mp4`/`.mkv`.
4. Klik **"▶️ Mulai Transkripsi"**.

### 2. Mode Offline (100% Tanpa Internet)
Jika ingin menjalankan tanpa koneksi internet sama sekali:
1. Unduh model offline sekali saja: klik ganda [`Pasang_Model_Otomatis.bat`](file:///c:/Documents/transkripsi%20video/Pasang_Model_Otomatis.bat).
2. Buka aplikasi, pilih **"🔒 Offline (Vosk Lokal)"**.
3. Pilih video dan klik **"▶️ Mulai Transkripsi"**.

---

## 💡 Mekanisme Kerja Streaming On-The-Fly
Seluruh program menggunakan prinsip streaming langsung:
$$\text{File Video (.mp4 / .mkv)} \xrightarrow[\text{quiet}]{\text{FFmpeg Pipe}} \text{PCM 16-bit 16000Hz (RAM Buffer)} \xrightarrow{} \begin{cases} \text{Vosk Offline Engine} \\ \text{Google Speech Online API} \end{cases} \xrightarrow{} \text{Layar GUI \& File Nota .txt}$$

* **Nol Penyimpanan Sementara**: Audio tidak diekstrak sebagai file terpisah ke SSD/HDD.
* **Transkripsi Berkelanjutan**: Mengalir dari detik ke-0 sampai video berdurasi jam-jaman tuntas.
