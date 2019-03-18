//
//  SessionChannel.m
//  pttai
//
//  Created by Zick on 11/1/18.
//  Copyright © 2018 AILabs. All rights reserved.
//

#import "SessionChannel.h"

#include <libssh2.h>

#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/time.h>

#ifndef INADDR_NONE
#define INADDR_NONE (in_addr_t)-1
#endif

enum {
    AUTH_NONE = 0,
    AUTH_PASSWORD,
    AUTH_PUBLICKEY
};

const int BUFFER_SIZE = 16384;

// FIXME, implement it
@interface BufferInfo : NSObject
@property (atomic) long headerLength;
@property (atomic) long contentLength;
@property (atomic) NSString *contentType;
@property (atomic) long expectedLength; // if valid, expectedLength == headerLength + contentLength
@property (atomic) long posJSOStart; // start of JSon object
@end

@interface DirectTCPIP : NSObject
@property (atomic) LIBSSH2_CHANNEL *channel;
@property (atomic) unsigned int lport;
@property (atomic) char *rhost;
@property (atomic) unsigned int rport;
@property (atomic) int priority; // FIXME, need it?
@end

@implementation DirectTCPIP

- (id)init {
    self = [super init];
    if (self) {
        self.channel = NULL;
        self.lport = 0;
        self.rhost = NULL;
        self.rport = 0;
        self.priority = -1; // the priority of 1, is higher than the priority of 0
    }
    return self;
}

- (void)dealloc {
    if (self.rhost) {
        free(self.rhost);
    }
}

@end



@interface SessionChannel ()

@property (atomic) LIBSSH2_SESSION *session;
@property (atomic) SCErrorCode codeSetup;
@property (atomic) SCErrorCode codeListen;
@property dispatch_semaphore_t smpSetup;
@property dispatch_semaphore_t smpListen;
@property dispatch_semaphore_t smpForward;

@property (atomic) NSOperationQueue *queue;

@property (atomic) NSMutableArray<NSNumber *> *forwards;
@property (atomic) NSMutableArray<DirectTCPIP *> *directs;
@property (atomic) NSMutableDictionary<NSNumber *, DirectTCPIP *> *dictDirectTCPIP; // forwardsock -> DirectTCPIP

@end

@implementation SessionChannel

- (id)init {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        int rc = libssh2_init(0);
        if (rc != 0) {
            NSLog(@"libssh2 initialization failed (%d)\n", rc);
        }
    });

    self = [super init];
    if (self) {
        self.session = NULL;
        self.codeSetup = kSCErrorUnknown;
        self.codeListen = kSCErrorUnknown;
        self.smpSetup = dispatch_semaphore_create(0);
        self.smpListen = dispatch_semaphore_create(0);
        self.smpForward = dispatch_semaphore_create(1);

        self.queue = [[NSOperationQueue alloc] init];

        dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
        self.forwards = [[NSMutableArray alloc] init];
        self.directs = [[NSMutableArray alloc] init];
        self.dictDirectTCPIP = [[NSMutableDictionary alloc] init];
        dispatch_semaphore_signal(self.smpForward);
    }

    return self;
}

- (SCErrorCode)loginServer:(NSString *)server username:(NSString *)username password:(NSString *)password {
    [self.queue addOperation:[self opLoginServer:[server cStringUsingEncoding:NSASCIIStringEncoding]
                                        username:[username cStringUsingEncoding:NSASCIIStringEncoding]
                                        password:[password cStringUsingEncoding:NSASCIIStringEncoding]]];
     dispatch_semaphore_wait(self.smpSetup, DISPATCH_TIME_FOREVER);

     return self.codeSetup;
}

