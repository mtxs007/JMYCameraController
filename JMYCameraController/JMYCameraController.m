//
//  JMYCameraController.m
//  Camera
//
//  Created by lifei on 16/1/4.
//  Copyright © 2016年 mtxs007. All rights reserved.
//

#import "JMYCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import "JMYPreviewView.h"

#define FlashButtonStyle 1

#if FlashButtonStyle
#import "JMYPopView.h"
#import "JMYPopViewCell.h"
#endif

static void * CapturingStillImageContext = &CapturingStillImageContext;
static void * SessionRunningContext = &SessionRunningContext;

typedef NS_ENUM(NSInteger, JMYCameraSetupResult) {
    JMYCameraSetupResultSuccess,
    JMYCameraSetupResultCameraNotAuthorized,
    JMYCameraSetupResultSessionConfigurationFailed,
};

#define JMYCameraSrcName(file) [@"JMYCameraController.bundle" stringByAppendingPathComponent:file]
#ifndef kSCREEN_WIDTH
#define kSCREEN_WIDTH  ([UIScreen mainScreen].bounds.size.width)
#endif
#ifndef kSCREEN_HEIGHT
#define kSCREEN_HEIGHT ([UIScreen mainScreen].bounds.size.height)
#endif
#pragma mark - 系统版本
#ifndef GET_SYSTEM_VERSION
#define GET_SYSTEM_VERSION [[UIDevice currentDevice] systemVersion].floatValue
#endif

@interface JMYCameraController ()
<
UIAlertViewDelegate,
UITableViewDelegate,
UITableViewDataSource
>
// Session management
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (strong, nonatomic) AVCaptureSession *session; // 执行输入设备和输出设备之间的数据传递
@property (strong, nonatomic) AVCaptureDeviceInput *videoDeviceInput; // 输入流
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput; //照片输出流对象
//@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer; // 预览图层，来显示照相机拍摄到的画面
@property (assign, nonatomic) AVCaptureFlashMode flashMode;
@property (strong, nonatomic) JMYPreviewView *previewView; // 放置预览图层的View
// 按钮
@property (strong, nonatomic) UIButton *stillButton;  // 拍照按钮
@property (strong, nonatomic) UIButton *backButton;   // 返回按钮
@property (strong, nonatomic) UIButton *toggleButton; // 切换前后镜头按钮

@property (strong, nonatomic) UIButton *resumeButton; //
@property (strong, nonatomic) UILabel  *cameraUnavailableLabel;

// Utilities.
@property (assign, nonatomic) JMYCameraSetupResult setupResult;
@property (assign, nonatomic, getter=isSessionRunning) BOOL sessionRunning;

#if FlashButtonStyle
@property (strong, nonatomic) JMYPopView *popView;
@property (copy,   nonatomic) NSArray *titles;
@property (assign, nonatomic) BOOL isOpen;
#else
@property (strong, nonatomic) UIButton *flashButton;  // 闪光灯切换按钮
#endif
@end

@implementation JMYCameraController

#pragma mark - Life Cycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Setup UI.
    [self setupUI];

    // Disable UI. The UI is enabled if and only if the session starts running.
    self.stillButton.enabled  = NO;
