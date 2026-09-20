// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Win32 values Swift's WinSDK module does not expose, and the port's own
// window messages. Anything that needs a Windows type to compute belongs
// here rather than in CWinShim, whose header must stay free of Windows
// headers (see Port/CWinShim/include/CWinShim.h).
#if os(Windows)
import WinSDK

/// The notification-area message the tray icon posts back to our window.
/// Applications own everything from `WM_APP` upwards.
let omTrayIconMessage = UINT(WM_APP) + 1
#endif
