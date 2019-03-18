//
//  ViewController.m
//  pttai
//
//  Created by Zick on 10/24/18.
//  Copyright © 2018 AILabs. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "AppUtil.h"
#import "SessionChannel.h"

@import WebKit;

@interface ViewController () <WKNavigationDelegate, UIWebViewDelegate, AVCaptureMetadataOutputObjectsDelegate>
@property (weak, nonatomic) IBOutlet UIView *webViewContainer;
@property (atomic) WKWebView *webView;

@property (weak, nonatomic) IBOutlet UIView *viewLogin;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UITextField *textFieldServer;
@property (weak, nonatomic) IBOutlet UITextField *textFieldUsername;
@property (weak, nonatomic) IBOutlet UITextField *textFieldPassword;
@property (weak, nonatomic) IBOutlet UITextField *textFieldInternalHTTP;
@property (weak, nonatomic) IBOutlet UITextField *textFieldInternalAPI;
@property (weak, nonatomic) IBOutlet UITextField *textFieldExternalHTTP;
@property (weak, nonatomic) IBOutlet UITextField *textFieldExternalAPI;
@property (weak, nonatomic) IBOutlet UIButton *buttonOptionDetail;
@property (weak, nonatomic) IBOutlet UIButton *buttonLogin;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *constraintScrollViewB;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *constraintContentViewH;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *constraintButtonLoginT;
- (IBAction)didPressOptionDetail:(id)sender;
- (IBAction)didPressLogin:(id)sender;

@property (weak, nonatomic) IBOutlet UIView *viewCamera;
@property (weak, nonatomic) IBOutlet UIView *viewPreview;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *constraintCameraTop;
- (IBAction)startStopReading;
- (BOOL)startReading;
- (void)stopReading;

@property SessionChannel *sc;
@property NSURLRequest *urlRequest;
@property BOOL bUDFetched;
@property BOOL bOptionDetail;

@property (nonatomic, strong) NSString *qrcode;
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;

@end



@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view, typically from a nib.
    self.webViewContainer.hidden = YES;
    self.viewLogin.hidden = NO;
    self.viewCamera.hidden = YES;
    self.constraintCameraTop.constant = 0.0;

    self.buttonOptionDetail.layer.cornerRadius = 4.0;
    self.buttonLogin.layer.cornerRadius = 4.0;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    [self updateUI];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (self.bUDFetched) {
        return;
    }

    self.bUDFetched = YES;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *strServer = [ud stringForKey:UD_LOGIN_SERVER];
    NSString *strUsername = [ud stringForKey:UD_LOGIN_USERNAME];
    NSString *strPassword = [ud stringForKey:UD_LOGIN_PASSWORD];
    id objInternalHTTP = [ud objectForKey:UD_LOGIN_INTERNAL_HTTP];
    id objInternalAPI = [ud objectForKey:UD_LOGIN_INTERNAL_API];
    id objExternalHTTP = [ud objectForKey:UD_LOGIN_EXTERNAL_HTTP];
    id objExternalAPI = [ud objectForKey:UD_LOGIN_EXTERNAL_API];

    self.textFieldServer.text = strServer;
    self.textFieldUsername.text = strUsername;
    self.textFieldPassword.text = strPassword;
    self.textFieldInternalHTTP.text = [objInternalHTTP stringValue];
    self.textFieldInternalAPI.text = [objInternalAPI stringValue];
    self.textFieldExternalHTTP.text = [objExternalHTTP stringValue];
    self.textFieldExternalAPI.text = [objExternalAPI stringValue];
}

- (IBAction)didPressOptionDetail:(id)sender {
    self.bOptionDetail = !self.bOptionDetail;
    [self updateUI];
}

- (IBAction)didPressLogin:(id)sender {
    [self.view endEditing:YES];

    NSString *strServer = self.textFieldServer.text;
    NSString *strUsername = self.textFieldUsername.text;
    NSString *strPassword = self.textFieldPassword.text;
    NSInteger intInternalHTTP = [self.textFieldInternalHTTP.text integerValue];
    NSInteger intInternalAPI = [self.textFieldInternalAPI.text integerValue];
    NSInteger intExternalHTTP = [self.textFieldExternalHTTP.text integerValue];
    NSInteger intExternalAPI = [self.textFieldExternalAPI.text integerValue];

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:strServer forKey:UD_LOGIN_SERVER];
    [ud setObject:strUsername forKey:UD_LOGIN_USERNAME];
