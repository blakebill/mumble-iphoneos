// Copyright 2009-2011 The 'Mumble for iOS' Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MUConnectionController.h"
#import "MUApplicationDelegate.h"
#import "MUServerRootViewController.h"
#import "MUServerCertificateTrustViewController.h"
#import "MUCertificateController.h"
#import "MUCertificateChainBuilder.h"
#import "MUDatabase.h"
#import "MUFavouriteServer.h"

#import "MLClient.h"

NSString *MUConnectionOpenedNotification = @"MUConnectionOpenedNotification";
NSString *MUConnectionClosedNotification = @"MUConnectionClosedNotification";

@interface MUConnectionController () <MLConnectionDelegate, MLServerModelDelegate, MUServerCertificateTrustViewControllerProtocol> {
    MLConnection               *_connection;
    MLServerModel              *_serverModel;
    MUServerRootViewController *_serverRoot;
    UIViewController           *_parentViewController;
    UIAlertController          *_alertCtrl;

    UIAlertController          *_rejectAlertCtrl;

    NSString                   *_hostname;
    NSUInteger                 _port;
    NSString                   *_username;
    NSString                   *_password;
    NSInteger                  _favouritePrimaryKey;
    BOOL                       _savePasswordOnJoin;
    NSUInteger                 _connectionAttempt;

}
- (void) establishConnection;
- (void) teardownConnection;
- (void) showConnectingView;
- (void) hideConnectingView;
- (void) hideConnectingViewWithCompletion:(void(^)(void))completion;
- (void)presentConnectionAlert:(UIAlertController *)alert forAttempt:(NSUInteger)attempt;
- (void)beginConnectionToHostname:(NSString *)hostname port:(NSUInteger)port username:(NSString *)username password:(NSString *)password favouriteKey:(NSInteger)key parent:(UIViewController *)parent;
@end

@implementation MUConnectionController

+ (MUConnectionController *) sharedController {
    static MUConnectionController *nc;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        nc = [[MUConnectionController alloc] init];
    });
    return nc;
}

- (void) connectToHostname:(NSString *)hostName port:(NSUInteger)port withUsername:(NSString *)userName andPassword:(NSString *)password withParentViewController:(UIViewController *)parentViewController {
    [self beginConnectionToHostname:hostName port:port username:userName password:password favouriteKey:-1 parent:parentViewController];
}

- (void)connectToFavouriteServer:(MUFavouriteServer *)server withParentViewController:(UIViewController *)parentViewController {
    NSString *username = server.userName.length ? server.userName : [NSUserDefaults.standardUserDefaults stringForKey:@"DefaultUserName"];
    [self beginConnectionToHostname:server.hostName port:server.port username:username password:server.password favouriteKey:server.primaryKey parent:parentViewController];
}

- (void)beginConnectionToHostname:(NSString *)hostname port:(NSUInteger)port username:(NSString *)username password:(NSString *)password favouriteKey:(NSInteger)key parent:(UIViewController *)parent {
    _hostname = [hostname copy];
    _port = port;
    _username = [username copy];
    _password = [password copy];
    _favouritePrimaryKey = key;
    _savePasswordOnJoin = NO;
    _rejectAlertCtrl = nil;
    _parentViewController = parent;
    [self establishConnection];
    [self showConnectingView];
}

- (BOOL) isConnected {
    return _connection != nil;
}

- (void) disconnectFromServer {
    [_serverRoot dismissViewControllerAnimated:YES completion:nil];
    [self teardownConnection];
}

