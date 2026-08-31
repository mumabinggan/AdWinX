//
//  ADBaseAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADBaseAdDetailViewController.h"
#import "ADAdDemoConstants.h"
#import <Masonry/Masonry.h>

@implementation ADBaseAdDetailViewController

- (instancetype)initWithAdGroup:(NSDictionary<NSString *, id> *)adGroup adItem:(NSDictionary<NSString *, NSString *> *)adItem
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _platformName = [adGroup[ADAdGroupTitleKey] copy];
        _appId = [adGroup[ADAdGroupAppIdKey] copy];
        _adTypeName = [adItem[ADAdItemNameKey] copy];
        _sdkClassName = [adItem[ADAdItemSDKClassKey] copy];
        _adDescription = [adItem[ADAdItemDescriptionKey] copy];
        _placementId = [adItem[ADAdItemPlacementIdKey] copy];
        self.title = _adTypeName;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.98 alpha:1.0];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.text = [NSString stringWithFormat:@"%@ - %@", self.platformName, self.adTypeName];
    titleLabel.font = [UIFont boldSystemFontOfSize:24.0];
    titleLabel.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    [self.view addSubview:titleLabel];

    UIView *cardView = [[UIView alloc] initWithFrame:CGRectZero];
    cardView.backgroundColor = [UIColor whiteColor];
    cardView.layer.cornerRadius = 14.0;
    cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    cardView.layer.shadowOpacity = 0.06;
    cardView.layer.shadowRadius = 12.0;
    cardView.layer.shadowOffset = CGSizeMake(0.0, 6.0);
    [self.view addSubview:cardView];

    UILabel *platformLabel = [self detailLabelWithText:[NSString stringWithFormat:@"广告平台：%@", self.platformName]];
    UILabel *appIdLabel = [self detailLabelWithText:[NSString stringWithFormat:@"AppID：%@", self.appId.length > 0 ? self.appId : @"待配置"]];
    UILabel *sdkClassLabel = [self detailLabelWithText:[NSString stringWithFormat:@"SDK 类：%@", self.sdkClassName.length > 0 ? self.sdkClassName : @"待接入"]];
    NSString *placementLabelTitle = [self.sdkClassName hasPrefix:@"BU"] ? @"代码位 ID" : @"广告位 ID";
    NSString *placementText = self.placementId.length > 0 ? self.placementId : [NSString stringWithFormat:@"待配置%@", placementLabelTitle];
    UILabel *placementLabel = [self detailLabelWithText:[NSString stringWithFormat:@"%@：%@", placementLabelTitle, placementText]];
    UILabel *descriptionLabel = [self detailLabelWithText:self.adDescription];
    descriptionLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];

    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[platformLabel, appIdLabel, sdkClassLabel, placementLabel, descriptionLabel]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 12.0;
    [cardView addSubview:stackView];

    self.showAdButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.showAdButton.enabled = self.placementId.length > 0;
    NSString *buttonTitle = self.showAdButton.enabled ? @"加载并展示广告" : @"配置广告位 ID 后展示广告";
    [self.showAdButton setTitle:buttonTitle forState:UIControlStateNormal];
    self.showAdButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    self.showAdButton.backgroundColor = self.showAdButton.enabled ? [UIColor systemBlueColor] : [UIColor colorWithWhite:0.86 alpha:1.0];
    [self.showAdButton setTitleColor:self.showAdButton.enabled ? [UIColor whiteColor] : [UIColor colorWithWhite:0.45 alpha:1.0] forState:UIControlStateNormal];
    self.showAdButton.layer.cornerRadius = 10.0;
    [self.showAdButton addTarget:self action:@selector(showAdButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.showAdButton];

    self.statusLabel = [self detailLabelWithText:@"状态：等待加载"];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    [self.view addSubview:self.statusLabel];

    self.adContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.adContainerView.backgroundColor = [UIColor whiteColor];
    self.adContainerView.layer.cornerRadius = 12.0;
    self.adContainerView.layer.masksToBounds = YES;
    [self.view addSubview:self.adContainerView];

    [titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.equalTo(self.view).offset(24.0);
        make.trailing.equalTo(self.view).offset(-24.0);
        make.top.equalTo(self.mas_topLayoutGuideBottom).offset(24.0);
    }];

    [cardView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(titleLabel.mas_bottom).offset(16.0);
        make.leading.equalTo(self.view).offset(20.0);
        make.trailing.equalTo(self.view).offset(-20.0);
    }];

    [stackView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(cardView).insets(UIEdgeInsetsMake(18.0, 18.0, 18.0, 18.0));
    }];

    [self.showAdButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(cardView.mas_bottom).offset(20.0);
        make.leading.equalTo(self.view).offset(20.0);
        make.trailing.equalTo(self.view).offset(-20.0);
        make.height.mas_equalTo(48.0);
    }];

    [self.statusLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.showAdButton.mas_bottom).offset(16.0);
        make.leading.equalTo(self.view).offset(20.0);
        make.trailing.equalTo(self.view).offset(-20.0);
    }];

    [self.adContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.statusLabel.mas_bottom).offset(12.0);
        make.leading.equalTo(self.view).offset(20.0);
        make.trailing.equalTo(self.view).offset(-20.0);
        make.height.mas_equalTo(260.0);
    }];
}

- (UILabel *)detailLabelWithText:(NSString *)text
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = [UIFont systemFontOfSize:16.0];
    label.textColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    label.numberOfLines = 0;
    return label;
}

- (void)showAdButtonTapped
{
    [self clearAdContainer];
    [self updateStatus:@"广告加载中..." loading:YES];
    [self loadAd];
}

- (void)loadAd
{
    [self updateStatus:@"当前广告类型未接入加载逻辑" loading:NO];
}

- (void)updateStatus:(NSString *)status loading:(BOOL)loading
{
    NSLog(@"%@ %@ %@", self.platformName, self.adTypeName, status);
    self.statusLabel.text = [NSString stringWithFormat:@"状态：%@", status];
    self.showAdButton.enabled = !loading && self.placementId.length > 0;
    [self.showAdButton setTitle:loading ? @"加载中..." : @"加载并展示广告" forState:UIControlStateNormal];
}

- (void)clearAdContainer
{
    [self.adContainerView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}

- (UIWindow *)adPresentationWindow
{
    return self.view.window ?: [UIApplication sharedApplication].keyWindow;
}

- (NSString *)statusTextForError:(NSError *)error prefix:(NSString *)prefix
{
    if (!error) {
        return prefix;
    }

    NSString *message = error.localizedDescription.length > 0 ? error.localizedDescription : @"无描述";
    return [NSString stringWithFormat:@"%@：domain=%@ code=%ld message=%@ userInfo=%@", prefix, error.domain, (long)error.code, message, error.userInfo];
}

@end
