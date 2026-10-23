// Use of this source code is governed by the BSD-style license in LICENSE.
#import "MUServerTableViewCell.h"
@implementation MUServerTableViewCell
- (id)initWithReuseIdentifier:(NSString *)identifier {
    return [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    UIListContentConfiguration *content = (id)self.contentConfiguration;
    CGFloat leading = _channelRow ? 16 : content.directionalLayoutMargins.leading + 48;
    self.separatorInset = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? UIEdgeInsetsMake(0, 16, 0, leading) : UIEdgeInsetsMake(0, leading, 0, 16);
}
@end