- (SCErrorCode)directTCPIPport:(unsigned int)lport rhost:(NSString *)rhost rport:(unsigned int)rport priority:(int)priority {
    DirectTCPIP *direct = [[DirectTCPIP alloc] init];
    const char *carrRHost = [rhost cStringUsingEncoding:NSASCIIStringEncoding];
    direct.lport = lport;
    direct.rhost = malloc(strlen(carrRHost) + 1);
    memcpy(direct.rhost, carrRHost, strlen(carrRHost));
    direct.rhost[strlen(carrRHost)] = '\0';
    direct.rport = rport;
    direct.priority = priority;

    dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
    [self.directs addObject:direct];
    dispatch_semaphore_signal(self.smpForward);

    [self.queue addOperation:[self opListenPort:lport]];
    dispatch_semaphore_wait(self.smpListen, DISPATCH_TIME_FOREVER);
    self.queue.maxConcurrentOperationCount = [self.directs count] + 2; // 1: session    n: listen    1: forward

    return self.codeListen;
}

- (void)startForwarding {
    // only one
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [self.queue addOperation:[self opForward]];
    });
}

- (NSBlockOperation *)opLoginServer:(const char *)server
                           username:(const char *)username
                           password:(const char *)password {
    return [NSBlockOperation blockOperationWithBlock:^{
        @autoreleasepool {
            int rc, auth = AUTH_NONE;
            int sock = -1;
            struct sockaddr_in sin;
            const char *keyfile1 = "/home/username/.ssh/id_rsa.pub"; // TODO
            const char *keyfile2 = "/home/username/.ssh/id_rsa"; // TODO
            SCErrorCode code = kSCErrorUnknown;

            do {
                sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
                if (sock == -1) {
                    perror("socket");
                    code = kSCErrorConnectSocketInit;
                    break;
                }

                sin.sin_family = AF_INET;       // TODO, IPv4 or IPv6, domain name
                if (INADDR_NONE == (sin.sin_addr.s_addr = inet_addr(server))) {
                    perror("inet_addr");
                    code = kSCErrorServerAddress;
                    break;
                }
                sin.sin_port = htons(22);
                if (connect(sock, (struct sockaddr*)(&sin), sizeof(struct sockaddr_in)) != 0) {
                    // FIXME, might be blocked. Ex. connect to 10.1.1.145, but the SSH server on that machine is not turned on.
                    NSLog(@"failed to connect!\n");
                    code = kSCErrorConnect;
                    break;
                }

                /* Create a session instance */
                self.session = libssh2_session_init();
                if (!self.session) {
                    NSLog(@"Could not initialize SSH session!\n");
                    code = kSCErrorSessionInit;
                    break;
                }

                // start it up. This will trade welcome banners, exchange keys, and setup crypto, compression, and MAC layers
                rc = libssh2_session_handshake(self.session, sock);
                if (rc) {
                    NSLog(@"Error when starting up SSH session: %d\n", rc);
                    code = kSCErrorSessionHandshake;
                    break;
                }

                /* At this point we havn't yet authenticated.  The first thing to do
                 * is check the hostkey's fingerprint against our known hosts Your app
                 * may have it hard coded, may go to a file, may present it to the
                 * user, that's your call
                 */
                const char *fingerprint = libssh2_hostkey_hash(self.session, LIBSSH2_HOSTKEY_HASH_SHA1);
                NSMutableString *msgFingerprint = [NSMutableString stringWithString:@"Fingerprint: "];
                for (int i = 0; i < 20; ++i) {
                    [msgFingerprint appendFormat:@"%02X ", (unsigned char)fingerprint[i]];
                }
                [msgFingerprint appendString:@"\n"];
                NSLog(@"%@", msgFingerprint);

                // check what authentication methods are available
                char *userauthlist = libssh2_userauth_list(self.session, username, (unsigned int)strlen(username));
                NSLog(@"Authentication methods: %s\n", userauthlist);
                if (strstr(userauthlist, "password")) {
                    auth |= AUTH_PASSWORD;
                }
                if (strstr(userauthlist, "publickey")) {
                    auth |= AUTH_PUBLICKEY;
                }

                if (auth & AUTH_PASSWORD) {
                    if (libssh2_userauth_password(self.session, username, password)) {
                        NSLog(@"Authentication by password failed.\n");
                        code = kSCErrorUsernamePassword;
                        break;
                    }
                } else if (auth & AUTH_PUBLICKEY) {
                    if (libssh2_userauth_publickey_fromfile(self.session, username, keyfile1, keyfile2, password)) {
                        NSLog(@"Authentication by public key failed!\n");
                        code = kSCErrorUsernamePassword;
                        break;
                    }
                    NSLog(@"Authentication by public key succeeded.\n");
                } else {
                    NSLog(@"No supported authentication methods found!\n");
                    code = kSCErrorUsernamePassword;
                    break;
                }

                libssh2_session_set_blocking(self.session, 1);
                libssh2_session_set_timeout(self.session, 5000);

                code = kSCSucceed;
            } while(NO); // do it once only

            // after the do-while, if fail, close all
            if (code != kSCSucceed) {
                if (sock != -1) {
                    close(sock);
                    sock = -1;
                }

                if (self.session != NULL) {
                    libssh2_session_disconnect(self.session, "Client disconnecting normally");
                    libssh2_session_free(self.session);
                    self.session = NULL;
                }
            }

            // no matter succeed or not, inform that already finish task
            self.codeSetup = code;
            dispatch_semaphore_signal(self.smpSetup);

            if (code == kSCSucceed) {
                [[NSRunLoop currentRunLoop] run]; // FIXME, check it
            }

            NSLog(@"login end"); // FIXME
        }
    }];
}

