//
//  AppUtil.h
//  pttai
//
//  Created by Zick on 10/31/18.
//  Copyright © 2018 AILabs. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define UD_LOGIN_SERVER         (@"ud_login_server")
#define UD_LOGIN_USERNAME       (@"ud_login_username")
#define UD_LOGIN_PASSWORD       (@"ud_login_password")
#define UD_LOGIN_INTERNAL_HTTP  (@"ud_login_internal_http")
#define UD_LOGIN_INTERNAL_API   (@"ud_login_internal_api")
#define UD_LOGIN_EXTERNAL_HTTP  (@"ud_login_external_http")
#define UD_LOGIN_EXTERNAL_API   (@"ud_login_external_api")

@interface AU : NSObject

+ (void)udInit;

@end

NS_ASSUME_NONNULL_END
