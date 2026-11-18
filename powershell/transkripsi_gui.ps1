<#
.SYNOPSIS
    Aplikasi Transkripsi Video Hybrid (Offline & Online) - PowerShell GUI (Windows Forms)
    - Mode Offline : Mesin Vosk (tanpa internet)
    - Mode Online  : Google Speech API (gratis & akurat)
    Streaming audio on-the-fly via FFmpeg pipe (tanpa file audio terpisah di disk).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Pastikan konsol dan pipeline PowerShell menggunakan UTF-8
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Runner proses asinkron C# langsung ke WinForms UI (mencegah deadlock & UI freeze saat ShowDialog)
Add-Type -ReferencedAssemblies "System.Windows.Forms" @"
using System;
using System.Diagnostics;
using System.Windows.Forms;
using System.Text;

public class TranscriptionProcessRunner {
    public static Process Run(string fileName, string args, TextBox txtOutput, Action onComplete) {
        var p = new Process();
        p.StartInfo.FileName = fileName;
        p.StartInfo.Arguments = args;
        p.StartInfo.UseShellExecute = false;
        p.StartInfo.RedirectStandardOutput = true;
        p.StartInfo.RedirectStandardError = true;
        p.StartInfo.CreateNoWindow = true;
        p.EnableRaisingEvents = true;
        p.StartInfo.StandardOutputEncoding = Encoding.UTF8;
        p.StartInfo.StandardErrorEncoding = Encoding.UTF8;
        try {
            p.StartInfo.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            p.StartInfo.EnvironmentVariables["PYTHONUTF8"] = "1";
        } catch {}

        p.OutputDataReceived += (s, e) => {
            if (e.Data != null && txtOutput != null && !txtOutput.IsDisposed) {
                txtOutput.BeginInvoke(new Action(() => {
                    txtOutput.AppendText(e.Data + "\r\n");
                    txtOutput.SelectionStart = txtOutput.Text.Length;
                    txtOutput.ScrollToCaret();
                }));
            }
        };

        p.ErrorDataReceived += (s, e) => {
            if (e.Data != null && txtOutput != null && !txtOutput.IsDisposed) {
                txtOutput.BeginInvoke(new Action(() => {
                    txtOutput.AppendText("[Log] " + e.Data + "\r\n");
                    txtOutput.SelectionStart = txtOutput.Text.Length;
                    txtOutput.ScrollToCaret();
                }));
            }
        };

        p.Exited += (s, e) => {
            if (txtOutput != null && !txtOutput.IsDisposed) {
                txtOutput.BeginInvoke(new Action(() => {
                    txtOutput.AppendText("\r\n=== TRANSKRIPSI SELESAI DENGAN SUKSES ===\r\n");
                    txtOutput.SelectionStart = txtOutput.Text.Length;
                    txtOutput.ScrollToCaret();
                    if (onComplete != null) {
                        try { onComplete(); } catch {}
                    }
                }));
            }
        };

        p.Start();
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        return p;
    }
}
"@

# Pastikan folder tools (ffmpeg.exe) masuk ke PATH
$toolsDir = Join-Path $PSScriptRoot "..\tools"
if (Test-Path $toolsDir) {
    $env:PATH = "$toolsDir;$env:PATH"
}

# Inisialisasi Form Utama
$form = New-Object System.Windows.Forms.Form
$form.Text = "Transkripsi Video Hybrid (Offline & Online) - PowerShell GUI"
$form.Size = New-Object System.Drawing.Size(860, 700)
$form.MinimumSize = New-Object System.Drawing.Size(720, 520)
$form.StartPosition = "CenterScreen"

# GroupBox Pengaturan
$grpConfig = New-Object System.Windows.Forms.GroupBox
$grpConfig.Text = " Pengaturan Transkripsi Video "
$grpConfig.Location = New-Object System.Drawing.Point(15, 12)
$grpConfig.Size = New-Object System.Drawing.Size(815, 155)
$grpConfig.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

