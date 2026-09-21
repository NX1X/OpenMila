// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The Win32 details Swift cannot reach, behind plain C types.
//
// This header deliberately includes NO Windows header. Swift imports the
// Windows SDK through its own WinSDK module, and a second module that also
// parses those headers fails: wintrust.h reached through a module map broke
// with "missing '#include <windef.h>'; 'HWND' must be declared before it is
// used". The SDK headers are therefore included by CWinShim.c only, which is
// an ordinary translation unit.
//
// What lives here is what WinSDK does not export at all (the whole wintrust
// surface: WINTRUST_DATA, WinVerifyTrust, the WTD_* constants) and the macros
// that expand to a cast pointer, which Swift cannot import (HWND_MESSAGE,
// IDI_APPLICATION).
#ifndef CWINSHIM_H
#define CWINSHIM_H

#include <stdint.h>

// SwiftPM treats include/CWinShim.h as this target's umbrella header, so a
// header that is not reached from here is invisible to Swift however public
// the directory is.
#include "om_process_loopback.h"

/// `HWND_MESSAGE`: the parent that makes a window message-only.
void *om_hwnd_message(void);

/// `IDI_APPLICATION` as `LoadIconW` wants it (a MAKEINTRESOURCE pointer).
const uint16_t *om_idi_application(void);

/// Authenticode verification for `path` (a NUL-terminated UTF-16 string).
///
/// Returns 0 when the file carries a signature that chains to a trusted root;
/// any other value is the provider's status and means untrusted. On success
/// the signer's subject name is written to `subject` as NUL-terminated UTF-16
/// (truncated to `capacity`), so the caller can check WHO signed it: a valid
/// signature by anyone is not enough. `subject` is left empty if the name
/// cannot be read, which callers must treat as a failed publisher check.
int32_t om_verify_authenticode(const uint16_t *path, uint16_t *subject, int32_t capacity);

// Names this process for the taskbar. Windows groups a window under the
// shortcut that launched it only when both carry the same AppUserModelID, and
// the installer stamps "NX1X.OpenMila" on its shortcuts, so the process has to
// say the same thing before it shows a window. Returns 0 on success.
int32_t om_set_app_user_model_id(const uint16_t *id);

// Paints the title bars of this process's top-level windows to match the app.
// WinUI themes everything inside the window and nothing outside it, so a dark
// app sat under a white caption bar. `dark` chooses the immersive dark caption;
// `caption`, `text` are 0x00BBGGRR colours for the bar and its title, or
// 0xFFFFFFFF to leave Windows' defaults. Returns how many windows were
// touched. Safe to call again: it re-applies to any window that has appeared.
int32_t om_apply_title_bar_theme(int32_t dark, uint32_t caption, uint32_t text);

// Whether Windows itself is in dark mode for applications, from
// AppsUseLightTheme in the user's registry. 1 dark, 0 light, -1 unknown.
int32_t om_apps_use_dark_theme(void);

#endif