//    self.backButton.enabled   = NO;
    self.toggleButton.enabled = NO;
    
    // Create the AVCaptureSession.
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    
    // Setup the preview view.
    self.previewView.session = self.session;
    
    // Communicate with the session and other session objects on this queue.
    self.sessionQueue = dispatch_queue_create("session_queue", DISPATCH_QUEUE_SERIAL);
    
    self.setupResult = JMYCameraSetupResultSuccess;
    
    // Check video authorization status. Video access is required and audio access is optional.
    switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]) {
        case AVAuthorizationStatusNotDetermined: {
            dispatch_suspend(self.sessionQueue);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    self.setupResult = JMYCameraSetupResultCameraNotAuthorized;
                }
                dispatch_resume(self.sessionQueue);
            }];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            // The user has previously granted access to the camera.
            break;
        }
        default: {
            self.setupResult = JMYCameraSetupResultCameraNotAuthorized;
            break;
        }
    }
    
    // Setup the capture session.
    // In general it is not safe to mutate an AVCaptureSession or any of its inputs, outputs, or connections from multiple threads at the same time.
    // Why not do all of this on the main queue?
    // Because -[AVCaptureSession startRunning] is a blocking call which can take a long time. We dispatch session setup to the sessionQueue
    // so that the main queue isn't blocked, which keeps the UI responsive.
    dispatch_async(self.sessionQueue, ^{
        if (self.setupResult != JMYCameraSetupResultSuccess) {
            return ;
        }
        
        NSError *error = nil;
        
        AVCaptureDevice *videoDevice = [JMYCameraController deviceWithMediaType:AVMediaTypeVideo preferringPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
        if (!videoDeviceInput) {
            NSLog(@"Could not create video device input: %@", error);
        }
        
        [self.session beginConfiguration];
        
        if ([self.session canAddInput:videoDeviceInput]) {
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
                AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
                if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
                    initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
                }
                
                AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
                previewLayer.connection.videoOrientation = initialVideoOrientation;
                previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            });
        }
        else {
            NSLog(@"Could not add video device input to the session");
            self.setupResult = JMYCameraSetupResultSessionConfigurationFailed;
        }
        
        AVCaptureStillImageOutput *stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if ([self.session canAddOutput:stillImageOutput]) {
            stillImageOutput.outputSettings = @{AVVideoCodecKey : AVVideoCodecJPEG};
            [self.session addOutput:stillImageOutput];
            self.stillImageOutput = stillImageOutput;
        }
        else {
            NSLog(@"Could not add still image output to the session");
            self.setupResult = JMYCameraSetupResultSessionConfigurationFailed;
        }
        
        [self.session commitConfiguration];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    dispatch_async(self.sessionQueue, ^{
        switch (self.setupResult) {
            case JMYCameraSetupResultSuccess: {
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                break;
            }
            case JMYCameraSetupResultCameraNotAuthorized: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 弹窗
                    NSString *message = NSLocalizedString( @"Camera doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                    float systemVersion = GET_SYSTEM_VERSION;
                    if (systemVersion >= 8.0) {
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Camera" message:message preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
                        [alertController addAction:cancelAction];
                        // Provide quick access to Settings.
                        UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Settings",@"Alert button to open Settings") style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                        }];
                        [alertController addAction:settingsAction];
                        [self presentViewController:alertController animated:YES completion:nil];
                    } else {
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Camera", nil)
                                                                        message:message
                                                                       delegate:self
                                                              cancelButtonTitle:NSLocalizedString(@"OK", @"Alert OK button")
                                                              otherButtonTitles:nil];
                        [alert show];
                    }
                });
                break;
            }
            case JMYCameraSetupResultSessionConfigurationFailed: {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 弹窗
                    NSString *message = NSLocalizedString(@"Unable to capture media", @"Alert message when something goes wrong during capture session configuration");
                    float systemVersion = GET_SYSTEM_VERSION;
                    if (systemVersion >= 8.0) {
                        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Camera" message:message preferredStyle:UIAlertControllerStyleAlert];
                        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
                        [alertController addAction:cancelAction];
                        [self presentViewController:alertController animated:YES completion:nil];
                    } else {
                        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Camera", nil)
                                                                        message:message
                                                                       delegate:self
                                                              cancelButtonTitle:NSLocalizedString(@"OK", @"Alert OK button")
                                                              otherButtonTitles:nil];
                        [alert show];
                    }
                });
                break;
            }
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    dispatch_async( self.sessionQueue, ^{
        if ( self.setupResult == JMYCameraSetupResultSuccess ) {
            [self.session stopRunning];
            [self removeObservers];
        }
    } );
    [super viewDidDisappear:animated];
}

