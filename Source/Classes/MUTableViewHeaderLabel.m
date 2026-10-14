// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUTableViewHeaderLabel.h"

@implementation MUTableViewHeaderLabel

- (id) init {
    if ((self = [super init])) {
        self.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        self.textColor = [UIColor secondaryLabelColor];
        self.backgroundColor = [UIColor clearColor];
        self.textAlignment = NSTextAlignmentNatural;
    }
    return self;
}

+ (CGFloat) defaultHeaderHeight {
    return 36.0f;
}

- (void) drawTextInRect:(CGRect)rect {
    UIEdgeInsets insets = UIEdgeInsetsMake(14.0f, 20.0f, 4.0f, 20.0f);
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, insets)];
}

+ (MUTableViewHeaderLabel *) labelWithText:(NSString *)text {
    MUTableViewHeaderLabel *label = [[MUTableViewHeaderLabel alloc] init];
    label.text = text;
    return label;
}

@end
