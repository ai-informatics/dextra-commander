// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#pragma once

#include <Base/Error.h>
#include "../Job.h"
#include <functional>
#include <string>

namespace nc::ops {

struct ArchiveUpdatingJobCallbacks {
    std::function<void(Error _err, const std::string &_archive_path)> m_OnUpdateError = [](Error, const std::string &) {
    };
};

// Replaces a single file inside an archive located on the native filesystem.
class ArchiveUpdatingJob final : public Job, public ArchiveUpdatingJobCallbacks
{
public:
    ArchiveUpdatingJob(std::string _archive_path, std::string _entry_path, std::string _new_contents_path);
    ~ArchiveUpdatingJob() override;

private:
    void Perform() override;

    std::string m_ArchivePath;
    std::string m_EntryPath;
    std::string m_NewContentsPath;
};

} // namespace nc::ops
