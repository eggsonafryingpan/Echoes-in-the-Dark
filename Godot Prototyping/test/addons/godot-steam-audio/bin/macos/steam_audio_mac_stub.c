// Mac stand-in for godot-steam-audio, which has no macOS build.
//
// Without a macOS entry in libgodot-steam-audio.gdextension, Godot prints
// "No GDExtension library found for current OS" (and two follow-on errors) at
// every launch on a Mac. This library gives it something to load: it reports
// success and registers nothing, so Steam Audio classes simply don't exist on
// Mac (they never did). Windows, Linux and Android keep loading the real one.
//
// Build (universal, run from this folder):
//   clang -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 \
//     -o libsteam_audio_mac_stub.dylib steam_audio_mac_stub.c
//
// The two declarations below mirror Godot's gdextension_interface.h.

#include <stdint.h>

typedef enum {
	GDEXTENSION_INITIALIZATION_CORE,
	GDEXTENSION_INITIALIZATION_SERVERS,
	GDEXTENSION_INITIALIZATION_SCENE,
	GDEXTENSION_INITIALIZATION_EDITOR,
	GDEXTENSION_MAX_INITIALIZATION_LEVEL,
} GDExtensionInitializationLevel;

typedef struct {
	GDExtensionInitializationLevel minimum_initialization_level;
	void *userdata;
	void (*initialize)(void *userdata, GDExtensionInitializationLevel p_level);
	void (*deinitialize)(void *userdata, GDExtensionInitializationLevel p_level);
} GDExtensionInitialization;

static void nothing(void *userdata, GDExtensionInitializationLevel p_level) {
	(void)userdata;
	(void)p_level;
}

__attribute__((visibility("default")))
uint8_t init_extension(void *p_get_proc_address, void *p_library, GDExtensionInitialization *r_initialization) {
	(void)p_get_proc_address;
	(void)p_library;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = 0;
	r_initialization->initialize = nothing;
	r_initialization->deinitialize = nothing;
	return 1;
}
