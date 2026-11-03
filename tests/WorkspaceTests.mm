#import "../src/Workspace.h"
#include <cstdio>

static void Check(BOOL condition, const char *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message); exit(1); }
}
int main(void) {
  @autoreleasepool {
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *url=[root URLByAppendingPathComponent:@"workspace.json"];
    Workspace *s=[[Workspace alloc] initWithURL:url];
    Check([s validate:nil],"default workspace is valid");
    Check(s.spaces.count==3 && s.profiles.count==2,"three spaces, two underlying profiles");
    Check([s.spaces[0][@"profileID"] isEqual:s.spaces[1][@"profileID"]],"personal/focus share a profile");
    Check(![s.spaces[0][@"profileID"] isEqual:s.spaces[2][@"profileID"]],"work has isolated storage");
    NSString *space=s.spaces[0][@"id"];
    NSMutableDictionary *tab=[s addTab:@"https://example.com" space:space]; NSString *identifier=tab[@"id"];
    tab[@"pinned"]=@YES; [s.data[@"splitTabs"] setArray:@[identifier,[s tabsIn:space][0][@"id"]]];
    Check([s save],"save with split references");
    Workspace *reopened=[[Workspace alloc] initWithURL:url];
    Check([[reopened tab:identifier][@"pinned"] boolValue],"pin survives restart");
    Check([reopened.data[@"splitTabs"] count]==2,"split layout survives restart");
    [reopened archive:identifier]; Check(![reopened tab:identifier],"archived tab is not active");
    Check(![reopened.data[@"splitTabs"] containsObject:identifier],"archive cleans split references");
    Check([[reopened restoreLastArchived][@"id"] isEqual:identifier],"restore preserves logical identity");
    Check([reopened save],"restored tab saves");
    [reopened archive:identifier];
    NSArray *all=[[reopened tabsIn:space] copy]; for (NSDictionary *t in all) [reopened archive:t[@"id"]];
    Check([reopened tabsIn:space].count==1,"closing final tab creates one home tab");
    Check([reopened save],"save replacement home tab");
    [@"broken JSON" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    Workspace *recovered=[[Workspace alloc] initWithURL:url];
    Check([recovered validate:nil],"recover last valid snapshot after corrupt file");
    Check([NSFileManager.defaultManager fileExistsAtPath:[url URLByAppendingPathExtension:@"recovery"].path],"corrupt original preserved");
    [recovered.data[@"tabs"] addObject:[@{@"id":@"bad",@"url":@"https://example.com",@"title":@"bad",@"spaceID":@"missing"} mutableCopy]];
    Check(![recovered save],"dangling references never overwrite disk");
    Check([[Workspace normalizedURL:@"example.com"] isEqual:@"https://example.com"],"domain resolution");
    Check([[Workspace normalizedURL:@"localhost:8765"] isEqual:@"http://localhost:8765"],"local development URLs");
    Check([[Workspace normalizedURL:@"hello & world"] containsString:@"hello%20%26%20world"],"search text escaped");
    Check([[Workspace normalizedURL:@"javascript:alert(1)"] hasPrefix:@"https://www.google.com/search"],"command input cannot execute javascript");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("PASS: workspace persistence, profile mapping, archive recovery, corruption fallback, validation, URL handling");
  }
}