//    [ud setObject:strPassword forKey:UD_LOGIN_PASSWORD];
    [ud setInteger:intInternalHTTP forKey:UD_LOGIN_INTERNAL_HTTP];
    [ud setInteger:intInternalAPI forKey:UD_LOGIN_INTERNAL_API];
    [ud setInteger:intExternalHTTP forKey:UD_LOGIN_EXTERNAL_HTTP];
    [ud setInteger:intExternalAPI forKey:UD_LOGIN_EXTERNAL_API];

    BOOL bSuccess = NO;
    NSMutableString *msg = [NSMutableString stringWithString:@""];
    do {
        self.sc = [[SessionChannel alloc] init];
        SCErrorCode code = kSCErrorUnknown;

        [msg appendFormat:@"SSH login ---- "];
        code = [self.sc loginServer:strServer username:strUsername password:strPassword];
        if (code != kSCSucceed) {
            [msg appendFormat:@"%ld", code];
            break;
        }
        [msg appendFormat:@"OK"];

        [msg appendFormat:@"    %ld : localhost : %ld ---- ", intExternalHTTP, intInternalHTTP];
        code = [self.sc directTCPIPport:(unsigned int)intExternalHTTP rhost:@"localhost" rport:(unsigned int)intInternalHTTP priority:1];
        if (code != kSCSucceed) {
            [msg appendFormat:@"%ld", code];
            break;
        }
        [msg appendString:@"OK"];

        [msg appendFormat:@"    %ld : localhost : %ld ---- ", intExternalAPI, intInternalAPI];
        code = [self.sc directTCPIPport:(unsigned int)intExternalAPI rhost:@"localhost" rport:(unsigned int)intInternalAPI priority:0];
        if (code != kSCSucceed) {
            [msg appendFormat:@"%ld", code];
            break;
        }
        [msg appendString:@"OK"];

        [self.sc startForwarding];
        bSuccess = YES;
    } while(NO);  // do it once only

    NSLog(@"%@", msg);

    if (!bSuccess) {
        return;
    }

    self.viewLogin.hidden = YES;
    self.webViewContainer.hidden = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];

    NSLog(@"==== start load url to Webview ====");
    self.urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%ld", intExternalHTTP]]];

    // remove WebView, cache
    NSSet *websiteDataTypes = [NSSet setWithArray:@[WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]];
    NSDate *dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes modifiedSince:dateFrom completionHandler:^{
    }];

    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:self.urlRequest];

    WKPreferences *pref = [[WKPreferences alloc] init];
    pref.javaScriptEnabled = YES;
    WKWebViewConfiguration *conf = [[WKWebViewConfiguration alloc] init];
    conf.preferences = pref;

    // make sure, get self.webViewContainer.bounds after viewDidLayoutSubviews
    self.webView = [[WKWebView alloc] initWithFrame:self.webViewContainer.bounds configuration:conf];
    self.webView.navigationDelegate = self;
    [self.webView loadRequest:self.urlRequest];
    [self.webViewContainer addSubview:self.webView];
}

- (void)updateUI {
    self.constraintButtonLoginT.constant = (self.bOptionDetail ? 288.0 : 32.0);
    self.constraintContentViewH.constant = (self.bOptionDetail ? 948.0 : 692.0);
    [self.textFieldInternalHTTP setHidden:!self.bOptionDetail];
    [self.textFieldInternalAPI setHidden:!self.bOptionDetail];
    [self.textFieldExternalHTTP setHidden:!self.bOptionDetail];
    [self.textFieldExternalAPI setHidden:!self.bOptionDetail];
    [self.buttonOptionDetail setImage:[UIImage imageNamed:(self.bOptionDetail ? @"iconUp" : @"iconDown")] forState:UIControlStateNormal];

    if (self.bUDFetched) {
        [UIView animateWithDuration:0.3 animations:^{
            [self.view layoutIfNeeded];
        }];
    }
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        self.constraintScrollViewB.constant = keyboardSize.height;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [UIView animateWithDuration:0.3 animations:^{
        self.constraintScrollViewB.constant = 0.0;
    }];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *URL = navigationAction.request.URL;
    NSString *scheme = [URL scheme];

    if ([scheme isEqualToString:@"opencamera"]) {
        NSLog(@"OPEN CAMERA");
        [self startStopReading];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

// when [self startStopReading], we could turn camera on & off.
// remember to setup view preview in ViewController

- (IBAction)startStopReading {
    if (self.viewCamera.hidden) {
        self.viewCamera.hidden = NO;

        if ([self startReading]) {
        }
    } else{
        self.viewCamera.hidden = YES;

        [self stopReading];
    }
}

- (BOOL)startReading {
    self.qrcode = nil;

    NSError *error = nil;
    AVCaptureDevice *captureDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&error];
    if (!input) {
        NSLog(@"%@", [error localizedDescription]);
        return NO;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    if (![session canAddInput:input]) {
        NSLog(@"fail to add input");
        return NO;
    }
    [session addInput:input];

    AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if (![session canAddOutput:captureMetadataOutput]) {
        NSLog(@"fail to add output");
        return NO;
    }
    [session addOutput:captureMetadataOutput];

    dispatch_queue_t dispatchQueue = dispatch_queue_create("myQueue", NULL);
    [captureMetadataOutput setMetadataObjectsDelegate:self queue:dispatchQueue];
    [captureMetadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:AVMetadataObjectTypeQRCode]];

    self.videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
    [self.videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [self.videoPreviewLayer setFrame:self.viewPreview.layer.bounds];
    [self.viewPreview.layer addSublayer:self.videoPreviewLayer];

    self.captureSession = session;
    [self.captureSession startRunning];

    return YES;
}

- (void)stopReading {
    NSLog(@"stopReading");
    [self.captureSession stopRunning];
    self.captureSession = nil;

    [self.videoPreviewLayer removeFromSuperlayer];
    self.videoPreviewLayer = nil;

    [self returnValueToWebView];
}

- (void)returnValueToWebView {
    @synchronized (self.qrcode) {
        NSString *javascript = [NSString stringWithFormat:@"getQRCode('%@')", self.qrcode];
        // NSLog(@"js: %@", javascript);
        [self.webView evaluateJavaScript:javascript completionHandler:^(NSString *result, NSError *error) {
            if (error != nil) {
                NSLog(@"eval JavaScript, Error: %@",error);
                return;
            }

            NSLog(@"eval JavaScript, Success");
        }];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    // Check if the metadataObjects array is not nil and it contains at least one object.
    if (metadataObjects != nil && [metadataObjects count] > 0) {
        // Get the metadata object.
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects objectAtIndex:0];
        if ([[metadataObj type] isEqualToString:AVMetadataObjectTypeQRCode]) {
            @synchronized (self.qrcode) {
                self.qrcode = [metadataObj stringValue];
            }
            [self performSelectorOnMainThread:@selector(startStopReading) withObject:nil waitUntilDone:NO];
        }
    }
}

@end
