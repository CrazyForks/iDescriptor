#ifndef DEVICEDATABASE_H
#define DEVICEDATABASE_H

#include "libirecovery.h"
#include <string>

struct DeviceDatabaseInfo {
    const char *modelIdentifier;
    const char *boardId;
    int boardNumber;
    int chipId;
    const char *marketingName;
    const char *displayName;
};

class DeviceDatabase
{
public:
    DeviceDatabase() = delete;

    static const DeviceDatabaseInfo *
    findByIdentifier(const std::string &identifier);
    static const DeviceDatabaseInfo *findByHwModel(const std::string &hwModel);
    static std::string parseRegionInfo(const std::string &code);

private:
    static const DeviceDatabaseInfo m_devices[];
};

#endif // DEVICEDATABASE_H
