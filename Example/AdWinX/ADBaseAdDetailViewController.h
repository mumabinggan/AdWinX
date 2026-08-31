//
//  ADBaseAdDetailViewController.h
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import <UIKit/UIKit.h>

@interface ADBaseAdDetailViewController : UIViewController

@property (nonatomic, copy) NSString *platformName;
@property (nonatomic, copy) NSString *appId;
@property (nonatomic, copy) NSString *adTypeName;
@property (nonatomic, copy) NSString *sdkClassName;
@property (nonatomic, copy) NSString *adDescription;
@property (nonatomic, copy) NSString *placementId;
@property (nonatomic, strong) UIButton *showAdButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *adContainerView;

- (instancetype)initWithAdGroup:(NSDictionary<NSString *, id> *)adGroup adItem:(NSDictionary<NSString *, NSString *> *)adItem;
- (void)showAdButtonTapped;
- (void)loadAd;
- (void)updateStatus:(NSString *)status loading:(BOOL)loading;
- (void)clearAdContainer;
- (UIWindow *)adPresentationWindow;
- (NSString *)statusTextForError:(NSError *)error prefix:(NSString *)prefix;

@end
