//
//  DHAIManager.m
//  iOSDebugHelper
//

#import "DHAIManager.h"
#import "DHLogManager.h"

static NSString *const kDHAIConfigKey = @"DH_AIConfig";

@implementation DHAIConfig
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:self.apiKey forKey:@"apiKey"];
    [c encodeObject:self.apiURL forKey:@"apiURL"];
    [c encodeObject:self.model forKey:@"model"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    self = [super init];
    if (self) {
        _apiKey = [c decodeObjectOfClass:NSString.class forKey:@"apiKey"] ?: @"";
        _apiURL = [c decodeObjectOfClass:NSString.class forKey:@"apiURL"] ?: @"https://api.deepseek.com/chat/completions";
        _model = [c decodeObjectOfClass:NSString.class forKey:@"model"] ?: @"deepseek-chat";
    }
    return self;
}
@end

@implementation DHAIResult
@end

@implementation DHAIManager

+ (instancetype)sharedManager {
    static DHAIManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [self new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _config = [DHAIConfig new];
        _config.apiURL = @"https://api.deepseek.com/chat/completions";
        _config.model = @"deepseek-chat";
        _config.apiKey = @"";
        [self loadConfig];
    }
    return self;
}

- (void)saveConfig {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.config];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:kDHAIConfigKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)loadConfig {
    NSData *data = [[NSUserDefaults standardUserDefaults] dataForKey:kDHAIConfigKey];
    if (data) {
        id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if ([obj isKindOfClass:[DHAIConfig class]]) self.config = obj;
    }
}

- (void)analyzeClassInfo:(NSString *)classInfo
             completion:(void(^)(DHAIResult * _Nullable, NSError * _Nullable))completion {
    if (!self.config.apiKey.length) {
        NSError *err = [NSError errorWithDomain:@"DHAI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"请先配置 DeepSeek API Key"}];
        completion(nil, err);
        return;
    }

    NSString *systemPrompt = @"你是一个专业的 iOS 逆向工程助手。分析给定的 Objective-C 类信息，找出最可能是 VIP、广告或内购相关的 Hook 目标。返回 JSON 格式：{\"report\":\"分析报告\",\"code\":\"Logos代码\",\"hooks\":[{\"selector\":\"isVip\",\"action\":\"return_true\",\"reason\":\"开启VIP\"}]}";

    NSDictionary *body = @{
        @"model": self.config.model,
        @"messages": @[
            @{@"role": @"system", @"content": systemPrompt},
            @{@"role": @"user", @"content": classInfo},
        ],
        @"temperature": @0.3,
    };

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:self.config.apiURL]];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", self.config.apiKey] forHTTPHeaderField:@"Authorization"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSError *jsonErr;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr) { completion(nil, jsonErr); return; }

        NSString *content = json[@"choices"][0][@"message"][@"content"];
        DHAIResult *result = [DHAIResult new];
        // 尝试解析 JSON 内容
        NSData *contentData = [content dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:contentData options:0 error:nil];
        if (parsed) {
            result.report = parsed[@"report"] ?: @"";
            result.logosCode = parsed[@"code"] ?: @"";
            result.suggestedHooks = parsed[@"hooks"] ?: @[];
        } else {
            result.report = content;
            result.logosCode = @"";
            result.suggestedHooks = @[];
        }
        DHLogInfo(@"AI分析完成，返回 %lu 条建议Hook", (unsigned long)result.suggestedHooks.count);
        completion(result, nil);
    }];
    [task resume];
}

@end
