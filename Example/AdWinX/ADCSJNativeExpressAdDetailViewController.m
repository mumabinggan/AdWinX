//
//  ADCSJNativeExpressAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADCSJNativeExpressAdDetailViewController.h"
#import <BUAdSDK/BUAdSDK.h>
#import <Masonry/Masonry.h>

@interface ADCSJNativeExpressAdDetailViewController () <BUNativeExpressAdViewDelegate>

@property (nonatomic, strong) BUNativeExpressAdManager *nativeExpressAdManager;
@property (nonatomic, strong) BUNativeExpressAdView *nativeExpressAdView;

@end

@implementation ADCSJNativeExpressAdDetailViewController

- (void)loadAd
{
    BUAdSlot *slot = [[BUAdSlot alloc] init];
    slot.ID = self.placementId;
    slot.AdType = BUAdSlotAdTypeFeed;
    slot.position = BUAdSlotPositionFeed;
    slot.imgSize = [BUSize sizeBy:BUProposalSize_Feed690_388];
    slot.supportRenderControl = YES;
    CGSize adSize = CGSizeMake(CGRectGetWidth(self.view.bounds) - 40.0, 0.0);
    self.nativeExpressAdManager = [[BUNativeExpressAdManager alloc] initWithSlot:slot adSize:adSize];
    self.nativeExpressAdManager.delegate = self;
    [self.nativeExpressAdManager loadAdDataWithCount:1];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    self.nativeExpressAdView = nil;
}

- (void)nativeExpressAdSuccessToLoad:(BUNativeExpressAdManager *)nativeExpressAdManager views:(NSArray<__kindof BUNativeExpressAdView *> *)views
{
    self.nativeExpressAdView = views.firstObject;
    self.nativeExpressAdView.rootViewController = self;
    [self updateStatus:@"穿山甲信息流广告加载成功，开始渲染" loading:YES];
    [self.nativeExpressAdView render];
}

- (void)nativeExpressAdFailToLoad:(BUNativeExpressAdManager *)nativeExpressAdManager error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲信息流广告加载失败"] loading:NO];
}

- (void)nativeExpressAdViewRenderSuccess:(BUNativeExpressAdView *)nativeExpressAdView
{
    [self.adContainerView addSubview:nativeExpressAdView];
    CGFloat adHeight = CGRectGetHeight(nativeExpressAdView.bounds) > 0.0 ? CGRectGetHeight(nativeExpressAdView.bounds) : 260.0;
    [nativeExpressAdView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.trailing.equalTo(self.adContainerView);
        make.height.mas_equalTo(adHeight);
    }];
    [self updateStatus:@"穿山甲信息流广告渲染并展示成功" loading:NO];
}

- (void)nativeExpressAdViewRenderFail:(BUNativeExpressAdView *)nativeExpressAdView error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲信息流广告渲染失败"] loading:NO];
}

- (void)nativeExpressAdViewWillShow:(BUNativeExpressAdView *)nativeExpressAdView
{
    [self updateStatus:@"穿山甲信息流广告已曝光" loading:NO];
}

- (void)nativeExpressAdViewDidClick:(BUNativeExpressAdView *)nativeExpressAdView
{
    [self updateStatus:@"穿山甲信息流广告已点击" loading:NO];
}

- (void)nativeExpressAdViewDidRemoved:(BUNativeExpressAdView *)nativeExpressAdView
{
    [self updateStatus:@"穿山甲信息流广告已移除" loading:NO];
    self.nativeExpressAdView = nil;
}

@end
