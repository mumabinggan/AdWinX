//
//  ADBaiduBaseAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/15/2026.
//

#import "ADBaiduBaseAdDetailViewController.h"
#import <Masonry/Masonry.h>

@interface ADBaiduBaseAdDetailViewController ()

@property (nonatomic, strong) UILabel *badgeLabel;

@end

@implementation ADBaiduBaseAdDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self rebuildBaiduDetailPage];
}

- (void)rebuildBaiduDetailPage
{
    [self.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.08 blue:0.15 alpha:1.0];

    UIView *heroView = [[UIView alloc] initWithFrame:CGRectZero];
    heroView.backgroundColor = [UIColor colorWithRed:0.07 green:0.15 blue:0.31 alpha:1.0];
    heroView.layer.cornerRadius = 24.0;
    heroView.layer.masksToBounds = YES;
    [self.view addSubview:heroView];

    self.badgeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.badgeLabel.text = @"BAIDU MOB ADS";
    self.badgeLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    self.badgeLabel.textColor = [UIColor colorWithRed:0.55 green:0.76 blue:1.0 alpha:1.0];
    [heroView addSubview:self.badgeLabel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = self.adTypeName;
    titleLabel.font = [UIFont systemFontOfSize:30.0 weight:UIFontWeightHeavy];
    titleLabel.textColor = [UIColor whiteColor];
    [heroView addSubview:titleLabel];

    UILabel *subtitleLabel = [self baiduLabelWithText:self.adDescription font:[UIFont systemFontOfSize:15.0] color:[UIColor colorWithRed:0.74 green:0.82 blue:0.93 alpha:1.0]];
    [heroView addSubview:subtitleLabel];

    UIView *infoPanel = [[UIView alloc] initWithFrame:CGRectZero];
    infoPanel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    infoPanel.layer.cornerRadius = 16.0;
    [heroView addSubview:infoPanel];

    UIStackView *infoStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self baiduInfoLabelWithTitle:@"平台" value:self.platformName],
        [self baiduInfoLabelWithTitle:@"AppID" value:self.appId.length > 0 ? self.appId : @"待配置"],
        [self baiduInfoLabelWithTitle:@"SDK" value:self.sdkClassName.length > 0 ? self.sdkClassName : @"待接入"],
        [self baiduInfoLabelWithTitle:@"广告位" value:self.placementId.length > 0 ? self.placementId : @"待配置"]
    ]];
    infoStack.axis = UILayoutConstraintAxisVertical;
    infoStack.spacing = 10.0;
    [infoPanel addSubview:infoStack];

    self.showAdButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.showAdButton.enabled = self.placementId.length > 0;
    [self.showAdButton setTitle:self.showAdButton.enabled ? @"请求百度广告" : @"配置广告位 ID 后展示" forState:UIControlStateNormal];
    self.showAdButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightBold];
    self.showAdButton.backgroundColor = self.showAdButton.enabled ? [UIColor colorWithRed:0.04 green:0.43 blue:1.0 alpha:1.0] : [UIColor colorWithWhite:1.0 alpha:0.18];
    [self.showAdButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.showAdButton.layer.cornerRadius = 14.0;
    [self.showAdButton addTarget:self action:@selector(showAdButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.showAdButton];

    UIView *statusPanel = [[UIView alloc] initWithFrame:CGRectZero];
    statusPanel.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    statusPanel.layer.cornerRadius = 18.0;
    statusPanel.layer.shadowColor = [UIColor blackColor].CGColor;
    statusPanel.layer.shadowOpacity = 0.18;
    statusPanel.layer.shadowRadius = 20.0;
    statusPanel.layer.shadowOffset = CGSizeMake(0.0, 8.0);
    [self.view addSubview:statusPanel];

    self.statusLabel = [self baiduLabelWithText:@"状态：等待请求百度广告" font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium] color:[UIColor colorWithRed:0.08 green:0.12 blue:0.18 alpha:1.0]];
    [statusPanel addSubview:self.statusLabel];

    self.adContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.adContainerView.backgroundColor = [UIColor colorWithRed:0.94 green:0.97 blue:1.0 alpha:1.0];
    self.adContainerView.layer.cornerRadius = 16.0;
    self.adContainerView.layer.borderWidth = 1.0;
    self.adContainerView.layer.borderColor = [UIColor colorWithRed:0.78 green:0.86 blue:0.96 alpha:1.0].CGColor;
    self.adContainerView.layer.masksToBounds = YES;
    [statusPanel addSubview:self.adContainerView];

    [heroView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.mas_topLayoutGuideBottom).offset(18.0);
        make.leading.equalTo(self.view).offset(16.0);
        make.trailing.equalTo(self.view).offset(-16.0);
    }];

    [self.badgeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(heroView).offset(22.0);
        make.leading.equalTo(heroView).offset(22.0);
        make.trailing.equalTo(heroView).offset(-22.0);
    }];

    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.badgeLabel.mas_bottom).offset(10.0);
        make.leading.trailing.equalTo(self.badgeLabel);
    }];

    [subtitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(titleLabel.mas_bottom).offset(10.0);
        make.leading.trailing.equalTo(self.badgeLabel);
    }];

    [infoPanel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(subtitleLabel.mas_bottom).offset(18.0);
        make.leading.trailing.equalTo(self.badgeLabel);
        make.bottom.equalTo(heroView).offset(-20.0);
    }];

    [infoStack mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(infoPanel).insets(UIEdgeInsetsMake(14.0, 16.0, 14.0, 16.0));
    }];

    [self.showAdButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(heroView.mas_bottom).offset(16.0);
        make.leading.equalTo(self.view).offset(16.0);
        make.trailing.equalTo(self.view).offset(-16.0);
        make.height.mas_equalTo(52.0);
    }];

    [statusPanel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.showAdButton.mas_bottom).offset(16.0);
        make.leading.trailing.equalTo(self.showAdButton);
        make.bottom.lessThanOrEqualTo(self.view).offset(-20.0);
    }];

    [self.statusLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.equalTo(statusPanel).offset(16.0);
        make.trailing.equalTo(statusPanel).offset(-16.0);
    }];

    [self.adContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statusLabel.mas_bottom).offset(14.0);
        make.leading.equalTo(statusPanel).offset(14.0);
        make.trailing.equalTo(statusPanel).offset(-14.0);
        make.height.mas_equalTo(300.0);
        make.bottom.equalTo(statusPanel).offset(-14.0);
    }];
}

