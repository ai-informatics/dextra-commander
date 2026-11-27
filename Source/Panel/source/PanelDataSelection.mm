// Copyright (C) 2017-2022 Michael Kazakov. Subject to GNU General Public License version 3.
#include "PanelDataSelection.h"
#include <Utility/ExtensionLowercaseComparison.h>
#include "PanelData.h"
#include "PanelDataItemVolatileData.h"
#include <VFS/VFS.h>
#include <algorithm>
#include <string_view>
#include <unordered_map>

namespace nc::panel::data {

// File systems like FAT store modification times with a granularity of 2 seconds.
static constexpr time_t g_ModificationTimeTolerance = 2;

SelectionBuilder::SelectionBuilder(const Model &_pd, bool _ignore_dirs_on_mask)
    : m_Data(_pd), m_IgnoreDirectoriesOnMaskSelection(_ignore_dirs_on_mask)
{
}

std::vector<bool> SelectionBuilder::SelectionByExtension(const std::string &_extension, bool _result_selection) const
{
    auto &comparison = utility::ExtensionLowercaseComparison::Instance();
    const auto extension = comparison.ExtensionToLowercase(_extension);
    const auto empty = extension.empty();
    const auto count = m_Data.SortedEntriesCount();

    std::vector<bool> selection(count);
    const auto &listing = m_Data.Listing();
    for( int i = 0, e = count; i != e; ++i ) {
        const auto raw_index = m_Data.RawIndexForSortIndex(i);
        selection[i] = m_Data.VolatileDataAtRawPosition(raw_index).is_selected();

        if( m_IgnoreDirectoriesOnMaskSelection && listing.IsDir(raw_index) )
            continue;

        bool legit = false;
        if( listing.HasExtension(raw_index) ) {
            if( comparison.Equal(listing.Extension(raw_index), extension) )
                legit = true;
        }
        else if( empty )
            legit = true;

        if( legit )
            selection[i] = _result_selection;
    }
    return selection;
}

std::vector<bool> SelectionBuilder::SelectionByMask(const utility::FileMask &_mask, bool _result_selection) const
{
    const auto count = m_Data.SortedEntriesCount();
    std::vector<bool> selection(count);
    const auto &listing = m_Data.Listing();
    for( int i = 0, e = count; i != e; ++i ) {
        const auto raw_index = m_Data.RawIndexForSortIndex(i);
        selection[i] = m_Data.VolatileDataAtRawPosition(raw_index).is_selected();

        if( m_IgnoreDirectoriesOnMaskSelection && listing.IsDir(raw_index) )
            continue;

        if( _mask.MatchName(listing.DisplayFilename(raw_index)) )
            selection[i] = _result_selection;
    }

    return selection;
}

std::vector<bool> SelectionBuilder::InvertSelection() const
{
    const auto count = m_Data.SortedEntriesCount();
    std::vector<bool> selection(count);
    for( int i = 0; i < count; ++i )
        selection[i] = !m_Data.VolatileDataAtSortPosition(i).is_selected();
    return selection;
}

// Maps the filenames of the entries shown in a panel to their sorted positions.
static std::unordered_map<std::string_view, int> SortedPositionsByFilename(const Model &_data)
{
    std::unordered_map<std::string_view, int> positions;
    const auto &listing = _data.Listing();
    const auto count = _data.SortedEntriesCount();
    positions.reserve(count);
    for( int i = 0; i < count; ++i )
        positions.emplace(listing.Filename(_data.RawIndexForSortIndex(i)), i);
    return positions;
}

FoldersComparison CompareFolders(const Model &_left, const Model &_right)
{
    FoldersComparison result;
    result.left.assign(_left.SortedEntriesCount(), false);
    result.right.assign(_right.SortedEntriesCount(), false);

    const auto &left_listing = _left.Listing();
    const auto &right_listing = _right.Listing();
    const auto right_positions = SortedPositionsByFilename(_right);
    std::vector<bool> right_matched(result.right.size(), false);

    for( int left_pos = 0, count = _left.SortedEntriesCount(); left_pos < count; ++left_pos ) {
        const auto left_raw = _left.RawIndexForSortIndex(left_pos);
        if( left_listing.IsDotDot(left_raw) )
            continue;

        const auto match = right_positions.find(left_listing.Filename(left_raw));
        if( match == right_positions.end() ) {
            result.left[left_pos] = true;
            continue;
        }

        const int right_pos = match->second;
        const auto right_raw = _right.RawIndexForSortIndex(right_pos);
        right_matched[right_pos] = true;

        const bool left_is_dir = left_listing.IsDir(left_raw);
        if( left_is_dir != right_listing.IsDir(right_raw) ) {
            result.left[left_pos] = true;
            result.right[right_pos] = true;
            continue;
        }
        if( left_is_dir )
            continue;

        if( left_listing.HasMTime(left_raw) && right_listing.HasMTime(right_raw) ) {
            const time_t left_time = left_listing.MTime(left_raw);
            const time_t right_time = right_listing.MTime(right_raw);
            if( left_time > right_time + g_ModificationTimeTolerance ) {
                result.left[left_pos] = true;
                continue;
            }
            if( right_time > left_time + g_ModificationTimeTolerance ) {
                result.right[right_pos] = true;
                continue;
            }
        }

        const bool left_has_size = left_listing.HasSize(left_raw);
        const bool sizes_differ = left_has_size != right_listing.HasSize(right_raw) ||
                                  (left_has_size && left_listing.Size(left_raw) != right_listing.Size(right_raw));
        if( sizes_differ ) {
            result.left[left_pos] = true;
            result.right[right_pos] = true;
        }
    }

    for( int right_pos = 0, count = _right.SortedEntriesCount(); right_pos < count; ++right_pos )
        if( !right_matched[right_pos] && !right_listing.IsDotDot(_right.RawIndexForSortIndex(right_pos)) )
            result.right[right_pos] = true;

    const auto selected = std::ranges::count(result.left, true) + std::ranges::count(result.right, true);
    result.differences = static_cast<size_t>(selected);
    return result;
}

} // namespace nc::panel::data
