// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MLClient.h"

@interface MUServerViewController : UITableViewController <MLServerModelDelegate>
- (id) initWithServerModel:(MLServerModel *)serverModel;
@end