- (void) showConnectingView {
    NSUInteger attempt = _connectionAttempt;
    NSString *title = [NSString stringWithFormat:@"%@...", NSLocalizedString(@"Connecting", nil)];
    NSString *msg = [NSString stringWithFormat:
                     NSLocalizedString(@"Connecting to %@:%lu", @"Connecting to hostname:port"),
                     _hostname, (unsigned long)_port];
    
    _alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                     message:msg
                                              preferredStyle:UIAlertControllerStyleAlert];
    [_alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
            if (attempt != self->_connectionAttempt) return;
            self->_savePasswordOnJoin = NO;
            self->_alertCtrl = nil;
            [self teardownConnection];
    }]];
    [self presentConnectionAlert:_alertCtrl forAttempt:_connectionAttempt];
    
}

- (void)presentConnectionAlert:(UIAlertController *)alert forAttempt:(NSUInteger)attempt {
    if (!alert || (alert != _alertCtrl && alert != _rejectAlertCtrl) || attempt != _connectionAttempt || !_parentViewController.view.window) return;
    UIViewController *presented = _parentViewController.presentedViewController;
    if (presented == alert) return;
    if (presented) {
        void (^dismiss)(void) = ^{
            if (attempt != self->_connectionAttempt) return;
            if (!presented.presentingViewController) {
                [self presentConnectionAlert:alert forAttempt:attempt];
                return;
            }
            [presented dismissViewControllerAnimated:YES completion:^{
                [self presentConnectionAlert:alert forAttempt:attempt];
            }];
        };
        id<UIViewControllerTransitionCoordinator> transition = presented.transitionCoordinator;
        if (transition) {
            [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                dispatch_async(dispatch_get_main_queue(), dismiss);
            }];
        } else {
            dismiss();
        }
    } else {
        [_parentViewController presentViewController:alert animated:YES completion:nil];
    }
}

- (void) hideConnectingView {
    [self hideConnectingViewWithCompletion:nil];
}

- (void) hideConnectingViewWithCompletion:(void (^)(void))completion {

    UIAlertController *connecting = _alertCtrl;
    _alertCtrl = nil;
    if (connecting.presentingViewController) {
        void (^dismiss)(void) = ^{ [connecting dismissViewControllerAnimated:YES completion:completion]; };
        id<UIViewControllerTransitionCoordinator> transition = connecting.transitionCoordinator;
        if (transition) {
            [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                dispatch_async(dispatch_get_main_queue(), dismiss);
            }];
        } else {
            dismiss();
        }
    } else if (completion != nil) {
        completion();
    }
}

- (void) establishConnection {
    _connectionAttempt++;
    _connection = [[MLConnection alloc] init];
    [_connection setDelegate:self];
    [_connection setForceTCP:[[NSUserDefaults standardUserDefaults] boolForKey:@"NetworkForceTCP"]];
    
    _serverModel = [[MLServerModel alloc] initWithConnection:_connection];
    [_serverModel addDelegate:self];
    
    _serverRoot = [[MUServerRootViewController alloc] initWithConnection:_connection andServerModel:_serverModel];
    
    // Set the connection's client cert if one is set in the app's preferences...
    NSData *certPersistentId = [[NSUserDefaults standardUserDefaults] objectForKey:@"DefaultCertificate"];
    if (certPersistentId != nil) {
        NSArray *certChain = [MUCertificateChainBuilder buildChainFromPersistentRef:certPersistentId];
        [_connection setCertificateChain:certChain];
    }
    
    [_connection connectToHost:_hostname port:_port];

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MUConnectionOpenedNotification object:nil];
    });
}

- (void) teardownConnection {
    [_serverModel removeDelegate:self];
    _serverModel = nil;
    [_connection setDelegate:nil];
    [_connection disconnect];
    _connection = nil;
    _serverRoot = nil;
    
    // Reset app badge. The connection is no more.
    [MUApplicationDelegate setApplicationBadgeCount:0];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:MUConnectionClosedNotification object:nil];
    });
}
            

- (void) connectionOpened:(MLConnection *)conn {
    NSArray *tokens = [MUDatabase accessTokensForServerWithHostname:[conn hostname] port:[conn port]];
    [conn authenticateWithUsername:_username password:_password accessTokens:tokens];
}

