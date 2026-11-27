// Copyright (C) 2017 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once
#include "DefaultAction.h"

namespace nc::panel::actions {

struct SyncPanels final : StateAction {
    [[nodiscard]] bool Predicate(MainWindowFilePanelState *_target) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

struct SwapPanels final : StateAction {
    [[nodiscard]] bool Predicate(MainWindowFilePanelState *_target) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

// Selects the items that differ between the two panels, like "Compare directories" of Total Commander.
struct CompareFolders final : StateAction {
    [[nodiscard]] bool Predicate(MainWindowFilePanelState *_target) const override;
    void Perform(MainWindowFilePanelState *_target, id _sender) const override;
};

} // namespace nc::panel::actions