- (UILabel *)baiduInfoLabelWithTitle:(NSString *)title value:(NSString *)value
{
    NSString *text = [NSString stringWithFormat:@"%@  %@", title, value];
    UILabel *label = [self baiduLabelWithText:text font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightMedium] color:[UIColor whiteColor]];
    label.alpha = 0.92;
    return label;
}

- (UILabel *)baiduLabelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    return label;
}

- (void)updateStatus:(NSString *)status loading:(BOOL)loading
{
    NSLog(@"%@ %@ %@", self.platformName, self.adTypeName, status);
    self.statusLabel.text = [NSString stringWithFormat:@"状态：%@", status];
    self.showAdButton.enabled = !loading && self.placementId.length > 0;
    [self.showAdButton setTitle:loading ? @"百度广告请求中..." : @"重新请求百度广告" forState:UIControlStateNormal];
    self.showAdButton.backgroundColor = self.showAdButton.enabled ? [UIColor colorWithRed:0.04 green:0.43 blue:1.0 alpha:1.0] : [UIColor colorWithWhite:1.0 alpha:0.18];
}

- (NSString *)baiduFailStatusWithPrefix:(NSString *)prefix code:(NSString *)code message:(NSString *)message
{
    NSString *safeCode = code.length > 0 ? code : @"unknown";
    NSString *safeMessage = message.length > 0 ? message : @"无描述";
    return [NSString stringWithFormat:@"%@：code=%@ message=%@", prefix, safeCode, safeMessage];
}

@end
