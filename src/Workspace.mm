#import "Workspace.h"

static NSString *NewID(void) { return NSUUID.UUID.UUIDString; }
static NSMutableDictionary *MutableCopy(id value) {
  NSData *bytes = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
  return [NSJSONSerialization JSONObjectWithData:bytes options:NSJSONReadingMutableContainers error:nil];
}
@interface Workspace ()
@property(nonatomic) NSMutableDictionary *data;
@property(nonatomic) NSURL *fileURL;
@property(nonatomic, nullable) NSError *lastError;
@end

@implementation Workspace
- (instancetype)initWithURL:(NSURL *)url {
  if (!(self = [super init])) return nil;
  _fileURL = url;
  NSData *bytes = [NSData dataWithContentsOfURL:url];
  if (!bytes && [NSFileManager.defaultManager fileExistsAtPath:url.path]) {
    @throw [NSException exceptionWithName:@"WorkspaceRecoveryRequired" reason:@"The workspace file exists but could not be read. Check its permissions; Aelo has not replaced it." userInfo:nil];
  }
  if (bytes) {
    NSError *readError=nil;
    _data = [NSJSONSerialization JSONObjectWithData:bytes options:NSJSONReadingMutableContainers error:&readError];
    _lastError=readError;
    if (![self validate:&readError]) {
      _lastError=readError;
      // Never overwrite a file we could not interpret. Recover the last valid snapshot.
      NSURL *backup = [url URLByAppendingPathExtension:@"backup"];
      NSData *prior = [NSData dataWithContentsOfURL:backup];
      _data = prior ? [NSJSONSerialization JSONObjectWithData:prior options:NSJSONReadingMutableContainers error:nil] : nil;
      if (![self validate:nil]) {
        @throw [NSException exceptionWithName:@"WorkspaceRecoveryRequired"
                                      reason:@"Your workspace could not be read. The original file is preserved; restore a valid backup before opening Aelo."
                                    userInfo:nil];
      }
      // The original invalid file remains available for recovery.
      [bytes writeToURL:[url URLByAppendingPathExtension:@"recovery"] options:NSDataWritingAtomic error:nil];
    }
  } else {
    _data = [@{@"version":@1, @"profiles":[NSMutableArray array], @"spaces":[NSMutableArray array],
               @"tabs":[NSMutableArray array], @"archive":[NSMutableArray array], @"splitTabs":[NSMutableArray array]} mutableCopy];
    [_data[@"profiles"] addObject:[@{@"id":@"default", @"name":@"Default"} mutableCopy]];
    [self addSpace:@"Personal" isolated:NO];
    [self addSpace:@"Focus" isolated:NO];
    [self addSpace:@"Work" isolated:YES];
    _data[@"activeSpace"] = self.spaces.firstObject[@"id"];
    [self save];
  }
  return self;
}
- (NSArray *)spaces { return _data[@"spaces"]; }
- (NSArray *)profiles { return _data[@"profiles"]; }
- (NSMutableDictionary *)space:(NSString *)identifier {
  for (NSMutableDictionary *s in self.spaces) if ([s[@"id"] isEqual:identifier]) return s;
  return nil;
}
- (NSMutableDictionary *)tab:(NSString *)identifier {
  for (NSMutableDictionary *t in _data[@"tabs"]) if ([t[@"id"] isEqual:identifier]) return t;
  return nil;
}
- (NSArray *)tabsIn:(NSString *)space {
  return [_data[@"tabs"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id t, NSDictionary *_) {
    return [t[@"spaceID"] isEqual:space];
  }]];
}
- (NSMutableDictionary *)addTab:(NSString *)url space:(NSString *)space {
  NSParameterAssert([self space:space]);
  NSMutableDictionary *tab = [@{@"id":NewID(), @"spaceID":space, @"url":url,
    @"title":[url isEqual:@"aelo://home"] ? @"New Tab" : url, @"pinned":@NO,
    @"created":@([NSDate timeIntervalSinceReferenceDate]), @"lastActive":@([NSDate timeIntervalSinceReferenceDate])} mutableCopy];
  [_data[@"tabs"] addObject:tab];
  [self activate:tab[@"id"]];
  return tab;
}
- (NSMutableDictionary *)addSpace:(NSString *)name isolated:(BOOL)isolated {
  NSString *profile = @"default";
  if (isolated) {
    profile = NewID();
    [_data[@"profiles"] addObject:[@{@"id":profile, @"name":name} mutableCopy]];
  }
  NSMutableDictionary *space = [@{@"id":NewID(), @"name":name, @"profileID":profile,
    @"theme":@([self.spaces count] % 4)} mutableCopy];
  [_data[@"spaces"] addObject:space];
  [self addTab:@"aelo://home" space:space[@"id"]];
  return space;
}
- (void)activate:(NSString *)identifier {
  NSMutableDictionary *tab = [self tab:identifier];
  if (!tab) return;
  _data[@"activeSpace"] = tab[@"spaceID"];
  [self space:tab[@"spaceID"]][@"activeTab"] = identifier;
  tab[@"lastActive"] = @([NSDate timeIntervalSinceReferenceDate]);
}
- (void)archive:(NSString *)identifier {
  NSMutableDictionary *tab = [self tab:identifier];
  if (!tab) return;
  NSString *spaceID = tab[@"spaceID"];
  NSMutableDictionary *archived = MutableCopy(tab);
  archived[@"archivedAt"] = @([NSDate timeIntervalSinceReferenceDate]);
  [_data[@"archive"] addObject:archived];
  [_data[@"tabs"] removeObject:tab];
  [_data[@"splitTabs"] removeObject:identifier];
  NSArray *remaining = [self tabsIn:spaceID];
  if (!remaining.count) [self addTab:@"aelo://home" space:spaceID];
  else if ([[self space:spaceID][@"activeTab"] isEqual:identifier]) [self space:spaceID][@"activeTab"] = remaining.firstObject[@"id"];
}
- (NSMutableDictionary *)restoreLastArchived {
  NSMutableDictionary *tab = [_data[@"archive"] lastObject];
  if (!tab) return nil;
  [_data[@"archive"] removeLastObject];
  [tab removeObjectForKey:@"archivedAt"];
  [_data[@"tabs"] addObject:tab];
  [self activate:tab[@"id"]];
  return tab;
}
- (BOOL)validate:(NSError **)error {
  BOOL valid = [_data isKindOfClass:NSDictionary.class] && [_data[@"version"] isEqual:@1];
  for (NSString *key in @[@"spaces",@"profiles",@"tabs",@"archive",@"splitTabs"])
    valid = valid && [_data[key] isKindOfClass:NSArray.class];
  if (valid) {
    NSMutableSet *profiles = [NSMutableSet set], *spaces = [NSMutableSet set], *tabs = [NSMutableSet set];
    for (id p in _data[@"profiles"]) {
      if (![p isKindOfClass:NSDictionary.class] || ![p[@"id"] isKindOfClass:NSString.class] || [profiles containsObject:p[@"id"]]) { valid=NO; break; }
      [profiles addObject:p[@"id"]];
    }
    for (id s in _data[@"spaces"]) {
      if (![s isKindOfClass:NSDictionary.class] || ![s[@"id"] isKindOfClass:NSString.class] || ![s[@"name"] isKindOfClass:NSString.class] || ![profiles containsObject:s[@"profileID"]] || [spaces containsObject:s[@"id"]]) { valid=NO; break; }
      [spaces addObject:s[@"id"]];
    }
    for (id t in _data[@"tabs"]) {
      if (![t isKindOfClass:NSDictionary.class] || ![t[@"id"] isKindOfClass:NSString.class] || ![t[@"url"] isKindOfClass:NSString.class] || ![t[@"title"] isKindOfClass:NSString.class] || ![spaces containsObject:t[@"spaceID"]] || [tabs containsObject:t[@"id"]]) { valid=NO; break; }
      [tabs addObject:t[@"id"]];
    }
    for (id t in _data[@"archive"]) {
      if (![t isKindOfClass:NSDictionary.class] || ![t[@"id"] isKindOfClass:NSString.class] || ![t[@"url"] isKindOfClass:NSString.class] || ![t[@"title"] isKindOfClass:NSString.class] || ![spaces containsObject:t[@"spaceID"]] || [tabs containsObject:t[@"id"]]) { valid=NO; break; }
      [tabs addObject:t[@"id"]];
    }
    valid = valid && self.spaces.count>0 && [spaces containsObject:_data[@"activeSpace"]];
    for (id s in self.spaces) {
      id active = s[@"activeTab"];
      valid = valid && [active isKindOfClass:NSString.class] && [[self tab:active][@"spaceID"] isEqual:s[@"id"]];
    }
    for (id identifier in _data[@"splitTabs"]) valid = valid && [self tab:identifier]!=nil;
  }
  if (!valid && error) *error = [NSError errorWithDomain:@"AeloWorkspace" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The workspace has invalid references or an unsupported format."}];
  return valid;
}
- (BOOL)save {
  NSError *error = nil;
  if (![self validate:&error]) { _lastError = error; return NO; }
  NSData *bytes = [NSJSONSerialization dataWithJSONObject:_data options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
  NSFileManager *fm = NSFileManager.defaultManager;
  if (![fm createDirectoryAtURL:_fileURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) { _lastError=error; return NO; }
  NSData *previous = [NSData dataWithContentsOfURL:_fileURL];
  if (previous) {
    id old = _data;
    _data = [NSJSONSerialization JSONObjectWithData:previous options:NSJSONReadingMutableContainers error:nil];
    BOOL priorValid = [self validate:nil];
    _data = old;
    if (priorValid && ![previous writeToURL:[_fileURL URLByAppendingPathExtension:@"backup"] options:NSDataWritingAtomic error:&error]) { _lastError=error; return NO; }
  }
  BOOL ok = [bytes writeToURL:_fileURL options:NSDataWritingAtomic error:&error];
  if (ok) [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:_fileURL.path error:nil];
  _lastError = error;
  return ok;
}
+ (NSString *)normalizedURL:(NSString *)input {
  NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!s.length) return @"aelo://home";
  if ([s isEqual:@"aelo://home"]) return s;
  NSURLComponents *parts = [NSURLComponents componentsWithString:s];
  if ([@[@"https",@"http",@"chrome",@"about"] containsObject:parts.scheme.lowercaseString]) return s;
  // All other schemes are treated as search text, never executed as scripts or local files.
  if (![s containsString:@" "] && ![s containsString:@"://"] && ([s containsString:@"."] || [s hasPrefix:@"localhost"] || [s hasPrefix:@"127.0.0.1"]))
    return [([s hasPrefix:@"localhost"] || [s hasPrefix:@"127.0.0.1"]) ? @"http://" : @"https://" stringByAppendingString:s];
  NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  return [@"https://www.google.com/search?q=" stringByAppendingString:[s stringByAddingPercentEncodingWithAllowedCharacters:safe]];
}
@end