# Baris 0: Pilihan Mode Mesin
$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "Mode Mesin:"
$lblMode.Location = New-Object System.Drawing.Point(15, 24)
$lblMode.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$lblMode.AutoSize = $true
$grpConfig.Controls.Add($lblMode)

$hasIdModel = (Test-Path "$PSScriptRoot\..\models\id\am") -or (Test-Path "$PSScriptRoot\models\id\am")
$rbOffline = New-Object System.Windows.Forms.RadioButton
$rbOffline.Text = "Offline (Vosk Lokal)"
$rbOffline.Location = New-Object System.Drawing.Point(160, 22)
$rbOffline.Size = New-Object System.Drawing.Size(180, 22)
$rbOffline.Checked = $hasIdModel
$grpConfig.Controls.Add($rbOffline)

$rbOnline = New-Object System.Windows.Forms.RadioButton
$rbOnline.Text = "Online (Google Speech API)"
$rbOnline.Location = New-Object System.Drawing.Point(350, 22)
$rbOnline.Size = New-Object System.Drawing.Size(220, 22)
$rbOnline.Checked = -not $hasIdModel
$grpConfig.Controls.Add($rbOnline)

# Baris 1: File Video (.mp4/.mkv)
$lblVideo = New-Object System.Windows.Forms.Label
$lblVideo.Text = "File Video (.mp4/.mkv):"
$lblVideo.Location = New-Object System.Drawing.Point(15, 54)
$lblVideo.AutoSize = $true
$grpConfig.Controls.Add($lblVideo)

$txtVideo = New-Object System.Windows.Forms.TextBox
$txtVideo.Location = New-Object System.Drawing.Point(160, 51)
$txtVideo.Size = New-Object System.Drawing.Size(515, 23)
$txtVideo.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$grpConfig.Controls.Add($txtVideo)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Buka File..."
$btnBrowse.Location = New-Object System.Drawing.Point(685, 49)
$btnBrowse.Size = New-Object System.Drawing.Size(115, 27)
$btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$grpConfig.Controls.Add($btnBrowse)

# Baris 2: Pilihan Bahasa
$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Text = "Pilihan Bahasa:"
$lblLang.Location = New-Object System.Drawing.Point(15, 87)
$lblLang.AutoSize = $true
$grpConfig.Controls.Add($lblLang)

$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(160, 84)
$cmbLang.Size = New-Object System.Drawing.Size(220, 23)
$cmbLang.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbLang.Items.Add("Bahasa Indonesia")
[void]$cmbLang.Items.Add("Bahasa Mandarin (China)")
[void]$cmbLang.Items.Add("Bahasa Jepang (Japan)")
$cmbLang.SelectedIndex = 0
$grpConfig.Controls.Add($cmbLang)

# Baris 3: Tombol Aksi
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Mulai Transkripsi"
$btnStart.Location = New-Object System.Drawing.Point(160, 115)
$btnStart.Size = New-Object System.Drawing.Size(145, 32)
$grpConfig.Controls.Add($btnStart)

$btnReadNote = New-Object System.Windows.Forms.Button
$btnReadNote.Text = "Baca Nota (.TXT)"
$btnReadNote.Location = New-Object System.Drawing.Point(315, 115)
$btnReadNote.Size = New-Object System.Drawing.Size(150, 32)
$grpConfig.Controls.Add($btnReadNote)

$btnReadSrt = New-Object System.Windows.Forms.Button
$btnReadSrt.Text = "Baca Subtitle (.SRT)"
$btnReadSrt.Location = New-Object System.Drawing.Point(475, 115)
$btnReadSrt.Size = New-Object System.Drawing.Size(165, 32)
$grpConfig.Controls.Add($btnReadSrt)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "Hapus Layar"
$btnClear.Location = New-Object System.Drawing.Point(645, 115)
$btnClear.Size = New-Object System.Drawing.Size(120, 32)
$grpConfig.Controls.Add($btnClear)

