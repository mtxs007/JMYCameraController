
//
//  JMYPopViewCell.m
//  Camera
//
//  Created by lifei on 16/1/11.
//  Copyright © 2016年 mtxs007. All rights reserved.
//

#import "JMYPopViewCell.h"

NSString *const kJMYPopViewCellID = @"JMYPopViewCellID";

@interface JMYPopViewCell ()
@property (strong, nonatomic) UILabel *titleLabel;
@end

@implementation JMYPopViewCell

- (void)awakeFromNib {
    // Initialization code
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont systemFontOfSize:13.0];
        [self.contentView addSubview:self.titleLabel];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)configureCellWithTitle:(NSString *)title {
    self.titleLabel.frame = (CGRect){15, 0, self.frame.size.width - 10, self.frame.size.height};
    self.titleLabel.text = title;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
