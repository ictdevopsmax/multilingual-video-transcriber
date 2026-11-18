package com.transkripsi;

import org.json.JSONArray;
import org.json.JSONObject;
import org.vosk.LogLevel;
import org.vosk.Model;
import org.vosk.Recognizer;

import javax.swing.*;
import javax.swing.filechooser.FileNameExtensionFilter;
import java.awt.*;
import java.io.*;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;

public class TranskripsiGUI extends JFrame {

    private JRadioButton rbOffline;
    private JRadioButton rbOnline;
    private JTextField txtVideoPath;
    private JComboBox<String> cmbLanguage;
    private JButton btnBrowse;
    private JButton btnStart;
    private JButton btnReadNote;
    private JButton btnReadSrt;
    private JButton btnClear;
    private JTextArea txtOutput;
    private JLabel lblStatus;
    private JProgressBar progressBar;

    private File currentOutputFile = null;
    private File currentSrtFile = null;
    private int srtCounter = 1;
    private volatile boolean isRunning = false;
    private Process currentProcess = null;
    private final HttpClient httpClient = HttpClient.newHttpClient();

    public TranskripsiGUI() {
        super("Transkripsi Video Hybrid (Offline & Online) - Java Swing GUI");
        try {
            UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
        } catch (Exception ignored) {}

        initUI();
        try {
            org.vosk.LibVosk.setLogLevel(LogLevel.WARNINGS);
        } catch (Throwable ignored) {}
    }

