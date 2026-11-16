// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#pragma once

#include <VFS/VFS.h>
#include "../Operation.h"

namespace nc::ops {

class ArchiveUpdatingJob;

// Writes an updated file back into an archive by rebuilding the archive, see nc::vfs::arc::ReplaceFileInArchive().
class ArchiveUpdating final : public Operation
{
public:
    // '_archive_path' - a path of the archive on '_native_host'.
    // '_entry_path' - a path of the file inside the archive, e.g. "/dir/file.txt".
    // '_new_contents_path' - a native path of the file with the new contents.
    ArchiveUpdating(const std::string &_archive_path,
                    const std::string &_entry_path,
                    const std::string &_new_contents_path,
                    const std::shared_ptr<VFSHost> &_native_host);
    ~ArchiveUpdating() override;

private:
    Job *GetJob() noexcept override;
    void OnUpdateError(Error _err, const std::string &_archive_path);

    std::unique_ptr<ArchiveUpdatingJob> m_Job;
    std::shared_ptr<VFSHost> m_NativeHost;
};

} // namespace nc::ops
