// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// GIO, for the XDG desktop portals. Wayland has no way for an application to
// grab a key combination for itself: the compositor owns input, and the only
// route is the GlobalShortcuts portal over D-Bus. GIO is the D-Bus client
// already present on any desktop running GTK, which the app needs anyway.
#include <gio/gio.h>
