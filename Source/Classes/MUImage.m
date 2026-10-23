// Copyright 2009-2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUImage.h"

@implementation MUImage

+ (UIImage *) tableViewCellImageFromImage:(UIImage *)srcImage {
    if (srcImage.size.height <= 0) return nil;
    CGSize size = CGSizeMake(srcImage.size.width * 44.0 / srcImage.size.height, 44.0);
    CGRect bounds = (CGRect){CGPointZero, size};
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:10] addClip];
        [srcImage drawInRect:bounds];
    }];
}

+ (UIImage *) symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

+ (UIImage *)channelSymbolForCurrentChannel:(BOOL)current {
    return [[self symbolNamed:current ? @"speaker.wave.2.fill" : @"speaker.wave.2" pointSize:22] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Keep the symbol a template; its image view owns the live speaking-state tint.
+ (UIImage *)userTalkSymbolForState:(NSInteger)talkState {
    return [[self symbolNamed:talkState == 0 ? @"person.fill" : @"person.wave.2.fill" pointSize:22] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

+ (UIColor *)userTalkColorForState:(NSInteger)talkState {
    return talkState == 0 ? [UIColor secondaryLabelColor] : [UIColor systemGreenColor];
}

+ (UIImage *) imageNamed:(NSString *)imageName {
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat height = [UIScreen mainScreen].bounds.size.height;
    // For now, we require all -568h images to also be @2x.
    if (height == 568 && scale == 2) {
        NSString *expectedFn = [NSString stringWithFormat:@"%@-568h", imageName];
        UIImage *attemptedImage = [UIImage imageNamed:expectedFn];
        if (attemptedImage != nil) {
            return attemptedImage;
        }
        // fallthrough
    }
    return [UIImage imageNamed:imageName];
}

// clearColorImage returns a 1x1 clearColor image
// that can be used as a transparent background image
// for UIKit APIs that force you to provide UIImages.
+ (UIImage *) clearColorImage {
	CGRect fillRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
	UIGraphicsBeginImageContext(fillRect.size);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(ctx, [UIColor clearColor].CGColor);
	CGContextFillRect(ctx, fillRect);
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return img;
}


@end