// 隐藏状态栏
- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Setup UI

- (void)setupUI {

    self.previewView = [[JMYPreviewView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.previewView];
    
    self.stillButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.stillButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_3")] forState:UIControlStateNormal];
    [self.stillButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_3_sel")] forState:UIControlStateHighlighted];
    [self.stillButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_3_sel")] forState:UIControlStateSelected];
    self.stillButton.frame = CGRectMake(0, 0, 75, 75);
    self.stillButton.center = CGPointMake(kSCREEN_WIDTH / 2, kSCREEN_HEIGHT - 55);
    [self.stillButton addTarget:self action:@selector(snapStillImage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stillButton];
    
    self.backButton   = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeCustom];

    
    [self setupButtonWithButton:self.backButton imageName:@"camera_ic_back" frame:CGRectMake(5, self.view.frame.size.height - 75, 40, 40) action:@selector(backPreviewViewController)];
    [self setupButtonWithButton:self.toggleButton imageName:@"camera_ic_2" frame:CGRectMake(self.view.frame.size.width - 50, 0, 50, 50) action:@selector(changeCamera)];
    
    self.resumeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.resumeButton setTitle:NSLocalizedString(@"Tap to resume", nil) forState:UIControlStateNormal];
    self.resumeButton.frame = CGRectMake(0, 0, 172, 40);
    self.resumeButton.center = self.view.center;
    [self.resumeButton addTarget:self action:@selector(resumeInterruptedSession) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.resumeButton];
    
    self.cameraUnavailableLabel = [[UILabel alloc] init];
    self.cameraUnavailableLabel.text = NSLocalizedString(@"Camera Unavailable", nil);
    self.cameraUnavailableLabel.frame = CGRectMake(0, 0, 215, 30);
    self.cameraUnavailableLabel.textAlignment = NSTextAlignmentCenter;
    self.cameraUnavailableLabel.center = self.view.center;
    [self.view addSubview:self.cameraUnavailableLabel];
    
    // 隐藏
    self.resumeButton.hidden = YES;
    self.cameraUnavailableLabel.hidden = YES;
    
    // 点击对焦
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusAndExposeTap:)];
    [self.previewView addGestureRecognizer:tap];
    
    // 设置闪光灯默认模式
    self.flashMode = AVCaptureFlashModeAuto;
    
    // tableView
#if FlashButtonStyle
    self.titles = @[@"自动", @"强制开", @"强制关"];
    self.isOpen = NO;
    self.flashMode = AVCaptureFlashModeAuto;
    
    self.popView = [[JMYPopView alloc] initWithFrame:(CGRect){0, 0, 55, 125} style:UITableViewStylePlain];
    self.popView.delegate = self;
    self.popView.dataSource = self;
    [self.view addSubview:self.popView];
#else
    self.flashButton  = [UIButton buttonWithType:UIButtonTypeCustom];
    [self setupButtonWithButton:self.flashButton imageName:@"camera_ic_anto" frame:CGRectMake(0, 0, 50, 50) action:@selector(changeFlashMode)];
    self.flashButton.enabled  = NO;
#endif
    
}