- (NSBlockOperation *)opListenPort:(unsigned int)lport {
    return [NSBlockOperation blockOperationWithBlock:^{
        @autoreleasepool {
            int sockopt;
            int listensock = -1;
            struct sockaddr_in sin;
            socklen_t sinlen;
            const char *local_ip = "127.0.0.1";
            SCErrorCode code = kSCErrorUnknown;

            do {
                listensock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
                if (listensock == -1) {
                    perror("socket");
                    code = kSCErrorListenSocketInit;
                    break;
                }

                sin.sin_family = AF_INET;
                sin.sin_port = htons(lport);
                if (INADDR_NONE == (sin.sin_addr.s_addr = inet_addr(local_ip))) {
                    perror("inet_addr");
                    code = kSCErrorLocalIP;
                    break;
                }
                sockopt = 1;
                setsockopt(listensock, SOL_SOCKET, SO_REUSEADDR, &sockopt, sizeof(sockopt));
                sinlen = sizeof(sin);
                if (-1 == bind(listensock, (struct sockaddr *)&sin, sinlen)) {
                    perror("bind");
                    code = kSCErrorBind;
                    break;
                }

                if (-1 == listen(listensock, 10)) {
                    perror("listen");
                    code = kSCErrorListen;
                    break;
                }
                NSLog(@"Waiting for TCP connection on %s:%d...\n", inet_ntoa(sin.sin_addr), ntohs(sin.sin_port));

                code = kSCSucceed;
            } while(NO); // do it once only

            // after the do-while, if fail, close all
            if (code != kSCSucceed) {
                if (listensock != -1) {
                    close(listensock);
                    listensock = -1;
                }
            }

            // no matter succeed or not, inform that already finish task
            self.codeListen = code;
            dispatch_semaphore_signal(self.smpListen);

            if (code == kSCSucceed) {
                while(1) {
                    int forwardsock = accept(listensock, (struct sockaddr *)&sin, &sinlen);
                    if (forwardsock == -1) {
                        perror("accept"); // TODO, error handling?
                        continue;
                    }

                    NSLog(@"listen-accept: %d    -> forwardsock: %d", lport, forwardsock);

                    dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                    DirectTCPIP *direct = nil;
                    for (DirectTCPIP *check in self.directs) {
                        if (check.lport == lport) {
                            direct = check;
                            break;
                        }
                    }
                    if (!direct) {
                        NSLog(@"can not find a valid DirectTCPIP");
                    } else {
                        NSNumber *number = [NSNumber numberWithInt:forwardsock];
                        [self.forwards addObject:number];
                        [self.dictDirectTCPIP setObject:direct forKey:number];
                    }
                    dispatch_semaphore_signal(self.smpForward);
                }
            }
        }
    }];
}

