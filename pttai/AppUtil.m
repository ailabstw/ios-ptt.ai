//
//  AppUtil.m
//  pttai
//
//  Created by Zick on 10/31/18.
//  Copyright © 2018 AILabs. All rights reserved.
//

#import "AppUtil.h"

@implementation AU

+ (void)udInit {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];

    [dict setObject:[NSNumber numberWithInteger:9774] forKey:UD_LOGIN_INTERNAL_HTTP];
    [dict setObject:[NSNumber numberWithInteger:14779] forKey:UD_LOGIN_INTERNAL_API];
    [dict setObject:[NSNumber numberWithInteger:9774] forKey:UD_LOGIN_EXTERNAL_HTTP];
    [dict setObject:[NSNumber numberWithInteger:14779] forKey:UD_LOGIN_EXTERNAL_API];

    [ud registerDefaults:dict];
}

@end
