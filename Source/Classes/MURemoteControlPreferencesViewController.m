#import "MUInterface.h"
// Copyright 2012 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MURemoteControlPreferencesViewController.h"
#import "MURemoteControlServer.h"
#import "MUImage.h"
#import "MUBackgroundView.h"

@interface MURemoteControlPreferencesViewController () {
}
@end

@implementation MURemoteControlPreferencesViewController

- (id) init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

#pragma mark - View controller life cycle

- (void) viewWillAppear:(BOOL)animated {
    self.navigationItem.title = NSLocalizedString(@"Remote Control", nil);
    
    self.tableView.backgroundView = [MUBackgroundView backgroundView];
    
    {
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    }

    self.tableView.scrollEnabled = YES;
}

#pragma mark - Table view data source

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 1;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"RemoteControlPrefsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
        MUConfigureStandardCell(cell);
    }
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = NSLocalizedString(@"Enable", nil);
            UISwitch *enableSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
            [enableSwitch addTarget:self action:@selector(enableSwitchChanged:) forControlEvents:UIControlEventValueChanged];
            enableSwitch.on = [[MURemoteControlServer sharedRemoteControlServer] isRunning];
            cell.accessoryView = enableSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }

    return cell;
}



#pragma mark - Table view delegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
}

#pragma mark - Action

- (void) enableSwitchChanged:(id)sender {
    UISwitch *enableSwitch = sender;
    MURemoteControlServer *server = [MURemoteControlServer sharedRemoteControlServer];
    [[NSUserDefaults standardUserDefaults] setBool:enableSwitch.isOn forKey:@"RemoteControlServerEnabled"];
    if (enableSwitch.isOn) {
        BOOL on = [server start];
        if (!on) {
            enableSwitch.on = NO;
        }
    } else {
        [server stop];
    }
}

@end
