// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#include "include/CWinShim.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <wintrust.h>
#include <softpub.h>
#include <string.h>

void om_wintrust_generic_verify_v2(uint8_t out[16]) {
    GUID guid = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    memcpy(out, &guid, sizeof(guid));
}
#else
// The target builds on every platform so the manifest stays simple; off
// Windows it has no contents, and C forbids an empty translation unit.
void om_wintrust_generic_verify_v2(uint8_t out[16]) { (void)out; }
#endif
