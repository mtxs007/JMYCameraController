//
//  JMYPreviewView.h
//  Camera
//
//  Created by lifei on 16/1/4.
//  Copyright © 2016年 mtxs007. All rights reserved.
//

#import <UIKit/UIKit.h>

@class AVCaptureSession;

@interface JMYPreviewView : UIView
@property (strong, nonatomic) AVCaptureSession *session;
@end
