// Copyright (C) 2017-2024 Michael Kazakov. Subject to GNU General Public License version 3.
#include "OpenFile.h"
#include "../NCPanelOpenWithMenuDelegate.h"
#include "../PanelController.h"
#include "../PanelView.h"
#include <Panel/PanelData.h>
#include "../PanelAux.h"
#include <VFS/VFS.h>
#include <Utility/ObjCpp.h>
#include <Utility/StringExtras.h>
#include <CUI/CommandPopover.h>
#include <algorithm>
#include <functional>
#include <set>
#include <tuple>

// A single application candidate shown in the app picker.
struct NCAppPickerEntry {
    NSString *path;
    NSString *name;
};

static NSString *const g_AppPickerRecentAppsKey = @"FilePanelsOpenWithAppPickerRecentApplications";
static constexpr size_t g_AppPickerMaxRecentApps = 9;
static constexpr size_t g_AppPickerMaxSearchResults = 15;
static const auto g_AppPickerIconSize = NSMakeSize(16, 16);

// Returns a rank of how well the name matches the query, smaller is better, nullopt if it doesn't match at all:
// 0 - the name starts with the query, i.e. "subl" -> "Sublime Text";
// 1 - some word of the name starts with the query, i.e. "text" -> "Sublime Text";
// 2 - initials of the words start with the query, i.e. "st" -> "Sublime Text";
// 3 - the name contains the query somewhere.
static std::optional<int> RankAppNameMatch(NSString *_name, NSString *_query)
{
    const auto opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    if( [_name rangeOfString:_query options:opts | NSAnchoredSearch].location != NSNotFound )
        return 0;

    NSCharacterSet *const separators = [NSCharacterSet characterSetWithCharactersInString:@" -_."];
    NSMutableString *const initials = [NSMutableString string];
    bool word_prefix = false;
    for( NSString *word in [_name componentsSeparatedByCharactersInSet:separators] ) {
        if( word.length == 0 )
            continue;
        [initials appendString:[word substringToIndex:1]];
        if( [word rangeOfString:_query options:opts | NSAnchoredSearch].location != NSNotFound )
            word_prefix = true;
    }
    if( word_prefix )
        return 1;
    if( [initials rangeOfString:_query options:opts | NSAnchoredSearch].location != NSNotFound )
        return 2;
    if( [_name rangeOfString:_query options:opts].location != NSNotFound )
        return 3;
    return std::nullopt;
}

// Recently picked applications, most recent first. Non-existing ones are skipped.
static NSArray<NSString *> *LoadRecentApps()
{
    NSArray *const stored = [NSUserDefaults.standardUserDefaults arrayForKey:g_AppPickerRecentAppsKey];
    NSMutableArray<NSString *> *const recent = [NSMutableArray array];
    for( id path in stored )
        if( [path isKindOfClass:NSString.class] && [NSFileManager.defaultManager fileExistsAtPath:path] )
            [recent addObject:path];
    return recent;
}

static void StoreRecentApp(NSString *_app_path)
{
    NSMutableArray<NSString *> *const recent = [LoadRecentApps() mutableCopy];
    [recent removeObject:_app_path];
    [recent insertObject:_app_path atIndex:0];
    while( recent.count > g_AppPickerMaxRecentApps )
        [recent removeLastObject];
    [NSUserDefaults.standardUserDefaults setObject:recent forKey:g_AppPickerRecentAppsKey];
}

// Feeds the command popover: shows the recently used applications initially and searches through all the installed
// applications as the user types.
@interface NCAppPickerMediator : NSObject <NCCommandPopoverDelegate>
- (instancetype)initWithApplications:(std::vector<NCAppPickerEntry>)_apps
                              onPick:(std::function<void(const std::string &_app_path)>)_on_pick;
- (NCCommandPopover *)makePopover;
@end

// Keeps the popover and its mediator alive while it's shown - popover items reference their target weakly.
static NCCommandPopover *g_AppPickerPopover = nil;
static NCAppPickerMediator *g_AppPickerMediator = nil;

@implementation NCAppPickerMediator {
    std::vector<NCAppPickerEntry> m_Apps;
    NSArray<NSString *> *m_Recent;
    std::function<void(const std::string &_app_path)> m_OnPick;
}

