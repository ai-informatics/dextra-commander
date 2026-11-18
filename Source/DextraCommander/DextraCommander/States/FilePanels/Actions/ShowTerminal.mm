// Copyright (C) 2017-2019 Michael Kazakov. Subject to GNU General Public License version 3.
#include "ShowTerminal.h"
#include "../MainWindowFilePanelState.h"
#include "../PanelController.h"
#include "../../MainWindowController.h"
#include <Utility/ObjCpp.h>

namespace nc::panel::actions {

static const auto g_ShowTitle = NSLocalizedString(@"Show Terminal", "Menu item title for showing terminal");

bool ShowTerminal::ValidateMenuItem(MainWindowFilePanelState *_target, NSMenuItem *_item) const
{
    _item.title = g_ShowTitle;
    return Predicate(_target);
}

void ShowTerminal::Perform(MainWindowFilePanelState *_target, [[maybe_unused]] id _sender) const
{
    std::string path;

    if( const auto pc = _target.activePanelController )
        if( pc.isUniform && pc.vfs->IsNativeFS() )
            path = pc.currentDirectoryPath;

    if( const auto mwc = objc_cast<NCMainWindowController>(_target.window.delegate) )
        [mwc requestTerminal:path];
}

bool ShowTerminalInOppositePanel::Predicate(MainWindowFilePanelState *_target) const
{
    // A terminal can always be closed, but it can be opened only while both panels are shown.
    return _target.terminalInOppositePanel != nil || (!_target.isPanelsSplitViewHidden && !_target.anyPanelCollapsed);
}

bool ShowTerminalInOppositePanel::ValidateMenuItem(MainWindowFilePanelState *_target, NSMenuItem *_item) const
{
    _item.title =
        _target.terminalInOppositePanel
            ? NSLocalizedString(@"Hide Terminal in Opposite Panel",
                                "Menu item title for hiding the terminal shown in place of the inactive panel")
            : NSLocalizedString(@"Show Terminal in Opposite Panel",
                                "Menu item title for showing a terminal in place of the inactive panel");
    return Predicate(_target);
}

void ShowTerminalInOppositePanel::Perform(MainWindowFilePanelState *_target, [[maybe_unused]] id _sender) const
{
    [_target toggleTerminalInOppositePanel];
}

} // namespace nc::panel::actions
