// Copyright (C) 2017-2020 Michael Kazakov. Subject to GNU General Public License version 3.
#include "SyncPanels.h"
#include "../MainWindowFilePanelState.h"
#include "../PanelController.h"
#include <Panel/PanelData.h>
#include <Panel/PanelDataSelection.h>
#include "../Views/FilePanelMainSplitView.h"
#include <DextraCommander/Core/Alert.h>

namespace nc::panel::actions {

bool SyncPanels::Predicate(MainWindowFilePanelState *_target) const
{
    const auto act_pc = _target.activePanelController;
    if( !act_pc )
        return false;

    if( _target.splitView.anyCollapsedOrOverlayed )
        return false;

    return true;
}

void SyncPanels::Perform(MainWindowFilePanelState *_target, id /*_sender*/) const
{
    if( _target.splitView.anyCollapsedOrOverlayed )
        return;

    const auto current = _target.activePanelController;
    const auto opposite = _target.oppositePanelController;

    if( !current || !opposite )
        return;

    if( current.isUniform ) {
        const auto request = std::make_shared<DirectoryChangeRequest>();
        request->RequestedDirectory = current.currentDirectoryPath;
        request->VFS = current.vfs;
        request->PerformAsynchronous = true;
        request->InitiatedByUser = true;
        [opposite GoToDirWithContext:request];
    }
    else {
        [opposite loadListing:current.data.ListingPtr()];
    }
}

bool SwapPanels::Predicate(MainWindowFilePanelState *_target) const
{
    return _target.isPanelActive && !_target.splitView.anyCollapsedOrOverlayed;
}

void SwapPanels::Perform(MainWindowFilePanelState *_target, id /*_sender*/) const
{
    [_target swapPanels];
}

bool CompareFolders::Predicate(MainWindowFilePanelState *_target) const
{
    if( _target.splitView.anyCollapsedOrOverlayed )
        return false;
    const auto left = _target.leftPanelController;
    const auto right = _target.rightPanelController;
    // Temporary panels with items from different folders can't be compared by names.
    return left && right && left.isUniform && right.isUniform;
}

void CompareFolders::Perform(MainWindowFilePanelState *_target, id /*_sender*/) const
{
    if( !Predicate(_target) )
        return;

    const auto left = _target.leftPanelController;
    const auto right = _target.rightPanelController;
    const auto comparison = data::CompareFolders(left.data, right.data);
    [left setEntriesSelection:comparison.left];
    [right setEntriesSelection:comparison.right];

    if( comparison.differences == 0 ) {
        Alert *const alert = [[Alert alloc] init];
        alert.messageText = NSLocalizedString(@"No differences found", "Result of comparing the folders of two panels");
        alert.informativeText =
            NSLocalizedString(@"The items in both panels have the same names, sizes and modification dates.",
                              "Result of comparing the folders of two panels");
        [alert addButtonWithTitle:NSLocalizedString(@"OK", "")];
        [alert beginSheetModalForWindow:_target.window
                      completionHandler:^([[maybe_unused]] NSModalResponse _response){
                      }];
    }
}

} // namespace nc::panel::actions
