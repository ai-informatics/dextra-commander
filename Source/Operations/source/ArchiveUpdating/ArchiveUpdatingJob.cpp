// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#include "ArchiveUpdatingJob.h"
#include <VFS/ArcLA.h>
#include <sys/stat.h>
#include <chrono>
#include <mutex>
#include <thread>
#include <unordered_map>

namespace nc::ops {

// Updates of the same archive must not overlap: each update reads the whole archive and then replaces it, so a
// concurrent update would lose the changes made by the other one.
static std::shared_ptr<std::mutex> LockForArchive(const std::string &_archive_path)
{
    [[clang::no_destroy]] static std::mutex guard;
    [[clang::no_destroy]] static std::unordered_map<std::string, std::weak_ptr<std::mutex>> locks;
    const std::lock_guard lock{guard};
    std::weak_ptr<std::mutex> &weak = locks[_archive_path];
    if( auto existing = weak.lock() )
        return existing;
    auto created = std::make_shared<std::mutex>();
    weak = created;
    return created;
}

ArchiveUpdatingJob::ArchiveUpdatingJob(std::string _archive_path,
                                       std::string _entry_path,
                                       std::string _new_contents_path)
    : m_ArchivePath(std::move(_archive_path)), m_EntryPath(std::move(_entry_path)),
      m_NewContentsPath(std::move(_new_contents_path))
{
    if( m_ArchivePath.empty() || m_EntryPath.empty() || m_NewContentsPath.empty() )
        throw std::invalid_argument("ArchiveUpdatingJob: invalid argument");

    // The progress is measured in bytes of the original archive processed so far.
    Statistics().SetPreferredSource(Statistics::SourceType::Bytes);
    if( struct stat st; stat(m_ArchivePath.c_str(), &st) == 0 )
        Statistics().CommitEstimated(Statistics::SourceType::Bytes, static_cast<uint64_t>(st.st_size));
}

ArchiveUpdatingJob::~ArchiveUpdatingJob() = default;

void ArchiveUpdatingJob::Perform()
{
    // Wait for other updates of this archive to finish, staying responsive to stopping meanwhile.
    const std::shared_ptr<std::mutex> archive_mutex = LockForArchive(m_ArchivePath);
    std::unique_lock archive_lock{*archive_mutex, std::defer_lock};
    while( !archive_lock.try_lock() ) {
        if( IsStopped() )
            return;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    uint64_t reported = 0;
    const auto progress = [&](uint64_t _processed_bytes) {
        if( _processed_bytes > reported ) {
            Statistics().CommitProcessed(Statistics::SourceType::Bytes, _processed_bytes - reported);
            reported = _processed_bytes;
        }
        BlockIfPaused();
    };
    const auto cancel_checker = [this] { return IsStopped(); };

    const std::expected<void, Error> rc =
        vfs::arc::ReplaceFileInArchive(m_ArchivePath, m_EntryPath, m_NewContentsPath, progress, cancel_checker);
    if( !rc ) {
        if( rc.error() != Error{Error::POSIX, ECANCELED} )
            m_OnUpdateError(rc.error(), m_ArchivePath);
        Stop();
    }
}

} // namespace nc::ops