$form.Controls.Add($grpConfig)

# Label Status
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Siap. Silakan klik 'Buka File' untuk memilih video."
$lblStatus.Location = New-Object System.Drawing.Point(15, 172)
$lblStatus.Size = New-Object System.Drawing.Size(815, 20)
$lblStatus.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($lblStatus)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 194)
$progressBar.Size = New-Object System.Drawing.Size(815, 16)
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($progressBar)

# GroupBox Output
$grpOutput = New-Object System.Windows.Forms.GroupBox
$grpOutput.Text = " Hasil Transkripsi (Streaming On-The-Fly Langsung) "
$grpOutput.Location = New-Object System.Drawing.Point(15, 220)
$grpOutput.Size = New-Object System.Drawing.Size(815, 430)
$grpOutput.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtOutput.ReadOnly = $true
$txtOutput.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtOutput.Font = New-Object System.Drawing.Font("Consolas", 10)
$grpOutput.Controls.Add($txtOutput)
$form.Controls.Add($grpOutput)

# State Variabel
$script:outputTxtPath = ""
$script:outputSrtPath = ""
$script:isTranscribing = $false
$script:transcriptionProcess = $null

# Event: Buka File Video
$btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Pilih File Video Berdurasi Panjang"
    $ofd.Filter = "File Video (*.mp4;*.mkv;*.avi;*.mov;*.flv;*.webm)|*.mp4;*.mkv;*.avi;*.mov;*.flv;*.webm|Semua File (*.*)|*.*"
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtVideo.Text = $ofd.FileName
        $dir = [System.IO.Path]::GetDirectoryName($ofd.FileName)
        $nameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($ofd.FileName)
        $script:outputTxtPath = [System.IO.Path]::Combine($dir, "$($nameNoExt)_transkripsi.txt")
        $script:outputSrtPath = [System.IO.Path]::Combine($dir, "$($nameNoExt)_subtitle.srt")
        $lblStatus.Text = "File dipilih. Nota (.txt) & Subtitle (.srt) siap dibuat."
    }
})

# Event: Baca Nota
$btnReadNote.Add_Click({
    $targetPath = $script:outputTxtPath
    if (-not $targetPath -or -not (Test-Path $targetPath)) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "Buka File Nota Catatan Transkripsi (.txt)"
        $ofd.Filter = "File Teks (*.txt)|*.txt|Semua File (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetPath = $ofd.FileName
        } else {
            return
        }
    }

    if (Test-Path $targetPath) {
        Start-Process "notepad.exe" -ArgumentList "`"$targetPath`""
    } else {
        [System.Windows.Forms.MessageBox]::Show("File nota belum ditemukan.", "Peringatan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

# Event: Baca Subtitle (.SRT)
$btnReadSrt.Add_Click({
    $targetPath = $script:outputSrtPath
    if (-not $targetPath -or -not (Test-Path $targetPath)) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = "Buka File Subtitle Video (.srt)"
        $ofd.Filter = "File Subtitle (*.srt)|*.srt|Semua File (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $targetPath = $ofd.FileName
        } else {
            return
        }
    }

    if (Test-Path $targetPath) {
        Start-Process "notepad.exe" -ArgumentList "`"$targetPath`""
    } else {
        [System.Windows.Forms.MessageBox]::Show("File subtitle (.srt) belum ditemukan.", "Peringatan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
})

# Event: Hapus Layar
$btnClear.Add_Click({
    $result = [System.Windows.Forms.MessageBox]::Show("Bersihkan seluruh hasil transkripsi di layar?", "Konfirmasi Hapus", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $txtOutput.Clear()
        $lblStatus.Text = "Status: Layar transkripsi telah dibersihkan."
    }
})

