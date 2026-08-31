//
//  ADViewController.m
//  AdWinX
//
//  Created by mumabinggan on 08/12/2026.
//  Copyright (c) 2026 mumabinggan. All rights reserved.
//

#import "ADViewController.h"
#import "ADAdDemoConstants.h"
#import "ADPlaceholderAdDetailViewController.h"
#import "ADGDTSplashAdDetailViewController.h"
#import "ADGDTRewardVideoAdDetailViewController.h"
#import "ADGDTInterstitialAdDetailViewController.h"
#import "ADGDTBannerAdDetailViewController.h"
#import "ADGDTNativeExpressAdDetailViewController.h"
#import "ADBaiduSplashAdDetailViewController.h"
#import "ADBaiduRewardVideoAdDetailViewController.h"
#import "ADBaiduInterstitialAdDetailViewController.h"
#import "ADBaiduNativeExpressAdDetailViewController.h"
#import "ADSigmobSplashAdDetailViewController.h"
#import "ADSigmobRewardVideoAdDetailViewController.h"
#import "ADSigmobInterstitialAdDetailViewController.h"
#import "ADCSJSplashAdDetailViewController.h"
#import "ADCSJRewardVideoAdDetailViewController.h"
#import "ADCSJInterstitialAdDetailViewController.h"
#import "ADCSJBannerAdDetailViewController.h"
#import "ADCSJNativeExpressAdDetailViewController.h"
#import "ADAdWinXRewardVideoAdDetailViewController.h"
#import "ADAdWinXNativeExpressAdDetailViewController.h"
#import "ADAdWinXInterstitialAdDetailViewController.h"
#import <Masonry/Masonry.h>

static NSString * const ADAdTypeCellIdentifier = @"ADAdTypeCellIdentifier";
static NSString * const ADAdTypeHeaderIdentifier = @"ADAdTypeHeaderIdentifier";

@interface ADAdTypeCell : UICollectionViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *placementIdLabel;

@end

@implementation ADAdTypeCell

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
        self.contentView.layer.cornerRadius = 10.0;
        self.contentView.layer.masksToBounds = YES;
        
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        _titleLabel.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        [self.contentView addSubview:_titleLabel];

        _placementIdLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _placementIdLabel.font = [UIFont monospacedDigitSystemFontOfSize:12.0 weight:UIFontWeightRegular];
        _placementIdLabel.textColor = [UIColor colorWithWhite:0.48 alpha:1.0];
        [self.contentView addSubview:_placementIdLabel];
        
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(self.contentView).offset(11.0);
            make.leading.equalTo(self.contentView).offset(16.0);
            make.trailing.equalTo(self.contentView).offset(-16.0);
        }];

        [_placementIdLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(_titleLabel.mas_bottom).offset(5.0);
            make.leading.trailing.equalTo(_titleLabel);
            make.bottom.lessThanOrEqualTo(self.contentView).offset(-10.0);
        }];
    }
    return self;
}

@end

@interface ADAdTypeHeaderView : UICollectionReusableView

@property (nonatomic, strong) UILabel *titleLabel;

@end

@implementation ADAdTypeHeaderView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont boldSystemFontOfSize:22.0];
        _titleLabel.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        [self addSubview:_titleLabel];
        
        [_titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.leading.equalTo(self).offset(20.0);
            make.trailing.equalTo(self).offset(-20.0);
            make.bottom.equalTo(self).offset(-8.0);
        }];
    }
    return self;
}

@end

@interface ADViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *adGroups;

@end

