// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#pragma once
#include <Base/Error.h>
#include <VFS/VFSDeclarations.h>
#include <cstdint>
#include <expected>
#include <functional>
#include <string_view>

namespace nc::vfs::arc {

// Checks whether ReplaceFileInArchive() is able to update the archive at the specified native path, without modifying
// anything. Only the archive's format, its compression and the first entry are inspected, so a successful check
// doesn't guarantee that the archive contains no encrypted entries further down.
// Errors are reported in the POSIX domain:
//  - EFTYPE: the archive's format or compression can't be written back;
//  - ENEEDAUTH: the archive is encrypted;
//  - other codes: I/O errors.
std::expected<void, Error> CanReplaceFilesInArchive(std::string_view _archive_path);

// Rewrites the archive located at the native path '_archive_path' so that the regular file stored inside it at
// '_entry_path' (an absolute path within the archive, e.g. "/dir/file.txt") gets the contents of the native file
// '_new_contents_path'. All other entries are carried over unchanged.
// libarchive can't copy compressed data verbatim, so every entry gets decompressed and compressed again.
// The new archive is written into a temporary file next to the original one, which then atomically replaces the
// original. The original archive is never left in a partially updated state.
// Supported formats: zip, 7z and tar, the latter optionally compressed with gzip, bzip2, xz, zstd or lz4.
// '_progress' is periodically called with the number of bytes of the original archive processed so far.
// Errors are reported in the POSIX domain:
//  - EFTYPE: the archive's format or compression can't be written back;
//  - ENEEDAUTH: the archive contains encrypted entries;
//  - ENOENT: there's no regular file at '_entry_path' inside the archive;
//  - ECANCELED: the operation was cancelled via '_cancel_checker';
//  - other codes: I/O errors.
std::expected<void, Error> ReplaceFileInArchive(std::string_view _archive_path,
                                                std::string_view _entry_path,
                                                std::string_view _new_contents_path,
                                                const std::function<void(uint64_t _processed_bytes)> &_progress = {},
                                                const VFSCancelChecker &_cancel_checker = {});

} // namespace nc::vfs::arc
