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

#endif
