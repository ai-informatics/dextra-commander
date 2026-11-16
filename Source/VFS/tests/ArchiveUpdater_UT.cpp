// Copyright (C) 2026 Alexey Irkhin. Subject to GNU General Public License version 3.
#include "Tests.h"
#include "TestEnv.h"
#include <VFS/VFS.h>
#include <VFS/ArcLA.h>
#include <Base/WriteAtomically.h>
#include <libarchive/archive.h>
#include <libarchive/archive_entry.h>
#include <fstream>
#include <sys/stat.h>

#define PREFIX "ArchiveUpdater "

namespace ArchiveUpdaterTest {

using namespace nc;
using namespace nc::vfs;

struct Item {
    std::string path;    // a path inside the archive, without the heading slash
    std::string content; // ignored for directories
    bool is_dir = false;
};

struct Format {
    std::string name;
    std::function<int(archive *)> set_format;
    std::function<int(archive *)> add_filter; // optional
    int expected_format_base;
    int expected_filter;
};

static std::vector<Item> Items()
{
    return {
        {.path = "file.txt", .content = "Hello, world!"},
        {.path = "dir", .is_dir = true},
        {.path = "dir/nested.txt", .content = "Nested file contents"},
        {.path = "dir/Привет.txt", .content = "Кириллица"},
    };
}

static std::vector<Format> SupportedFormats()
{
    const auto none = std::function<int(archive *)>{};
    return {
        {"zip", archive_write_set_format_zip, none, ARCHIVE_FORMAT_ZIP, ARCHIVE_FILTER_NONE},
        {"7z", archive_write_set_format_7zip, none, ARCHIVE_FORMAT_7ZIP, ARCHIVE_FILTER_NONE},
        {"tar", archive_write_set_format_pax_restricted, none, ARCHIVE_FORMAT_TAR, ARCHIVE_FILTER_NONE},
        {"tar.gz",
         archive_write_set_format_pax_restricted,
         archive_write_add_filter_gzip,
         ARCHIVE_FORMAT_TAR,
         ARCHIVE_FILTER_GZIP},
        {"tar.bz2",
         archive_write_set_format_pax_restricted,
         archive_write_add_filter_bzip2,
         ARCHIVE_FORMAT_TAR,
         ARCHIVE_FILTER_BZIP2},
        {"tar.xz", archive_write_set_format_ustar, archive_write_add_filter_xz, ARCHIVE_FORMAT_TAR, ARCHIVE_FILTER_XZ},
        {"tar.zst",
         archive_write_set_format_gnutar,
         archive_write_add_filter_zstd,
         ARCHIVE_FORMAT_TAR,
         ARCHIVE_FILTER_ZSTD},
        {"tar.lz4",
         archive_write_set_format_pax_restricted,
         archive_write_add_filter_lz4,
         ARCHIVE_FORMAT_TAR,
         ARCHIVE_FILTER_LZ4},
    };
}

static void MakeArchive(const std::filesystem::path &_path,
                        const std::function<int(archive *)> &_set_format,
                        const std::function<int(archive *)> &_add_filter,
                        const std::vector<Item> &_items,
                        const std::function<void(archive *)> &_tweak = {})
{
    archive *const a = archive_write_new();
    REQUIRE(_set_format(a) == ARCHIVE_OK);
    if( _add_filter )
        REQUIRE(_add_filter(a) == ARCHIVE_OK);
    if( _tweak )
        _tweak(a);
    REQUIRE(archive_write_open_filename(a, _path.c_str()) == ARCHIVE_OK);
    for( const Item &item : _items ) {
        archive_entry *const e = archive_entry_new();
        archive_entry_set_pathname_utf8(e, item.path.c_str());
        archive_entry_set_filetype(e, item.is_dir ? AE_IFDIR : AE_IFREG);
        archive_entry_set_perm(e, item.is_dir ? 0755 : 0644);
        archive_entry_set_mtime(e, 1700000000, 0);
        archive_entry_set_size(e, item.is_dir ? 0 : static_cast<la_int64_t>(item.content.size()));
        REQUIRE(archive_write_header(a, e) == ARCHIVE_OK);
        if( !item.is_dir )
            REQUIRE(archive_write_data(a, item.content.data(), item.content.size()) ==
                    static_cast<la_ssize_t>(item.content.size()));
        archive_entry_free(e);
    }
    REQUIRE(archive_write_close(a) == ARCHIVE_OK);
    archive_write_free(a);
}

static std::filesystem::path MakeFile(const std::filesystem::path &_path, std::string_view _content)
{
    REQUIRE(base::WriteAtomically(_path, {reinterpret_cast<const std::byte *>(_content.data()), _content.size()}));
    return _path;
}

static std::string ReadFromArchive(VFSHost &_host, std::string_view _path)
{
    const VFSFilePtr file = _host.CreateFile(_path).value();
    REQUIRE(file->Open(VFSFlags::OF_Read));
    const auto data = file->ReadFile();
    REQUIRE(data);
    return {reinterpret_cast<const char *>(data->data()), data->size()};
}

static std::string ReadRaw(const std::filesystem::path &_path)
{
    std::ifstream in(_path, std::ios::binary);
    return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

// Returns the format and the outermost filter of the archive as reported by libarchive.
static std::pair<int, int> FormatOf(const std::filesystem::path &_path)
{
    archive *const a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    REQUIRE(archive_read_open_filename(a, _path.c_str(), 16384) == ARCHIVE_OK);
    archive_entry *e = nullptr;
    REQUIRE(archive_read_next_header(a, &e) == ARCHIVE_OK);
    const auto result = std::pair{archive_format(a) & ARCHIVE_FORMAT_BASE_MASK, archive_filter_code(a, 0)};
    archive_read_free(a);
    return result;
}

static size_t FilesInDirectory(const std::filesystem::path &_dir)
{
    return static_cast<size_t>(std::distance(std::filesystem::directory_iterator(_dir), {}));
}

TEST_CASE(PREFIX "Replaces a file and preserves everything else, for all supported formats")
{
    for( const Format &format : SupportedFormats() ) {
        INFO(format.name);
        const TestDir dir;
        const auto arc_path = dir.directory / ("test." + format.name);
        MakeArchive(arc_path, format.set_format, format.add_filter, Items());
        const std::string new_content = "This is a new and noticeably longer content of the nested file";
        const auto new_path = MakeFile(dir.directory / "new.txt", new_content);

        REQUIRE(arc::CanReplaceFilesInArchive(arc_path.native()));
        REQUIRE(arc::ReplaceFileInArchive(arc_path.native(), "/dir/nested.txt", new_path.native()));

        const auto host = std::make_shared<ArchiveHost>(arc_path.native(), TestEnv().vfs_native);
        CHECK(ReadFromArchive(*host, "/dir/nested.txt") == new_content);
        CHECK(ReadFromArchive(*host, "/file.txt") == "Hello, world!");
        CHECK(ReadFromArchive(*host, "/dir/Привет.txt") == "Кириллица");
        CHECK(host->StatTotalRegs() == 3);
        CHECK(host->IsDirectory("/dir", 0));
        CHECK(host->Stat("/dir/nested.txt", 0)->size == new_content.size());

        const auto [fmt, filter] = FormatOf(arc_path);
        CHECK(fmt == format.expected_format_base);
        CHECK(filter == format.expected_filter);

        // Only the archive and the new contents file must remain - no temporary files
        CHECK(FilesInDirectory(dir.directory) == 2);
    }
}

TEST_CASE(PREFIX "Replaces a file with a non-ASCII name")
{
    for( const Format &format : SupportedFormats() ) {
        INFO(format.name);
        const TestDir dir;
        const auto arc_path = dir.directory / ("test." + format.name);
        MakeArchive(arc_path, format.set_format, format.add_filter, Items());
        const auto new_path = MakeFile(dir.directory / "new.txt", "Новое содержимое");

        REQUIRE(arc::ReplaceFileInArchive(arc_path.native(), "/dir/Привет.txt", new_path.native()));

        const auto host = std::make_shared<ArchiveHost>(arc_path.native(), TestEnv().vfs_native);
        CHECK(ReadFromArchive(*host, "/dir/Привет.txt") == "Новое содержимое");
        CHECK(ReadFromArchive(*host, "/dir/nested.txt") == "Nested file contents");
    }
}

TEST_CASE(PREFIX "Can be applied repeatedly")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.zip";
    MakeArchive(arc_path, archive_write_set_format_zip, {}, Items());
    for( int i = 0; i < 3; ++i ) {
        const std::string content = "Revision #" + std::to_string(i);
        const auto new_path = MakeFile(dir.directory / "new.txt", content);
        REQUIRE(arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native()));
        const auto host = std::make_shared<ArchiveHost>(arc_path.native(), TestEnv().vfs_native);
        CHECK(ReadFromArchive(*host, "/file.txt") == content);
        CHECK(host->StatTotalRegs() == 3);
    }
}

