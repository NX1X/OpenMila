// Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0.
#include "include/CWinShim.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <wintrust.h>
#include <softpub.h>
#include <string.h>

void *om_hwnd_message(void) { return (void *)HWND_MESSAGE; }

const uint16_t *om_idi_application(void) { return (const uint16_t *)IDI_APPLICATION; }

// SetCurrentProcessExplicitAppUserModelID lives in shell32 and is declared in
// shobjidl_core.h, which drags in a large part of the COM headers; it is
// resolved at run time instead, which also keeps the call harmless on a
// Windows build where the export is somehow missing.
// dwmapi is resolved at run time for the same reason shell32 is above: no
// link-time dependency, and a Windows too old to have the attribute simply
// leaves the caption alone.
typedef HRESULT(WINAPI *dwm_set_attr_fn)(HWND, DWORD, LPCVOID, DWORD);

struct om_title_bar_args {
    dwm_set_attr_fn set;
    BOOL dark;
    DWORD caption;
    DWORD text;
    DWORD pid;
    int32_t touched;
};

static BOOL CALLBACK om_title_bar_apply(HWND window, LPARAM parameter) {
    struct om_title_bar_args *args = (struct om_title_bar_args *)parameter;
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner != args->pid) return TRUE;
    if (!IsWindowVisible(window)) return TRUE;
    // Attribute numbers from dwmapi.h: 20 DWMWA_USE_IMMERSIVE_DARK_MODE
    // (Windows 10 20H1+), 35 DWMWA_CAPTION_COLOR and 36 DWMWA_TEXT_COLOR
    // (Windows 11). Older systems return an error for the ones they lack,
    // which is fine: the bar then stays as Windows drew it.
    args->set(window, 20, &args->dark, sizeof(args->dark));
    if (args->caption != 0xFFFFFFFF) args->set(window, 35, &args->caption, sizeof(args->caption));
    if (args->text != 0xFFFFFFFF) args->set(window, 36, &args->text, sizeof(args->text));
    args->touched += 1;
    return TRUE;
}

int32_t om_apply_title_bar_theme(int32_t dark, uint32_t caption, uint32_t text) {
    HMODULE dwm = LoadLibraryW(L"dwmapi.dll");
    if (!dwm) return -1;
    dwm_set_attr_fn set = (dwm_set_attr_fn)(void *)GetProcAddress(dwm, "DwmSetWindowAttribute");
    int32_t touched = -1;
    if (set) {
        struct om_title_bar_args args = { set, dark ? TRUE : FALSE, caption, text,
                                          GetCurrentProcessId(), 0 };
        EnumWindows(om_title_bar_apply, (LPARAM)&args);
        touched = args.touched;
    }
    FreeLibrary(dwm);
    return touched;
}

int32_t om_apps_use_dark_theme(void) {
    DWORD value = 1;
    DWORD size = sizeof(value);
    LSTATUS status = RegGetValueW(HKEY_CURRENT_USER,
                                  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                                  L"AppsUseLightTheme", RRF_RT_REG_DWORD, NULL, &value, &size);
    if (status != ERROR_SUCCESS) return -1;
    return value == 0 ? 1 : 0;
}

int32_t om_set_app_user_model_id(const uint16_t *id) {
    typedef HRESULT(WINAPI * set_id_fn)(PCWSTR);
    HMODULE shell = LoadLibraryW(L"shell32.dll");
    if (!shell) return -1;
    set_id_fn set_id = (set_id_fn)(void *)GetProcAddress(shell, "SetCurrentProcessExplicitAppUserModelID");
    int32_t result = -1;
    if (set_id) result = SUCCEEDED(set_id((PCWSTR)id)) ? 0 : -2;
    FreeLibrary(shell);
    return result;
}

// Reads the subject name of the certificate that signed `path` into `subject`.
// Separate from the trust decision on purpose: trust says the chain is good,
// this says who it belongs to, and the caller needs both.
static void om_signer_subject(LPCWSTR path, uint16_t *subject, int32_t capacity) {
    if (capacity > 0) subject[0] = 0;

    HCERTSTORE store = NULL;
    HCRYPTMSG message = NULL;
    if (!CryptQueryObject(CERT_QUERY_OBJECT_FILE, path,
                          CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED_EMBED,
                          CERT_QUERY_FORMAT_FLAG_BINARY, 0, NULL, NULL, NULL,
                          &store, &message, NULL)) {
        return;
    }

    DWORD size = 0;
    CMSG_SIGNER_INFO *signer = NULL;
    if (CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0, NULL, &size) && size > 0) {
        signer = (CMSG_SIGNER_INFO *)LocalAlloc(LPTR, size);
    }
    if (signer && CryptMsgGetParam(message, CMSG_SIGNER_INFO_PARAM, 0, signer, &size)) {
        CERT_INFO info;
        info.Issuer = signer->Issuer;
        info.SerialNumber = signer->SerialNumber;
        PCCERT_CONTEXT certificate = CertFindCertificateInStore(
            store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
            CERT_FIND_SUBJECT_CERT, &info, NULL);
        if (certificate) {
            CertGetNameStringW(certificate, CERT_NAME_SIMPLE_DISPLAY_TYPE, 0, NULL,
                               (LPWSTR)subject, (DWORD)capacity);
            CertFreeCertificateContext(certificate);
        }
    }
    if (signer) LocalFree(signer);
    if (message) CryptMsgClose(message);
    if (store) CertCloseStore(store, 0);
}

int32_t om_verify_authenticode(const uint16_t *path, uint16_t *subject, int32_t capacity) {
    WINTRUST_FILE_INFO file;
    memset(&file, 0, sizeof(file));
    file.cbStruct = sizeof(file);
    file.pcwszFilePath = (LPCWSTR)path;

    WINTRUST_DATA data;
    memset(&data, 0, sizeof(data));
    data.cbStruct = sizeof(data);
    data.dwUIChoice = WTD_UI_NONE;
    data.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
    data.dwUnionChoice = WTD_CHOICE_FILE;
    data.dwStateAction = WTD_STATEACTION_VERIFY;
    data.dwProvFlags = WTD_SAFER_FLAG;
    data.pFile = &file;

    GUID action = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    LONG status = WinVerifyTrust(NULL, &action, &data);

    data.dwStateAction = WTD_STATEACTION_CLOSE;
    WinVerifyTrust(NULL, &action, &data);

    if (status == 0) om_signer_subject((LPCWSTR)path, subject, capacity);
    return (int32_t)status;
}
#else
// The target builds on every platform so the manifest stays simple; off
// Windows it has nothing to do, and C forbids an empty translation unit.
void *om_hwnd_message(void) { return 0; }
const uint16_t *om_idi_application(void) { return 0; }
int32_t om_verify_authenticode(const uint16_t *path, uint16_t *subject, int32_t capacity) {
    (void)path;
    if (capacity > 0) subject[0] = 0;
    return -1;
}
#endif
