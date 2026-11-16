// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#include <libarchive/archive.h>
#include <libarchive/archive_entry.h>

#include "Updater.h"
#include <cerrno>
#include <climits>
#include <copyfile.h>
#include <cstdlib>
#include <fcntl.h>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace nc::vfs::arc {

namespace {

constexpr size_t g_BufferSize = 256 * 1024;

struct ReaderDeleter {
    void operator()(archive *_a) const noexcept { archive_read_free(_a); }
};
struct WriterDeleter {
    void operator()(archive *_a) const noexcept { archive_write_free(_a); }
};
using ReaderPtr = std::unique_ptr<archive, ReaderDeleter>;
using WriterPtr = std::unique_ptr<archive, WriterDeleter>;

// Format and compression to use when writing an updated copy of an archive.
struct WriteSettings {
    int format = 0;
    std::optional<int> filter;
};

Error PosixError(int _code) noexcept
{
    return Error{Error::POSIX, _code};
}

// Converts the error state of a libarchive object into an Error, falling back to EIO when libarchive has no errno.
Error ArchiveError(archive *_a) noexcept
{
    const int err = archive_errno(_a);
    return PosixError(err > 0 ? err : EIO);
}

// Closes the file descriptor upon destruction.
class ScopedFD
{
public:
    explicit ScopedFD(int _fd) noexcept : m_FD(_fd) {}
    ScopedFD(const ScopedFD &) = delete;
    ScopedFD &operator=(const ScopedFD &) = delete;
    ~ScopedFD()
    {
        if( m_FD >= 0 )
            close(m_FD);
    }
    [[nodiscard]] int Get() const noexcept { return m_FD; }

private:
    int m_FD;
};

// Unlinks the temporary file unless it was released after a successful replacement.
class TemporaryFile
{
public:
    TemporaryFile() = default;
    TemporaryFile(const TemporaryFile &) = delete;
    TemporaryFile &operator=(const TemporaryFile &) = delete;
    ~TemporaryFile()
    {
        if( m_FD >= 0 )
            close(m_FD);
        if( !m_Path.empty() )
            unlink(m_Path.c_str());
    }

    // Creates a hidden temporary file in the same directory as '_neighbour', so that it can be renamed over it.
    std::expected<void, Error> Create(const std::filesystem::path &_neighbour)
    {
        std::string templ = (_neighbour.parent_path() / ("." + _neighbour.filename().native() + ".XXXXXX")).native();
        const int fd = mkstemp(templ.data());
        if( fd < 0 )
            return std::unexpected(PosixError(errno));
        m_FD = fd;
        m_Path = std::move(templ);
        return {};
    }

    void CloseFD() noexcept
    {
        if( m_FD >= 0 )
            close(m_FD);
        m_FD = -1;
    }

    // Stops tracking the file, i.e. it won't be removed upon destruction.
    void Release() noexcept { m_Path.clear(); }

