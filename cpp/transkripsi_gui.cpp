/*
 * Transkripsi Video Offline - C++ Native GUI (Win32 API)
 * Menggunakan Vosk C API & FFmpeg Streaming Audio on-the-fly (tanpa file audio terpisah).
 * Mendukung Bahasa Indonesia & Bahasa Mandarin (China).
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <iostream>
#include <fstream>
#include <string>
#include <thread>
#include <atomic>
#include <vector>

// Vosk C API header (Pastikan vosk_api.h dan libvosk.dll tersedia)
#include "vosk_api.h"

// ID Komponen Kontrol GUI
#define ID_BTN_BROWSE     1001
#define ID_BTN_START      1002
#define ID_BTN_READ_NOTE  1003
#define ID_CMB_LANG       1004
#define ID_TXT_VIDEO      1005
#define ID_TXT_OUTPUT     1006
#define ID_LBL_STATUS     1007
#define ID_BTN_READ_SRT   1008
#define ID_BTN_CLEAR      1009

// Global State
HWND g_hwndMain = NULL;
HWND g_hwndTxtVideo = NULL;
HWND g_hwndCmbLang = NULL;
HWND g_hwndBtnStart = NULL;
HWND g_hwndBtnReadNote = NULL;
HWND g_hwndBtnReadSrt = NULL;
HWND g_hwndBtnClear = NULL;
HWND g_hwndTxtOutput = NULL;
HWND g_hwndLblStatus = NULL;

std::atomic<bool> g_isTranscribing(false);
std::string g_videoPath = "";
std::string g_outputTxtPath = "";
std::string g_outputSrtPath = "";
std::thread g_workerThread;

// Fungsi Helper untuk menambahkan teks ke Edit Control secara aman dari thread
void AppendOutputText(const std::string& text) {
    if (!g_hwndTxtOutput) return;
    int len = GetWindowTextLengthA(g_hwndTxtOutput);
    SendMessageA(g_hwndTxtOutput, EM_SETSEL, (WPARAM)len, (LPARAM)len);
    SendMessageA(g_hwndTxtOutput, EM_REPLACESEL, FALSE, (LPARAM)text.c_str());
}

void SetStatusText(const std::string& text) {
    if (g_hwndLblStatus) {
        SetWindowTextA(g_hwndLblStatus, ("Status: " + text).c_str());
    }
}

std::string FormatSrtTimestamp(double seconds) {
    if (seconds < 0) seconds = 0;
    int h = (int)(seconds / 3600);
    int m = (int)((seconds % 3600) / 60);
    int s = (int)(seconds % 60);
    int ms = (int)((seconds - (int)seconds) * 1000);
    if (ms >= 1000) ms = 999;
    char buf[32];
    sprintf_s(buf, "%02d:%02d:%02d,%03d", h, m, s, ms);
    return std::string(buf);
}

// Deteksi lokasi folder model Vosk
std::string DetectModelFolder(const std::string& langCode) {
    std::vector<std::string> searchPaths = {
        "models/" + langCode,
        "../models/" + langCode,
        "models/vosk-model-small-" + langCode + "-0.4",
        "models/vosk-model-small-" + langCode + "-0.22",
        "../models/vosk-model-small-" + langCode + "-0.4",
        "../models/vosk-model-small-" + langCode + "-0.22",
        langCode
    };

    for (const auto& p : searchPaths) {
        DWORD attrib = GetFileAttributesA(p.c_str());
        if (attrib != INVALID_FILE_ATTRIBUTES && (attrib & FILE_ATTRIBUTE_DIRECTORY)) {
            return p;
        }
    }
    return "";
}

// Ekstraksi text dari JSON sederhana hasil Vosk: {"text" : "isi teks"}
std::string ExtractTextFromJson(const std::string& json) {
    size_t keyPos = json.find("\"text\" :");
    if (keyPos == std::string::npos) {
        keyPos = json.find("\"text\":");
    }
    if (keyPos == std::string::npos) return "";

    size_t firstQuote = json.find("\"", keyPos + 7);
    if (firstQuote == std::string::npos) return "";
    size_t secondQuote = json.find("\"", firstQuote + 1);
    if (secondQuote == std::string::npos) return "";

    return json.substr(firstQuote + 1, secondQuote - firstQuote - 1);
}

// Background Worker: Membaca stream audio video on-the-fly via FFmpeg pipe & transkripsi dengan Vosk
void TranscriptionWorker(std::string videoPath, std::string modelPath, std::string outTxtPath, std::string outSrtPath) {
    SetStatusText("Memuat model Vosk offline ke memori...");
    VoskModel* model = vosk_model_new(modelPath.c_str());
    if (!model) {
        AppendOutputText("[Error]: Gagal memuat model Vosk dari: " + modelPath + "\r\n");
        SetStatusText("Error: Model gagal dimuat.");
        g_isTranscribing = false;
        SetWindowTextA(g_hwndBtnStart, "▶️ Mulai Transkripsi");
        return;
    }

    VoskRecognizer* recognizer = vosk_recognizer_new(model, 16000.0f);
    vosk_recognizer_set_words(recognizer, 1);

    SetStatusText("Membaca stream audio dari video secara on-the-fly...");

    // Buat/inisialisasi file nota teks (.txt) dan subtitle (.srt)
    std::ofstream outFile(outTxtPath, std::ios::out | std::ios::trunc);
    if (outFile.is_open()) {
        outFile << "=== NOTA CATATAN TRANSKRIPSI VIDEO (C++) ===\n";
        outFile << "File Video: " << videoPath << "\n";
        outFile << "-------------------------------------------\n\n";
        outFile.close();
    }
    std::ofstream outSrt(outSrtPath, std::ios::out | std::ios::trunc);
    if (outSrt.is_open()) {
        outSrt.close();
    }

    // Perintah FFmpeg streaming langsung format PCM s16le 16kHz mono ke stdout
    std::string ffmpegCmd = "ffmpeg -loglevel quiet -i \"" + videoPath + "\" -ar 16000 -ac 1 -f s16le -";

    FILE* pipe = _popen(ffmpegCmd.c_str(), "rb");
    if (!pipe) {
        AppendOutputText("[Error]: Gagal menjalankan ffmpeg pipe.\r\n");
        SetStatusText("Error: FFmpeg tidak ditemukan.");
        vosk_recognizer_free(recognizer);
        vosk_model_free(model);
        g_isTranscribing = false;
        SetWindowTextA(g_hwndBtnStart, "▶️ Mulai Transkripsi");
        return;
    }

    char buffer[4096];
    size_t bytesRead = 0;
    long long totalBytes = 0;
    int srtIdx = 1;

    while (g_isTranscribing && (bytesRead = fread(buffer, 1, sizeof(buffer), pipe)) > 0) {
        totalBytes += bytesRead;
        int accepted = vosk_recognizer_accept_waveform(recognizer, buffer, (int)bytesRead);
        if (accepted) {
            const char* resJson = vosk_recognizer_result(recognizer);
            std::string text = ExtractTextFromJson(resJson);
            if (!text.empty()) {
                double curSec = (double)totalBytes / 32000.0;
                double stSec = (curSec > 3.5) ? (curSec - 3.5) : 0.0;
                AppendOutputText(text + "\r\n");
                std::ofstream f(outTxtPath, std::ios::out | std::ios::app);
                if (f.is_open()) {
                    f << text << "\n";
                }
                std::ofstream fSrt(outSrtPath, std::ios::out | std::ios::app);
                if (fSrt.is_open()) {
                    fSrt << srtIdx << "\n" << FormatSrtTimestamp(stSec) << " --> " << FormatSrtTimestamp(curSec) << "\n" << text << "\n\n";
                    srtIdx++;
                }
            }
        }
    }

    // Final result
    const char* finalJson = vosk_recognizer_final_result(recognizer);
    std::string finalText = ExtractTextFromJson(finalJson);
    if (!finalText.empty()) {
        double curSec = (double)totalBytes / 32000.0;
        double stSec = (curSec > 3.0) ? (curSec - 3.0) : 0.0;
        AppendOutputText(finalText + "\r\n");
        std::ofstream f(outTxtPath, std::ios::out | std::ios::app);
        if (f.is_open()) {
            f << finalText << "\n";
        }
        std::ofstream fSrt(outSrtPath, std::ios::out | std::ios::app);
        if (fSrt.is_open()) {
            fSrt << srtIdx << "\n" << FormatSrtTimestamp(stSec) << " --> " << FormatSrtTimestamp(curSec) << "\n" << finalText << "\n\n";
            srtIdx++;
        }
    }

    _pclose(pipe);
    vosk_recognizer_free(recognizer);
    vosk_model_free(model);

    if (g_isTranscribing) {
        AppendOutputText("\r\n=== TRANSKRIPSI SELESAI DENGAN SUKSES ===\r\n");
        SetStatusText("Selesai! Nota & Subtitle (.srt) tersimpan.");
        MessageBoxA(g_hwndMain, ("Transkripsi selesai!\r\n\r\n1. Nota TXT: " + outTxtPath + "\r\n2. Subtitle SRT: " + outSrtPath).c_str(), "Sukses", MB_ICONINFORMATION);
    }

    g_isTranscribing = false;
    SetWindowTextA(g_hwndBtnStart, "▶️ Mulai Transkripsi");
}

// Dialog Browse File Video
void OnBrowseFile() {
    char filename[MAX_PATH] = "";
    OPENFILENAMEA ofn;
    ZeroMemory(&ofn, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_hwndMain;
    ofn.lpstrFilter = "Video Files (*.mp4;*.mkv;*.avi;*.mov)\0*.mp4;*.mkv;*.avi;*.mov;*.flv;*.webm\0Semua File (*.*)\0*.*\0";
    ofn.lpstrFile = filename;
    ofn.nMaxFile = MAX_PATH;
    ofn.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrTitle = "Pilih File Video Berdurasi Panjang";

    if (GetOpenFileNameA(&ofn)) {
        g_videoPath = filename;
        SetWindowTextA(g_hwndTxtVideo, filename);

        // Buat path file output nota (.txt) dan subtitle (.srt)
        std::string s(filename);
        size_t lastDot = s.find_last_of('.');
        if (lastDot != std::string::npos) {
            g_outputTxtPath = s.substr(0, lastDot) + "_transkripsi.txt";
            g_outputSrtPath = s.substr(0, lastDot) + "_subtitle.srt";
        } else {
            g_outputTxtPath = s + "_transkripsi.txt";
            g_outputSrtPath = s + "_subtitle.srt";
        }
        SetStatusText("File video dipilih. Nota (.txt) & Subtitle (.srt) siap dibuat.");
    }
}

// Buka Nota Catatan Teks
void OnReadNote() {
    if (g_outputTxtPath.empty()) {
        char filename[MAX_PATH] = "";
        OPENFILENAMEA ofn;
        ZeroMemory(&ofn, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = g_hwndMain;
        ofn.lpstrFilter = "File Nota Teks (*.txt)\0*.txt\0Semua File (*.*)\0*.*\0";
        ofn.lpstrFile = filename;
        ofn.nMaxFile = MAX_PATH;
        ofn.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST;
        ofn.lpstrTitle = "Pilih File Nota Catatan Transkripsi";
        if (GetOpenFileNameA(&ofn)) {
            g_outputTxtPath = filename;
        } else {
            return;
        }
    }

    ShellExecuteA(NULL, "open", g_outputTxtPath.c_str(), NULL, NULL, SW_SHOWNORMAL);
}

// Buka File Subtitle (.SRT)
void OnReadSrt() {
    if (g_outputSrtPath.empty()) {
        char filename[MAX_PATH] = "";
        OPENFILENAMEA ofn;
        ZeroMemory(&ofn, sizeof(ofn));
        ofn.lStructSize = sizeof(ofn);
        ofn.hwndOwner = g_hwndMain;
        ofn.lpstrFilter = "File Subtitle (*.srt)\0*.srt\0Semua File (*.*)\0*.*\0";
        ofn.lpstrFile = filename;
        ofn.nMaxFile = MAX_PATH;
        ofn.Flags = OFN_EXPLORER | OFN_FILEMUSTEXIST;
        ofn.lpstrTitle = "Pilih File Subtitle Video (.srt)";
        if (GetOpenFileNameA(&ofn)) {
            g_outputSrtPath = filename;
        } else {
            return;
        }
    }

    ShellExecuteA(NULL, "open", g_outputSrtPath.c_str(), NULL, NULL, SW_SHOWNORMAL);
}

// Toggle Mulai/Berhenti Transkripsi
void OnToggleTranscription() {
    if (g_isTranscribing) {
        g_isTranscribing = false;
        SetStatusText("Transkripsi dihentikan pengguna.");
        SetWindowTextA(g_hwndBtnStart, "▶️ Mulai Transkripsi");
        if (g_workerThread.joinable()) {
            g_workerThread.detach();
        }
        return;
    }

    char videoBuf[MAX_PATH];
    GetWindowTextA(g_hwndTxtVideo, videoBuf, MAX_PATH);
    g_videoPath = videoBuf;

    if (g_videoPath.empty() || GetFileAttributesA(g_videoPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
        MessageBoxA(g_hwndMain, "Silakan pilih file video yang valid terlebih dahulu!", "File Tidak Ditemukan", MB_ICONWARNING);
        return;
    }

    int selIdx = (int)SendMessage(g_hwndCmbLang, CB_GETCURSEL, 0, 0);
    std::string langCode = "id";
    std::string langName = "Bahasa Indonesia";
    if (selIdx == 1) {
        langCode = "cn";
        langName = "Bahasa Mandarin (China)";
    } else if (selIdx == 2) {
        langCode = "ja";
        langName = "Bahasa Jepang (Japan)";
    }
    std::string modelPath = DetectModelFolder(langCode);

    if (modelPath.empty()) {
        MessageBoxA(g_hwndMain, 
            "Model offline Vosk belum ditemukan!\r\n"
            "Silakan unduh model dengan skrip 'unduh_model.ps1' atau letakkan model di folder 'models/'.", 
            "Model Tidak Ditemukan", MB_ICONERROR);
        return;
    }

    g_isTranscribing = true;
    SetWindowTextA(g_hwndBtnStart, "⏹️ Hentikan Transkripsi");
    SetWindowTextA(g_hwndTxtOutput, "");

    AppendOutputText("=== MEMULAI TRANSKRIPSI VIDEO DARI DETIK KE-0 SAMPAI SELESAI ===\r\n");
    AppendOutputText("File Video : " + g_videoPath + "\r\n");
    AppendOutputText("Bahasa     : " + langName + "\r\n");
    AppendOutputText("Model Vosk    : " + modelPath + "\r\n");
    AppendOutputText("File Nota     : " + g_outputTxtPath + "\r\n");
    AppendOutputText("File Subtitle : " + g_outputSrtPath + "\r\n");
    AppendOutputText("Metode        : Streaming audio on-the-fly (tanpa ekstraksi file audio di harddisk)\r\n\r\n");

    if (g_workerThread.joinable()) {
        g_workerThread.join();
    }
    g_workerThread = std::thread(TranscriptionWorker, g_videoPath, modelPath, g_outputTxtPath, g_outputSrtPath);
}

// Window Procedure GUI
LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_CREATE: {
        HFONT hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);

        // Label File Video
        HWND lbl1 = CreateWindowA("STATIC", "File Video (.mp4/.mkv):", WS_VISIBLE | WS_CHILD, 15, 18, 150, 20, hwnd, NULL, NULL, NULL);
        SendMessage(lbl1, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Input Path Video
        g_hwndTxtVideo = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "", WS_VISIBLE | WS_CHILD | ES_AUTOHSCROLL, 170, 15, 480, 24, hwnd, (HMENU)ID_TXT_VIDEO, NULL, NULL);
        SendMessage(g_hwndTxtVideo, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Tombol Buka File
        g_hwndBtnBrowse = CreateWindowA("BUTTON", "📁 Buka File", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON, 660, 14, 110, 26, hwnd, (HMENU)ID_BTN_BROWSE, NULL, NULL);
        SendMessage(g_hwndBtnBrowse, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Label Bahasa
        HWND lbl2 = CreateWindowA("STATIC", "Pilihan Bahasa:", WS_VISIBLE | WS_CHILD, 15, 53, 150, 20, hwnd, NULL, NULL, NULL);
        SendMessage(lbl2, WM_SETFONT, (WPARAM)hFont, TRUE);

        // ComboBox Bahasa
        g_hwndCmbLang = CreateWindowA("COMBOBOX", "", WS_VISIBLE | WS_CHILD | CBS_DROPDOWNLIST, 170, 50, 200, 120, hwnd, (HMENU)ID_CMB_LANG, NULL, NULL);
        SendMessageA(g_hwndCmbLang, CB_ADDSTRING, 0, (LPARAM)"Bahasa Indonesia");
        SendMessageA(g_hwndCmbLang, CB_ADDSTRING, 0, (LPARAM)"Bahasa Mandarin (China)");
        SendMessageA(g_hwndCmbLang, CB_ADDSTRING, 0, (LPARAM)"Bahasa Jepang (Japan)");
        SendMessageA(g_hwndCmbLang, CB_SETCURSEL, 0, 0);
        SendMessage(g_hwndCmbLang, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Tombol Mulai Transkripsi
        g_hwndBtnStart = CreateWindowA("BUTTON", "▶️ Mulai Transkripsi", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON, 170, 85, 140, 30, hwnd, (HMENU)ID_BTN_START, NULL, NULL);
        SendMessage(g_hwndBtnStart, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Tombol Baca Nota
        g_hwndBtnReadNote = CreateWindowA("BUTTON", "📝 Baca Nota (.TXT)", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON, 318, 85, 145, 30, hwnd, (HMENU)ID_BTN_READ_NOTE, NULL, NULL);
        SendMessage(g_hwndBtnReadNote, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Tombol Baca Subtitle
        g_hwndBtnReadSrt = CreateWindowA("BUTTON", "🎬 Baca Subtitle (.SRT)", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON, 470, 85, 160, 30, hwnd, (HMENU)ID_BTN_READ_SRT, NULL, NULL);
        SendMessage(g_hwndBtnReadSrt, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Tombol Hapus Layar
        g_hwndBtnClear = CreateWindowA("BUTTON", "🗑️ Hapus", WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON, 638, 85, 95, 30, hwnd, (HMENU)ID_BTN_CLEAR, NULL, NULL);
        SendMessage(g_hwndBtnClear, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Label Status
        g_hwndLblStatus = CreateWindowA("STATIC", "Status: Siap. Silakan klik 'Buka File' untuk memilih video.", WS_VISIBLE | WS_CHILD, 15, 125, 755, 20, hwnd, (HMENU)ID_LBL_STATUS, NULL, NULL);
        SendMessage(g_hwndLblStatus, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Edit Area Hasil Transkripsi (Multiline, Readonly, Scrollbar)
        g_hwndTxtOutput = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
            WS_VISIBLE | WS_CHILD | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY | WS_VSCROLL,
            15, 155, 755, 420, hwnd, (HMENU)ID_TXT_OUTPUT, NULL, NULL);
        SendMessage(g_hwndTxtOutput, WM_SETFONT, (WPARAM)hFont, TRUE);
        break;
    }
    case WM_COMMAND: {
        int id = LOWORD(wParam);
        if (id == ID_BTN_BROWSE) {
            OnBrowseFile();
        } else if (id == ID_BTN_START) {
            OnToggleTranscription();
        } else if (id == ID_BTN_READ_NOTE) {
            OnReadNote();
        } else if (id == ID_BTN_READ_SRT) {
            OnReadSrt();
        } else if (id == ID_BTN_CLEAR) {
            if (MessageBoxA(hwnd, "Bersihkan seluruh hasil transkripsi di layar?", "Konfirmasi Hapus", MB_YESNO | MB_ICONQUESTION) == IDYES) {
                SetWindowTextA(g_hwndTxtOutput, "");
                SetWindowTextA(g_hwndLblStatus, "Status: Layar transkripsi telah dibersihkan.");
            }
        }
        break;
    }
    case WM_DESTROY:
        g_isTranscribing = false;
        if (g_workerThread.joinable()) {
            g_workerThread.detach();
        }
        PostQuitMessage(0);
        break;
    default:
        return DefWindowProcA(hwnd, msg, wParam, lParam);
    }
    return 0;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    vosk_set_log_level(-1);

    const char CLASS_NAME[] = "TranskripsiVideoOfflineApp";
    WNDCLASSA wc = {};
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = CLASS_NAME;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);

    RegisterClassA(&wc);

    g_hwndMain = CreateWindowExA(
        0, CLASS_NAME, "Transkripsi Video Offline - C++ Win32 GUI (Vosk & FFmpeg Streaming)",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT, CW_USEDEFAULT, 805, 630,
        NULL, NULL, hInstance, NULL
    );

    if (!g_hwndMain) return 0;

    ShowWindow(g_hwndMain, nCmdShow);
    UpdateWindow(g_hwndMain);

    MSG msg = {};
    while (GetMessageA(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    return (int)msg.wParam;
}

