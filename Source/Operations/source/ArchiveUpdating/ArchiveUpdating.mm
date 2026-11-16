// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#include "ArchiveUpdating.h"
#include "ArchiveUpdatingJob.h"
#include "../Internal.h"
#include <Operations/Localizable.h>
#include <Utility/PathManip.h>
#include <Utility/StringExtras.h>

namespace nc::ops {

ArchiveUpdating::ArchiveUpdating(const std::string &_archive_path,
                                 const std::string &_entry_path,
                                 const std::string &_new_contents_path,
                                 const std::shared_ptr<VFSHost> &_native_host)
    : m_NativeHost(_native_host)
{
    if( !m_NativeHost )
        throw std::invalid_argument("ArchiveUpdating: invalid argument");

    m_Job = std::make_unique<ArchiveUpdatingJob>(_archive_path, _entry_path, _new_contents_path);
    m_Job->m_OnUpdateError = [this](Error _err, const std::string &_path) { OnUpdateError(_err, _path); };

    NSString *const filename = [NSString stringWithUTF8StdStringView:utility::PathManip::Filename(_entry_path)];
    NSString *const archive = [NSString stringWithUTF8StdStringView:utility::PathManip::Filename(_archive_path)];
    SetTitle([NSString localizedStringWithFormat:localizable::ArchiveUpdatingTitle(), filename, archive].UTF8String);
}

ArchiveUpdating::~ArchiveUpdating() = default;

Job *ArchiveUpdating::GetJob() noexcept
{
    return m_Job.get();
}

void ArchiveUpdating::OnUpdateError(Error _err, const std::string &_archive_path)
{
    // Provide human-readable explanations for the errors specific to updating archives.
    if( _err == Error{Error::POSIX, EFTYPE} )
        _err.LocalizedFailureReason(localizable::ArchiveUpdatingUnsupportedFormatReason().UTF8String);
    else if( _err == Error{Error::POSIX, ENEEDAUTH} )
        _err.LocalizedFailureReason(localizable::ArchiveUpdatingEncryptedReason().UTF8String);
    else if( _err == Error{Error::POSIX, ENOENT} )
        _err.LocalizedFailureReason(localizable::ArchiveUpdatingEntryNotFoundReason().UTF8String);
    ReportHaltReason(localizable::ArchiveUpdatingFailedMessage(), _err, _archive_path, *m_NativeHost);
}

} // namespace nc::ops
