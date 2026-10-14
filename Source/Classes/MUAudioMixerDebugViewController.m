// Copyright 2013 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUAudioMixerDebugViewController.h"
#import "MLClient.h"

@interface MUAudioMixerDebugViewController () {
    NSDictionary  *_mixerInfo;
    NSTimer       *_timer;
    NSDateFormatter *_dateFormatter;
}
@end

@implementation MUAudioMixerDebugViewController

- (id) init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        // ...
    }
    return self;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self navigationItem] setTitle:NSLocalizedString(@"Mixer Debug", nil)];
    
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneDebugging:)];
    [[self navigationItem] setRightBarButtonItem:doneButton];
    
    [_timer invalidate];
    __weak MUAudioMixerDebugViewController *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf updateMixerInfo:timer]; }];
    _timer.tolerance = .2;
    [self updateMixerInfo:self];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate]; _timer = nil;
}

- (void)dealloc { [_timer invalidate]; }

- (void) updateMixerInfo:(id)sender {
    _mixerInfo = [[MLAudio sharedAudio] copyAudioOutputMixerDebugInfo];
    [[self tableView] reloadData];
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) { // Metadata
        return 1;
    } else if (section == 1) { // Sources
        return [[_mixerInfo objectForKey:@"sources"] count];
    } else if (section == 2) { // Removed
        return [[_mixerInfo objectForKey:@"removed"] count];
    }
    
    return 0;
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"AudioMixerDebugCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
    }
    
    if (indexPath.section == 0) { // Meta
        if (indexPath.row == 0) { // Last Update
            if (!_dateFormatter) { _dateFormatter = [NSDateFormatter new]; _dateFormatter.dateFormat = @"HH:mm:ss:SSS"; }
            NSDate *date = [_mixerInfo objectForKey:@"last-update"];
            cell.textLabel.text = NSLocalizedString(@"Last Updated", nil);
            cell.detailTextLabel.text = [_dateFormatter stringFromDate:date];
        }
    }
    
    if (indexPath.section == 1) {
        NSDictionary *info = [[_mixerInfo objectForKey:@"sources"] objectAtIndex:indexPath.row];
        cell.textLabel.text = [info objectForKey:@"kind"];
        cell.detailTextLabel.text = [info objectForKey:@"identifier"];
    } else if (indexPath.section == 2) {
        NSDictionary *info = [[_mixerInfo objectForKey:@"removed"] objectAtIndex:indexPath.row];
        cell.textLabel.text = [info objectForKey:@"kind"];
        cell.detailTextLabel.text = [info objectForKey:@"identifier"];    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    return cell;
}
- (NSString *) tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Metadata";
    } else if (section == 1) {
        return @"Sources";
    } else if (section == 2) {
        return @"Removed";
    }

    return @"Unknown";
}

- (void) doneDebugging:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
