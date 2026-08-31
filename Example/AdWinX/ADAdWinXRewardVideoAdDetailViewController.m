//
//  ADAdWinXRewardVideoAdDetailViewController.m
//  AdWinX
//
//  Created by AdWinX on 08/30/2026.
//

#import "ADAdWinXRewardVideoAdDetailViewController.h"
#import <AdWinX/AdWinX.h>

@interface ADAdWinXRewardVideoAdDetailViewController ()

/// 拍卖结果：加载成功后持有，供展示使用（Adapter 实例由 ADXAdManager 内部缓存）
@property (nonatomic, strong, nullable) ADXAuctionResult *auctionResult;

@end

@implementation ADAdWinXRewardVideoAdDetailViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    // 演示预载生命周期：进入页面（≈进入关卡）即后台预载，用户触发点直接取走展示
    __weak typeof(self) weakSelf = self;
    [[ADXAdManager sharedManager] preloadRewardVideoAdWithSlotName:self.placementId
                                                        completion:^(ADXAuctionResult *result) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (result && result.winnerResult) {
            [strongSelf updateStatus:[NSString stringWithFormat:@"预载成功：%@（price=%ld 分），点击按钮即取即展示",
                                     result.winnerResult.sourceId, (long)result.winnerResult.price]
                            loading:NO];
        } else {
            [strongSelf updateStatus:@"预载无可用广告（点击按钮将现场重新 load）" loading:NO];
        }
    }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    // 演示退出关卡清理预载（实际业务在退出关卡/场景切换时调用）
    if (self.isMovingFromParentViewController) {
        [[ADXAdManager sharedManager] discardPreloadedAdWithSlotName:self.placementId];
    }
}

- (void)loadAd
{
    [self updateStatus:@"AdWinX 聚合激励视频拍卖中（Sigmob + 穿山甲 瀑布）..." loading:YES];
    __weak typeof(self) weakSelf = self;
    [[ADXAdManager sharedManager] loadRewardVideoAdWithSlotName:self.placementId
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
            [strongSelf updateStatus:[NSString stringWithFormat:@"赢家：%@（price=%ld 分），点击下方按钮展示",
                                     result.winnerResult.sourceId, (long)result.winnerResult.price]
                            loading:NO];
            strongSelf.showAdButton.enabled = YES;
            [strongSelf.showAdButton setTitle:@"展示激励视频" forState:UIControlStateNormal];
        } else {
            [strongSelf updateStatus:@"本次无可用广告" loading:NO];
        }
    }];
}

- (void)showAdButtonTapped
{
    // 第一优先：取走预载结果即取即展示（毫秒级，无拍卖等待）
    ADXAuctionResult *preloaded = [[ADXAdManager sharedManager] takeRewardVideoAdWithSlotName:self.placementId];
    if (preloaded && preloaded.winnerResult) {
        self.auctionResult = preloaded;
        [self showCurrentResult];
        return;
    }

    // 预载未命中（未预载/无填充/已过期被取走）：现场 load 兜底
    if (!self.auctionResult || !self.auctionResult.winnerResult) {
        [self loadAd];
        return;
    }

    [self showCurrentResult];
}

- (void)showCurrentResult
{
    [self updateStatus:@"展示中（失败自动降级次高价候选）..." loading:YES];
    __weak typeof(self) weakSelf = self;
    [[ADXAdManager sharedManager] showRewardVideoAdWithResult:self.auctionResult
                                             fromViewController:self
                                                  rewardCallback:^(BOOL granted) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf updateStatus:granted ? @"激励达成：可以发奖" : @"未达到激励条件（提前关闭）" loading:NO];
    }
                                                      completion:^(BOOL shown, NSString * _Nullable shownSourceId) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (shown) {
            NSString *sourceText = [shownSourceId isEqualToString:strongSelf.auctionResult.winnerResult.sourceId]
                ? @"原赢家" : @"降级候选";
            [strongSelf updateStatus:[NSString stringWithFormat:@"展示成功：%@（%@）", shownSourceId, sourceText] loading:NO];
        } else {
            [strongSelf updateStatus:@"所有候选展示失败" loading:NO];
            strongSelf.auctionResult = nil;
        }
        // 展示结束补一次预载（≈复活后继续玩，下次死亡还有广告可用）
        [[ADXAdManager sharedManager] preloadRewardVideoAdWithSlotName:strongSelf.placementId completion:nil];
    }];
}

@end