@implementation ADViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"AdWinX Demo";
    self.view.backgroundColor = [UIColor whiteColor];
    self.adGroups = @[
        @{
            ADAdGroupTitleKey: @"AdWinX 聚合",
            ADAdGroupAppIdKey: @"—",
            ADAdGroupItemsKey: @[
                [self adItemWithName:@"激励视频" sdkClass:@"ADXAdManager" placementId:@"reward_main" description:@"AdWinX 聚合激励视频入口：Sigmob + 穿山甲 瀑布流拍卖（70/50/30/0 四档），展示失败自动降级次高价候选。"],
                [self adItemWithName:@"插屏广告" sdkClass:@"ADXAdManagerInterstitial" placementId:@"interstitial_main" description:@"AdWinX 聚合插屏入口：GDT + 百度 竞价，Sigmob + 穿山甲 瀑布流（70/50/30/0 四档），展示失败自动降级次高价候选。"],
                [self adItemWithName:@"信息流广告" sdkClass:@"ADXAdManagerNative" placementId:@"native_main" description:@"AdWinX 聚合信息流入口：GDT + 百度 竞价，穿山甲 瀑布流（70/50/30/0 四档），渲染失败自动降级次高价候选。"]
            ]
        },
        @{
            ADAdGroupTitleKey: @"百度",
            ADAdGroupAppIdKey: ADBaiduAppId,
            ADAdGroupItemsKey: @[
                [self adItemWithName:@"开屏广告" sdkClass:@"BaiduMobAdSplash" placementId:@"20155634" description:@"百度开屏广告入口，使用半屏容器请求并展示开屏广告。"],
                [self adItemWithName:@"激励视频" sdkClass:@"BaiduMobAdRewardVideo" placementId:@"20204536" description:@"百度激励视频入口，加载素材后自动拉起播放并展示奖励回调。"],
                [self adItemWithName:@"插屏广告" sdkClass:@"BaiduMobAdExpressInterstitial" placementId:@"20155646" description:@"百度模板插屏广告入口，加载成功后从当前详情页展示。"],
                [self adItemWithName:@"列表广告" sdkClass:@"BaiduMobAdNative" placementId:@"20155638" description:@"百度列表广告入口，使用优选模板信息流在专属容器中渲染展示。"]
            ]
        },
        @{
            ADAdGroupTitleKey: @"Sigmob",
            ADAdGroupAppIdKey: ADSigmobAppId,
            ADAdGroupItemsKey: @[
                [self adItemWithName:@"开屏广告" sdkClass:@"WindSplashAdView" placementId:ADSigmobSplashPlacementId description:@"Sigmob 全局开屏广告入口，启动时由全局管理器展示，也可在这里手动加载展示。"],
                [self adItemWithName:@"激励视频" sdkClass:@"WindRewardVideoAd" placementId:ADSigmobRewardPlacementId description:@"Sigmob 全局激励视频入口，由全局管理器持有广告对象并处理奖励回调。"],
                [self adItemWithName:@"插屏广告" sdkClass:@"WindNewIntersititialAd" placementId:ADSigmobInterstitialPlacementId description:@"Sigmob 新插屏广告入口，点击按钮后加载并从当前详情页展示。"]
            ]
        },
        @{
            ADAdGroupTitleKey: @"穿山甲",
            ADAdGroupAppIdKey: ADCSJAppId,
            ADAdGroupItemsKey: @[
                [self adItemWithName:@"开屏广告" sdkClass:@"BUSplashAd" placementId:ADCSJSplashCodeId description:[NSString stringWithFormat:@"穿山甲开屏广告入口，代码位：%@，广告位：%@。", ADCSJSplashCodeId, ADCSJSplashPlacementId]],
                [self adItemWithName:@"激励视频" sdkClass:@"BUNativeExpressRewardedVideoAd" placementId:ADCSJRewardCodeId description:[NSString stringWithFormat:@"穿山甲激励视频入口，代码位：%@，广告位：%@。", ADCSJRewardCodeId, ADCSJRewardPlacementId]],
                [self adItemWithName:@"插屏广告" sdkClass:@"BUNativeExpressFullscreenVideoAd" placementId:ADCSJInterstitialCodeId description:[NSString stringWithFormat:@"穿山甲插屏广告入口，代码位：%@，广告位：%@。", ADCSJInterstitialCodeId, ADCSJInterstitialPlacementId]],
                [self adItemWithName:@"Banner 广告" sdkClass:@"BUNativeExpressBannerView" placementId:ADCSJBannerCodeId description:[NSString stringWithFormat:@"穿山甲 Banner 广告入口，代码位：%@，广告位：%@。", ADCSJBannerCodeId, ADCSJBannerPlacementId]],
                [self adItemWithName:@"信息流广告" sdkClass:@"BUNativeExpressAdManager" placementId:ADCSJNativeCodeId description:[NSString stringWithFormat:@"穿山甲信息流广告入口，代码位：%@，广告位：%@。", ADCSJNativeCodeId, ADCSJNativePlacementId]]
            ]
        },
        @{
            ADAdGroupTitleKey: @"优量汇（测试媒体）",
            ADAdGroupAppIdKey: ADGDTAppId,
            ADAdGroupItemsKey: @[
//                [self adItemWithName:@"开屏广告" sdkClass:@"GDTSplashAd" placementId:@"2023121674786777" description:@"优量汇开屏广告入口，点击按钮后加载并展示开屏广告。"],
                [self adItemWithName:@"开屏广告" sdkClass:@"GDTSplashAd" placementId:@"2395092167243073" description:@"优量汇开屏广告入口，点击按钮后加载并展示开屏广告。"],
                [self adItemWithName:@"激励视频" sdkClass:@"GDTRewardVideoAd" placementId:@"5385493127546540" description:@"优量汇激励视频入口，点击按钮后加载并展示激励视频广告。"],
                [self adItemWithName:@"插屏广告" sdkClass:@"GDTUnifiedInterstitialAd" placementId:@"3395994137547804" description:@"优量汇插屏广告入口，点击按钮后加载并展示插屏广告。"],
                [self adItemWithName:@"Banner 广告" sdkClass:@"GDTUnifiedBannerView" placementId:@"4345697167550817" description:@"优量汇 Banner 广告入口，点击按钮后在详情页容器中展示 Banner。"],
                [self adItemWithName:@"信息流广告" sdkClass:@"GDTNativeExpressAd" placementId:@"6355293177655172" description:@"优量汇模板信息流广告入口，点击按钮后在详情页容器中渲染信息流。"]
            ]
        },
        @{
            ADAdGroupTitleKey: @"优量汇（官方Demo）",
            ADAdGroupAppIdKey: ADGDTAppId,
            ADAdGroupItemsKey: @[
//                [self adItemWithName:@"开屏广告" sdkClass:@"GDTSplashAd" placementId:@"2023121674786777" description:@"优量汇开屏广告入口，点击按钮后加载并展示开屏广告。"],
                [self adItemWithName:@"开屏广告" sdkClass:@"GDTSplashAd" placementId:@"2023121674786777" description:@"优量汇开屏广告入口，点击按钮后加载并展示开屏广告。"],
                [self adItemWithName:@"激励视频" sdkClass:@"GDTRewardVideoAd" placementId:@"8020744212936426" description:@"优量汇激励视频入口，点击按钮后加载并展示激励视频广告。"],
                [self adItemWithName:@"插屏广告" sdkClass:@"GDTUnifiedInterstitialAd" placementId:@"1050652855580392" description:@"优量汇插屏广告入口，点击按钮后加载并展示插屏广告。"],
                [self adItemWithName:@"Banner 广告" sdkClass:@"GDTUnifiedBannerView" placementId:@"1080958885885321" description:@"优量汇 Banner 广告入口，点击按钮后在详情页容器中展示 Banner。"],
                [self adItemWithName:@"信息流广告" sdkClass:@"GDTNativeExpressAd" placementId:@"8061016643928855" description:@"优量汇模板信息流广告入口，点击按钮后在详情页容器中渲染信息流。"]
            ]
        }
    ];
    
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 12.0;
    layout.minimumInteritemSpacing = 12.0;
    layout.sectionInset = UIEdgeInsetsMake(8.0, 20.0, 24.0, 20.0);
    layout.headerReferenceSize = CGSizeMake(CGRectGetWidth(self.view.bounds), 58.0);
    
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor whiteColor];
    self.collectionView.alwaysBounceVertical = YES;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:[ADAdTypeCell class] forCellWithReuseIdentifier:ADAdTypeCellIdentifier];
    [self.collectionView registerClass:[ADAdTypeHeaderView class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:ADAdTypeHeaderIdentifier];
    [self.view addSubview:self.collectionView];
    
    [self.collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return self.adGroups.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self adItemsInSection:section].count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ADAdTypeCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:ADAdTypeCellIdentifier forIndexPath:indexPath];
    NSDictionary<NSString *, NSString *> *adItem = [self adItemsInSection:indexPath.section][indexPath.item];
    NSString *placementId = adItem[ADAdItemPlacementIdKey];
    NSString *placementLabelTitle = [adItem[ADAdItemSDKClassKey] hasPrefix:@"BU"] ? @"代码位 ID" : @"广告位 ID";
    cell.titleLabel.text = adItem[ADAdItemNameKey];
    cell.placementIdLabel.text = placementId.length > 0 ? [NSString stringWithFormat:@"%@：%@", placementLabelTitle, placementId] : [NSString stringWithFormat:@"%@：待配置", placementLabelTitle];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath
{
    ADAdTypeHeaderView *headerView = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                        withReuseIdentifier:ADAdTypeHeaderIdentifier
                                                                               forIndexPath:indexPath];
    headerView.titleLabel.text = self.adGroups[indexPath.section][ADAdGroupTitleKey];
    return headerView;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary<NSString *, id> *adGroup = self.adGroups[indexPath.section];
    NSDictionary<NSString *, NSString *> *adItem = [self adItemsInSection:indexPath.section][indexPath.item];
    UIViewController *detailViewController = [self detailViewControllerForAdGroup:adGroup adItem:adItem];
    [self.navigationController pushViewController:detailViewController animated:YES];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat width = CGRectGetWidth(collectionView.bounds) - 40.0;
    return CGSizeMake(width, 68.0);
}