- (instancetype)initWithApplications:(std::vector<NCAppPickerEntry>)_apps
                              onPick:(std::function<void(const std::string &_app_path)>)_on_pick
{
    self = [super init];
    if( self ) {
        m_Apps = std::move(_apps);
        m_Recent = LoadRecentApps();
        m_OnPick = std::move(_on_pick);
    }
    return self;
}

- (NCCommandPopoverItem *)itemForAppAtPath:(NSString *)_path withName:(NSString *)_name
{
    NCCommandPopoverItem *const item = [[NCCommandPopoverItem alloc] init];
    item.title = _name;
    item.toolTip = _path;
    NSImage *const icon = [[NSWorkspace.sharedWorkspace iconForFile:_path] copy];
    icon.size = g_AppPickerIconSize;
    item.image = icon;
    item.representedObject = _path;
    item.target = self;
    item.action = @selector(callout:);
    return item;
}

- (NCCommandPopover *)makePopover
{
    NCCommandPopover *const popover =
        [[NCCommandPopover alloc] initWithTitle:NSLocalizedString(@"Open With", "Title of the app picker popover")];
    popover.delegate = self;
    popover.minimumTitleWidth = 240.;
    if( m_Recent.count != 0 ) {
        [popover addItem:[NCCommandPopoverItem
                             sectionHeaderWithTitle:NSLocalizedString(@"Recently Used",
                                                                      "Recently used apps in the app picker")]];
        for( NSString *path in m_Recent )
            [popover addItem:[self itemForAppAtPath:path
                                           withName:[NSFileManager.defaultManager displayNameAtPath:path]]];
    }
    else {
        [popover addItem:[NCCommandPopoverItem
                             sectionHeaderWithTitle:NSLocalizedString(@"Type to search for an application",
                                                                      "Hint in the app picker without recent apps")]];
    }
    return popover;
}

