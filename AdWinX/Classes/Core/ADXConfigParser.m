//
//  ADXConfigParser.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXConfigParser.h"
#import "ADXConfig.h"
#import "ADXSlotConfig.h"
#import "ADXAdSourceInfo.h"
#import "ADXLogger.h"

NSString * const ADXConfigResourceBundleName = @"AdWinX";
NSString * const ADXConfigDefaultFileName = @"adx_default_config";

@implementation ADXConfigParser

+ (nullable ADXConfig *)parseConfigWithData:(NSData *)data
{
    if (!data) {
        return nil;
    }

    NSError *jsonError = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:data
                                                    options:0
                                                      error:&jsonError];
    if (jsonError || ![jsonObject isKindOfClass:[NSDictionary class]]) {
        ADXLogError(@"配置解析失败：JSON 结构非法，error: %@", jsonError);
        return nil;
    }

    NSDictionary *root = jsonObject;
    ADXConfig *config = [[ADXConfig alloc] init];
    config.configVersion = [root[@"configVersion"] integerValue];

    // 远程日志开关（可选）：仅接受 0~3 合法值，越界/缺失保持 -1（不干预本地默认）
    NSInteger logLevel = [root[@"logLevel"] integerValue];
    if (logLevel >= 0 && logLevel <= 3) {
        config.logLevel = logLevel;
    }

    // 应用级 ADN 配置
    NSDictionary *adnApps = root[@"adnApps"];
    if ([adnApps isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
        [adnApps enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            if ([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSDictionary class]]) {
                parsed[key] = obj;
            }
        }];
        config.adnApps = parsed;
    }

    // 广告位配置
    NSArray *slots = root[@"slots"];
    if (![slots isKindOfClass:[NSArray class]]) {
        // slots 是必要字段，缺失则整体视为非法
        ADXLogError(@"配置解析失败：缺少 slots 字段");
        return nil;
    }

    NSMutableArray *parsedSlots = [NSMutableArray array];
    for (id slotObj in slots) {
        ADXSlotConfig *slot = [self parseSlotWithDictionary:slotObj];
        if (slot) {
            [parsedSlots addObject:slot];
        }
    }

    if (parsedSlots.count == 0) {
        ADXLogError(@"配置解析失败：无有效广告位");
        return nil;
    }

    config.slots = parsedSlots;
    return config;
}

