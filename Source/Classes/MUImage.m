// Copyright 2009-2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUImage.h"

@implementation MUImage

+ (UIImage *) tableViewCellImageFromImage:(UIImage *)srcImage {
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGFloat scaledWidth = srcImage.size.width * (44.0f/srcImage.size.height);
    CGRect rect = CGRectMake(0, 0, scaledWidth, 44.0f);
    
    // Create the rounded-rect mask
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat radius = 10.0f;
    CGContextBeginPath(ctx);
    CGContextMoveToPoint(ctx, rect.origin.x, rect.origin.y + radius);
    CGContextAddLineToPoint(ctx, rect.origin.x, rect.origin.y + rect.size.height - radius);
    CGContextAddArc(ctx, rect.origin.x + radius, rect.origin.y + rect.size.height - radius, radius, M_PI, M_PI / 2, 1);
    CGContextAddLineToPoint(ctx, rect.origin.x + rect.size.width, rect.origin.y + rect.size.height);
    CGContextAddLineToPoint(ctx, rect.origin.x + rect.size.width, rect.origin.y);
    CGContextAddLineToPoint(ctx, rect.origin.x + radius, rect.origin.y);
    CGContextAddArc(ctx, rect.origin.x + radius, rect.origin.y + radius, radius, -M_PI / 2, M_PI, 1);
    CGContextClosePath(ctx);
    [[UIColor blackColor] set];
    CGContextFillPath(ctx);
    UIImage *alphaMask = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // Draw the image
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, scale);
    ctx = UIGraphicsGetCurrentContext();
    CGContextClipToMask(ctx, rect, alphaMask.CGImage);
    [srcImage drawInRect:rect];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return scaledImage;
}

// clearColorImage returns a 1x1 clearColor image
// that can be used as a transparent background image
// for UIKit APIs that force you to provide UIImages.
+ (UIImage *) symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

+ (UIImage *) symbolNamed:(NSString *)name pointSize:(CGFloat)pointSize color:(UIColor *)color {
    UIImage *image = [self symbolNamed:name pointSize:pointSize];
    return [[image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPaletteColors:@[color]]] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

+ (UIImage *) channelSymbol {
    return [self channelSymbolForCurrentChannel:NO];
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
