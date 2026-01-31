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
#include <QDebug>
#include <iostream>
#include <libimobiledevice/afc.h>
#include <libimobiledevice/lockdown.h>
#include <string.h>

AFCFileTree get_file_tree(afc_client_t afcClient, const std::string &path,
                          bool checkDir)
{

    AFCFileTree result;
    result.currentPath = path;

    char **dirs = NULL;
    if (afc_read_directory(afcClient, path.c_str(), &dirs) != AFC_E_SUCCESS) {
        result.success = false;
        return result;
    }

    for (int i = 0; dirs[i]; i++) {
        std::string entryName = dirs[i];
        if (entryName == "." || entryName == "..")
            continue;

        char **info = NULL;
        std::string fullPath = path;
        if (fullPath.back() != '/')
            fullPath += "/";
        fullPath += entryName;
        bool isDir = false;
        if (!checkDir) {
            isDir = false;
        } else if (afc_get_file_info(afcClient, fullPath.c_str(), &info) ==
                       AFC_E_SUCCESS &&
                   info) {
            if (entryName == "var") {
                qDebug() << "File info for var:" << info[0] << info[1]
                         << info[2] << info[3] << info[4] << info[5];
            }
            for (int j = 0; info[j]; j += 2) {
                if (strcmp(info[j], "st_ifmt") == 0) {
                    if (strcmp(info[j + 1], "S_IFDIR") == 0) {
                        isDir = true;
                    } else if (strcmp(info[j + 1], "S_IFLNK") == 0) {
                        /*symlink*/
                        char **dir_contents = NULL;
                        if (afc_read_directory(afcClient, fullPath.c_str(),
                                               &dir_contents) ==
                            AFC_E_SUCCESS) {
                            isDir = true;
                            if (dir_contents) {
                                afc_dictionary_free(dir_contents);
                            }
                        }
                    }
                    break;
                }
            }
            afc_dictionary_free(info);
        }
        result.entries.push_back({entryName, isDir});
    }
    if (dirs) {
        afc_dictionary_free(dirs);
    }
    result.success = true;
    return result;
}