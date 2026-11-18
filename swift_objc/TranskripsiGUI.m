#import <Cocoa/Cocoa.h>

// ==============================================================================
// Transkripsi Video Offline - Objective-C macOS GUI (Cocoa / AppKit)
// Menggunakan FFmpeg Audio Streaming on-the-fly & Vosk Offline Engine
// Mendukung Bahasa Indonesia & Bahasa Mandarin (China)
// ==============================================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong, nonatomic) NSWindow *window;
@property (strong, nonatomic) NSTextField *txtVideoPath;
@property (strong, nonatomic) NSPopUpButton *cmbLanguage;
@property (strong, nonatomic) NSButton *btnBrowse;
@property (strong, nonatomic) NSButton *btnStart;
@property (strong, nonatomic) NSButton *btnReadNote;
@property (strong, nonatomic) NSButton *btnReadSrt;
@property (strong, nonatomic) NSButton *btnClear;
@property (strong, nonatomic) NSTextView *txtOutput;
@property (strong, nonatomic) NSTextField *lblStatus;
@property (strong, nonatomic) NSProgressIndicator *progressIndicator;

@property (copy, nonatomic) NSString *videoPath;
@property (copy, nonatomic) NSString *outputTxtPath;
@property (copy, nonatomic) NSString *outputSrtPath;
@property (assign, nonatomic) BOOL isTranscribing;
@property (strong, nonatomic) NSTask *currentTask;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSRect frame = NSMakeRect(100, 100, 800, 640);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled |
                                                         NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable |
                                                         NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"Transkripsi Video Offline - Objective-C GUI (Vosk Streaming)"];
    [self.window setDelegate:self];

    NSView *contentView = [self.window contentView];

    // Label & Field Video
    NSTextField *lblVideo = [NSTextField labelWithString:@"File Video (.mp4/.mkv):"];
    [lblVideo setFrame:NSMakeRect(20, 590, 160, 22)];
    [contentView addSubview:lblVideo];

    self.txtVideoPath = [[NSTextField alloc] initWithFrame:NSMakeRect(180, 590, 460, 24)];
    [contentView addSubview:self.txtVideoPath];

    self.btnBrowse = [NSButton buttonWithTitle:@"📁 Buka File" target:self action:@selector(onBrowseVideo:)];
    [self.btnBrowse setFrame:NSMakeRect(650, 588, 130, 28)];
    [contentView addSubview:self.btnBrowse];

    // Pilihan Bahasa
    NSTextField *lblLang = [NSTextField labelWithString:@"Pilihan Bahasa:"];
    [lblLang setFrame:NSMakeRect(20, 550, 160, 22)];
    [contentView addSubview:lblLang];

    self.cmbLanguage = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, 548, 220, 26) pullsDown:NO];
    [self.cmbLanguage addItemsWithTitles:@[@"Bahasa Indonesia", @"Bahasa Mandarin (China)", @"Bahasa Jepang (Japan)"]];
    [contentView addSubview:self.cmbLanguage];

    // Tombol Aksi
    self.btnStart = [NSButton buttonWithTitle:@"▶️ Mulai Transkripsi" target:self action:@selector(onToggleTranscription:)];
    [self.btnStart setFrame:NSMakeRect(180, 508, 170, 32)];
    [self.btnStart setBezelStyle:NSBezelStyleRounded];
    [contentView addSubview:self.btnStart];

    self.btnReadNote = [NSButton buttonWithTitle:@"📝 Baca Nota (Buka TXT)" target:self action:@selector(onReadNote:)];
    [self.btnReadNote setFrame:NSMakeRect(360, 508, 180, 32)];
    [self.btnReadNote setBezelStyle:NSBezelStyleRounded];
    [contentView addSubview:self.btnReadNote];

    // Status Label & Progress
    self.lblStatus = [NSTextField labelWithString:@"Status: Siap. Silakan klik 'Buka File' untuk memilih video."];
    [self.lblStatus setFrame:NSMakeRect(20, 475, 760, 20)];
    [self.lblStatus setFont:[NSFont italicSystemFontOfSize:11]];
    [contentView addSubview:self.lblStatus];

    self.progressIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 455, 760, 16)];
    [self.progressIndicator setIndeterminate:YES];
    [self.progressIndicator setStyle:NSProgressIndicatorStyleBar];
    [contentView addSubview:self.progressIndicator];

    // Area Teks Output
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 20, 760, 425)];
    [scroll setBorderType:NSBezelBorder];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    self.txtOutput = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 760, 425)];
    [self.txtOutput setEditable:NO];
    [self.txtOutput setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
    [scroll setDocumentView:self.txtOutput];
    [contentView addSubview:scroll];

    [self.window makeKeyAndOrderFront:nil];
}