    [[nodiscard]] int FD() const noexcept { return m_FD; }
    [[nodiscard]] const std::string &Path() const noexcept { return m_Path; }

private:
    int m_FD = -1;
    std::string m_Path;
};

std::expected<ReaderPtr, Error> OpenReader(const std::string &_path)
{
    ReaderPtr reader{archive_read_new()};
    if( !reader )
        return std::unexpected(PosixError(ENOMEM));
    archive_read_support_filter_all(reader.get());
    archive_read_support_format_all(reader.get());
    if( archive_read_open_filename(reader.get(), _path.c_str(), g_BufferSize) != ARCHIVE_OK )
        return std::unexpected(ArchiveError(reader.get()));
    return reader;
}

// Reads the first header. libarchive reports the archive's format only after that.
std::expected<archive_entry *, Error> ReadFirstHeader(archive *_reader)
{
    archive_entry *entry = nullptr;
    const int rc = archive_read_next_header(_reader, &entry);
    if( rc == ARCHIVE_EOF )
        return std::unexpected(PosixError(ENOENT)); // an empty archive has nothing to replace
    if( rc < ARCHIVE_WARN )
        return std::unexpected(ArchiveError(_reader));
    return entry;
}

std::expected<WriteSettings, Error> DeduceWriteSettings(archive *_reader)
{
    WriteSettings settings;
    const int format = archive_format(_reader);
    const int base_format = format & ARCHIVE_FORMAT_BASE_MASK;
    if( base_format == ARCHIVE_FORMAT_ZIP || base_format == ARCHIVE_FORMAT_7ZIP )
        settings.format = base_format;
    else if( base_format == ARCHIVE_FORMAT_TAR )
        // A specific tar flavor is preserved, a generic one is written back as a restricted POSIX tar.
        settings.format = format == ARCHIVE_FORMAT_TAR ? ARCHIVE_FORMAT_TAR_PAX_RESTRICTED : format;
    else
        return std::unexpected(PosixError(EFTYPE));

    for( int i = 0, e = archive_filter_count(_reader); i < e; ++i ) {
        const int filter = archive_filter_code(_reader, i);
        if( filter == ARCHIVE_FILTER_NONE )
            continue;
        if( settings.filter )
            return std::unexpected(PosixError(EFTYPE)); // stacked compression, e.g. a gzipped uuencoded tar
        switch( filter ) {
            case ARCHIVE_FILTER_GZIP:
            case ARCHIVE_FILTER_BZIP2:
            case ARCHIVE_FILTER_XZ:
            case ARCHIVE_FILTER_ZSTD:
            case ARCHIVE_FILTER_LZ4:
                settings.filter = filter;
                break;
            default:
                return std::unexpected(PosixError(EFTYPE));
        }
    }

    // Only tar archives are expected to be compressed as a whole.
    if( settings.filter && base_format != ARCHIVE_FORMAT_TAR )
        return std::unexpected(PosixError(EFTYPE));

    return settings;
}

int SetWriterFormat(archive *_writer, int _format) noexcept
{
    switch( _format ) {
        case ARCHIVE_FORMAT_ZIP:
            return archive_write_set_format_zip(_writer);
        case ARCHIVE_FORMAT_7ZIP:
            return archive_write_set_format_7zip(_writer);
        case ARCHIVE_FORMAT_TAR_USTAR:
            return archive_write_set_format_ustar(_writer);
        case ARCHIVE_FORMAT_TAR_PAX_INTERCHANGE:
            return archive_write_set_format_pax(_writer);
        case ARCHIVE_FORMAT_TAR_GNUTAR:
            return archive_write_set_format_gnutar(_writer);
        default:
            return archive_write_set_format_pax_restricted(_writer);
    }
}

int AddWriterFilter(archive *_writer, int _filter) noexcept
{
    switch( _filter ) {
        case ARCHIVE_FILTER_GZIP:
            return archive_write_add_filter_gzip(_writer);
        case ARCHIVE_FILTER_BZIP2:
            return archive_write_add_filter_bzip2(_writer);
        case ARCHIVE_FILTER_XZ:
            return archive_write_add_filter_xz(_writer);
        case ARCHIVE_FILTER_ZSTD:
            return archive_write_add_filter_zstd(_writer);
        case ARCHIVE_FILTER_LZ4:
            return archive_write_add_filter_lz4(_writer);
        default:
            return ARCHIVE_FATAL;
    }
}

std::expected<WriterPtr, Error> OpenWriter(const WriteSettings &_settings, int _fd)
{
    WriterPtr writer{archive_write_new()};
    if( !writer )
        return std::unexpected(PosixError(ENOMEM));
    if( SetWriterFormat(writer.get(), _settings.format) != ARCHIVE_OK )
        return std::unexpected(ArchiveError(writer.get()));
    if( _settings.filter && AddWriterFilter(writer.get(), *_settings.filter) != ARCHIVE_OK )
        return std::unexpected(ArchiveError(writer.get()));
    if( _settings.format == ARCHIVE_FORMAT_ZIP )
        // Entry names are passed through as they were read, mark them as UTF-8 to keep non-ASCII names readable.
        archive_write_set_format_option(writer.get(), "zip", "hdrcharset", "UTF-8");
    // Don't pad the last block - the size of the archive shouldn't depend on the block size.
    archive_write_set_bytes_in_last_block(writer.get(), 1);
    if( archive_write_open_fd(writer.get(), _fd) != ARCHIVE_OK )
        return std::unexpected(ArchiveError(writer.get()));
    return writer;
}

// Archives may store paths with or without the heading slash, while the paths within VFS always have one.
bool EntryPathMatches(const char *_entry_path, std::string_view _vfs_path) noexcept
{
    if( _entry_path == nullptr )
        return false;
    std::string_view entry_path{_entry_path};
    if( entry_path.starts_with('/') )
        entry_path.remove_prefix(1);
    if( _vfs_path.starts_with('/') )
        _vfs_path.remove_prefix(1);
    return !entry_path.empty() && entry_path == _vfs_path;
}

std::expected<void, Error> WriteHeader(archive *_writer, archive_entry *_entry)
{
    if( archive_write_header(_writer, _entry) < ARCHIVE_WARN )
        return std::unexpected(ArchiveError(_writer));
    return {};
}

std::expected<void, Error> WriteData(archive *_writer, const void *_data, size_t _size)
{
    if( archive_write_data(_writer, _data, _size) < 0 )
        return std::unexpected(ArchiveError(_writer));
    return {};
}

// Copies the data of the current entry from the reader to the writer.
std::expected<void, Error>
CopyEntryData(archive *_reader, archive *_writer, std::vector<std::byte> &_buffer, const VFSCancelChecker &_cancel)
{
    while( true ) {
        if( _cancel && _cancel() )
            return std::unexpected(PosixError(ECANCELED));
        const la_ssize_t read = archive_read_data(_reader, _buffer.data(), _buffer.size());
        if( read < 0 )
            return std::unexpected(ArchiveError(_reader));
        if( read == 0 )
            return {};
        if( auto rc = WriteData(_writer, _buffer.data(), static_cast<size_t>(read)); !rc )
            return rc;
    }
}

// Writes the entry with its contents taken from the native file.
std::expected<void, Error> WriteReplacedEntry(archive *_writer,
                                              archive_entry *_entry,
                                              const std::string &_contents_path,
                                              std::vector<std::byte> &_buffer,
                                              const VFSCancelChecker &_cancel)
{
    const ScopedFD fd{open(_contents_path.c_str(), O_RDONLY | O_CLOEXEC)};
    if( fd.Get() < 0 )
        return std::unexpected(PosixError(errno));

    struct stat st;
    if( fstat(fd.Get(), &st) != 0 )
        return std::unexpected(PosixError(errno));

    archive_entry_set_size(_entry, st.st_size);
    archive_entry_set_mtime(_entry, st.st_mtimespec.tv_sec, st.st_mtimespec.tv_nsec);

    if( auto rc = WriteHeader(_writer, _entry); !rc )
        return rc;

    while( true ) {
        if( _cancel && _cancel() )
            return std::unexpected(PosixError(ECANCELED));
        const ssize_t read_bytes = read(fd.Get(), _buffer.data(), _buffer.size());
        if( read_bytes < 0 ) {
            if( errno == EINTR )
                continue;
            return std::unexpected(PosixError(errno));
        }
        if( read_bytes == 0 )
            return {};
        if( auto rc = WriteData(_writer, _buffer.data(), static_cast<size_t>(read_bytes)); !rc )
            return rc;
    }
}

std::expected<std::string, Error> RealPath(std::string_view _path)
{
    char buf[PATH_MAX];
    if( realpath(std::string(_path).c_str(), buf) == nullptr )
        return std::unexpected(PosixError(errno));
    return std::string(buf);
}

} // namespace

