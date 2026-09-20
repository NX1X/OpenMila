// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// libsecret (the Secret Service: GNOME Keyring, KWallet's Secret Service
// interface, KeePassXC) for the Linux secret store. Only the non-variadic
// entry points are used, so Swift can call them: secret_schema_newv,
// secret_password_storev_sync, secret_password_lookupv_sync,
// secret_password_clearv_sync.
#include <libsecret/secret.h>
