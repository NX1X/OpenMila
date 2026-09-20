// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Windows headers Swift needs for the platform layer, in one place. Swift's
// WinSDK module covers most of Win32, but the shell, crypto and multimedia
// headers below are either absent from it or need the macros expanded here.
#ifndef CWINSHIM_H
#define CWINSHIM_H

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shlobj.h>
#include <dpapi.h>
#include <tlhelp32.h>
#include <shellapi.h>
#include <softpub.h>
#include <wintrust.h>

// WINTRUST_ACTION_GENERIC_VERIFY_V2 is a GUID initialiser macro, which Swift
// cannot import; expose it as a function instead.
static inline GUID om_wintrust_generic_verify_v2(void) {
    GUID guid = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    return guid;
}

// The notification-area message the tray icon uses.
#define OM_WM_TRAYICON (WM_APP + 1)
#endif

#endif