TEST_CASE(PREFIX "Accepts an empty replacement")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.tar.gz";
    MakeArchive(arc_path, archive_write_set_format_pax_restricted, archive_write_add_filter_gzip, Items());
    const auto new_path = MakeFile(dir.directory / "new.txt", "");
    REQUIRE(arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native()));
    const auto host = std::make_shared<ArchiveHost>(arc_path.native(), TestEnv().vfs_native);
    CHECK(ReadFromArchive(*host, "/file.txt").empty());
}

TEST_CASE(PREFIX "Fails with ENOENT and keeps the archive intact when the entry doesn't exist")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.zip";
    MakeArchive(arc_path, archive_write_set_format_zip, {}, Items());
    const std::string original = ReadRaw(arc_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    SECTION("non-existent path")
    {
        const auto rc = arc::ReplaceFileInArchive(arc_path.native(), "/no/such/file.txt", new_path.native());
        REQUIRE(!rc);
        CHECK(rc.error() == Error{Error::POSIX, ENOENT});
    }
    SECTION("a directory can't be replaced")
    {
        const auto rc = arc::ReplaceFileInArchive(arc_path.native(), "/dir", new_path.native());
        REQUIRE(!rc);
        CHECK(rc.error() == Error{Error::POSIX, ENOENT});
    }
    CHECK(ReadRaw(arc_path) == original);
    CHECK(FilesInDirectory(dir.directory) == 2);
}

