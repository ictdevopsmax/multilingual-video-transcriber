import Cocoa
import Foundation

// ==============================================================================
// Transkripsi Video Offline - Swift macOS GUI (AppKit)
// Menggunakan FFmpeg Audio Streaming on-the-fly & Vosk Offline Engine
// Mendukung Bahasa Indonesia & Bahasa Mandarin (China)
// ==============================================================================

class MainWindowController: NSWindowController, NSWindowDelegate {
    var txtVideoPath: NSTextField!
    var cmbLanguage: NSPopUpButton!
    var btnBrowse: NSButton!
    var btnStart: NSButton!
    var btnReadNote: NSButton!
    var btnReadSrt: NSButton!
    var btnClear: NSButton!
    var txtOutput: NSTextView!
    var lblStatus: NSTextField!
    var progressIndicator: NSProgressIndicator!

    var videoPath: String = ""
    var outputTxtPath: String = ""
    var outputSrtPath: String = ""
    var isTranscribing: Bool = false
    var currentProcess: Process?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "Transkripsi Video Offline - Swift macOS GUI (Vosk Streaming)"
        window.delegate = self
        setupUI(contentView: window.contentView!)
    }

    func setupUI(contentView: NSView) {
        // Label & Input File Video
        let lblVideo = NSTextField(labelWithString: "File Video (.mp4/.mkv):")
        lblVideo.frame = NSRect(x: 20, y: 590, width: 160, height: 22)
        contentView.addSubview(lblVideo)

        txtVideoPath = NSTextField(frame: NSRect(x: 180, y: 590, width: 460, height: 24))
        txtVideoPath.isEditable = true
        contentView.addSubview(txtVideoPath)

        btnBrowse = NSButton(title: "📁 Buka File", target: self, action: #selector(browseVideoFile))
        btnBrowse.frame = NSRect(x: 650, y: 588, width: 130, height: 28)
        contentView.addSubview(btnBrowse)

        // Pilihan Bahasa
        let lblLang = NSTextField(labelWithString: "Pilihan Bahasa:")
        lblLang.frame = NSRect(x: 20, y: 550, width: 160, height: 22)
        contentView.addSubview(lblLang)

        cmbLanguage = NSPopUpButton(frame: NSRect(x: 180, y: 548, width: 220, height: 26), pullsDown: false)
        cmbLanguage.addItems(withTitles: ["Bahasa Indonesia", "Bahasa Mandarin (China)", "Bahasa Jepang (Japan)"])
        contentView.addSubview(cmbLanguage)

        // Tombol Aksi
        btnStart = NSButton(title: "▶️ Mulai Transkripsi", target: self, action: #selector(toggleTranscription))
        btnStart.frame = NSRect(x: 180, y: 508, width: 145, height: 32)
        btnStart.bezelStyle = .rounded
        contentView.addSubview(btnStart)

        btnReadNote = NSButton(title: "📝 Baca Nota (.TXT)", target: self, action: #selector(readNoteFile))
        btnReadNote.frame = NSRect(x: 335, y: 508, width: 150, height: 32)
        btnReadNote.bezelStyle = .rounded
        contentView.addSubview(btnReadNote)

        btnReadSrt = NSButton(title: "🎬 Baca Subtitle (.SRT)", target: self, action: #selector(readSrtFile))
        btnReadSrt.frame = NSRect(x: 495, y: 508, width: 165, height: 32)
        btnReadSrt.bezelStyle = .rounded
        contentView.addSubview(btnReadSrt)

        btnClear = NSButton(title: "🗑️ Hapus", target: self, action: #selector(clearOutput))
        btnClear.frame = NSRect(x: 668, y: 508, width: 100, height: 32)
        btnClear.bezelStyle = .rounded
        contentView.addSubview(btnClear)

        // Status Label & Progress Indicator
        lblStatus = NSTextField(labelWithString: "Status: Siap. Silakan klik 'Buka File' untuk memilih video.")
        lblStatus.frame = NSRect(x: 20, y: 475, width: 760, height: 20)
        lblStatus.font = NSFont.italicSystemFont(ofSize: 11)
        contentView.addSubview(lblStatus)

        progressIndicator = NSProgressIndicator(frame: NSRect(x: 20, y: 455, width: 760, height: 16))
        progressIndicator.isIndeterminate = true
        progressIndicator.style = .bar
        contentView.addSubview(progressIndicator)

        // Area Hasil Transkripsi
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: 760, height: 425))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        txtOutput = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 425))
        txtOutput.isEditable = false
        txtOutput.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        txtOutput.autoresizingMask = [.width]
        scrollView.documentView = txtOutput

        contentView.addSubview(scrollView)
    }

    @objc func browseVideoFile() {
        let panel = NSOpenPanel()
        panel.title = "Pilih File Video Berdurasi Panjang"
        panel.allowedFileTypes = ["mp4", "mkv", "avi", "mov", "webm", "flv"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            videoPath = url.path
            txtVideoPath.stringValue = videoPath

            let dir = url.deletingLastPathComponent().path
            let baseName = url.deletingPathExtension().lastPathComponent
            outputTxtPath = "\(dir)/\(baseName)_transkripsi.txt"
            outputSrtPath = "\(dir)/\(baseName)_subtitle.srt"

            lblStatus.stringValue = "File dipilih. Nota (.txt) & Subtitle (.srt) siap dibuat."
        }
    }

    @objc func readNoteFile() {
        var path = outputTxtPath
        if path.isEmpty || !FileManager.default.fileExists(atPath: path) {
            let panel = NSOpenPanel()
            panel.title = "Pilih File Nota Transkripsi (.txt)"
            panel.allowedFileTypes = ["txt"]
            if panel.runModal() == .OK, let url = panel.url {
                path = url.path
            } else {
                return
            }
        }

        let fileURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(fileURL)
    }

    @objc func clearOutput() {
        txtOutput.string = ""
        lblStatus.stringValue = "Status: Layar transkripsi telah dibersihkan."
    }

    @objc func readSrtFile() {
        var path = outputSrtPath
        if path.isEmpty || !FileManager.default.fileExists(atPath: path) {
            let panel = NSOpenPanel()
            panel.title = "Pilih File Subtitle Video (.srt)"
            panel.allowedFileTypes = ["srt"]
            if panel.runModal() == .OK, let url = panel.url {
                path = url.path
            } else {
                return
            }
        }

        let fileURL = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(fileURL)
    }

    func detectModelPath(langCode: String) -> String? {
        let cwd = FileManager.default.currentDirectoryPath
        let searchPaths = [
            "\(cwd)/models/\(langCode)",
            "\(cwd)/../models/\(langCode)",
            "\(cwd)/models/vosk-model-small-\(langCode)-0.4",
            "\(cwd)/models/vosk-model-small-\(langCode)-0.22",
            "\(cwd)/../models/vosk-model-small-\(langCode)-0.4",
            "\(cwd)/../models/vosk-model-small-\(langCode)-0.22"
        ]

        for p in searchPaths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue {
                return p
            }
        }
        return nil
    }

    @objc func toggleTranscription() {
        if isTranscribing {
            isTranscribing = false
            currentProcess?.terminate()
            btnStart.title = "▶️ Mulai Transkripsi"
            progressIndicator.stopAnimation(nil)
            lblStatus.stringValue = "Transkripsi dihentikan."
            return
        }

        videoPath = txtVideoPath.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if videoPath.isEmpty || !FileManager.default.fileExists(atPath: videoPath) {
            let alert = NSAlert()
            alert.messageText = "File Tidak Valid"
            alert.informativeText = "Silakan klik 'Buka File' untuk memilih file video .mp4/.mkv yang valid."
            alert.runModal()
            return
        }

        let selIdx = cmbLanguage.indexOfSelectedItem
        var langCode = "id"
        if selIdx == 1 {
            langCode = "cn"
        } else if selIdx == 2 {
            langCode = "ja"
        }
        guard let modelPath = detectModelPath(langCode: langCode) else {
            let alert = NSAlert()
            alert.messageText = "Model Vosk Tidak Ditemukan"
            alert.informativeText = "Model offline untuk \(cmbLanguage.titleOfSelectedItem ?? "") belum ada di folder 'models/\(langCode)'."
            alert.runModal()
            return
        }

        isTranscribing = true
        btnStart.title = "⏹️ Hentikan Transkripsi"
        progressIndicator.startAnimation(nil)
        txtOutput.string = ""

        appendOutput("=== MEMULAI TRANSKRIPSI VIDEO DARI DETIK KE-0 SAMPAI SELESAI ===\n")
        appendOutput("File Video    : \(videoPath)\n")
        appendOutput("Bahasa        : \(cmbLanguage.titleOfSelectedItem ?? "")\n")
        appendOutput("Model Vosk    : \(modelPath)\n")
        appendOutput("File Nota     : \(outputTxtPath)\n")
        appendOutput("File Subtitle : \(outputSrtPath)\n")
        appendOutput("Metode        : Streaming audio on-the-fly via FFmpeg pipe (tanpa file audio terpisah)\n\n")

        // Inisialisasi file nota dan subtitle
        let header = "=== NOTA CATATAN TRANSKRIPSI VIDEO (Swift) ===\nFile Video: \(videoPath)\nBahasa: \(cmbLanguage.titleOfSelectedItem ?? "")\n---------------------------------------------\n\n"
        try? header.write(toFile: outputTxtPath, atomically: true, encoding: .utf8)
        try? "".write(toFile: outputSrtPath, atomically: true, encoding: .utf8)

        lblStatus.stringValue = "Memproses streaming audio video secara on-the-fly..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.runTranscription(video: self?.videoPath ?? "", model: modelPath, outTxt: self?.outputTxtPath ?? "", outSrt: self?.outputSrtPath ?? "")
        }
    }

    func runTranscription(video: String, model: String, outTxt: String, outSrt: String) {
        // Runner Python streaming Vosk terpasang
        let pyScript = """
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
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

m = Model(model_path)
rec = KaldiRecognizer(m, 16000.0)
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
                f.write(txt + '\\n')
            with open(out_srt, 'a', encoding='utf-8') as f:
                f.write(f"{srt_idx}\\n{format_srt_time(st_sec)} --> {format_srt_time(cur_sec)}\\n{txt}\\n\\n")
            srt_idx += 1

final_res = json.loads(rec.FinalResult())
final_txt = final_res.get('text', '').strip()
if final_txt:
    cur_sec = total_bytes / 32000.0
    st_sec = max(0.0, cur_sec - 3.0)
    print(final_txt, flush=True)
    with open(out_txt, 'a', encoding='utf-8') as f:
        f.write(final_txt + '\\n')
    with open(out_srt, 'a', encoding='utf-8') as f:
        f.write(f"{srt_idx}\\n{format_srt_time(st_sec)} --> {format_srt_time(cur_sec)}\\n{final_txt}\\n\\n")
    srt_idx += 1
"""
        let tempScript = "\(NSTemporaryDirectory())vosk_swift_runner.py"
        try? pyScript.write(toFile: tempScript, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", tempScript, video, model, outTxt, outSrt]

        let pipe = Pipe()
        process.standardOutput = pipe
        self.currentProcess = process

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                DispatchQueue.main.async {
                    self?.appendOutput(str)
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.appendOutput("\n[Error]: \(error.localizedDescription)\n")
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isTranscribing = false
            self.btnStart.title = "▶️ Mulai Transkripsi"
            self.progressIndicator.stopAnimation(nil)
            self.lblStatus.stringValue = "Selesai! Nota & Subtitle (.srt) tersimpan."
            self.appendOutput("\n=== TRANSKRIPSI SELESAI DENGAN SUKSES ===\n")

            let alert = NSAlert()
            alert.messageText = "Transkripsi Selesai"
            alert.informativeText = "File tersimpan:\n1. Nota: \(outTxt)\n2. Subtitle: \(outSrt)\n\nKlik 'Baca Subtitle (.SRT)' untuk membuka."
            alert.runModal()
        }
    }

    func appendOutput(_ text: String) {
        let prev = txtOutput.string
        txtOutput.string = prev + text
        txtOutput.scrollToEndOfDocument(nil)
    }
}

// Entry Point Aplikasi macOS
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = MainWindowController()
controller.showWindow(nil)
app.activate(ignoringOtherApps: true)
app.run()

