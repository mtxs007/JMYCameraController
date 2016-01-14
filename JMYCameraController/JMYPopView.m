//
//  JMYPopView.m
//  Camera
//
//  Created by lifei on 16/1/11.
//  Copyright © 2016年 mtxs007. All rights reserved.
//

#import "JMYPopView.h"
#import "JMYPopViewCell.h"

@implementation JMYPopView 

- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    self = [super initWithFrame:frame style:style];
    if (self) {
        self.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.backgroundColor = [UIColor clearColor];
        [self registerClass:[JMYPopViewCell class] forCellReuseIdentifier:kJMYPopViewCellID];
    }
    return self;
}

@end