#pragma mark - Private

- (NSArray<NSDictionary<NSString *, NSString *> *> *)adItemsInSection:(NSInteger)section
{
    return self.adGroups[section][ADAdGroupItemsKey];
}

- (UIViewController *)detailViewControllerForAdGroup:(NSDictionary<NSString *, id> *)adGroup adItem:(NSDictionary<NSString *, NSString *> *)adItem
{
    NSString *sdkClass = adItem[ADAdItemSDKClassKey];
    Class detailClass = [ADPlaceholderAdDetailViewController class];
    if ([sdkClass isEqualToString:@"GDTSplashAd"]) {
        detailClass = [ADGDTSplashAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"GDTRewardVideoAd"]) {
        detailClass = [ADGDTRewardVideoAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"GDTUnifiedInterstitialAd"]) {
        detailClass = [ADGDTInterstitialAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"GDTUnifiedBannerView"]) {
        detailClass = [ADGDTBannerAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"GDTNativeExpressAd"]) {
        detailClass = [ADGDTNativeExpressAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BaiduMobAdSplash"]) {
        detailClass = [ADBaiduSplashAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BaiduMobAdRewardVideo"]) {
        detailClass = [ADBaiduRewardVideoAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BaiduMobAdExpressInterstitial"]) {
        detailClass = [ADBaiduInterstitialAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BaiduMobAdNative"]) {
        detailClass = [ADBaiduNativeExpressAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"WindSplashAdView"]) {
        detailClass = [ADSigmobSplashAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"WindRewardVideoAd"]) {
        detailClass = [ADSigmobRewardVideoAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"WindNewIntersititialAd"]) {
        detailClass = [ADSigmobInterstitialAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BUSplashAd"]) {
        detailClass = [ADCSJSplashAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BUNativeExpressRewardedVideoAd"]) {
        detailClass = [ADCSJRewardVideoAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BUNativeExpressFullscreenVideoAd"]) {
        detailClass = [ADCSJInterstitialAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BUNativeExpressBannerView"]) {
        detailClass = [ADCSJBannerAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"BUNativeExpressAdManager"]) {
        detailClass = [ADCSJNativeExpressAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"ADXAdManager"]) {
        detailClass = [ADAdWinXRewardVideoAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"ADXAdManagerNative"]) {
        detailClass = [ADAdWinXNativeExpressAdDetailViewController class];
    } else if ([sdkClass isEqualToString:@"ADXAdManagerInterstitial"]) {
        detailClass = [ADAdWinXInterstitialAdDetailViewController class];
    }
    return [[detailClass alloc] initWithAdGroup:adGroup adItem:adItem];
}

- (NSDictionary<NSString *, NSString *> *)adItemWithName:(NSString *)name sdkClass:(NSString *)sdkClass placementId:(NSString *)placementId description:(NSString *)description
{
    return @{
        ADAdItemNameKey: name,
        ADAdItemSDKClassKey: sdkClass,
        ADAdItemDescriptionKey: description,
        ADAdItemPlacementIdKey: placementId ?: @""
    };
}

@end
