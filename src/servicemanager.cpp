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

#include "servicemanager.h"
#include "iDescriptor.h"
#include <QtConcurrent>

IdeviceFfiError *
ServiceManager::safeAfcReadDirectory(const iDescriptorDevice *device,
                                     const char *path, char ***dirs,
                                     std::optional<AfcClientHandle *> altAfc)
{
    size_t count = 0;
    return executeAfcClientOperation(
        device,
        [path, dirs, &count, device](AfcClientHandle *client) {
            return afc_list_directory(client, path, dirs, &count);
        },
        altAfc);
}

IdeviceFfiError *
ServiceManager::safeAfcGetFileInfo(const iDescriptorDevice *device,
                                   const char *path, AfcFileInfo *info,
                                   std::optional<AfcClientHandle *> altAfc)
{
    return executeAfcClientOperation(
        device,
        [path, info, device](AfcClientHandle *client) {
            return afc_get_file_info(client, path, info);
        },
        altAfc);
}

IdeviceFfiError *ServiceManager::safeAfcFileOpen(
    const iDescriptorDevice *device, const char *path, AfcFopenMode mode,
    AfcFileHandle **handle, std::optional<AfcClientHandle *> altAfc)
{
    return executeAfcClientOperation(
        device,
        [path, mode, handle, device](AfcClientHandle *client) {
            return afc_file_open(client, path, mode, handle);
        },
        altAfc);
}

IdeviceFfiError *
ServiceManager::safeAfcFileRead(const iDescriptorDevice *device,
                                AfcFileHandle *handle, uint8_t **data,
                                uintptr_t length, size_t *bytes_read)
{
    return executeAfcOperation(
        device,
        [data, length, bytes_read](AfcFileHandle *handle) {
            return afc_file_read(handle, data, length, bytes_read);
        },
        handle);
}

IdeviceFfiError *
ServiceManager::safeAfcFileWrite(const iDescriptorDevice *device,
                                 AfcFileHandle *handle, const uint8_t *data,
                                 uint32_t length)
{
    return executeAfcOperation(
        device,
        [data, length](AfcFileHandle *handle) {
            return afc_file_write(handle, data, length);
        },
        handle);
}

IdeviceFfiError *
ServiceManager::safeAfcFileClose(const iDescriptorDevice *device,
                                 AfcFileHandle *handle)
{
    return executeAfcOperation(
        device, [](AfcFileHandle *handle) { return afc_file_close(handle); },
        handle);
}

IdeviceFfiError *
ServiceManager::safeAfcFileSeek(const iDescriptorDevice *device,
                                AfcFileHandle *handle, int64_t offset,
                                int whence)
{
    off_t newPos;
    return executeAfcOperation(
        device,
        [offset, whence, &newPos](AfcFileHandle *handle) {
            return afc_file_seek(handle, offset, whence, &newPos);
        },
        handle);
}

IdeviceFfiError *
ServiceManager::safeAfcFileTell(const iDescriptorDevice *device,
                                AfcFileHandle *handle, off_t *position)
{
    return executeAfcOperation(
        device,
        [position](AfcFileHandle *handle) {
            return afc_file_tell(handle, position);
        },
        handle);
}

QByteArray
ServiceManager::safeReadAfcFileToByteArray(const iDescriptorDevice *device,
                                           const char *path)
{
    return executeOperation<QByteArray>(device, [path, device]() -> QByteArray {
        return read_afc_file_to_byte_array(device, path);
    });
}

AFCFileTree ServiceManager::safeGetFileTree(const iDescriptorDevice *device,
                                            const std::string &path,
                                            bool checkDir)
{
    return executeOperation<AFCFileTree>(
        device, [path, device, checkDir]() -> AFCFileTree {
            return get_file_tree(device, checkDir, path);
        });
}

QFuture<AFCFileTree>
ServiceManager::getFileTreeAsync(const iDescriptorDevice *device,
                                 const std::string &path, bool checkDir)
{
    return QtConcurrent::run([device, path, checkDir]() {
        return get_file_tree(device, checkDir, path);
    });
}

MountedImageInfo
ServiceManager::getMountedImage(const iDescriptorDevice *device)
{
    return executeOperation<MountedImageInfo>(
        device,
        [device]() -> MountedImageInfo { return _get_mounted_image(device); });
}

IdeviceFfiError *ServiceManager::mountImage(const iDescriptorDevice *device,
                                            const char *image_file,
                                            const char *signature_file)
{
    return executeOperation<IdeviceFfiError *>(
        device, [device, image_file, signature_file]() -> IdeviceFfiError * {
            return mount_dev_image(device, image_file, signature_file);
        });
}

void ServiceManager::getCableInfo(const iDescriptorDevice *device,
                                  plist_t &response)
{
    executeOperation<void>(
        device, [device, &response]() { _get_cable_info(device, response); });
}

