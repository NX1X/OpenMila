// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// The few Win32 details Swift cannot express, behind plain C types.
//
// This header deliberately includes NO Windows header. Swift imports the
// Windows SDK through its own WinSDK module, and a second module that also
// parses those headers fails: wintrust.h reached through our module map broke
// with "missing '#include <windef.h>'; 'HWND' must be declared before it is
// used". The SDK headers are therefore included by CWinShim.c only, which is
// an ordinary translation unit, and everything crossing into Swift uses
// stdint types.
#ifndef CWINSHIM_H
#define CWINSHIM_H

#include <stdint.h>

/// Writes the 16 bytes of `WINTRUST_ACTION_GENERIC_VERIFY_V2` into `out`.
/// It is a GUID initialiser macro in wintrust.h, so Swift cannot import it;
/// the bytes are copied from the SDK's own definition rather than restated
/// here, where they could go stale or be mistyped.
void om_wintrust_generic_verify_v2(uint8_t out[16]);

#endif