std::expected<void, Error> CanReplaceFilesInArchive(std::string_view _archive_path)
{
    const std::expected<std::string, Error> archive_path = RealPath(_archive_path);
    if( !archive_path )
        return std::unexpected(archive_path.error());

    const std::expected<ReaderPtr, Error> reader = OpenReader(*archive_path);
    if( !reader )
        return std::unexpected(reader.error());

    const std::expected<archive_entry *, Error> first = ReadFirstHeader(reader->get());
    if( !first )
        return std::unexpected(first.error());

    if( const std::expected<WriteSettings, Error> settings = DeduceWriteSettings(reader->get()); !settings )
        return std::unexpected(settings.error());

    if( archive_entry_is_encrypted(*first) || archive_read_has_encrypted_entries(reader->get()) > 0 )
        return std::unexpected(PosixError(ENEEDAUTH));

    return {};
}

std::expected<void, Error> ReplaceFileInArchive(std::string_view _archive_path,
                                                std::string_view _entry_path,
                                                std::string_view _new_contents_path,
                                                const std::function<void(uint64_t _processed_bytes)> &_progress,
                                                const VFSCancelChecker &_cancel_checker)
{
    // Resolve symlinks so that the archive itself gets replaced, not a symlink pointing at it.
    const std::expected<std::string, Error> archive_path = RealPath(_archive_path);
    if( !archive_path )
        return std::unexpected(archive_path.error());

    struct stat archive_st;
    if( stat(archive_path->c_str(), &archive_st) != 0 )
        return std::unexpected(PosixError(errno));
    if( !S_ISREG(archive_st.st_mode) )
        return std::unexpected(PosixError(EFTYPE));

    const std::expected<ReaderPtr, Error> reader = OpenReader(*archive_path);
    if( !reader )
        return std::unexpected(reader.error());

    std::expected<archive_entry *, Error> entry = ReadFirstHeader(reader->get());
    if( !entry )
        return std::unexpected(entry.error());

    const std::expected<WriteSettings, Error> settings = DeduceWriteSettings(reader->get());
    if( !settings )
        return std::unexpected(settings.error());

    TemporaryFile temp_file;
    if( auto rc = temp_file.Create(*archive_path); !rc )
        return rc;

    std::expected<WriterPtr, Error> writer = OpenWriter(*settings, temp_file.FD());
    if( !writer )
        return std::unexpected(writer.error());

    const std::string new_contents_path{_new_contents_path};
    std::vector<std::byte> buffer(g_BufferSize);
    bool replaced = false;
    archive_entry *current = *entry;
    while( true ) {
        if( _cancel_checker && _cancel_checker() )
            return std::unexpected(PosixError(ECANCELED));

        // Encrypted entries can't be decrypted and re-encrypted reliably.
        if( archive_entry_is_encrypted(current) )
            return std::unexpected(PosixError(ENEEDAUTH));

        const bool is_target = archive_entry_filetype(current) == AE_IFREG &&
                               archive_entry_hardlink(current) == nullptr &&
                               EntryPathMatches(archive_entry_pathname(current), _entry_path);
        if( is_target ) {
            if( auto rc = WriteReplacedEntry(writer->get(), current, new_contents_path, buffer, _cancel_checker); !rc )
                return rc;
            replaced = true;
        }
        else {
            if( auto rc = WriteHeader(writer->get(), current); !rc )
                return rc;
            if( auto rc = CopyEntryData(reader->get(), writer->get(), buffer, _cancel_checker); !rc )
                return rc;
        }

        if( _progress )
            _progress(static_cast<uint64_t>(archive_filter_bytes(reader->get(), -1)));

        const int rc = archive_read_next_header(reader->get(), &current);
        if( rc == ARCHIVE_EOF )
            break;
        if( rc < ARCHIVE_WARN )
            return std::unexpected(ArchiveError(reader->get()));
    }

    if( !replaced )
        return std::unexpected(PosixError(ENOENT));

    if( archive_write_close(writer->get()) != ARCHIVE_OK )
        return std::unexpected(ArchiveError(writer->get()));
    writer->reset();

    // Make sure the data has reached the disk before the new archive replaces the original one.
    if( fsync(temp_file.FD()) != 0 )
        return std::unexpected(PosixError(errno));

    // Carry over the permissions and the extended attributes of the original archive.
    fchmod(temp_file.FD(), archive_st.st_mode & ALLPERMS);
    if( const ScopedFD original{open(archive_path->c_str(), O_RDONLY | O_CLOEXEC)}; original.Get() >= 0 )
        fcopyfile(original.Get(), temp_file.FD(), nullptr, COPYFILE_XATTR);
    temp_file.CloseFD();

    if( rename(temp_file.Path().c_str(), archive_path->c_str()) != 0 )
        return std::unexpected(PosixError(errno));
    temp_file.Release();

    return {};
}

} // namespace nc::vfs::arc