- (void) connection:(MLConnection *)conn closedWithError:(NSError *)err {
    if (err == nil) {
        [self hideConnectingView];
        return;
    }
    UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Connection closed", nil)
                                                                       message:[err localizedDescription]
                                                                preferredStyle:UIAlertControllerStyleAlert];
    [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    [self hideConnectingViewWithCompletion:^{
        [self->_parentViewController presentViewController:alertCtrl animated:YES completion:nil];
    }];
    [self teardownConnection];
}

- (void) connection:(MLConnection*)conn unableToConnectWithError:(NSError *)err {
    NSString *msg = [err localizedDescription];

    // errSSLClosedAbort: "connection closed via error".
    //
    // This is the error we get when users hit a global ban on the server.
    // Ideally, we'd provide better descriptions for more of these errors,
    // but when using NSStream's TLS support, the NSErrors we get are simply
    // OSStatus codes in an NSError wrapper without a useful description.
    //
    // In the future, libmumble should probably wrap the SecureTransport range of
    // OSStatus codes to improve this situation, but this will do for now.
    if ([[err domain] isEqualToString:NSOSStatusErrorDomain] && [err code] == -9806) {
        msg = NSLocalizedString(@"The TLS connection was closed due to an error.\n\n"
                                @"The server might be temporarily rejecting your connection because you have "
                                @"attempted to connect too many times in a row.", nil);
    }
    
    UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Unable to connect", nil)
                                                                       message:msg
                                                                preferredStyle:UIAlertControllerStyleAlert];
    
    [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    [self hideConnectingViewWithCompletion:^{
        [self->_parentViewController presentViewController:alertCtrl animated:YES completion:nil];
    }];
    
    [self teardownConnection];
}

// The connection encountered an invalid SSL certificate chain.
- (void) connection:(MLConnection *)conn trustFailureInCertificateChain:(NSArray *)chain {
    // Check the database whether the user trusts the leaf certificate of this server.
    NSString *storedDigest = [MUDatabase digestForServerWithHostname:[conn hostname] port:[conn port]];
    MLCertificate *cert = [[conn peerCertificates] firstObject];
    NSString *serverDigest = [cert hexDigest];
    
    void (^cancelHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        // Tear down the connection.
        [self teardownConnection];
    };
    void (^ignoreHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        // Ignore just reconnects to the server without
        // performing any verification on the certificate chain
        // the server presents us.
        [self->_connection setIgnoreSSLVerification:YES];
        [self->_connection reconnect];
        [self showConnectingView];
    };
    void (^trustHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        // Store the cert hash of the leaf certificate.  We then ignore certificate
        // verification errors from this host as long as it keeps on presenting us
        // the same certificate it always has.
        MLCertificate *cert = [[self->_connection peerCertificates] objectAtIndex:0];
        NSString *digest = [cert hexDigest];
        [MUDatabase storeDigest:digest forServerWithHostname:[self->_connection hostname] port:[self->_connection port]];
        [self->_connection setIgnoreSSLVerification:YES];
        [self->_connection reconnect];
        [self showConnectingView];
    };
    void (^showCertsHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        MUServerCertificateTrustViewController *certTrustView = [[MUServerCertificateTrustViewController alloc] initWithCertificates:[self->_connection peerCertificates]];
        [certTrustView setDelegate:self];
        UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:certTrustView];
        [self->_parentViewController presentViewController:navCtrl animated:YES completion:nil];
    };
    
    if (storedDigest) {
        if ([storedDigest isEqualToString:serverDigest]) {
            // Match
            [conn setIgnoreSSLVerification:YES];
            [conn reconnect];
            return;
        } else {
            // Mismatch.  The server is using a new certificate, different from the one it previously
            // presented to us.
            NSString *title = NSLocalizedString(@"Certificate Mismatch", nil);
            NSString *msg = NSLocalizedString(@"The server presented a different certificate than the one stored for this server", nil);
            
            UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                                               message:msg
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:ignoreHandler]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Trust New Certificate", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:trustHandler]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Show Certificates", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:showCertsHandler]];
            
            [self hideConnectingViewWithCompletion:^{
                [self->_parentViewController presentViewController:alertCtrl animated:YES completion:nil];
            }];
        }
    } else {
        // No certhash of this certificate in the database for this hostname-port combo.  Let the user decide
        // what to do.
        NSString *title = NSLocalizedString(@"Unable to validate server certificate", nil);
        NSString *msg = NSLocalizedString(@"Mumble was unable to validate the certificate chain of the server.", nil);
        
        UIAlertController *alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                                           message:msg
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                       style:UIAlertActionStyleCancel
                                                     handler:cancelHandler]];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Ignore", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:ignoreHandler]];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Trust Certificate", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:trustHandler]];
        [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Show Certificates", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:showCertsHandler]];
        
        [self hideConnectingViewWithCompletion:^{
            [self->_parentViewController presentViewController:alertCtrl animated:YES completion:nil];
        }];
    }
}