- (void)setupButtonWithButton:(UIButton *)button imageName:(NSString *)imageName frame:(CGRect)frame action:(SEL)action {
    [button setImage:[UIImage imageNamed:JMYCameraSrcName(imageName)] forState:UIControlStateNormal];
    [button setFrame:frame];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

#pragma mark - Action

// 拍照
- (void)snapStillImage {
    dispatch_async(self.sessionQueue, ^{
        AVCaptureConnection *connection = [self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo];
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.previewView.layer;
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        // Update the orientation on the still image output video connection before capturing.
        connection.videoOrientation = previewLayer.connection.videoOrientation;
        
        // Flash set to Auto for Still Capture.
        [JMYCameraController setFlashMode:self.flashMode forDevice:self.videoDeviceInput.device];
        
        // Capture a still image.
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:connection completionHandler:^( CMSampleBufferRef imageDataSampleBuffer, NSError *error ) {
            if ( imageDataSampleBuffer ) {
                // The sample buffer is not retained. Create image data before saving the still image to the photo library asynchronously.
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
                    if ( status == PHAuthorizationStatusAuthorized ) {
                        // To preserve the metadata, we create an asset from the JPEG NSData representation.
                        // Note that creating an asset from a UIImage discards the metadata.
                        // In iOS 9, we can use -[PHAssetCreationRequest addResourceWithType:data:options].
                        // In iOS 8, we save the image to a temporary file and use +[PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:].
                        if ( [PHAssetCreationRequest class] ) {
                            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
                            } completionHandler:^( BOOL success, NSError *error ) {
                                if (!success) {
                                    NSLog(@"Error occurred while saving image to photo library: %@", error);
                                }
                            }];
                        }
                        else {
                            NSString *temporaryFileName = [NSProcessInfo processInfo].globallyUniqueString;
                            NSString *temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[temporaryFileName stringByAppendingPathExtension:@"jpg"]];
                            NSURL *temporaryFileURL = [NSURL fileURLWithPath:temporaryFilePath];
                            
                            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                                NSError *error = nil;
                                [imageData writeToURL:temporaryFileURL options:NSDataWritingAtomic error:&error];
                                if (error) {
                                    NSLog(@"Error occured while writing image data to a temporary file: %@", error);
                                }
                                else {
                                    [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:temporaryFileURL];
                                }
                            } completionHandler:^( BOOL success, NSError *error ) {
                                if (!success) {
                                    NSLog(@"Error occurred while saving image to photo library: %@", error);
                                }
                                
                                // Delete the temporary file.
                                [[NSFileManager defaultManager] removeItemAtURL:temporaryFileURL error:nil];
                            }];
                        }
                    }
                }];
            }
            else {
                NSLog(@"Could not capture still image: %@", error);
            }
        }];
    } );
}

// 返回上一页
- (void)backPreviewViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// 切换前后摄像头
- (void)changeCamera {
    self.toggleButton.enabled = NO;
    self.stillButton.enabled  = NO;
//    self.backButton.enabled   = NO;
#if !FlashButtonStyle
    self.flashButton.enabled  = NO;
#endif
    
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDevice *currentVideoDevice = self.videoDeviceInput.device;
        AVCaptureDevicePosition preferredPosition = AVCaptureDevicePositionUnspecified;
        AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
        
        switch (currentPosition)
        {
            case AVCaptureDevicePositionUnspecified:
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                break;
        }
        
        AVCaptureDevice *videoDevice = [JMYCameraController deviceWithMediaType:AVMediaTypeVideo preferringPosition:preferredPosition];
        AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        
        [self.session beginConfiguration];
        
        // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
        [self.session removeInput:self.videoDeviceInput];
        
        if ( [self.session canAddInput:videoDeviceInput] ) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
            
            [JMYCameraController setFlashMode:self.flashMode forDevice:videoDevice];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:videoDevice];
            
            [self.session addInput:videoDeviceInput];
            self.videoDeviceInput = videoDeviceInput;
        }
        else {
            [self.session addInput:self.videoDeviceInput];
        }
        
        [self.session commitConfiguration];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            self.toggleButton.enabled = YES;
            self.stillButton.enabled  = YES;
//            self.backButton.enabled   = YES;
#if !FlashButtonStyle
            self.flashButton.enabled  = YES;
#endif
        } );
    } );
}