IdeviceFfiError *ServiceManager::install_IPA(const iDescriptorDevice *device,
                                             const char *ipa_path,
                                             const char *file_name)
{
    return executeOperation<IdeviceFfiError *>(
        device, [device, ipa_path, file_name]() -> IdeviceFfiError * {
            return _install_IPA(device, ipa_path, file_name);
        });
}

bool ServiceManager::enableWirelessConnections(const iDescriptorDevice *device)
{
    return executeOperation<bool>(device, [device]() -> bool {
        plist_t value = plist_new_bool(true);
        bool success = false;
        IdeviceFfiError *err =
            lockdownd_set_value(device->lockdown, "EnableWifiConnections",
                                value, "com.apple.mobile.wireless_lockdown");

        if (err != NULL) {
            qDebug() << "Failed to enable wireless connections." << err->message
                     << "Code:" << err->code;
            idevice_error_free(err);
        } else {
            success = true;
        }

        plist_free(value);
        return success;
    });
}

IdeviceFfiError *ServiceManager::exportFileToPath(
    const iDescriptorDevice *device, const char *device_path,
    const char *local_path,
    std::function<void(qint64, qint64)> progressCallback,
    std::atomic<bool> *cancelRequested)
{
    qDebug()
        << "[serviceManager::exportFileToPath] Exporting file from device path:"
        << device_path << "to local path:" << local_path;
    return executeOperation<IdeviceFfiError *>(
        device,
        [device, device_path, local_path, progressCallback,
         cancelRequested]() -> IdeviceFfiError * {
            AfcFileHandle *afcHandle = nullptr;
            qDebug() << "Opening file on device:" << device_path;
            IdeviceFfiError *err_open = safeAfcFileOpen(
                device, device_path, AfcFopenMode::AfcRdOnly, &afcHandle);

            if (err_open != nullptr) {
                qDebug() << "Failed to open file on device:" << device_path
                         << "Error Code:" << err_open->code
                         << "Message:" << err_open->message;
                return err_open;
            }
            qDebug() << "File opened on device successfully";

            FILE *out = fopen(local_path, "wb");
            if (!out) {
                qDebug() << "Failed to open local file:" << local_path;
                IdeviceFfiError *err_close =
                    safeAfcFileClose(device, afcHandle);
                if (err_close != nullptr) {
                    // idevice_error_free(err_close);
                }
                return new IdeviceFfiError{1, "FAILED_TO_OPEN_LOCAL_FILE"};
            }
            qDebug() << "Local file opened successfully";

            const size_t CHUNK_SIZE = 256 * 1024; // 256KB chunks
            uint8_t *chunkData = nullptr;
            size_t bytesRead = 0;
            qint64 totalBytesRead = 0;

            // Get file size for progress
            AfcFileInfo fileInfo;
            IdeviceFfiError *info_err =
                safeAfcGetFileInfo(device, device_path, &fileInfo);
            qint64 totalFileSize = 0;
            if (info_err == nullptr) {
                totalFileSize = fileInfo.size;
                // afc_file_info_free(&fileInfo);
            } else {
                // idevice_error_free(info_err);
            }

            IdeviceFfiError *read_err = nullptr;
            // Read file in chunks
            while (true) {
                std::this_thread::sleep_for(std::chrono::seconds(2));
                // Check for cancellation
                if (cancelRequested && cancelRequested->load()) {
                    fclose(out);
                    safeAfcFileClose(device, afcHandle);
                    return new IdeviceFfiError{1, "OPERATION_CANCELLED"};
                }

                read_err = safeAfcFileRead(device, afcHandle, &chunkData,
                                           CHUNK_SIZE, &bytesRead);

                if (read_err != nullptr) {
                    qDebug() << "Error reading file:" << read_err->message;
                    fclose(out);
                    safeAfcFileClose(device, afcHandle);
                    return read_err;
                }

                if (bytesRead == 0) {
                    // End of file reached
                    break;
                }

                // Write chunk to local file
                size_t written = fwrite(chunkData, 1, bytesRead, out);

                // Free the memory allocated by afc_file_read
                afc_file_read_data_free(chunkData, bytesRead);
                chunkData = nullptr;

                if (written != bytesRead) {
                    qDebug() << "Failed to write all bytes to local file";
                    fclose(out);
                    safeAfcFileClose(device, afcHandle);
                    return new IdeviceFfiError{1, "WRITE_ERROR"};
                }

                totalBytesRead += bytesRead;

                // Report progress
                if (progressCallback) {
                    progressCallback(totalBytesRead, totalFileSize);
                }
            }

            fclose(out);

            IdeviceFfiError *err_close = safeAfcFileClose(device, afcHandle);
            if (err_close != nullptr) {
                qDebug() << "Failed to close AFC file:" << err_close->message;
                return err_close;
            }

            return nullptr; // Success
        });
}