- (NSArray<NCCommandPopoverItem *> *)commandPopover:(NCCommandPopover *) [[maybe_unused]] _popover
                               itemsForSearchString:(NSString *)_search
{
    NSString *const query = [_search stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if( query.length == 0 )
        return @[];

    // rank, not recent, index - recently used apps go first among equally good matches
    std::vector<std::tuple<int, bool, size_t>> ranked;
    for( size_t i = 0; i < m_Apps.size(); ++i )
        if( auto rank = RankAppNameMatch(m_Apps[i].name, query) )
            ranked.emplace_back(*rank, ![m_Recent containsObject:m_Apps[i].path], i);
    std::ranges::sort(ranked);

    NSMutableArray<NCCommandPopoverItem *> *const items = [NSMutableArray array];
    for( size_t i = 0; i < std::min(ranked.size(), g_AppPickerMaxSearchResults); ++i ) {
        const auto &app = m_Apps[std::get<2>(ranked[i])];
        [items addObject:[self itemForAppAtPath:app.path withName:app.name]];
    }
    return items;
}

- (void)callout:(id)_sender
{
    if( auto item = nc::objc_cast<NCCommandPopoverItem>(_sender) )
        if( NSString *const path = nc::objc_cast<NSString>(item.representedObject) ) {
            StoreRecentApp(path);
            if( m_OnPick )
                m_OnPick(path.fileSystemRepresentation);
        }
}

- (void)commandPopoverDidClose:(NCCommandPopover *) [[maybe_unused]] _popover
{
    g_AppPickerPopover.delegate = nil;
    // Release asynchronously - the action of the clicked item is sent right after the popover is closed.
    dispatch_async(dispatch_get_main_queue(), ^{
      g_AppPickerPopover = nil;
      g_AppPickerMediator = nil;
    });
}

@end

namespace nc::panel::actions {

static void PerformOpeningFilesWithDefaultHandler(const std::vector<VFSListingItem> &_items,
                                                  PanelController *_target,
                                                  FileOpener &_file_opener,
                                                  std::string_view _with_app_at_path = {});

static bool CommonPredicate(PanelController *_target)
{
    const auto i = _target.view.item;
    if( !i )
        return false;

    return !i.IsDotDot() || _target.data.Stats().selected_entries_amount > 0;
}

static bool ShouldRebuildSubmenu(NSMenuItem *_item) noexcept
{
    return !_item.hasSubmenu || objc_cast<NCPanelOpenWithMenuDelegate>(_item.submenu.delegate) == nil;
}

OpenFileWithSubmenu::OpenFileWithSubmenu(NCPanelOpenWithMenuDelegate *_menu_delegate) : m_MenuDelegate(_menu_delegate)
{
}

bool OpenFileWithSubmenu::Predicate(PanelController *_target) const
{
    return CommonPredicate(_target);
}

bool OpenFileWithSubmenu::ValidateMenuItem(PanelController *_target, NSMenuItem *_item) const
{
    if( ShouldRebuildSubmenu(_item) ) {
        NSMenu *const menu = [[NSMenu alloc] init];
        menu.identifier = NCPanelOpenWithMenuDelegate.regularMenuIdentifier;
        menu.delegate = m_MenuDelegate;
        [m_MenuDelegate addManagedMenu:menu];
        _item.submenu = menu;
    }

    m_MenuDelegate.target = _target;

    return Predicate(_target);
}

AlwaysOpenFileWithSubmenu::AlwaysOpenFileWithSubmenu(NCPanelOpenWithMenuDelegate *_menu_delegate)
    : m_MenuDelegate(_menu_delegate)
{
}

bool AlwaysOpenFileWithSubmenu::Predicate(PanelController *_target) const
{
    return CommonPredicate(_target);
}

bool AlwaysOpenFileWithSubmenu::ValidateMenuItem(PanelController *_target, NSMenuItem *_item) const
{
    if( ShouldRebuildSubmenu(_item) ) {
        NSMenu *const menu = [[NSMenu alloc] init];
        menu.identifier = NCPanelOpenWithMenuDelegate.alwaysOpenWithMenuIdentifier;
        menu.delegate = m_MenuDelegate;
        [m_MenuDelegate addManagedMenu:menu];
        _item.submenu = menu;
    }

    m_MenuDelegate.target = _target;

    return Predicate(_target);
}

OpenFilesWithDefaultHandler::OpenFilesWithDefaultHandler(FileOpener &_file_opener) : m_FileOpener(_file_opener)
{
}

bool OpenFilesWithDefaultHandler::Predicate(PanelController *_target) const
{
    return static_cast<bool>(_target.view.item);
}

bool OpenFilesWithDefaultHandler::ValidateMenuItem(PanelController *_target, NSMenuItem *_item) const
{
    if( const auto vfs_item = _target.view.item ) {
        _item.title = [NSString
            stringWithFormat:NSLocalizedString(@"Open \u201c%@\u201d", "Open an item"), vfs_item.DisplayNameNS()];
    }

    return Predicate(_target);
}

void OpenFilesWithDefaultHandler::Perform(PanelController *_target, id /*_sender*/) const
{
    if( !Predicate(_target) ) {
        NSBeep();
        return;
    }

    const auto entries = _target.selectedEntriesOrFocusedEntryWithDotDot;
    PerformOpeningFilesWithDefaultHandler(entries, _target, m_FileOpener);
}

static void PerformOpeningFilesWithDefaultHandler(const std::vector<VFSListingItem> &_items,
                                                  PanelController *_target,
                                                  FileOpener &_file_opener,
                                                  std::string_view _with_app_at_path)
{
    if( _items.empty() )
        return;

    if( _items.size() > 1 ) {
        const auto same_host =
            std::ranges::all_of(_items, [&](const auto &i) { return i.Host() == _items.front().Host(); });
        if( same_host ) {
            std::vector<std::string> items;
            items.reserve(_items.size());
            for( auto &i : _items )
                items.emplace_back(i.Path());
            _file_opener.Open(items, _items.front().Host(), _target, _with_app_at_path);
        }
    }
    else /* if( _items.size() == 1 ) */ {
        auto &item = _items.front();
        const std::string path = item.IsDotDot() ? item.Directory() : item.Path();
        _file_opener.Open(path, item.Host(), _target, _with_app_at_path);
    }
}

// Gathers .app bundles from the standard application folders, also looking one level deep into plain subfolders
// like "/Applications/Utilities". The result is sorted by display name.
static std::vector<NCAppPickerEntry> GatherInstalledApplications()
{
    NSFileManager *const fm = NSFileManager.defaultManager;
    std::vector<NSURL *> roots;
    for( NSURL *url in [fm URLsForDirectory:NSApplicationDirectory inDomains:NSAllDomainsMask] )
        roots.emplace_back(url);
    roots.emplace_back([NSURL fileURLWithPath:@"/System/Library/CoreServices/Applications" isDirectory:true]);

    std::vector<NCAppPickerEntry> apps;
    std::set<std::string> seen;
    const auto add_app = [&](NSURL *_url) {
        NSString *const path = _url.URLByResolvingSymlinksInPath.path;
        if( !path || !seen.emplace(path.fileSystemRepresentation).second )
            return;
        apps.push_back({.path = path, .name = [fm displayNameAtPath:path]});
    };

    const auto scan = [&](NSURL *_dir, int _depth, const auto &_self) -> void {
        NSArray<NSURL *> *const items = [fm contentsOfDirectoryAtURL:_dir
                                          includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsPackageKey]
                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                               error:nil];
        for( NSURL *url in items ) {
            if( [url.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame ) {
                add_app(url);
                continue;
            }
            NSNumber *is_dir = nil;
            NSNumber *is_package = nil;
            [url getResourceValue:&is_dir forKey:NSURLIsDirectoryKey error:nil];
            [url getResourceValue:&is_package forKey:NSURLIsPackageKey error:nil];
            if( _depth > 0 && is_dir.boolValue && !is_package.boolValue )
                _self(url, _depth - 1, _self);
        }
    };

    for( NSURL *root : roots )
        scan(root, 1, scan);

    std::ranges::sort(apps, [](const auto &_lhs, const auto &_rhs) {
        return [_lhs.name localizedStandardCompare:_rhs.name] == NSOrderedAscending;
    });
    return apps;
}

OpenFilesWithAppPicker::OpenFilesWithAppPicker(FileOpener &_file_opener) : m_FileOpener(_file_opener)
{
}

bool OpenFilesWithAppPicker::Predicate(PanelController *_target) const
{
    return CommonPredicate(_target);
}

void OpenFilesWithAppPicker::Perform(PanelController *_target, id /*_sender*/) const
{
    if( !Predicate(_target) || !_target.view ) {
        NSBeep();
        return;
    }

    // Capture the items now - the panel's cursor could move while the popover is shown.
    auto items = _target.selectedEntriesOrFocusedEntry;
    if( items.empty() ) {
        NSBeep();
        return;
    }

    if( g_AppPickerPopover )
        [g_AppPickerPopover close];

    FileOpener *const file_opener = &m_FileOpener;
    g_AppPickerMediator = [[NCAppPickerMediator alloc]
        initWithApplications:GatherInstalledApplications()
                      onPick:[items = std::move(items), _target, file_opener](const std::string &_app_path) {
                          PerformOpeningFilesWithDefaultHandler(items, _target, *file_opener, _app_path);
                      }];
    g_AppPickerPopover = [g_AppPickerMediator makePopover];

    PanelView *const view = _target.view;
    [g_AppPickerPopover showRelativeToRect:NSMakeRect(4, view.bounds.size.height - 8, view.bounds.size.width - 8, 0)
                                    ofView:view
                                 alignment:NCCommandPopoverAlignment::Center];
}
context::OpenFileWithDefaultHandler::OpenFileWithDefaultHandler(const std::vector<VFSListingItem> &_items,
                                                                FileOpener &_file_opener)
    : m_Items(_items), m_FileOpener(_file_opener)
{
}

bool context::OpenFileWithDefaultHandler::Predicate([[maybe_unused]] PanelController *_target) const
{
    const auto has_reg_files = std::ranges::any_of(m_Items, [](auto &_i) { return _i.IsReg(); });
    if( has_reg_files )
        return true;

    const auto all_are_native = std::ranges::all_of(m_Items, [](auto &_i) { return _i.Host()->IsNativeFS(); });
    return all_are_native;
}

void context::OpenFileWithDefaultHandler::Perform(PanelController *_target, id /*_sender*/) const
{
    PerformOpeningFilesWithDefaultHandler(m_Items, _target, m_FileOpener);
}

} // namespace nc::panel::actions