- (void)resumeInterruptedSession
{
    dispatch_async( self.sessionQueue, ^{
        // The session might fail to start running, e.g., if a phone or FaceTime call is still using audio or video.
        // A failure to start the session running will be communicated via a session runtime error notification.
        // To avoid repeatedly failing to start the session running, we only try to restart the session running in the
        // session runtime error handler if we aren't trying to resume the session running.
        [self.session startRunning];
        self.sessionRunning = self.session.isRunning;
        if ( ! self.session.isRunning ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                NSString *message = NSLocalizedString(@"Unable to resume", @"Alert message when unable to resume the session running");
                float systemVersion = GET_SYSTEM_VERSION;
                if (systemVersion >= 8.0) {
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Camera" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"Alert OK button") style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } else {
                    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Camera", nil)
                                                                    message:message
                                                                   delegate:self
                                                          cancelButtonTitle:NSLocalizedString(@"OK", @"Alert OK button")
                                                          otherButtonTitles:nil];
                    [alert show];
                }
            } );
        }
        else {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.resumeButton.hidden = YES;
            } );
        }
    } );
}

// 对焦
- (void)focusAndExposeTap:(UIGestureRecognizer *)recognizer {
#if FlashButtonStyle
    self.isOpen = NO;
    [self.popView reloadData];
#endif
    CGPoint devicePoint = [(AVCaptureVideoPreviewLayer *)self.previewView.layer captureDevicePointOfInterestForPoint:[recognizer locationInView:recognizer.view]];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
}

#pragma mark - Private Method

+ (AVCaptureDevice *)deviceWithMediaType:(NSString *)mediaType preferringPosition:(AVCaptureDevicePosition)position
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:mediaType];
    AVCaptureDevice *captureDevice = devices.firstObject;
    
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == position ) {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

+ (void)setFlashMode:(AVCaptureFlashMode)flashMode forDevice:(AVCaptureDevice *)device
{
    if ( device.hasFlash && [device isFlashModeSupported:flashMode] ) {
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            device.flashMode = flashMode;
            [device unlockForConfiguration];
        }
        else {
            NSLog(@"Could not lock device for configuration: %@", error);
        }
    }
}

#pragma mark - KVO and Notifications

// 监听
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == CapturingStillImageContext ) {
        BOOL isCapturingStillImage = [change[NSKeyValueChangeNewKey] boolValue];
        
        if ( isCapturingStillImage ) {
            dispatch_async( dispatch_get_main_queue(), ^{
                self.previewView.layer.opacity = 0.0;
                [UIView animateWithDuration:0.25 animations:^{
                    self.previewView.layer.opacity = 1.0;
                }];
            } );
        }
    }
    else if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
            self.toggleButton.enabled = isSessionRunning && ( [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo].count > 1 );
            self.stillButton.enabled = isSessionRunning;
            
#if !FlashButtonStyle
            self.flashButton.enabled = isSessionRunning;
#endif
//            self.backButton.enabled = isSessionRunning;
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)addObservers
{
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [self.stillImageOutput addObserver:self forKeyPath:@"capturingStillImage" options:NSKeyValueObservingOptionNew context:CapturingStillImageContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    // A session can only run when the app is full screen. It will be interrupted in a multi-app layout, introduced in iOS 9,
    // see also the documentation of AVCaptureSessionInterruptionReason. Add observers to handle these session interruptions
    // and show a preview is paused message. See the documentation of AVCaptureSessionWasInterruptedNotification for other
    // interruption reasons.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
    [self.stillImageOutput removeObserver:self forKeyPath:@"capturingStillImage" context:CapturingStillImageContext];
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog(@"Capture session runtime error: %@", error);
    
    // Automatically try to restart the session running if media services were reset and the last start running succeeded.
    // Otherwise, enable the user to try to resume the session running.
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                    self.resumeButton.hidden = NO;
                } );
            }
        } );
    }
    else {
        self.resumeButton.hidden = NO;
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    // In some scenarios we want to enable the user to resume the session running.
    // For example, if music playback is initiated via control center while using AVCam,
    // then the user can let AVCam resume the session running, which will stop music playback.
    // Note that stopping music playback in control center will not automatically resume the session running.
    // Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
    BOOL showResumeButton = NO;
    
    // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
    if (&AVCaptureSessionInterruptionReasonKey) {
        AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
        NSLog(@"Capture session was interrupted with reason %ld", (long)reason);
        
        if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
            reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
            showResumeButton = YES;
        }
        else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
            // Simply fade-in a label to inform the user that the camera is unavailable.
            self.cameraUnavailableLabel.hidden = NO;
            self.cameraUnavailableLabel.alpha = 0.0;
            [UIView animateWithDuration:0.25 animations:^{
                self.cameraUnavailableLabel.alpha = 1.0;
            }];
        }
    }
    else {
        NSLog(@"Capture session was interrupted");
        showResumeButton = ( [UIApplication sharedApplication].applicationState == UIApplicationStateInactive );
    }
    
    if ( showResumeButton ) {
        // Simply fade-in a button to enable the user to try to resume the session running.
        self.resumeButton.hidden = NO;
        self.resumeButton.alpha = 0.0;
        [UIView animateWithDuration:0.25 animations:^{
            self.resumeButton.alpha = 1.0;
        }];
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog(@"Capture session interruption ended");
    
    if ( ! self.resumeButton.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.resumeButton.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.resumeButton.hidden = YES;
        }];
    }
    if ( ! self.cameraUnavailableLabel.hidden ) {
        [UIView animateWithDuration:0.25 animations:^{
            self.cameraUnavailableLabel.alpha = 0.0;
        } completion:^( BOOL finished ) {
            self.cameraUnavailableLabel.hidden = YES;
        }];
    }
}