// The server rejected our connection.
- (UIAlertController *)passwordAlertForReason:(MLRejectReason)reason attempt:(NSUInteger)attempt {
    BOOL serverPassword = reason == MLRejectReasonWrongServerPassword;
    NSString *title = serverPassword ? (_password.length ? NSLocalizedString(@"Incorrect Password", nil) : NSLocalizedString(@"Password Required", nil)) : NSLocalizedString(@"Authentication Required", nil);
    NSString *message = serverPassword ? [NSString stringWithFormat:NSLocalizedString(@"Enter the server password to connect to %@.", nil), _hostname] : NSLocalizedString(@"Enter the password for this user, or check your certificate.", nil);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.secureTextEntry = YES;
        field.textContentType = UITextContentTypePassword;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.placeholder = NSLocalizedString(@"Password", nil);
        [field addTarget:self action:@selector(rejectionPasswordChanged:) forControlEvents:UIControlEventEditingChanged];
    }];
    __weak MUConnectionController *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        MUConnectionController *controller = weakSelf;
        if (!controller || attempt != controller->_connectionAttempt) return;
        controller->_savePasswordOnJoin = NO;
        controller->_rejectAlertCtrl = nil;
    }]];
    for (NSNumber *save in @[@NO, @YES]) {
        UIAlertAction *connect = [UIAlertAction actionWithTitle:save.boolValue ? NSLocalizedString(@"Save and Connect", nil) : NSLocalizedString(@"Connect Once", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            MUConnectionController *controller = weakSelf;
            NSString *password = [weakAlert.textFields.firstObject.text copy];
            if (!controller || attempt != controller->_connectionAttempt || !password.length) return;
            controller->_password = password;
            controller->_savePasswordOnJoin = save.boolValue;
            controller->_rejectAlertCtrl = nil;
            [controller establishConnection];
            [controller showConnectingView];
        }];
        connect.enabled = NO;
        [alert addAction:connect];
    }
    return alert;
}

- (void)rejectionPasswordChanged:(UITextField *)field {
    if (field != _rejectAlertCtrl.textFields.firstObject) return;
    for (UIAlertAction *action in _rejectAlertCtrl.actions) {
        if (action.style != UIAlertActionStyleCancel) action.enabled = field.text.length > 0;
    }
}