- (void)onBrowseVideo:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setTitle:@"Pilih File Video Berdurasi Panjang"];
    [panel setAllowedFileTypes:@[@"mp4", @"mkv", @"avi", @"mov", @"webm", @"flv"]];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];

    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = [[panel URLs] firstObject];
        self.videoPath = [url path];
        [self.txtVideoPath setStringValue:self.videoPath];

        NSString *dir = [[url URLByDeletingLastPathComponent] path];
        NSString *baseName = [[url URLByDeletingPathExtension] lastPathComponent];
        self.outputTxtPath = [NSString stringWithFormat:@"%@/%@_transkripsi.txt", dir, baseName];

        [self.lblStatus setStringValue:[NSString stringWithFormat:@"File dipilih. Nota akan disimpan ke: %@", self.outputTxtPath]];
    }
}

- (void)onReadNote:(id)sender {
    NSString *path = self.outputTxtPath;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setTitle:@"Pilih File Nota Transkripsi (.txt)"];
        [panel setAllowedFileTypes:@[@"txt"]];
        if ([panel runModal] == NSModalResponseOK) {
            path = [[[panel URLs] firstObject] path];
        } else {
            return;
        }
    }
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (NSString *)detectModelPathForLanguage:(NSString *)langCode {
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSArray *searchPaths = @[
        [NSString stringWithFormat:@"%@/models/%@", cwd, langCode],
        [NSString stringWithFormat:@"%@/../models/%@", cwd, langCode],
        [NSString stringWithFormat:@"%@/models/vosk-model-small-%@-0.4", cwd, langCode],
        [NSString stringWithFormat:@"%@/models/vosk-model-small-%@-0.22", cwd, langCode]
    ];

    BOOL isDir = NO;
    for (NSString *p in searchPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&isDir] && isDir) {
            return p;
        }
    }
    return nil;
}

- (void)onToggleTranscription:(id)sender {
    if (self.isTranscribing) {
        self.isTranscribing = NO;
        if (self.currentTask && [self.currentTask isRunning]) {
            [self.currentTask terminate];
        }
        [self.btnStart setTitle:@"▶️ Mulai Transkripsi"];
        [self.progressIndicator stopAnimation:nil];
        [self.lblStatus setStringValue:@"Transkripsi dihentikan."];
        return;
    }

    self.videoPath = [[self.txtVideoPath stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (self.videoPath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:self.videoPath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"File Video Tidak Ditemukan"];
        [alert setInformativeText:@"Silakan pilih file video .mp4/.mkv yang valid terlebih dahulu."];
        [alert runModal];
        return;
    }

    NSInteger selIdx = [self.cmbLanguage indexOfSelectedItem];
    NSString *langCode = @"id";
    if (selIdx == 1) {
        langCode = @"cn";
    } else if (selIdx == 2) {
        langCode = @"ja";
    }
    NSString *modelPath = [self detectModelPathForLanguage:langCode];

    if (!modelPath) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Model Vosk Belum Ditemukan"];
        [alert setInformativeText:[NSString stringWithFormat:@"Model offline untuk %@ belum ada di folder 'models/%@'.", [self.cmbLanguage titleOfSelectedItem], langCode]];
        [alert runModal];
        return;
    }

    self.isTranscribing = YES;
    [self.btnStart setTitle:@"⏹️ Hentikan Transkripsi"];
    [self.progressIndicator startAnimation:nil];
    [self.txtOutput setString:@""];

    [self appendOutput:@"=== MEMULAI TRANSKRIPSI VIDEO DARI DETIK KE-0 SAMPAI SELESAI ===\n"];
    [self appendOutput:[NSString stringWithFormat:@"File Video : %@\n", self.videoPath]];
    [self appendOutput:[NSString stringWithFormat:@"Bahasa     : %@\n", [self.cmbLanguage titleOfSelectedItem]]];
    [self appendOutput:[NSString stringWithFormat:@"Model Vosk : %@\n", modelPath]];
    [self appendOutput:[NSString stringWithFormat:@"File Nota  : %@\n", self.outputTxtPath]];
    [self appendOutput:@"Metode     : Streaming audio on-the-fly via FFmpeg pipe (tanpa file audio terpisah)\n\n"];

    NSString *header = [NSString stringWithFormat:@"=== NOTA CATATAN TRANSKRIPSI (Objective-C) ===\nFile: %@\nBahasa: %@\n---------------------------------------------\n\n", self.videoPath, [self.cmbLanguage titleOfSelectedItem]];
    [header writeToFile:self.outputTxtPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [self.lblStatus setStringValue:@"Memproses streaming audio video secara on-the-fly..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self executeStreamingTranscriptionWithVideo:self.videoPath model:modelPath outputTxt:self.outputTxtPath];
    });
}