- (NSBlockOperation *)opForward {
    return [NSBlockOperation blockOperationWithBlock:^{
        @autoreleasepool {
            fd_set fds;
            struct timeval tv;
            int maxFS, rc;
            int currentsock = -1;
            LIBSSH2_CHANNEL *channel;
            char *rhost;
            unsigned int rport;
            ssize_t lenRecv, lenSend, len, wr, i;
            char bufRecv[BUFFER_SIZE];
            char bufSend[BUFFER_SIZE];

            while (1) {
                FD_ZERO(&fds);
                tv.tv_sec = 0;
                tv.tv_usec = 100000;
                maxFS = -1;
                currentsock = -1;
                channel = NULL;
                rhost = NULL;
                rport = 0;

                dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                for (NSNumber *number in self.forwards) {
                    int forwardsock = [number intValue];
                    FD_SET(forwardsock, &fds);
                    if (maxFS < forwardsock) {
                        maxFS = forwardsock;
                    }
                }
                dispatch_semaphore_signal(self.smpForward);

                if (maxFS == -1) {
                    sleep(1);   // FIXME, check handling, maxFS ==- -1; ?
                    continue;
                }

                rc = select(maxFS + 1, &fds, NULL, NULL, &tv);
                if (-1 == rc) {
                    perror("select");
                    continue;    // TODO, error handling?
                } else {
                    // NSLog(@"rc: %d **********************************", rc); // FIXME, delegate, report
                }

                if (rc) {
                    dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                    for (NSNumber *number in self.forwards) {
                        int forwardsock = [number intValue];
                        if (FD_ISSET(forwardsock, &fds)) {
                            currentsock = forwardsock;
                            break;
                        }
                    }
                    DirectTCPIP *direct = [self.dictDirectTCPIP objectForKey:[NSNumber numberWithInt:currentsock]];
                    if (direct) {
                        channel = direct.channel;
                        rhost = direct.rhost;
                        rport = direct.rport;
                    }
                    dispatch_semaphore_signal(self.smpForward);
                }

                if (currentsock == -1) {
                    continue;
                }

                len = recv(currentsock, bufRecv, sizeof(bufRecv), 0);
                if (len < 0) {
                    perror("read");
                    continue;    // TODO, error handling?
                }

                lenRecv = len;
                int errorflag = 0; // bool, yes or no
                if (len > 0) {
                    do {
                        FD_ZERO(&fds);
                        FD_SET(currentsock, &fds);
                        tv.tv_sec = 0;
                        tv.tv_usec = 100000;    // FIXME, if content-length valid, and has to read more => set bigger time val.
                        rc = select(currentsock + 1, &fds, NULL, NULL, &tv);
                        if (-1 == rc) {
                            perror("select");
                            errorflag = 1;
                            break; // error
                        }
                        if (rc == 0) {
                            break; // no need to recv more
                        }

                        if (rc && FD_ISSET(currentsock, &fds)) {
                            len = recv(currentsock, bufRecv + lenRecv, sizeof(bufRecv) - lenRecv, 0);
                            if (len <= 0) {
                                perror("read");
                                errorflag = 1;
                                break;
                            }
                            lenRecv += len;
                            if (lenRecv > sizeof(bufRecv)) {
                                // FIXME, maybe larger then the size of bufRecv
                                assert(0);
                            }
                        }
                    } while(1);

                    if (errorflag) {
                        continue;   // try keep get data, but fail
                    }
                }

                dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                if (lenRecv == 0) {
                    NSNumber *number = [NSNumber numberWithInt:currentsock];
                    [self.forwards removeObject:number];
                    [self.dictDirectTCPIP removeObjectForKey:number];
                } else {
                    // carousel implementation
                    [self.forwards sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                        if (![obj1 isKindOfClass:[NSNumber class]] || ![obj2 isKindOfClass:[NSNumber class]]) {
                            return NSOrderedSame;
                        }

                        NSNumber *number1 = (NSNumber *)obj1;
                        NSNumber *number2 = (NSNumber *)obj2;
                        DirectTCPIP *direct1 = [self.dictDirectTCPIP objectForKey:number1];
                        DirectTCPIP *direct2 = [self.dictDirectTCPIP objectForKey:number2];
                        if (!direct1 || !direct2) {
                            return NSOrderedSame;
                        }

                        int priority1 = direct1.priority;
                        int priority2 = direct2.priority;
                        if (priority1 != priority2) {
                            return (priority1 > priority2 ? NSOrderedAscending : NSOrderedDescending);
                        }

                        BOOL handled1 = ([obj1 intValue] == currentsock);
                        BOOL handled2 = ([obj2 intValue] == currentsock);
                        if (handled1 != handled2) {
                            return (handled2 ? NSOrderedAscending : NSOrderedDescending);
                        }

                        return NSOrderedSame;
                    }];
                }
                dispatch_semaphore_signal(self.smpForward);

                if (0 == lenRecv) {
                    NSLog(@"The client, currentsock: %d, disconnected!", currentsock);
                    close(currentsock);
                    continue; // the client close the connection, thus do nothing in this iteration
                }

                if (!channel) {
                    const char *shost = "127.0.0.1";
                    NSLog(@"Forwarding connection from %s:%d here to remote %s:%d\n", shost, rport, rhost, rport);
                    channel = libssh2_channel_direct_tcpip_ex(self.session, rhost, rport, shost, rport);
                    if (!channel) {
                        NSLog(@"Could not open the direct-tcpip channel!    (Note that this can be a problem at the server!    Please review the server logs.)\n");
                        continue;    // TODO, error handling?
                    } else {
                        dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                        DirectTCPIP *direct = [self.dictDirectTCPIP objectForKey:[NSNumber numberWithInt:currentsock]];
                        if (direct) {
                            direct.channel = channel;
                        }
                        dispatch_semaphore_signal(self.smpForward);
                    }
                }

                wr = 0;
                errorflag = 0; // bool, yes or no
                while(wr < lenRecv) {
                    i = libssh2_channel_write(channel, bufRecv + wr, lenRecv - wr);
                    if (LIBSSH2_ERROR_EAGAIN == i) {
                        continue;
                    }
                    if (i < 0) {
                        NSLog(@"libssh2_channel_write: %ld\n", i);
                        errorflag = 1;    // TODO, error handling?
                        break;
                    }
                    wr += i;
                }
                if (errorflag) {
                    continue;
                }

                int first = 1;
                ssize_t expectedLength = -1;
                ssize_t totallen = 0;

                while (1) {
                    lenSend = libssh2_channel_read(channel, bufSend, sizeof(bufSend));
                    if (LIBSSH2_ERROR_EAGAIN == lenSend) {
                        break;
                    } else if (LIBSSH2_ERROR_TIMEOUT == lenSend) {
                        [self printInfo:[NSString stringWithFormat:@"timeout: %ld   first?: %@    expectedLength = %ld",
                                         libssh2_session_get_timeout(self.session),
                                         (first ? @"YES" : @"NO"),
                                         expectedLength]
                                    buf:bufRecv
                                    len:lenRecv];
                        break;
                    } else if (lenSend < 0) {
                        NSLog(@"libssh2_channel_read: %d", (int)lenSend);
                        continue;    // TODO, error handling?
                    }

                    if (first) {
                        first = 0;
                        if (lenSend > 0) {
                            expectedLength = [self expectedLengthWithBuf:bufSend len:lenSend];
                        }
                    }

                    wr = 0;
                    errorflag = 0;
                    while (wr < lenSend) {
                        i = send(currentsock, bufSend + wr, lenSend - wr, 0);
                        if (i <= 0) {
                            perror("write");
                            errorflag = 1;    // TODO, error handling?
                            break;
                        }
                        wr += i;
                    }
                    if (errorflag) {
                        break;
                    }

                    if (expectedLength > 0) {
                        totallen += lenSend;
                        if (expectedLength <= totallen) {
                            break;
                        }
                    } else {
                        if (lenSend < BUFFER_SIZE) { // maybe it is the last one, FIXME, not accurate
                            int breakIter = 0;
                            if (lenSend > 7) {
                                char output[8];
                                memcpy(output, bufSend + lenSend - 7, 7);
                                output[7] = '\0';
                                // NSLog(@"tail: %s", output);
                                if (memcmp(output, "\r\n0\r\n\r\n", 7) == 0) {
                                    breakIter = 1;
                                }
                            }
                            if (breakIter) {
                                break;
                            } else {
                                [self printInfo:@"maybe the last one" buf:bufSend len:lenSend];
                            }
                        }
                    }

                    if (libssh2_channel_eof(channel)) {
                        NSLog(@"The server at %s:%d disconnected! --------------------------------------------------------------------------\n", rhost, rport);
                        if (channel) {
                            libssh2_channel_free(channel);
                            channel = NULL;
                        }

                        dispatch_semaphore_wait(self.smpForward, DISPATCH_TIME_FOREVER);
                        DirectTCPIP *direct = [self.dictDirectTCPIP objectForKey:[NSNumber numberWithInt:currentsock]];
                        if (direct) {
                            direct.channel = NULL;
                        }
                        dispatch_semaphore_signal(self.smpForward);

                        // break it, next iter will setup direct tcpip
                        break;
                    }
                }
            }
        }
    }];
}

