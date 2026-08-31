//
//  ADXConfigManager.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXConfigManager.h"
#import "ADXConfig.h"
#import "ADXConfigParser.h"
#import "ADXLogger.h"

static NSString * const kDiskCacheFileName = @"adx_config.json";
static NSTimeInterval const kRemoteFetchTimeout = 10;

@interface ADXConfigManager ()

@property (nonatomic, strong, nullable) ADXConfig *memoryConfig;
@property (nonatomic, copy, nullable) NSData *cachedRawData;  // 磁盘缓存对应的原始 JSON
@property (nonatomic, assign) BOOL fetchingRemote;  // 防重入标记

@end

@implementation ADXConfigManager

+ (instancetype)sharedManager
{
    static ADXConfigManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ADXConfigManager alloc] init];
    });
    return instance;
}

- (ADXConfig *)currentConfig
{
    @synchronized (self) {
        if (!self.memoryConfig) {
            self.memoryConfig = [self loadBestAvailableConfig];
        }
        return self.memoryConfig;
    }
}

- (nullable ADXSlotConfig *)slotConfigWithName:(NSString *)slotName
{
    return [self.currentConfig slotConfigWithName:slotName];
}

- (BOOL)updateConfig:(ADXConfig *)config
{
    return [self updateConfig:config rawData:nil];
}

/// 用原始 JSON 数据替换当前配置并写盘
///
/// @param config 已解析校验的配置
/// @param rawData 拉取到的原始 JSON 数据；非 nil 时直接写盘（保真，避免模型回转丢字段）
- (BOOL)updateConfig:(ADXConfig *)config rawData:(nullable NSData *)rawData
{
    if (!config) {
        return NO;
    }

    @synchronized (self) {
        // 版本比对：只接受更新的版本
        ADXConfig *current = self.currentConfig;  // 确保基线已加载
        if (config.configVersion <= current.configVersion) {
            ADXLogInfo(@"配置更新忽略：新版本 %ld ≤ 当前版本 %ld",
                       (long)config.configVersion, (long)current.configVersion);
            return NO;
        }

        self.memoryConfig = config;
    }

    // 远程日志开关：配置显式携带 logLevel 时应用（远程排障：下发新版本配置临时点亮日志）
    [self applyLogLevelFromConfig:config];

    [self saveRawDataToDisk:rawData];
    ADXLogInfo(@"配置已更新至版本 %ld（%lu 个广告位）",
               (long)config.configVersion, (unsigned long)config.slots.count);
    return YES;
}

/// 应用配置中的远程日志级别（logLevel < 0 表示配置未设置，不干预）
- (void)applyLogLevelFromConfig:(ADXConfig *)config
{
    if (config.logLevel < 0) {
        return;
    }
    [ADXLogger setLogLevel:(ADXLogLevel)config.logLevel];
    ADXLogInfo(@"远程日志开关：级别已调整为 %ld", (long)config.logLevel);
}

- (void)clearDiskCache
{
    @synchronized (self) {
        self.memoryConfig = nil;
        self.cachedRawData = nil;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self diskCachePath] error:nil];
}

- (void)fetchRemoteConfigWithCompletion:(nullable void (^)(BOOL updated, NSError * _Nullable error))completion
{
    NSURL *url = self.remoteConfigURL;
    if (!url) {
        // 未配置远程地址：跳过（本地三层配置已可用，不视为错误）
        ADXLogInfo(@"远程配置拉取跳过：未配置 remoteConfigURL");
        [self finishFetchOnMainWithUpdated:NO error:nil completion:completion];
        return;
    }

    if (![url.scheme.lowercaseString isEqualToString:@"https"]) {
        NSError *error = [NSError errorWithDomain:@"com.adwinx.config"
                                             code:1001
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"远程配置地址仅支持 HTTPS：%@", url]}];
        ADXLogError(@"远程配置拉取失败：%@", error.localizedDescription);
        [self finishFetchOnMainWithUpdated:NO error:error completion:completion];
        return;
    }

    // 防重入：上一次拉取未结束时直接跳过
    @synchronized (self) {
        if (self.fetchingRemote) {
            ADXLogInfo(@"远程配置拉取跳过：上一次拉取进行中");
            [self finishFetchOnMainWithUpdated:NO error:nil completion:completion];
            return;
        }
        self.fetchingRemote = YES;
    }

    ADXLogInfo(@"远程配置拉取开始（SDK %@，当前版本 %ld）",
               ADXSDKVersion, (long)self.currentConfig.configVersion);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = kRemoteFetchTimeout;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [self handleRemoteResponseWithData:data response:response error:error completion:completion];
    }];
    [task resume];
}

#pragma mark - Private