- (void)executeStreamingTranscriptionWithVideo:(NSString *)video model:(NSString *)model outputTxt:(NSString *)outTxt {
    NSString *pyScript = [NSString stringWithFormat:
        @"import sys, os, json, subprocess\n"
        @"from vosk import Model, KaldiRecognizer, SetLogLevel\n"
        @"SetLogLevel(-1)\n"
        @"video, model_path, out_txt = sys.argv[1], sys.argv[2], sys.argv[3]\n"
        @"m = Model(model_path)\n"
        @"rec = KaldiRecognizer(m, 16000.0)\n"
        @"rec.SetWords(True)\n"
        @"cmd = ['ffmpeg', '-loglevel', 'quiet', '-i', video, '-ar', '16000', '-ac', '1', '-f', 's16le', '-']\n"
        @"p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=4000)\n"
        @"while True:\n"
        @"    data = p.stdout.read(4000)\n"
        @"    if len(data) == 0: break\n"
        @"    if rec.AcceptWaveform(data):\n"
        @"        t = json.loads(rec.Result()).get('text', '').strip()\n"
        @"        if t:\n"
        @"            print(t, flush=True)\n"
        @"            with open(out_txt, 'a', encoding='utf-8') as f: f.write(t + '\\n')\n"
        @"final_t = json.loads(rec.FinalResult()).get('text', '').strip()\n"
        @"if final_t:\n"
        @"    print(final_t, flush=True)\n"
        @"    with open(out_txt, 'a', encoding='utf-8') as f: f.write(final_t + '\\n')\n"];

    NSString *tempPy = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vosk_objc_runner.py"];
    [pyScript writeToFile:tempPy atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/env"];
    [task setArguments:@[@"python3", tempPy, video, model, outTxt]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    self.currentTask = task;

    NSFileHandle *handle = [pipe fileHandleForReading];
    [handle setReadabilityHandler:^(NSFileHandle *h) {
        NSData *data = [h availableData];
        if (data.length > 0) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (str.length > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self appendOutput:str];
                });
            }
        }
    }];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendOutput:[NSString stringWithFormat:@"\n[Error]: %@\n", exception.reason]];
        });
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        self.isTranscribing = NO;
        [self.btnStart setTitle:@"▶️ Mulai Transkripsi"];
        [self.progressIndicator stopAnimation:nil];
        [self.lblStatus setStringValue:[NSString stringWithFormat:@"Selesai! Nota tersimpan di: %@", outTxt]];
        [self appendOutput:@"\n=== TRANSKRIPSI SELESAI DENGAN SUKSES ===\n"];

        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Transkripsi Selesai"];
        [alert setInformativeText:[NSString stringWithFormat:@"Nota otomatis disimpan di:\n%@\n\nKlik 'Baca Nota' untuk membuka.", outTxt]];
        [alert runModal];
    });
}

- (void)appendOutput:(NSString *)text {
    NSAttributedString *attr = [[NSAttributedString alloc] initWithString:text];
    [[self.txtOutput textStorage] appendAttributedString:attr];
    [self.txtOutput scrollToEndOfDocument:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}

