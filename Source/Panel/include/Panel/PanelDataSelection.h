// Copyright (C) 2017-2022 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once

#include <vector>
#include <string>
#include <Utility/FileMask.h>

namespace nc::panel::data {

class Model;

class SelectionBuilder
{
public:
    SelectionBuilder(const nc::panel::data::Model &_pd, bool _ignore_dirs_on_mask = true);

    // it would be good to transform these methods into something like this:
    // pair<vector<unsigned>,vector<bool>> to reduce redundant operations.

    [[nodiscard]] std::vector<bool> SelectionByExtension(const std::string &_extension,
                                                         bool _result_selection = true) const;
    [[nodiscard]] std::vector<bool> SelectionByMask(const utility::FileMask &_mask,
                                                    bool _result_selection = true) const;

    [[nodiscard]] std::vector<bool> InvertSelection() const;

private:
    const nc::panel::data::Model &m_Data;
    bool m_IgnoreDirectoriesOnMaskSelection;
};

/**
 * The selections produced by comparing the contents of two panels, see CompareFolders().
 */
struct FoldersComparison {
    // Indexed by the sorted positions in the left panel.
    std::vector<bool> left;

    // Indexed by the sorted positions in the right panel.
    std::vector<bool> right;

    // The number of entries selected in both panels.
    size_t differences = 0;
};

/**
 * Compares the entries shown in two panels to find what differs, like "Compare directories" of Total Commander.
 * Selects an entry that is missing on the other side, the newer one of two files with different modification times,
 * and both of two files with the same modification time but different sizes. The contents of the files are not
 * compared, neither are the directories present on both sides. ".." is ignored.
 */
[[nodiscard]] FoldersComparison CompareFolders(const nc::panel::data::Model &_left,
                                               const nc::panel::data::Model &_right);

}; // namespace nc::panel::data
