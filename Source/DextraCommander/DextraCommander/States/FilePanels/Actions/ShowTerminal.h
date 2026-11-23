// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once
#include "DefaultAction.h"

namespace nc::panel::actions {

struct ShowTerminal final : StateAction {
    [[nodiscard]] bool ValidateMenuItem(MainWindowFilePanelState *_target, NSMenuItem *_item) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

// Shows or hides a terminal in place of the inactive panel.
struct ShowTerminalInOppositePanel final : StateAction {
    [[nodiscard]] bool Predicate(MainWindowFilePanelState *_target) const override;
    [[nodiscard]] bool ValidateMenuItem(MainWindowFilePanelState *_target, NSMenuItem *_item) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

// Changes the folder of the terminal shown in place of the inactive panel to the folder of the panel next to it.
struct SyncTerminalInOppositePanelWithPanel final : StateAction {
    [[nodiscard]] bool Predicate(MainWindowFilePanelState *_target) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

} // namespace nc::panel::actions