    private void initUI() {
        setSize(870, 710);
        setMinimumSize(new Dimension(720, 530));
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setLocationRelativeTo(null);
        setLayout(new BorderLayout(10, 10));

        // Panel Pengaturan Atas
        JPanel topPanel = new JPanel();
        topPanel.setLayout(new BoxLayout(topPanel, BoxLayout.Y_AXIS));
        topPanel.setBorder(BorderFactory.createEmptyBorder(12, 12, 5, 12));

        // Baris 0: Pilihan Mode Mesin
        JPanel modeRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 4));
        modeRow.add(new JLabel("Mode Mesin: "));
        boolean hasIdModel = new File("models/id/am").exists() || new File("../models/id/am").exists();
        rbOffline = new JRadioButton("🔒 Offline (Vosk Lokal)", hasIdModel);
        rbOnline = new JRadioButton("🌐 Online (Google Speech API)", !hasIdModel);
        ButtonGroup modeGroup = new ButtonGroup();
        modeGroup.add(rbOffline);
        modeGroup.add(rbOnline);
        modeRow.add(rbOffline);
        modeRow.add(rbOnline);
        topPanel.add(modeRow);

        // Baris 1: Buka File Video
        JPanel fileRow = new JPanel(new BorderLayout(8, 0));
        fileRow.setBorder(BorderFactory.createTitledBorder("Pilih File Video"));
        
        txtVideoPath = new JTextField();
        btnBrowse = new JButton("📁 Buka File");
        btnBrowse.addActionListener(e -> chooseVideoFile());

        fileRow.add(new JLabel(" File (.mp4/.mkv): "), BorderLayout.WEST);
        fileRow.add(txtVideoPath, BorderLayout.CENTER);
        fileRow.add(btnBrowse, BorderLayout.EAST);
        topPanel.add(fileRow);

        // Baris 2: Pengaturan Bahasa & Tombol Aksi
        JPanel actionRow = new JPanel(new FlowLayout(FlowLayout.LEFT, 10, 8));
        actionRow.add(new JLabel("Pilihan Bahasa:"));
        
        cmbLanguage = new JComboBox<>(new String[]{"Bahasa Indonesia", "Bahasa Mandarin (China)", "Bahasa Jepang (Japan)"});
        actionRow.add(cmbLanguage);

        btnStart = new JButton("▶️ Mulai Transkripsi");
        btnStart.addActionListener(e -> toggleTranscription());
        actionRow.add(btnStart);

        btnReadNote = new JButton("📝 Baca Nota (TXT)");
        btnReadNote.addActionListener(e -> openNoteFile());
        actionRow.add(btnReadNote);

        btnReadSrt = new JButton("🎬 Baca Subtitle (.SRT)");
        btnReadSrt.addActionListener(e -> openSrtFile());
        actionRow.add(btnReadSrt);

        btnClear = new JButton("🗑️ Hapus Layar");
        btnClear.addActionListener(e -> clearOutput());
        actionRow.add(btnClear);

        topPanel.add(actionRow);

        // Baris 3: Status & Progress
        JPanel statusPanel = new JPanel(new BorderLayout(5, 5));
        lblStatus = new JLabel("Status: Siap. Silakan klik 'Buka File' untuk memulai.");
        lblStatus.setFont(new Font("SansSerif", Font.ITALIC, 12));
        progressBar = new JProgressBar();
        progressBar.setIndeterminate(false);

        statusPanel.add(lblStatus, BorderLayout.NORTH);
        statusPanel.add(progressBar, BorderLayout.SOUTH);
        topPanel.add(statusPanel);

        add(topPanel, BorderLayout.NORTH);

        // Panel Tengah: Output Transkripsi
        JPanel centerPanel = new JPanel(new BorderLayout());
        centerPanel.setBorder(BorderFactory.createTitledBorder("Hasil Transkripsi Langsung (Streaming On-The-Fly)"));

        txtOutput = new JTextArea();
        txtOutput.setEditable(false);
        txtOutput.setFont(new Font("Consolas", Font.PLAIN, 13));
        txtOutput.setLineWrap(true);
        txtOutput.setWrapStyleWord(true);

        JScrollPane scrollPane = new JScrollPane(txtOutput);
        centerPanel.add(scrollPane, BorderLayout.CENTER);

        add(centerPanel, BorderLayout.CENTER);
    }

    private void chooseVideoFile() {
        JFileChooser chooser = new JFileChooser();
        chooser.setDialogTitle("Pilih File Video Berdurasi Panjang");
        FileNameExtensionFilter filter = new FileNameExtensionFilter(
                "Video Files (*.mp4, *.mkv, *.avi, *.mov, *.webm)", "mp4", "mkv", "avi", "mov", "webm", "flv");
        chooser.setFileFilter(filter);

        if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
            File selected = chooser.getSelectedFile();
            txtVideoPath.setText(selected.getAbsolutePath());

            String parent = selected.getParent();
            String name = selected.getName();
            int dotIdx = name.lastIndexOf('.');
            String baseName = (dotIdx > 0) ? name.substring(0, dotIdx) : name;
            currentOutputFile = new File(parent, baseName + "_transkripsi.txt");
            currentSrtFile = new File(parent, baseName + "_subtitle.srt");

            lblStatus.setText("File dipilih. Nota (.txt) & Subtitle (.srt) siap dibuat.");
        }
    }

    private String formatTimestamp(double seconds) {
        if (seconds < 0) seconds = 0;
        int h = (int)(seconds / 3600);
        int m = (int)((seconds % 3600) / 60);
        int s = (int)(seconds % 60);
        return String.format("[%02d:%02d:%02d]", h, m, s);
    }

    private String formatSrtTimestamp(double seconds) {
        if (seconds < 0) seconds = 0;
        int h = (int)(seconds / 3600);
        int m = (int)((seconds % 3600) / 60);
        int s = (int)(seconds % 60);
        int ms = (int)Math.round((seconds - (int)seconds) * 1000);
        if (ms >= 1000) ms = 999;
        return String.format("%02d:%02d:%02d,%03d", h, m, s, ms);
    }

    private String getFfmpegPath() {
        String[] candidates = {
                "../tools/ffmpeg.exe",
                "tools/ffmpeg.exe",
                "C:/Users/Admin/Documents/transkripsi video/tools/ffmpeg.exe"
        };
        for (String c : candidates) {
            File f = new File(c);
            if (f.exists() && f.isFile()) {
                return f.getAbsolutePath();
            }
        }
        return "ffmpeg";
    }

    private File detectModelPath() {
        String langStr = cmbLanguage.getSelectedItem() != null ? cmbLanguage.getSelectedItem().toString() : "";
        String langCode = langStr.contains("Indonesia") ? "id" : (langStr.contains("Jepang") || langStr.contains("Japan") ? "ja" : "cn");
        String[] candidates = {
                "../models/" + langCode,
                "models/" + langCode,
                "../models",
                "models"
        };

        for (String c : candidates) {
            File f = new File(c);
            if (f.exists() && f.isDirectory()) {
                if (f.getName().equalsIgnoreCase(langCode)) return f;
                File direct = new File(f, langCode);
                if (direct.exists() && direct.isDirectory()) return direct;

                File[] subs = f.listFiles(File::isDirectory);
                if (subs != null) {
                    for (File sub : subs) {
                        if (sub.getName().toLowerCase().contains(langCode)) {
                            return sub;
                        }
                    }
                }
            }
        }
        return null;
    }

    private void toggleTranscription() {
        if (isRunning) {
            isRunning = false;
            if (currentProcess != null) {
                currentProcess.destroy();
            }
            btnStart.setText("▶️ Mulai Transkripsi");
            progressBar.setIndeterminate(false);
            lblStatus.setText("Transkripsi dihentikan pengguna.");
            return;
        }

        String videoPath = txtVideoPath.getText().trim();
        if (videoPath.isEmpty() || !new File(videoPath).exists()) {
            JOptionPane.showMessageDialog(this, "Silakan pilih file video yang valid terlebih dahulu!", "File Tidak Ditemukan", JOptionPane.WARNING_MESSAGE);
            return;
        }

        boolean isOnline = rbOnline.isSelected();
        File modelDir = null;

        if (!isOnline) {
            modelDir = detectModelPath();
            if (modelDir == null) {
                if (cmbLanguage.getSelectedItem().toString().contains("Indonesia")) {
                    int resp = JOptionPane.showConfirmDialog(this,
                            "Model offline Vosk resmi untuk Bahasa Indonesia tidak tersedia di server Vosk.\n\n" +
                                    "Namun Anda dapat menggunakan 'Mode Online (Google Speech API)' secara GRATIS & berakurasi tinggi tanpa perlu API key.\n\n" +
                                    "Apakah Anda ingin langsung beralih ke Mode Online sekarang?",
                            "Beralih ke Mode Online", JOptionPane.YES_NO_OPTION);
                    if (resp == JOptionPane.YES_OPTION) {
                        rbOnline.setSelected(true);
                        isOnline = true;
                    } else {
                        return;
                    }
                } else {
                    JOptionPane.showMessageDialog(this,
                            "Model offline Vosk untuk " + cmbLanguage.getSelectedItem() + " belum ditemukan.\n" +
                                    "Silakan klik 'Pasang_Model_Otomatis.bat' atau gunakan 'Mode Online'.",
                            "Model Vosk Tidak Ditemukan", JOptionPane.ERROR_MESSAGE);
                    return;
                }
            }
        }

        isRunning = true;
        btnStart.setText("⏹️ Hentikan Transkripsi");
        progressBar.setIndeterminate(true);
        txtOutput.setText("");

        String modeName = isOnline ? "ONLINE (Google Speech API)" : "OFFLINE (Vosk Lokal)";
        appendOutput("=== MEMULAI TRANSKRIPSI VIDEO (" + modeName + ") DARI JAM KE-0 ===\n");
        appendOutput("File Video    : " + videoPath + "\n");
        appendOutput("Bahasa        : " + cmbLanguage.getSelectedItem() + "\n");
        if (!isOnline && modelDir != null) appendOutput("Model Vosk    : " + modelDir.getAbsolutePath() + "\n");
        appendOutput("File Nota     : " + (currentOutputFile != null ? currentOutputFile.getAbsolutePath() : "") + "\n");
        appendOutput("File Subtitle : " + (currentSrtFile != null ? currentSrtFile.getAbsolutePath() : "") + "\n");
        appendOutput("Mode          : Streaming audio on-the-fly via RAM buffer (tanpa file audio terpisah di disk)\n\n");

        final boolean finalIsOnline = isOnline;
        final File fModel = modelDir;
        new Thread(() -> {
            if (finalIsOnline) {
                runOnlineWorker(new File(videoPath));
            } else {
                runOfflineWorker(new File(videoPath), fModel);
            }
        }).start();
    }

    private void runOfflineWorker(File videoFile, File modelDir) {
        BufferedWriter writer = null;
        BufferedWriter srtWriter = null;
        try {
            srtCounter = 1;
            if (currentOutputFile != null) {
                writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(currentOutputFile), StandardCharsets.UTF_8));
                writer.write("=== NOTA CATATAN TRANSKRIPSI VIDEO (OFFLINE) ===\nFile: " + videoFile.getAbsolutePath() + "\nBahasa: " + cmbLanguage.getSelectedItem() + "\n-----------------------------------------\n\n");
                writer.flush();
            }
            if (currentSrtFile != null) {
                srtWriter = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(currentSrtFile), StandardCharsets.UTF_8));
            }

            updateStatus("Memuat model Vosk offline ke memori...");
            try (Model model = new Model(modelDir.getAbsolutePath());
                 Recognizer recognizer = new Recognizer(model, 16000.0f)) {

                recognizer.setWords(true);
                updateStatus("Membaca stream audio dari file video secara on-the-fly...");

                ProcessBuilder pb = new ProcessBuilder(getFfmpegPath(), "-loglevel", "quiet", "-i", videoFile.getAbsolutePath(), "-ar", "16000", "-ac", "1", "-f", "s16le", "-");
                currentProcess = pb.start();

                try (InputStream in = currentProcess.getInputStream()) {
                    byte[] buffer = new byte[4096];
                    int nbytes;
                    long totalBytes = 0;

                    while (isRunning && (nbytes = in.read(buffer)) >= 0) {
                        totalBytes += nbytes;
                        if (recognizer.acceptWaveForm(buffer, nbytes)) {
                            String jsonStr = recognizer.getResult();
                            processJsonResult(jsonStr, totalBytes / 32000.0, writer, srtWriter);
                        }
                    }

                    String finalJson = recognizer.getFinalResult();
                    processJsonResult(finalJson, totalBytes / 32000.0, writer, srtWriter);
                }

                if (isRunning) {
                    appendOutput("\n=== TRANSKRIPSI OFFLINE SELESAI DENGAN SUKSES ===\n");
                    updateStatus("Selesai! Nota & Subtitle (.srt) tersimpan.");
                    SwingUtilities.invokeLater(() -> JOptionPane.showMessageDialog(this, "Transkripsi video offline selesai!\n\n1. Nota TXT: " + (currentOutputFile != null ? currentOutputFile.getAbsolutePath() : "") + "\n2. Subtitle SRT: " + (currentSrtFile != null ? currentSrtFile.getAbsolutePath() : "") + "\n\nKlik 'Baca Subtitle (.SRT)' untuk melihat.", "Selesai", JOptionPane.INFORMATION_MESSAGE));
                }
            }
        } catch (Exception ex) {
            appendOutput("\n[Error]: " + ex.getMessage() + "\n");
        } finally {
            cleanup(writer, srtWriter);
        }
    }

    private void runOnlineWorker(File videoFile) {
        BufferedWriter writer = null;
        BufferedWriter srtWriter = null;
        try {
            srtCounter = 1;
            if (currentOutputFile != null) {
                writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(currentOutputFile), StandardCharsets.UTF_8));
                writer.write("=== NOTA CATATAN TRANSKRIPSI VIDEO (ONLINE) ===\nFile: " + videoFile.getAbsolutePath() + "\nBahasa: " + cmbLanguage.getSelectedItem() + "\n-----------------------------------------\n\n");
                writer.flush();
            }
            if (currentSrtFile != null) {
                srtWriter = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(currentSrtFile), StandardCharsets.UTF_8));
            }

            updateStatus("Menghubungkan streaming audio online...");
            ProcessBuilder pb = new ProcessBuilder(getFfmpegPath(), "-loglevel", "quiet", "-i", videoFile.getAbsolutePath(), "-ar", "16000", "-ac", "1", "-f", "s16le", "-");
            currentProcess = pb.start();

            String langStr = cmbLanguage.getSelectedItem() != null ? cmbLanguage.getSelectedItem().toString() : "";
            String langCode = langStr.contains("Indonesia") ? "id-ID" : (langStr.contains("Jepang") || langStr.contains("Japan") ? "ja-JP" : "zh-CN");
            int chunkSize = 320000; // 10 detik chunk di RAM
            byte[] chunkBuffer = new byte[chunkSize];
            long totalBytes = 0;

            try (InputStream in = currentProcess.getInputStream()) {
                while (isRunning) {
                    int totalRead = 0;
                    while (totalRead < chunkSize) {
                        int r = in.read(chunkBuffer, totalRead, chunkSize - totalRead);
                        if (r <= 0) break;
                        totalRead += r;
                    }
                    if (totalRead == 0) break;

                    double startSec = totalBytes / 32000.0;
                    double endSec = startSec + (totalRead / 32000.0);
                    totalBytes += totalRead;
                    String ts = formatTimestamp(startSec);

                    byte[] wav = createWavInMemory(chunkBuffer, totalRead, 16000, (short)1, (short)16);
                    String recognized = recognizeOnline(wav, langCode);

                    if (recognized != null && !recognized.isEmpty()) {
                        String line = ts + " " + recognized;
                        appendOutput(line + "\n");
                        if (writer != null) {
                            writer.write(line + "\n");
                            writer.flush();
                        }
                        if (srtWriter != null) {
                            srtWriter.write(srtCounter + "\n" + formatSrtTimestamp(startSec) + " --> " + formatSrtTimestamp(endSec) + "\n" + recognized + "\n\n");
                            srtWriter.flush();
                            srtCounter++;
                        }
                    }
                }
            }

            if (isRunning) {
                appendOutput("\n=== TRANSKRIPSI ONLINE SELESAI DENGAN SUKSES ===\n");
                updateStatus("Selesai! Nota & Subtitle (.srt) tersimpan.");
                SwingUtilities.invokeLater(() -> JOptionPane.showMessageDialog(this, "Transkripsi video online selesai!\n\n1. Nota TXT: " + (currentOutputFile != null ? currentOutputFile.getAbsolutePath() : "") + "\n2. Subtitle SRT: " + (currentSrtFile != null ? currentSrtFile.getAbsolutePath() : "") + "\n\nKlik 'Baca Subtitle (.SRT)' untuk melihat.", "Selesai", JOptionPane.INFORMATION_MESSAGE));
            }
        } catch (Exception ex) {
            appendOutput("\n[Error Online]: " + ex.getMessage() + "\n");
        } finally {
            cleanup(writer, srtWriter);
        }
    }

    private String recognizeOnline(byte[] wavBytes, String lang) {
        try {
            String url = "https://www.google.com/speech-api/v2/recognize?output=json&lang=" + lang + "&key=AIzaSyBOti4mM-6x9WDnZIjIeyEU21OpBXqWBgw&client=chromium";
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Content-Type", "audio/x-wav")
                    .POST(HttpRequest.BodyPublishers.ofByteArray(wavBytes))
                    .build();

            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            String[] lines = response.body().split("\n");
            for (String line : lines) {
                try {
                    JSONObject obj = new JSONObject(line.trim());
                    if (obj.has("result")) {
                        JSONArray resArr = obj.getJSONArray("result");
                        if (resArr.length() > 0) {
                            JSONArray altArr = resArr.getJSONObject(0).getJSONArray("alternative");
                            if (altArr.length() > 0) {
                                return altArr.getJSONObject(0).getString("transcript").trim();
                            }
                        }
                    }
                } catch (Exception ignored) {}
            }
        } catch (Exception ignored) {}
        return null;
    }

    private byte[] createWavInMemory(byte[] pcmData, int pcmLength, int sampleRate, short channels, short bitsPerSample) throws IOException {
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        DataOutputStream dos = new DataOutputStream(baos);

        dos.writeBytes("RIFF");
        dos.writeInt(Integer.reverseBytes(36 + pcmLength));
        dos.writeBytes("WAVE");
        dos.writeBytes("fmt ");
        dos.writeInt(Integer.reverseBytes(16));
        dos.writeShort(Short.reverseBytes((short) 1));
        dos.writeShort(Short.reverseBytes(channels));
        dos.writeInt(Integer.reverseBytes(sampleRate));
        dos.writeInt(Integer.reverseBytes(sampleRate * channels * (bitsPerSample / 8)));
        dos.writeShort(Short.reverseBytes((short) (channels * (bitsPerSample / 8))));
        dos.writeShort(Short.reverseBytes(bitsPerSample));
        dos.writeBytes("data");
        dos.writeInt(Integer.reverseBytes(pcmLength));
        dos.write(pcmData, 0, pcmLength);
        dos.flush();

        return baos.toByteArray();
    }

    private void processJsonResult(String jsonStr, double sec, BufferedWriter writer, BufferedWriter srtWriter) {
        try {
            JSONObject obj = new JSONObject(jsonStr);
            if (obj.has("text")) {
                String text = obj.getString("text").trim();
                if (!text.isEmpty()) {
                    double startSec = Math.max(0, sec - 3.5);
                    double endSec = sec;

                    if (obj.has("result")) {
                        JSONArray words = obj.getJSONArray("result");
                        if (words.length() > 0) {
                            JSONObject firstWord = words.getJSONObject(0);
                            JSONObject lastWord = words.getJSONObject(words.length() - 1);
                            if (firstWord.has("start")) startSec = firstWord.getDouble("start");
                            if (lastWord.has("end")) endSec = lastWord.getDouble("end");
                        }
                    }

                    String line = formatTimestamp(startSec) + " " + text;
                    appendOutput(line + "\n");
                    if (writer != null) {
                        writer.write(line + "\n");
                        writer.flush();
                    }
                    if (srtWriter != null) {
                        srtWriter.write(srtCounter + "\n" + formatSrtTimestamp(startSec) + " --> " + formatSrtTimestamp(endSec) + "\n" + text + "\n\n");
                        srtWriter.flush();
                        srtCounter++;
                    }
                }
            }
        } catch (Exception ignored) {}
    }

    private void cleanup(BufferedWriter writer, BufferedWriter srtWriter) {
        if (writer != null) {
            try { writer.close(); } catch (IOException ignored) {}
        }
        if (srtWriter != null) {
            try { srtWriter.close(); } catch (IOException ignored) {}
        }
        if (currentProcess != null && currentProcess.isAlive()) {
            currentProcess.destroy();
        }
        SwingUtilities.invokeLater(() -> {
            isRunning = false;
            btnStart.setText("▶️ Mulai Transkripsi");
            progressBar.setIndeterminate(false);
        });
    }

    private void appendOutput(String str) {
        SwingUtilities.invokeLater(() -> {
            txtOutput.append(str);
            txtOutput.setCaretPosition(txtOutput.getDocument().getLength());
        });
    }

    private void updateStatus(String status) {
        SwingUtilities.invokeLater(() -> lblStatus.setText("Status: " + status));
    }

    private void openNoteFile() {
        File fileToOpen = currentOutputFile;
        if (fileToOpen == null || !fileToOpen.exists()) {
            JFileChooser chooser = new JFileChooser();
            chooser.setDialogTitle("Buka File Nota Catatan Transkripsi (.txt)");
            chooser.setFileFilter(new FileNameExtensionFilter("File Teks (*.txt)", "txt"));
            if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
                fileToOpen = chooser.getSelectedFile();
            } else {
                return;
            }
        }

        try {
            if (Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.OPEN)) {
                Desktop.getDesktop().open(fileToOpen);
            } else {
                JOptionPane.showMessageDialog(this, "File nota berada di: " + fileToOpen.getAbsolutePath());
            }
        } catch (Exception ex) {
            JOptionPane.showMessageDialog(this, "Gagal membuka file: " + ex.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void openSrtFile() {
        File fileToOpen = currentSrtFile;
        if (fileToOpen == null || !fileToOpen.exists()) {
            JFileChooser chooser = new JFileChooser();
            chooser.setDialogTitle("Buka File Subtitle Video (.srt)");
            chooser.setFileFilter(new FileNameExtensionFilter("File Subtitle (*.srt)", "srt"));
            if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
                fileToOpen = chooser.getSelectedFile();
            } else {
                return;
            }
        }

        try {
            if (Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.OPEN)) {
                Desktop.getDesktop().open(fileToOpen);
            } else {
                JOptionPane.showMessageDialog(this, "File subtitle berada di: " + fileToOpen.getAbsolutePath());
            }
        } catch (Exception ex) {
            JOptionPane.showMessageDialog(this, "Gagal membuka file: " + ex.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
        }
    }

    private void clearOutput() {
        int opt = JOptionPane.showConfirmDialog(this, "Bersihkan seluruh hasil transkripsi di layar?", "Konfirmasi Hapus", JOptionPane.YES_NO_OPTION);
        if (opt == JOptionPane.YES_OPTION) {
            txtOutput.setText("");
            updateStatus("Layar transkripsi telah dibersihkan.");
        }
    }

    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> new TranskripsiGUI().setVisible(true));
    }
}