- (void) connection:(MLConnection *)conn rejectedWithReason:(MLRejectReason)reason explanation:(NSString *)explanation {
    if (conn != _connection) return;
    NSUInteger attempt = _connectionAttempt;
    _savePasswordOnJoin = NO;
    NSString *title = NSLocalizedString(@"Connection Rejected", nil);
    NSString *msg = nil;
    UIAlertController *alertCtrl = nil;
    
    void (^cancelHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        if (attempt != self->_connectionAttempt) return;
        self->_rejectAlertCtrl = nil;
        // Rejection handler has already handled the teardown for us.
    };
    void (^reconnectHandler)(UIAlertAction * _Nonnull action) = ^(UIAlertAction * _Nonnull action) {
        if (attempt != self->_connectionAttempt) return;
        self->_username = [self->_rejectAlertCtrl.textFields.firstObject.text copy];

        self->_rejectAlertCtrl = nil;
        [self establishConnection];
        [self showConnectingView];
    };
    void (^usernameConfigHandler)(UITextField * _Nonnull textField) = ^(UITextField * _Nonnull textField) {
        [textField setText:self->_username];
    };
    [self teardownConnection];
    
    switch (reason) {
        case MLRejectReasonAuthenticatorFailure:
            msg = explanation.length ? explanation : NSLocalizedString(@"Authentication failed", nil);
            alertCtrl = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
            [alertCtrl addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:cancelHandler]];
            break;
        case MLRejectReasonNone:
            msg = NSLocalizedString(@"No reason", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            break;
        case MLRejectReasonWrongVersion:
            msg = NSLocalizedString(@"Client/server version mismatch", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            break;
        case MLRejectReasonInvalidUsername:
            msg = NSLocalizedString(@"Invalid username", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addTextFieldWithConfigurationHandler:usernameConfigHandler];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Reconnect", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:reconnectHandler]];
            break;
        case MLRejectReasonWrongUserPassword:
        case MLRejectReasonWrongServerPassword:
            alertCtrl = [self passwordAlertForReason:reason attempt:attempt];
            break;
        case MLRejectReasonUsernameInUse:
            msg = NSLocalizedString(@"Username already in use", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addTextFieldWithConfigurationHandler:usernameConfigHandler];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"Reconnect", nil)
                                                           style:UIAlertActionStyleDefault
                                                         handler:reconnectHandler]];
            break;
        case MLRejectReasonServerIsFull:
            msg = NSLocalizedString(@"Server is full", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            break;
        case MLRejectReasonNoCertificate:
            msg = NSLocalizedString(@"A certificate is needed to connect to this server", nil);
            
            alertCtrl = [UIAlertController alertControllerWithTitle:title
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
            
            [alertCtrl addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleCancel
                                                         handler:cancelHandler]];
            break;
    }

    _rejectAlertCtrl = alertCtrl;

    [self hideConnectingViewWithCompletion:^{
        [self presentConnectionAlert:alertCtrl forAttempt:attempt];
    }];
}

#pragma mark - MLServerModelDelegate

- (void) serverModel:(MLServerModel *)model joinedServerAsUser:(MLUser *)user {
    if (model != _serverModel) return;
    if (_savePasswordOnJoin && _password.length) {
        if (_favouritePrimaryKey >= 0) {
            [MUDatabase storePassword:_password forFavouriteWithPrimaryKey:_favouritePrimaryKey];
        } else {
            MUFavouriteServer *favourite = [[MUFavouriteServer alloc] initWithDisplayName:_hostname hostName:_hostname port:_port userName:user.userName password:_password];
            [MUDatabase storeFavourite:favourite];
        }
    }
    _savePasswordOnJoin = NO;
    [MUDatabase storeUsername:[user userName] forServerWithHostname:[model hostname] port:[model port]];

    [self hideConnectingViewWithCompletion:^{
        [self->_serverRoot takeOwnershipOfConnectionDelegate];

        self->_username = nil;
        self->_hostname = nil;
        self->_password = nil;
        
        self->_serverRoot.modalPresentationStyle = UIModalPresentationFullScreen;
        [[self->_parentViewController navigationController] presentViewController:self->_serverRoot animated:YES completion:nil];
        self->_parentViewController = nil;
    }];
}

- (void) serverCertificateTrustViewControllerDidDismiss:(MUServerCertificateTrustViewController *)trustView {
    [self showConnectingView];
    [_connection reconnect];
}

@end
