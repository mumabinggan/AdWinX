//
//  ADXAdapterRegistry.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXAdapterRegistry.h"

static NSMutableDictionary<NSString *, Class> *_adapterClasses;

/// 复合键：adnName|adType（如 "GDT|0"），同一 ADN 可注册多种广告类型的 Adapter
static NSString *ADXAdapterRegistryKey(NSString *adnName, ADXAdType adType)
{
    return [NSString stringWithFormat:@"%@|%ld", adnName, (long)adType];
}

@implementation ADXAdapterRegistry

+ (void)initialize
{
    if (self == [ADXAdapterRegistry class]) {
        _adapterClasses = [NSMutableDictionary dictionary];
    }
}

+ (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName
{
    // 兼容入口：旧 API 仅用于开屏（历史上只有开屏 Adapter）
    [self registerAdapterClass:adapterClass forAdnName:adnName adType:ADXAdTypeSplash];
}

+ (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName adType:(ADXAdType)adType
{
    @synchronized (_adapterClasses) {
        _adapterClasses[ADXAdapterRegistryKey(adnName, adType)] = adapterClass;
    }
}

+ (BOOL)hasRegisteredAdapterForAdnName:(NSString *)adnName adType:(ADXAdType)adType
{
    @synchronized (_adapterClasses) {
        return _adapterClasses[ADXAdapterRegistryKey(adnName, adType)] != nil;
    }
}

+ (nullable id<ADXAdapter>)adapterForSourceInfo:(ADXAdSourceInfo *)sourceInfo
{
    Class adapterClass;
    @synchronized (_adapterClasses) {
        adapterClass = _adapterClasses[ADXAdapterRegistryKey(sourceInfo.adnName, sourceInfo.adType)];
    }

    if (!adapterClass) {
        return nil;
    }
    return [[adapterClass alloc] init];
}

+ (NSDictionary<NSString *, Class> *)allRegisteredAdapterClasses
{
    // 按 adnName 去重：同一 ADN 的开屏/激励视频等 Adapter 只保留一个类做 SDK 初始化
    // （各 Adapter 的 +setupSDKWithConfig: 内部均有静态去重，初始化语义一致）
    NSMutableDictionary<NSString *, Class> *deduped = [NSMutableDictionary dictionary];
    @synchronized (_adapterClasses) {
        [_adapterClasses enumerateKeysAndObjectsUsingBlock:^(NSString *key, Class adapterClass, BOOL *stop) {
            NSString *adnName = [key substringToIndex:[key rangeOfString:@"|"].location];
            if (!deduped[adnName]) {
                deduped[adnName] = adapterClass;
            }
        }];
    }
    return [deduped copy];
}

@end
