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

#include "../../iDescriptor.h"
#include "../../servicemanager.h"
#include <QByteArray>
#include <QDebug>

QByteArray read_afc_file_to_byte_array(const iDescriptorDevice *device,
                                       const char *path)
{
    AfcFileHandle *handle = nullptr;
    IdeviceFfiError *err_open = // Use distinct variable name
        ServiceManager::safeAfcFileOpen(device, path, AfcRdOnly, &handle);

    if (err_open) {
        qDebug() << "Could not open file" << path
                 << "Error:" << err_open->message;
        idevice_error_free(err_open); // Free the error object
        return QByteArray();
    }

    AfcFileInfo info = {};
    IdeviceFfiError *err_info = // Use distinct variable name
        ServiceManager::safeAfcGetFileInfo(device, path, &info);

    if (err_info) {
        qDebug() << "Could not get file info for file" << path
                 << "Error:" << err_info->message;
        idevice_error_free(err_info); // Free the error object
        ServiceManager::safeAfcFileClose(device, handle); // Close handle
        return QByteArray();
    }

    size_t fileSize = info.size;
    if (fileSize == 0) {
        ServiceManager::safeAfcFileClose(device, handle);
        afc_file_info_free(&info); // Free internal strings of info
        return QByteArray();
    }

    QByteArray buffer;
    buffer.reserve(fileSize);

    uint8_t *chunkData = nullptr;
    size_t bytesRead = 0;
    IdeviceFfiError *read_err = ServiceManager::safeAfcFileRead(
        device, handle, &chunkData, fileSize, &bytesRead);

    if (read_err) {
        qDebug() << "AFC Error: Read failed for file" << path
                 << "Error:" << read_err->message;
        idevice_error_free(read_err);
        ServiceManager::safeAfcFileClose(device, handle);
        afc_file_info_free(&info); // Free internal strings of info
        return QByteArray();
    }

    buffer.append(reinterpret_cast<const char *>(chunkData), bytesRead);
    afc_file_read_data_free(chunkData, bytesRead);

    ServiceManager::safeAfcFileClose(device, handle);

    if (bytesRead != fileSize) {
        qDebug() << "AFC Error: Read mismatch for file" << path
                 << "Read:" << bytesRead << "Expected:" << fileSize;
        afc_file_info_free(&info); // Free internal strings of info
        return QByteArray();       // Read failed
    }

    afc_file_info_free(&info); // Free internal strings of info on success path
    return buffer;
}