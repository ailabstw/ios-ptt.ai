//
//  SessionChannel.h
//  pttai
//
//  Created by Zick on 11/1/18.
//  Copyright © 2018 AILabs. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SCErrorCode) {
    kSCSucceed = 0,

    kSCErrorUnknown = -1,

    kSCErrorGeneric = -2,

    kSCErrorConnectSocketInit = -10,
    kSCErrorServerAddress = -11,
    kSCErrorConnect = -12,
    kSCErrorSessionInit = -13,
    kSCErrorSessionHandshake = -14,
    kSCErrorUsernamePassword = -15,
    kSCErrorListenSocketInit = -16,
    kSCErrorLocalIP = -17,
    kSCErrorBind = -18,
    kSCErrorListen = -19,
};

@interface SessionChannel : NSObject
- (SCErrorCode)loginServer:(NSString *)server username:(NSString *)username password:(NSString *)password;
- (SCErrorCode)directTCPIPport:(unsigned int)lport rhost:(NSString *)rhost rport:(unsigned int)rport priority:(int)priority;
- (void)startForwarding;
@end