- (ssize_t)expectedLengthWithBuf:(char *)buf len:(ssize_t)len {
    char check[BUFFER_SIZE];
    ssize_t checklen = MIN(len, BUFFER_SIZE - 1);
    memcpy(check, buf, checklen);
    check[checklen] = '\0';

    ssize_t result = -1;

    do {
        const char *headerEndCode = "\r\n\r\n";
        char *hEnd = strstr(check, headerEndCode);
        if (hEnd == NULL) {
            break; // can not find end of header
        }

        const char *clBeginCode = "Content-Length:";
        char *clBegin = strstr(check, clBeginCode);
        if (clBegin == NULL) {
            break; // can not find begin of content length;
        }
        if (clBegin - check >= hEnd - check) {
            break; // actually, not in the header
        }
        clBegin += strlen(clBeginCode);

        const char *clEndCode = "\r\n";
        char *clEnd = strstr(clBegin, clEndCode);
        if (clEnd == NULL) {
            break; // can not find end of content length;
        }

        char clNumber[32];
        if (clEnd - clBegin >= 31) {
            break;
        }

        strncpy(clNumber, clBegin, clEnd - clBegin);
        clNumber[clEnd - clBegin] = '\0';

        ssize_t contentLength = atol(clNumber);
        result = contentLength + (hEnd - check + strlen(headerEndCode));
//        NSLog(@"contentLength: %ld    expectedLength: %ld\n", contentLength, result);
    } while(false);

    if (result == -1) {
        // [self printInfo:@"can not get Content-Length" buf:buf len:len]; // FIXME
    }

    return result;
}

- (void)printInfo:(NSString *)info buf:(char *)buf len:(ssize_t)len {
    char output[BUFFER_SIZE];
    ssize_t lenOutput = MIN(len, BUFFER_SIZE - 1);
    memcpy(output, buf, lenOutput);
    output[lenOutput] = '\0';
    NSLog(@"[PrintBuf][Start] %@    len: %ld    buf: \n%s\n[PrintBuf][End]\n", info, len, output);
}

@end