#pragma mark - Device Configuration

- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDeviceInput.device;
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            // Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
            // Call -set(Focus/Exposure)Mode: to apply the new point of interest.
            if ( device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            NSLog(@"Could not lock device for configuration: %@", error);
        }
    } );
}

#if FlashButtonStyle
#pragma mark - UITableViewDelegate 
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 50;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 25;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {

    UIButton *flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [flashButton setFrame:CGRectMake(0, 0, 50, 50)];
    [flashButton addTarget:self action:@selector(openOrCloseRows:) forControlEvents:UIControlEventTouchUpInside];
    switch (self.flashMode) {
        case AVCaptureFlashModeOff: {
            [flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_off")] forState:UIControlStateNormal];
            break;
        }
        case AVCaptureFlashModeOn: {
            [flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_on")] forState:UIControlStateNormal];
            break;
        }
        case AVCaptureFlashModeAuto: {
            [flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_anto")] forState:UIControlStateNormal];
            break;
        }
    }
    return flashButton;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    switch (indexPath.row) {
        case 0:
        {
            self.flashMode = AVCaptureFlashModeAuto;
            break;
        }
        case 1:
        {
            self.flashMode = AVCaptureFlashModeOn;
            break;
        }
        case 2:
        {
            self.flashMode = AVCaptureFlashModeOff;
            break;
        }
        default:
            break;
    }
    self.isOpen = NO;
    [tableView reloadData];
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isOpen) {
        return 3;
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    JMYPopViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kJMYPopViewCellID forIndexPath:indexPath];
    [cell configureCellWithTitle:self.titles[indexPath.row]];
    return cell;
}

#pragma mark - Action
- (void)openOrCloseRows:(id)sender {
    self.isOpen = !self.isOpen;
    [self.popView reloadData];
}

#else 
// 切换闪光灯模式
- (void)changeFlashMode {
    
    switch (self.flashMode) {
        case AVCaptureFlashModeOff: {
            self.flashMode = AVCaptureFlashModeOn;
            [self.flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_on")] forState:UIControlStateNormal];
            break;
        }
        case AVCaptureFlashModeOn: {
            self.flashMode = AVCaptureFlashModeAuto;
            [self.flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_anto")] forState:UIControlStateNormal];
            break;
        }
        case AVCaptureFlashModeAuto: {
            self.flashMode = AVCaptureFlashModeOff;
            [self.flashButton setImage:[UIImage imageNamed:JMYCameraSrcName(@"camera_ic_off")] forState:UIControlStateNormal];
            break;
        }
    }
}
#endif

@end

