TEST_CASE(PREFIX "Refuses formats which can't be written back")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.cpio";
    MakeArchive(arc_path, archive_write_set_format_cpio_newc, {}, Items());
    const std::string original = ReadRaw(arc_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    const auto can = arc::CanReplaceFilesInArchive(arc_path.native());
    REQUIRE(!can);
    CHECK(can.error() == Error{Error::POSIX, EFTYPE});

    const auto rc = arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native());
    REQUIRE(!rc);
    CHECK(rc.error() == Error{Error::POSIX, EFTYPE});
    CHECK(ReadRaw(arc_path) == original);
    CHECK(FilesInDirectory(dir.directory) == 2);
}

TEST_CASE(PREFIX "Refuses a file which is not an archive")
{
    const TestDir dir;
    const auto arc_path = MakeFile(dir.directory / "not_an_archive.zip", "definitely not an archive");
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");
    CHECK(!arc::CanReplaceFilesInArchive(arc_path.native()));
    CHECK(!arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native()));
    CHECK(ReadRaw(arc_path) == "definitely not an archive");
}

TEST_CASE(PREFIX "Refuses encrypted archives")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.zip";
    MakeArchive(arc_path, archive_write_set_format_zip, {}, Items(), [](archive *_a) {
        REQUIRE(archive_write_set_options(_a, "zip:encryption=zipcrypt") == ARCHIVE_OK);
        REQUIRE(archive_write_set_passphrase(_a, "secret") == ARCHIVE_OK);
    });
    const std::string original = ReadRaw(arc_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    const auto can = arc::CanReplaceFilesInArchive(arc_path.native());
    REQUIRE(!can);
    CHECK(can.error() == Error{Error::POSIX, ENEEDAUTH});

    const auto rc = arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native());
    REQUIRE(!rc);
    CHECK(rc.error() == Error{Error::POSIX, ENEEDAUTH});
    CHECK(ReadRaw(arc_path) == original);
    CHECK(FilesInDirectory(dir.directory) == 2);
}

TEST_CASE(PREFIX "Cancellation keeps the archive intact")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.7z";
    MakeArchive(arc_path, archive_write_set_format_7zip, {}, Items());
    const std::string original = ReadRaw(arc_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    const auto rc =
        arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native(), {}, [] { return true; });
    REQUIRE(!rc);
    CHECK(rc.error() == Error{Error::POSIX, ECANCELED});
    CHECK(ReadRaw(arc_path) == original);
    CHECK(FilesInDirectory(dir.directory) == 2);
}

TEST_CASE(PREFIX "Preserves the permissions of the archive")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.zip";
    MakeArchive(arc_path, archive_write_set_format_zip, {}, Items());
    REQUIRE(chmod(arc_path.c_str(), 0640) == 0);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    REQUIRE(arc::ReplaceFileInArchive(arc_path.native(), "/file.txt", new_path.native()));
    struct stat st;
    REQUIRE(stat(arc_path.c_str(), &st) == 0);
    CHECK((st.st_mode & ALLPERMS) == 0640);
}

TEST_CASE(PREFIX "Updates the archive behind a symlink and keeps the symlink")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.zip";
    const auto link_path = dir.directory / "link.zip";
    MakeArchive(arc_path, archive_write_set_format_zip, {}, Items());
    std::filesystem::create_symlink(arc_path, link_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "via a symlink");

    REQUIRE(arc::ReplaceFileInArchive(link_path.native(), "/file.txt", new_path.native()));
    CHECK(std::filesystem::is_symlink(link_path));
    const auto host = std::make_shared<ArchiveHost>(arc_path.native(), TestEnv().vfs_native);
    CHECK(ReadFromArchive(*host, "/file.txt") == "via a symlink");
}

TEST_CASE(PREFIX "Reports the progress")
{
    const TestDir dir;
    const auto arc_path = dir.directory / "test.tar.xz";
    MakeArchive(arc_path, archive_write_set_format_pax_restricted, archive_write_add_filter_xz, Items());
    const auto archive_size = std::filesystem::file_size(arc_path);
    const auto new_path = MakeFile(dir.directory / "new.txt", "new");

    std::vector<uint64_t> reports;
    REQUIRE(arc::ReplaceFileInArchive(
        arc_path.native(), "/file.txt", new_path.native(), [&](uint64_t _bytes) { reports.push_back(_bytes); }));
    REQUIRE(!reports.empty());
    CHECK(std::ranges::is_sorted(reports));
    CHECK(reports.back() <= archive_size);
}

} // namespace ArchiveUpdaterTest

#undef PREFIX