+ (nullable ADXConfig *)parseBundledDefaultConfig
{
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *fileURL = [bundle URLForResource:ADXConfigDefaultFileName
                              withExtension:@"json"
                               subdirectory:[NSString stringWithFormat:@"%@.bundle", ADXConfigResourceBundleName]];
    if (!fileURL) {
        ADXLogError(@"内置兜底配置不存在：%@.bundle/%@.json",
                    ADXConfigResourceBundleName, ADXConfigDefaultFileName);
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    return [self parseConfigWithData:data];
}

#pragma mark - Private

/// 解析单个广告位，字段非法返回 nil（跳过该条）
+ (nullable ADXSlotConfig *)parseSlotWithDictionary:(id)slotObj
{
    if (![slotObj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = slotObj;

    NSString *slotName = dict[@"slotName"];
    if (![slotName isKindOfClass:[NSString class]] || slotName.length == 0) {
        ADXLogError(@"广告位配置跳过：slotName 缺失或非法");
        return nil;
    }

    ADXAdType adType = ADXAdTypeSplash;
    NSString *adTypeString = dict[@"adType"];
    if ([adTypeString isKindOfClass:[NSString class]]) {
        adType = [self adTypeFromString:adTypeString];
    }

    ADXSlotConfig *slot = [[ADXSlotConfig alloc] init];
    slot.slotName = slotName;
    slot.adType = adType;
    slot.bidTimeout = [dict[@"bidTimeout"] doubleValue] > 0 ? [dict[@"bidTimeout"] doubleValue] : 5;
    slot.totalTimeout = [dict[@"totalTimeout"] doubleValue] > 0 ? [dict[@"totalTimeout"] doubleValue] : 5;
    slot.waterfallTimeout = [dict[@"waterfallTimeout"] doubleValue] > 0 ? [dict[@"waterfallTimeout"] doubleValue] : 5;

    NSArray *adSources = dict[@"adSources"];
    if (![adSources isKindOfClass:[NSArray class]]) {
        ADXLogError(@"广告位 %@ 跳过：缺少 adSources", slotName);
        return nil;
    }

    NSMutableArray *parsedSources = [NSMutableArray array];
    for (id sourceObj in adSources) {
        ADXAdSourceInfo *source = [self parseAdSourceWithDictionary:sourceObj adType:adType];
        if (source) {
            [parsedSources addObject:source];
        }
    }

    if (parsedSources.count == 0) {
        ADXLogError(@"广告位 %@ 跳过：无有效广告源", slotName);
        return nil;
    }

    slot.adSources = parsedSources;
    return slot;
}

/// 解析单个广告源，字段非法返回 nil（跳过该条）
+ (nullable ADXAdSourceInfo *)parseAdSourceWithDictionary:(id)sourceObj adType:(ADXAdType)adType
{
    if (![sourceObj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = sourceObj;

    NSString *sourceId = dict[@"sourceId"];
    NSString *adnName = dict[@"adnName"];
    NSString *placementId = dict[@"placementId"];
    if (![sourceId isKindOfClass:[NSString class]] || sourceId.length == 0 ||
        ![adnName isKindOfClass:[NSString class]] || adnName.length == 0 ||
        ![placementId isKindOfClass:[NSString class]] || placementId.length == 0) {
        ADXLogError(@"广告源配置跳过：sourceId/adnName/placementId 缺失或非法");
        return nil;
    }

    ADXRuntimeMode runtimeMode = ADXRuntimeModeWaterfall;
    NSString *modeString = dict[@"runtimeMode"];
    if ([modeString isKindOfClass:[NSString class]]) {
        runtimeMode = [modeString isEqualToString:@"bidding"] ? ADXRuntimeModeBidding : ADXRuntimeModeWaterfall;
    }

    NSInteger floorEcpm = [dict[@"floorEcpm"] integerValue];
    NSTimeInterval timeout = [dict[@"timeout"] doubleValue] > 0 ? [dict[@"timeout"] doubleValue] : 5;

    // appId 允许缺失（应用级 adnApps 可覆盖），此处先置空串
    NSString *appId = [dict[@"appId"] isKindOfClass:[NSString class]] ? dict[@"appId"] : @"";

    ADXAdSourceInfo *source = [ADXAdSourceInfo sourceWithId:sourceId
                                                        adn:adnName
                                                       mode:runtimeMode
                                                     adType:adType
                                                 floorEcpm:floorEcpm
                                                   realEcpm:floorEcpm   // 初始值 = floorEcpm，下方按需覆盖
                                                    timeout:timeout
                                                placementId:placementId
                                                      appId:appId
                                                extraParams:nil];

    // 优先级：数值越大越高，缺省 0
    source.priority = [dict[@"priority"] integerValue];
    // realEcpm：服务端下发的编排用统计值，缺省回落 floorEcpm（初期无数据形态）
    NSInteger configRealEcpm = [dict[@"realEcpm"] integerValue];
    if (configRealEcpm > 0) {
        source.realEcpm = configRealEcpm;
    }

    return source;
}

+ (ADXAdType)adTypeFromString:(NSString *)string
{
    if ([string isEqualToString:@"reward_video"]) {
        return ADXAdTypeRewardVideo;
    }
    if ([string isEqualToString:@"interstitial"]) {
        return ADXAdTypeInterstitial;
    }
    if ([string isEqualToString:@"banner"]) {
        return ADXAdTypeBanner;
    }
    if ([string isEqualToString:@"native_express"]) {
        return ADXAdTypeNativeExpress;
    }
    return ADXAdTypeSplash;  // "splash" 及未知值兜底
}

@end
