//
//  ADAdWinXNativeExpressAdDetailViewController.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADAdWinXNativeExpressAdDetailViewController.h"
#import <AdWinX/AdWinX.h>
#import <Masonry/Masonry.h>

@interface ADAdWinXNativeExpressAdDetailViewController ()

/// 拍卖结果：加载成功后持有，供渲染使用（Adapter 实例由 ADXAdManager 内部缓存）
@property (nonatomic, strong, nullable) ADXAuctionResult *auctionResult;

@end

@implementation ADAdWinXNativeExpressAdDetailViewController

- (void)loadAd
{
    [self updateStatus:@"AdWinX 聚合信息流拍卖中（GDT + 百度 竞价，穿山甲 瀑布 70/50/30/0）..." loading:YES];
    CGFloat adWidth = CGRectGetWidth(self.view.bounds) - 40.0;
    __weak typeof(self) weakSelf = self;
    [[ADXAdManager sharedManager] loadNativeAdWithSlotName:self.placementId
                                                    adWidth:adWidth
                                                completion:^(ADXAuctionResult *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!result) {
            [strongSelf updateStatus:[NSString stringWithFormat:@"配置中无 %@ 广告位", strongSelf.placementId] loading:NO];
            return;
        }

        strongSelf.auctionResult = result;
        [strongSelf updateStatus:[NSString stringWithFormat:@"拍卖完成：%@，耗时 %.2fs，候选数 %lu",
                                 result.winReason, result.totalDuration, (unsigned long)result.allCandidates.count]
                        loading:NO];

        if (result.winnerResult) {
            [strongSelf updateStatus:[NSString stringWithFormat:@"赢家：%@（price=%ld 分），点击下方按钮渲染",
                                     result.winnerResult.sourceId, (long)result.winnerResult.price]
                            loading:NO];
            strongSelf.showAdButton.enabled = YES;
            [strongSelf.showAdButton setTitle:@"渲染信息流广告" forState:UIControlStateNormal];
        } else {
            [strongSelf updateStatus:@"本次无可用广告" loading:NO];
        }
    }];
}

- (void)showAdButtonTapped
{
    if (!self.auctionResult || !self.auctionResult.winnerResult) {
        [self loadAd];
        return;
    }

    [self updateStatus:@"渲染中（失败自动降级次高价候选）..." loading:YES];
    __weak typeof(self) weakSelf = self;
    [[ADXAdManager sharedManager] renderNativeAdViewWithResult:self.auctionResult
                                              rootViewController:self
                                                    completion:^(UIView * _Nullable adView, NSString * _Nullable shownSourceId) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (adView) {
            [strongSelf.adContainerView addSubview:adView];
            CGFloat adHeight = CGRectGetHeight(adView.bounds) > 0.0 ? CGRectGetHeight(adView.bounds) : 260.0;
            [adView mas_makeConstraints:^(MASConstraintMaker *make) {
                make.top.leading.trailing.equalTo(strongSelf.adContainerView);
                make.height.mas_equalTo(adHeight);
            }];
            NSString *sourceText = [shownSourceId isEqualToString:strongSelf.auctionResult.winnerResult.sourceId]
                ? @"原赢家" : @"降级候选";
            [strongSelf updateStatus:[NSString stringWithFormat:@"渲染成功：%@（%@），已加入容器",
                                     shownSourceId, sourceText] loading:NO];
        } else {
            [strongSelf updateStatus:@"所有候选渲染失败" loading:NO];
            strongSelf.auctionResult = nil;
        }
    }];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    self.auctionResult = nil;
}

@end