/// 远程响应统一处理：状态码 → 数据 → 解析校验 → 版本比对落盘
- (void)handleRemoteResponseWithData:(nullable NSData *)data
                            response:(nullable NSURLResponse *)response
                               error:(nullable NSError *)error
                          completion:(nullable void (^)(BOOL updated, NSError * _Nullable error))completion
{
    @synchronized (self) {
        self.fetchingRemote = NO;
    }

    void (^finish)(BOOL, NSError *) = ^(BOOL updated, NSError *finishError) {
        [self finishFetchOnMainWithUpdated:updated error:finishError completion:completion];
    };

    if (error) {
        ADXLogError(@"远程配置拉取失败：网络错误 %@", error.localizedDescription);
        finish(NO, error);
        return;
    }

    NSHTTPURLResponse *httpResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    if (!httpResponse || httpResponse.statusCode != 200) {
        NSInteger statusCode = httpResponse.statusCode;
        NSError *statusError = [NSError errorWithDomain:@"com.adwinx.config"
                                                   code:1002
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                          [NSString stringWithFormat:@"远程配置响应异常：HTTP %ld", (long)statusCode]}];
        ADXLogError(@"%@", statusError.localizedDescription);
        finish(NO, statusError);
        return;
    }

    if (data.length == 0) {
        NSError *emptyError = [NSError errorWithDomain:@"com.adwinx.config"
                                                  code:1003
                                              userInfo:@{NSLocalizedDescriptionKey: @"远程配置响应体为空"}];
        ADXLogError(@"%@", emptyError.localizedDescription);
        finish(NO, emptyError);
        return;
    }

    // Parser 完成结构校验：JSON 合法性、slots 必要字段、逐源 sourceId/adnName/placementId 校验
    ADXConfig *config = [ADXConfigParser parseConfigWithData:data];
    if (!config) {
        NSError *parseError = [NSError errorWithDomain:@"com.adwinx.config"
                                                  code:1004
                                              userInfo:@{NSLocalizedDescriptionKey: @"远程配置校验失败：解析被拒绝"}];
        ADXLogError(@"%@", parseError.localizedDescription);
        finish(NO, parseError);
        return;
    }

    // updateConfig 内部完成版本比对（只升不降）并写磁盘，rawData 保真落盘
    BOOL updated = [self updateConfig:config rawData:data];
    finish(updated, nil);
}

/// 拉取结果统一回主线程
- (void)finishFetchOnMainWithUpdated:(BOOL)updated
                               error:(nullable NSError *)error
                          completion:(nullable void (^)(BOOL updated, NSError * _Nullable error))completion
{
    if (!completion) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(updated, error);
    });
}

/// 三层加载：磁盘缓存与内置兜底比对版本取高者
///
/// 磁盘缓存来自远程下发（updateConfig 保证只升不降）；内置兜底随 SDK 发版更新。
/// 取版本更高的一方：远程下发过新配置则缓存生效，SDK 发版升级内置配置则覆盖旧缓存。
- (ADXConfig *)loadBestAvailableConfig
{
    // 1. 内置兜底（作为版本比对基线）
    ADXConfig *bundledConfig = [ADXConfigParser parseBundledDefaultConfig];

    // 2. 磁盘缓存
    NSData *data = [NSData dataWithContentsOfFile:[self diskCachePath]];
    if (data) {
        ADXConfig *cachedConfig = [ADXConfigParser parseConfigWithData:data];
        if (cachedConfig) {
            if (!bundledConfig || cachedConfig.configVersion >= bundledConfig.configVersion) {
                self.cachedRawData = data;
                [self applyLogLevelFromConfig:cachedConfig];
                ADXLogInfo(@"配置来源：磁盘缓存（版本 %ld）", (long)cachedConfig.configVersion);
                return cachedConfig;
            }
            ADXLogInfo(@"配置来源：内置兜底（版本 %ld > 磁盘缓存版本 %ld，SDK 发版覆盖旧缓存）",
                       (long)bundledConfig.configVersion, (long)cachedConfig.configVersion);
            [self applyLogLevelFromConfig:bundledConfig];
            return bundledConfig;
        }
        // 磁盘数据损坏（Parser 拒绝）：不写回，回退内置兜底
        ADXLogError(@"磁盘缓存损坏，回退内置兜底配置");
    }

    if (bundledConfig) {
        [self applyLogLevelFromConfig:bundledConfig];
        ADXLogInfo(@"配置来源：内置兜底（版本 %ld）", (long)bundledConfig.configVersion);
        return bundledConfig;
    }

    // 3. 全部失败：空配置（请求会因广告位不存在而失败，但不崩溃）
    ADXLogError(@"配置加载失败：磁盘缓存与内置兜底均不可用");
    return [[ADXConfig alloc] init];
}

- (void)saveRawDataToDisk:(nullable NSData *)rawData
{
    if (!rawData) {
        // 无原始数据（如调试构造的配置）则跳过写盘，仅内存生效
        return;
    }

    @synchronized (self) {
        self.cachedRawData = rawData;
    }
    [rawData writeToFile:[self diskCachePath] atomically:YES];
}

- (NSString *)diskCachePath
{
    NSString *cachesDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    return [cachesDirectory stringByAppendingPathComponent:kDiskCacheFileName];
}

@end
