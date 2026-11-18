// vosk_api.h - Vosk Speech Recognition API Header for C/C++
#ifndef VOSK_API_H
#define VOSK_API_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VoskModel VoskModel;
typedef struct VoskRecognizer VoskRecognizer;

#if defined(_WIN32)
#ifdef VOSK_BUILD
#define VOSK_EXPORT __declspec(dllexport)
#else
#define VOSK_EXPORT __declspec(dllimport)
#endif
#else
#define VOSK_EXPORT __attribute__((visibility("default")))
#endif

// Model creation and lifecycle
VOSK_EXPORT VoskModel *vosk_model_new(const char *model_path);
VOSK_EXPORT void vosk_model_free(VoskModel *model);

// Recognizer lifecycle
VOSK_EXPORT VoskRecognizer *vosk_recognizer_new(VoskModel *model, float sample_rate);
VOSK_EXPORT void vosk_recognizer_free(VoskRecognizer *recognizer);
VOSK_EXPORT void vosk_recognizer_set_words(VoskRecognizer *recognizer, int words);

// Audio stream ingestion (Accepts raw PCM chunk)
VOSK_EXPORT int vosk_recognizer_accept_waveform(VoskRecognizer *recognizer, const char *data, int length);

// Results retrieval
VOSK_EXPORT const char *vosk_recognizer_result(VoskRecognizer *recognizer);
VOSK_EXPORT const char *vosk_recognizer_partial_result(VoskRecognizer *recognizer);
VOSK_EXPORT const char *vosk_recognizer_final_result(VoskRecognizer *recognizer);

// Log level
VOSK_EXPORT void vosk_set_log_level(int log_level);

#ifdef __cplusplus
}
#endif

#endif // VOSK_API_H

