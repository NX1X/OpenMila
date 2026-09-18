// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
//
// Pseudo-terminal functions. glibc only declares them under _XOPEN_SOURCE, which
// Swift's Glibc module map does not define, so they are invisible to Swift even
// though libc exports them. These prototypes match glibc's own declarations.
#ifndef COPENMILAPOSIX_H
#define COPENMILAPOSIX_H

#if defined(__linux__)
int posix_openpt(int flags);
int grantpt(int fd);
int unlockpt(int fd);
char *ptsname(int fd);
#endif

#endif
