// Copyright (C) 2024-2026 Michael Kazakov. Subject to GNU General Public License version 3.
#pragma once
#include <Cocoa/Cocoa.h>

@class NCCommandPopover;
@class NCCommandPopoverItem;

// Controls the horizontal alignment of the popover window relative to the positioning rectangle
enum class NCCommandPopoverAlignment : uint8_t {
    Left = 0,
    Center = 1,
    Right = 2
};

// NCCommandPopoverItem mimics the semantics of NSMenuItem but for NCCommandPopover instead
@interface NCCommandPopoverItem : NSObject

- (instancetype _Nonnull)init;

+ (instancetype _Nonnull)separatorItem;

+ (instancetype _Nonnull)sectionHeaderWithTitle:(NSString *_Nonnull)_title;

@property(nonatomic, copy) NSString *_Nonnull title;

@property(nonatomic, nullable, copy) NSString *toolTip;

@property(nonatomic, nullable, strong) NSImage *image;

@property(nonatomic, nullable, weak) id target;

@property(nonatomic, nullable) SEL action;

@property(nonatomic) NSInteger tag;

@property(nonatomic, nullable, strong) id representedObject;

@property(nonatomic, readonly) bool separatorItem;

@property(nonatomic, readonly) bool sectionHeader;

@end

@protocol NCCommandPopoverDelegate <NSObject>
@optional
// Called after the popover is closed due to any reason.
- (void)commandPopoverDidClose:(NCCommandPopover *_Nonnull)_popover;

// If implemented, it's called whenever the search string is not empty and the returned items are shown instead of
// the regular ones filtered by their titles. This allows searching over a set of items wider than the initial one.
- (NSArray<NCCommandPopoverItem *> *_Nonnull)commandPopover:(NCCommandPopover *_Nonnull)_popover
                                       itemsForSearchString:(NSString *_Nonnull)_search;
@end

@interface NCCommandPopover : NSObject <NSWindowDelegate>

- (instancetype _Nonnull)init NS_UNAVAILABLE;
- (instancetype _Nonnull)initWithTitle:(NSString *_Nonnull)_title;

// Adds a new item to be shown in the list later
- (void)addItem:(NCCommandPopoverItem *_Nonnull)_newItem;

// Shows the popover positioning it under the specified rectangle of a particular view.
// Can be aligned horizontally.
- (void)showRelativeToRect:(NSRect)_positioning_rect
                    ofView:(NSView *_Nonnull)_positioning_view
                 alignment:(NCCommandPopoverAlignment)_alignment;

- (void)close;

@property(nonatomic, nullable, weak) id<NCCommandPopoverDelegate> delegate;

// The minimum width of the titles column, useful when the items can change while searching. Zero by default.
@property(nonatomic) double minimumTitleWidth;

@end