# Pencarian Model Vosk
function Get-VoskModelPath([string]$lang) {
    $code = if ($lang -like "*Indonesia*") { "id" } elseif ($lang -like "*Jepang*" -or $lang -like "*Japan*") { "ja" } else { "cn" }
    $possiblePaths = @(
        "$PSScriptRoot\..\models\$code",
        "$PSScriptRoot\models\$code",
        "$PSScriptRoot\..\models\vosk-model-small-$code-0.4",
        "$PSScriptRoot\..\models\vosk-model-small-$code-0.22",
        "$PSScriptRoot\..\models"
    )

    foreach ($p in $possiblePaths) {
        if (Test-Path $p) {
            if ($p -match $code) { return $p }
            $subs = Get-ChildItem -Path $p -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$code*" }
            if ($subs) { return $subs[0].FullName }
        }
    }
    return $null
}

# Event: Mulai / Berhenti Transkripsi
$btnStart.Add_Click({
    if ($script:isTranscribing) {
        $script:isTranscribing = $false
        if ($script:transcriptionProcess -and -not $script:transcriptionProcess.HasExited) {
            try { $script:transcriptionProcess.Kill() } catch {}
        }
        $btnStart.Text = "Mulai Transkripsi"
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $lblStatus.Text = "Transkripsi dihentikan."
        return
    }

    $videoPath = $txtVideo.Text.Trim()
    if (-not (Test-Path $videoPath)) {
        [System.Windows.Forms.MessageBox]::Show("Silakan pilih file video yang valid terlebih dahulu!", "File Tidak Ditemukan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $isOnline = $rbOnline.Checked
    $modeStr = if ($isOnline) { "online" } else { "offline" }
    $modeDisplay = if ($isOnline) { "Online (Google Speech API)" } else { "Offline (Vosk Lokal)" }
    $modelPath = ""

    if (-not $isOnline) {
        $modelPath = Get-VoskModelPath -lang $cmbLang.SelectedItem
        if (-not $modelPath) {
            if ($cmbLang.SelectedItem -like "*Indonesia*") {
                $switchResp = [System.Windows.Forms.MessageBox]::Show("Model offline Vosk resmi untuk Bahasa Indonesia tidak tersedia di server Vosk.`n`nNamun Anda dapat menggunakan 'Mode Online (Google Speech API)' secara GRATIS & berakurasi tinggi tanpa perlu API key.`n`nApakah Anda ingin langsung beralih ke Mode Online sekarang?", "Beralih ke Mode Online", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                if ($switchResp -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $rbOnline.Checked = $true
                    $isOnline = $true
                    $modeStr = "online"
                    $modeDisplay = "Online (Google Speech API)"
                } else {
                    return
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Model Vosk untuk $($cmbLang.SelectedItem) belum ditemukan di folder 'models/'.`nSilakan klik 'Pasang_Model_Otomatis.bat' atau gunakan 'Mode Online'.", "Model Tidak Ditemukan", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
        }
    }

    $script:isTranscribing = $true
    $btnStart.Text = "Hentikan Transkripsi"
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $txtOutput.Clear()
    
    $txtOutput.AppendText("=== MEMULAI TRANSKRIPSI VIDEO ($($modeStr.ToUpper())) DARI DETIK KE-0 SAMPAI SELESAI ===`r`n")
    $txtOutput.AppendText("File Video    : $videoPath`r`n")
    $txtOutput.AppendText("Bahasa        : $($cmbLang.SelectedItem)`r`n")
    $txtOutput.AppendText("Mode Mesin    : $modeDisplay`r`n")
    $txtOutput.AppendText("File Nota     : $script:outputTxtPath`r`n")
    $txtOutput.AppendText("File Subtitle : $script:outputSrtPath`r`n")
    $txtOutput.AppendText("Mode          : Streaming audio on-the-fly via FFmpeg pipe (tanpa file audio terpisah)`r`n`r`n")

    # Inisialisasi file nota dan subtitle
    "=== NOTA CATATAN TRANSKRIPSI VIDEO ($($modeStr.ToUpper())) ===`r`nFile Video: $videoPath`r`nBahasa: $($cmbLang.SelectedItem)`r`n----------------------------------------`r`n`r`n" | Out-File -FilePath $script:outputTxtPath -Encoding utf8
    "" | Out-File -FilePath $script:outputSrtPath -Encoding utf8

    $lblStatus.Text = "Memproses streaming audio video secara $($modeStr)..."

    # Embedded hybrid runner
    $pyScript = @'
import sys, os, json, subprocess, shutil, io

# Paksa encoding UTF-8 untuk output di Windows agar mendukung karakter multi-bahasa (Mandarin, Jepang, dll.)
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
else:
    try:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')
    except Exception:
        pass

def safe_print(text):
    try:
        print(text, flush=True)
    except Exception:
        try:
            sys.stdout.buffer.write((str(text) + '\n').encode('utf-8', errors='replace'))
            sys.stdout.flush()
        except Exception:
            pass

mode = sys.argv[1]
video_path = sys.argv[2]
lang_name = sys.argv[3]
raw_model = sys.argv[4]
model_path = "" if raw_model == "none" else raw_model
out_txt = sys.argv[5]
out_srt = sys.argv[6]

ffmpeg_bin = shutil.which('ffmpeg')
if not ffmpeg_bin:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(os.getcwd(), 'tools', 'ffmpeg.exe'),
        os.path.join(script_dir, '..', 'tools', 'ffmpeg.exe'),
        r'C:\Users\Admin\Documents\transkripsi video\tools\ffmpeg.exe'
    ]
    for c in candidates:
        if os.path.exists(c):
            ffmpeg_bin = c
            break
if not ffmpeg_bin:
    ffmpeg_bin = 'ffmpeg'

cmd = [ffmpeg_bin, '-loglevel', 'error', '-i', video_path, '-ar', '16000', '-ac', '1', '-f', 's16le', '-']
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=32000)

def format_time(sec):
    h, m, s = int(sec // 3600), int((sec % 3600) // 60), int(sec % 60)
    return f"[{h:02d}:{m:02d}:{s:02d}]"

def format_srt_time(sec):
    if sec is None or sec < 0: sec = 0.0
    h, m, s = int(sec // 3600), int((sec % 3600) // 60), int(sec % 60)
    ms = int(round((sec - int(sec)) * 1000))
    if ms >= 1000: ms = 999
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

srt_idx = 1

if mode == "online":
    try:
        import speech_recognition as sr
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", "SpeechRecognition", "--quiet"])
        import speech_recognition as sr

    recognizer = sr.Recognizer()
    if "Indonesia" in lang_name:
        lang_code = "id-ID"
    elif "Jepang" in lang_name or "Japan" in lang_name:
        lang_code = "ja-JP"
    else:
        lang_code = "zh-CN"
    chunk_bytes = 32000 * 8 # 8 detik per potongan audio
    total_bytes = 0

    while True:
        raw_chunk = p.stdout.read(chunk_bytes)
        if not raw_chunk or len(raw_chunk) == 0:
            break
        st_sec = total_bytes / 32000.0
        chunk_len_sec = len(raw_chunk) / 32000.0
        ed_sec = st_sec + chunk_len_sec
        total_bytes += len(raw_chunk)
        ts = format_time(st_sec)
        audio_data = sr.AudioData(raw_chunk, 16000, 2)
        try:
            txt = recognizer.recognize_google(audio_data, language=lang_code).strip()
            if txt:
                line = f"{ts} {txt}"
                # 1. Simpan ke file teks dan SRT terlebih dahulu agar aman
                with open(out_txt, 'a', encoding='utf-8') as f:
                    f.write(line + '\n')
                with open(out_srt, 'a', encoding='utf-8') as f:
                    f.write(f"{srt_idx}\n{format_srt_time(st_sec)} --> {format_srt_time(ed_sec)}\n{txt}\n\n")
                srt_idx += 1
                # 2. Tampilkan di antarmuka GUI secara aman
                safe_print(line)
        except sr.UnknownValueError:
            pass
        except sr.RequestError as e:
            safe_print(f"{ts} [Koneksi Internet Terganggu]: {e}")
        except Exception as e:
            safe_print(f"{ts} [Error Transkripsi]: {e}")

else:
    from vosk import Model, KaldiRecognizer, SetLogLevel
    SetLogLevel(-1)
    if not model_path or not os.path.exists(model_path):
        safe_print(f"[Error]: Model Vosk offline tidak ditemukan di {model_path}")
        sys.exit(1)

    model = Model(model_path)
    rec = KaldiRecognizer(model, 16000.0)
    rec.SetWords(True)
    total_bytes = 0

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
                words = res.get('result', [])
                if words and 'start' in words[0] and 'end' in words[-1]:
                    st_sec = words[0]['start']
                    ed_sec = words[-1]['end']
                    ts = format_time(st_sec)
                else:
                    st_sec = max(0.0, cur_sec - 3.5)
                    ed_sec = cur_sec
                    ts = format_time(cur_sec)

                line = f"{ts} {txt}"
                with open(out_txt, 'a', encoding='utf-8') as f:
                    f.write(line + '\n')
                with open(out_srt, 'a', encoding='utf-8') as f:
                    f.write(f"{srt_idx}\n{format_srt_time(st_sec)} --> {format_srt_time(ed_sec)}\n{txt}\n\n")
                srt_idx += 1
                safe_print(line)

    final_res = json.loads(rec.FinalResult())
    final_txt = final_res.get('text', '').strip()
    if final_txt:
        ed_sec = total_bytes / 32000.0
        st_sec = max(0.0, ed_sec - 3.0)
        ts = format_time(ed_sec)
        line = f"{ts} {final_txt}"
        with open(out_txt, 'a', encoding='utf-8') as f:
            f.write(line + '\n')
        with open(out_srt, 'a', encoding='utf-8') as f:
            f.write(f"{srt_idx}\n{format_srt_time(st_sec)} --> {format_srt_time(ed_sec)}\n{final_txt}\n\n")
        srt_idx += 1
        safe_print(line)
'@

    $tempPy = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "vosk_ps_hybrid.py")
    [System.IO.File]::WriteAllText($tempPy, $pyScript, [System.Text.Encoding]::UTF8)

    $modelArg = if ([string]::IsNullOrWhiteSpace($modelPath)) { "none" } else { $modelPath }
    $psiArgs = "`"$tempPy`" `"$modeStr`" `"$videoPath`" `"$($cmbLang.SelectedItem)`" `"$modelArg`" `"$($script:outputTxtPath)`" `"$($script:outputSrtPath)`""

    $onComplete = [System.Action]{
        $script:isTranscribing = $false
        $btnStart.Text = "Mulai Transkripsi"
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $lblStatus.Text = "Selesai! Nota & Subtitle (.srt) tersimpan."
        [System.Windows.Forms.MessageBox]::Show("Transkripsi berhasil diselesaikan!`n`n1. Nota TXT: $script:outputTxtPath`n2. Subtitle SRT: $script:outputSrtPath", "Sukses", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }

    $script:transcriptionProcess = [TranscriptionProcessRunner]::Run("python", $psiArgs, $txtOutput, $onComplete)
})

# Pastikan proses anak ditutup jika jendela GUI ditutup
$form.Add_FormClosing({
    if ($script:transcriptionProcess -and -not $script:transcriptionProcess.HasExited) {
        try { $script:transcriptionProcess.Kill() } catch {}
    }
})

# Tampilkan Form GUI
[void]$form.ShowDialog()
