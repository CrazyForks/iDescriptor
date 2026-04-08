/*
 * iDescriptor: A free and open-source idevice management tool.
 *
 * Copyright (C) 2025 Uncore <https://github.com/uncor3>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "win_common.h"
#include <string>
#include <windows.h>
#include <winsvc.h>

bool IsServiceRunning(LPCSTR serviceName)
{
    SC_HANDLE scm = OpenSCManagerA(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) {
        return false;
    }

    SC_HANDLE svc = OpenServiceA(scm, serviceName, SERVICE_QUERY_STATUS);
    if (!svc) {
        CloseServiceHandle(scm);
        return false;
    }

    SERVICE_STATUS_PROCESS status;
    DWORD bytesNeeded = 0;
    bool isRunning = false;

    if (QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                             reinterpret_cast<LPBYTE>(&status), sizeof(status),
                             &bytesNeeded)) {
        isRunning = (status.dwCurrentState == SERVICE_RUNNING);
    }

    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return isRunning;
}

bool CheckRegistry(HKEY hKeyRoot, LPCSTR subKey, LPCSTR displayNameToFind)
{
    HKEY hKey;
    if (RegOpenKeyExA(hKeyRoot, subKey, 0, KEY_READ, &hKey) != ERROR_SUCCESS) {
        return false;
    }

    char keyName[256];
    DWORD keyNameSize = sizeof(keyName);
    DWORD index = 0;

    while (RegEnumKeyExA(hKey, index++, keyName, &keyNameSize, NULL, NULL, NULL,
                         NULL) == ERROR_SUCCESS) {
        HKEY appKey;
        if (RegOpenKeyExA(hKey, keyName, 0, KEY_READ, &appKey) ==
            ERROR_SUCCESS) {
            char displayName[256];
            DWORD displayNameSize = sizeof(displayName);
            if (RegQueryValueExA(appKey, "DisplayName", NULL, NULL,
                                 (LPBYTE)displayName,
                                 &displayNameSize) == ERROR_SUCCESS) {
                if (strcmp(displayName, displayNameToFind) == 0) {
                    RegCloseKey(appKey);
                    RegCloseKey(hKey);
                    return true;
                }
            }
            RegCloseKey(appKey);
        }
        keyNameSize = sizeof(keyName);
    }

    RegCloseKey(hKey);
    return false;
}

bool CheckRegistryKeyExists(HKEY hKeyRoot, LPCSTR subKey)
{
    HKEY hKey;
    LONG result = RegOpenKeyExA(hKeyRoot, subKey, 0, KEY_READ, &hKey);
    if (result == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return true;
    }
    return false;
}

SERVICE_AVAILABILITY IsAppleMobileDeviceSupportInstalled()
{
    bool installed = false;

    if (CheckRegistry(HKEY_LOCAL_MACHINE,
                      "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                      "Apple Mobile Device Support")) {
        installed = true;
    } else if (CheckRegistry(HKEY_LOCAL_MACHINE,
                             "SOFTWARE\\WOW6432Node\\Microsoft\\Wi"
                             "ndows\\CurrentVersion\\Uninstall",
                             "Apple Mobile Device Support")) {
        installed = true;
    }

    if (!installed) {
        return SERVICE_UNAVAILABLE;
    }

    if (IsServiceRunning("Apple Mobile Device Service")) {
        return SERVICE_AVAILABLE;
    }

    return SERVICE_AVAILABLE_BUT_NOT_RUNNING;
}

SERVICE_AVAILABILITY IsWinFspInstalled()
{
    bool installed = false;

    if (CheckRegistry(HKEY_LOCAL_MACHINE,
                      "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                      "WinFsp 2025")) {
        installed = true;
    } else if (CheckRegistry(HKEY_LOCAL_MACHINE,
                             "SOFTWARE\\WOW6432Node\\Microsoft\\Wi"
                             "ndows\\CurrentVersion\\Uninstall",
                             "WinFsp 2025")) {
        installed = true;
    }

    if (!installed) {
        return SERVICE_UNAVAILABLE;
    }

    if (IsServiceRunning("WinFsp.Launcher")) {
        return SERVICE_AVAILABLE;
    }

    return SERVICE_AVAILABLE_BUT_NOT_RUNNING;
}

bool is_iDescriptorInstalled()
{
    if (CheckRegistry(HKEY_LOCAL_MACHINE,
                      "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                      "iDescriptor")) {
        return true;
    }
    if (CheckRegistry(HKEY_LOCAL_MACHINE,
                      "SOFTWARE\\WOW6432Node\\Microsoft\\Wi"
                      "ndows\\CurrentVersion\\Uninstall",
                      "iDescriptor")) {
        return true;
    }
    return false;
}

bool StartServiceByName(LPCSTR serviceName, DWORD timeoutMs = 30000)
{
    SC_HANDLE scm = OpenSCManagerA(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) {
        return false;
    }

    SC_HANDLE svc = OpenServiceA(scm, serviceName,
                                 SERVICE_START | SERVICE_QUERY_STATUS |
                                     SERVICE_CHANGE_CONFIG);
    if (!svc) {
        CloseServiceHandle(scm);
        return false;
    }

    // set startup type to Automatic
    ChangeServiceConfigA(svc,
                         SERVICE_NO_CHANGE,  // service type
                         SERVICE_AUTO_START, // start type
                         SERVICE_NO_CHANGE,  // error control
                         nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
                         nullptr);

    SERVICE_STATUS_PROCESS status;
    DWORD bytesNeeded = 0;

    if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                              reinterpret_cast<LPBYTE>(&status), sizeof(status),
                              &bytesNeeded)) {
        CloseServiceHandle(svc);
        CloseServiceHandle(scm);
        return false;
    }

    if (status.dwCurrentState == SERVICE_RUNNING) {
        CloseServiceHandle(svc);
        CloseServiceHandle(scm);
        return true;
    }

    if (!StartServiceA(svc, 0, nullptr)) {
        CloseServiceHandle(svc);
        CloseServiceHandle(scm);
        return false;
    }

    DWORD startTick = GetTickCount();
    do {
        Sleep(500);

        if (!QueryServiceStatusEx(svc, SC_STATUS_PROCESS_INFO,
                                  reinterpret_cast<LPBYTE>(&status),
                                  sizeof(status), &bytesNeeded)) {
            break;
        }

        if (status.dwCurrentState == SERVICE_RUNNING) {
            CloseServiceHandle(svc);
            CloseServiceHandle(scm);
            return true;
        }

    } while (GetTickCount() - startTick < timeoutMs &&
             (status.dwCurrentState == SERVICE_START_PENDING));

    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    return false;
}

SERVICE_AVAILABILITY IsBonjourServiceInstalled()
{
    bool installed = CheckRegistryKeyExists(HKEY_LOCAL_MACHINE,
                                            "SOFTWARE\\Apple Inc.\\Bonjour");
    if (!installed) {
        return SERVICE_UNAVAILABLE;
    }

    // Modern Bonjour service name
    if (IsServiceRunning("Bonjour Service")) {
        return SERVICE_AVAILABLE;
    }

    // Fallback for older installs
    if (IsServiceRunning("mDNSResponder")) {
        return SERVICE_AVAILABLE;
    }

    return SERVICE_AVAILABLE_BUT_NOT_RUNNING;
}

/* These require the app to be run as Administrator */
// bool StartBonjourService()
// {
//     // Modern Bonjour service name
//     if (IsServiceRunning("Bonjour Service")) {
//         return true;
//     }
//     if (StartServiceByName("Bonjour Service")) {
//         return true;
//     }

//     // Apparently it used to be called mDNSResponder
//     if (IsServiceRunning("mDNSResponder")) {
//         return true;
//     }
//     if (StartServiceByName("mDNSResponder")) {
//         return true;
//     }

//     return false;
// }

// bool StartAppleMobileDeviceService()
// {
//     if (IsServiceRunning("Apple Mobile Device Service")) {
//         return true;
//     }
//     return StartServiceByName("Apple Mobile Device Service");
// }

// bool StartWinFspService()
// {
//     if (IsServiceRunning("WinFsp.Launcher")) {
//         return true;
//     }
//     return StartServiceByName("WinFsp.Launcher");
// }