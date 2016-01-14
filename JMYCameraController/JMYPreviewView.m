//
//  JMYPreviewView.m
//  Camera
//
//  Created by lifei on 16/1/4.
//  Copyright © 2016年 mtxs007. All rights reserved.
//

#import "JMYPreviewView.h"
#import <AVFoundation/AVFoundation.h>

@implementation JMYPreviewView
+ (Class)layerClass
{
    return [AVCaptureVideoPreviewLayer class];
}

- (AVCaptureSession *)session
{
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    return previewLayer.session;
}

- (void)setSession:(AVCaptureSession *)session
{
    AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)self.layer;
    previewLayer.session = session;
}
@end
