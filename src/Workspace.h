#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Workspace organization is independent of the browser engine's profile data.
@interface Workspace : NSObject
@property(nonatomic, readonly) NSMutableDictionary *data;
@property(nonatomic, readonly) NSURL *fileURL;
@property(nonatomic, readonly, nullable) NSError *lastError;
- (instancetype)initWithURL:(NSURL *)url;
- (NSArray<NSMutableDictionary *> *)spaces;
- (NSArray<NSMutableDictionary *> *)profiles;
- (nullable NSMutableDictionary *)space:(NSString *)identifier;
- (nullable NSMutableDictionary *)tab:(NSString *)identifier;
- (NSArray<NSMutableDictionary *> *)tabsIn:(NSString *)space;
- (NSMutableDictionary *)addTab:(NSString *)url space:(NSString *)space;
- (NSMutableDictionary *)addSpace:(NSString *)name isolated:(BOOL)isolated;
- (void)archive:(NSString *)identifier;
- (nullable NSMutableDictionary *)restoreLastArchived;
- (void)activate:(NSString *)identifier;
- (BOOL)save;
- (BOOL)validate:(NSError **)error;
+ (NSString *)normalizedURL:(NSString *)input;
@end
NS_ASSUME_NONNULL_END
