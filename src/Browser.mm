#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "Workspace.h"
#include <map>
#include <string>
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_parser.h"
#include "include/wrapper/cef_library_loader.h"

static NSString *NS(const CefString &s) { return [NSString stringWithUTF8String:s.ToString().c_str()] ?: @""; }
static CefString CS(NSString *s) { return CefString(s.UTF8String ?: ""); }
static NSString *DataURL(NSString *html) {
  return [@"data:text/html;base64," stringByAppendingString:[[html dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
}
static NSColor *Ink(void) { return [NSColor colorWithSRGBRed:.18 green:.20 blue:.27 alpha:1]; }
static NSColor *Accent(void) { return [NSColor colorWithSRGBRed:.34 green:.36 blue:.72 alpha:1]; }

@class OrbitDelegate;
static OrbitDelegate *gApp;

@interface BrowserSession : NSObject {
@public
  CefRefPtr<CefBrowser> browser;
  CefRefPtr<CefClient> client;
}
@property(nonatomic) NSView *container;
@property(nonatomic) BOOL closing;
@property(nonatomic) BOOL archivePending;
@end
@implementation BrowserSession
@end

@interface OrbitDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSSplitViewDelegate>
@property(nonatomic) Workspace *store;
@property(nonatomic) NSWindow *window;
@property(nonatomic) NSView *sidebar;
@property(nonatomic) NSTableView *tabs;
@property(nonatomic) NSPopUpButton *spacePicker;
@property(nonatomic) NSButton *address;
@property(nonatomic) NSButton *backButton;
@property(nonatomic) NSButton *forwardButton;
@property(nonatomic) NSButton *reloadButton;
@property(nonatomic) NSButton *splitButton;
@property(nonatomic) NSButton *profileButton;
@property(nonatomic) NSProgressIndicator *progress;
@property(nonatomic) NSTextField *status;
@property(nonatomic) NSSplitView *split;
@property(nonatomic) NSPanel *commandPanel;
@property(nonatomic) NSTextField *commandInput;
@property(nonatomic) NSTableView *suggestions;
@property(nonatomic) NSArray<NSDictionary *> *commandResults;
@property(nonatomic) NSMutableDictionary<NSString *, BrowserSession *> *sessions;
@property(nonatomic) NSArray<NSDictionary *> *rows;
@property(nonatomic) NSMutableArray<NSButton *> *spaceButtons;
@property(nonatomic) NSMutableArray<NSView *> *sidebarControls;
@property(nonatomic) NSTimer *saveTimer;
@property(nonatomic) NSString *focusedTab;
@property(nonatomic) NSString *storageRoot;
@property(nonatomic) BOOL quitting;
@property(nonatomic) BOOL refreshing;
- (void)setup;
- (void)layout;
- (void)refresh;
- (void)newTab:(id)sender;
- (void)command:(id)sender;
- (void)quit:(id)sender;
- (void)didCreate:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier;
- (void)didClose:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier;
- (void)allowClose:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier;
- (void)cancelClose:(NSString *)identifier;
- (void)didNavigate:(NSString *)url title:(NSString *)title tab:(NSString *)identifier;
- (void)didLoad:(BOOL)loading back:(BOOL)back forward:(BOOL)forward tab:(NSString *)identifier;
- (void)focusTab:(NSString *)identifier;
- (void)loadFailure:(NSString *)message tab:(NSString *)identifier;
@end

static std::map<std::string,CefRefPtr<CefRequestContext>> contexts;
static std::map<int,CefRefPtr<CefBrowser>> liveBrowsers;

class OrbitClient final : public CefClient, public CefLifeSpanHandler,
                          public CefDisplayHandler, public CefLoadHandler,
                          public CefFocusHandler, public CefDownloadHandler, public CefJSDialogHandler {
 public:
  explicit OrbitClient(NSString *identifier) : identifier_(identifier.UTF8String) {}
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    liveBrowsers[browser->GetIdentifier()] = browser;
    if (!browser->IsPopup()) [gApp didCreate:browser tab:ID()];
  }
  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    if (browser->IsPopup()) return false;
    [gApp allowClose:browser tab:ID()];
    return true;
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser> browser, const CefString &message, bool reload, CefRefPtr<CefJSDialogCallback> callback) override {
    NSAlert *alert=[[NSAlert alloc] init]; alert.messageText=@"Leave this page?";
    alert.informativeText=@"Changes you made on this page may not be saved.";
    [alert addButtonWithTitle:@"Stay on page"]; [alert addButtonWithTitle:@"Leave page"];
    NSString *identifier=ID();
    [alert beginSheetModalForWindow:gApp.window completionHandler:^(NSModalResponse response) {
      BOOL leave=response==NSAlertSecondButtonReturn;
      if (!leave) [gApp cancelClose:identifier];
      callback->Continue(leave,CefString());
    }];
    return true;
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    liveBrowsers.erase(browser->GetIdentifier());
    if (!browser->IsPopup()) [gApp didClose:browser tab:ID()];
    if (gApp.quitting && liveBrowsers.empty()) CefQuitMessageLoop();
  }
  void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
    if (!browser->IsPopup()) [gApp didNavigate:@"" title:NS(title) tab:ID()];
  }
  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString &url) override {
    if (frame->IsMain() && !browser->IsPopup()) [gApp didNavigate:NS(url) title:@"" tab:ID()];
  }
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool loading, bool back, bool forward) override {
    if (!browser->IsPopup()) [gApp didLoad:loading back:back forward:forward tab:ID()];
  }
  void OnGotFocus(CefRefPtr<CefBrowser> browser) override {
    if (!browser->IsPopup()) [gApp focusTab:ID()];
  }
  void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                   ErrorCode code, const CefString &text, const CefString &url) override {
    if (code != ERR_ABORTED && frame->IsMain() && !browser->IsPopup())
      [gApp loadFailure:[NSString stringWithFormat:@"Couldn’t load this page · %@ (%d)", NS(text), (int)code] tab:ID()];
  }
  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                        const CefString &name, CefRefPtr<CefBeforeDownloadCallback> callback) override {
    callback->Continue(CS([NSHomeDirectory() stringByAppendingPathComponent:[@"Downloads" stringByAppendingPathComponent:NS(name).lastPathComponent]]), true);
    return true;
  }
  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDownloadItem> item,
                          CefRefPtr<CefDownloadItemCallback> callback) override {
    if (item->IsComplete()) gApp.status.stringValue = [@"Downloaded · " stringByAppendingString:NS(item->GetFullPath()).lastPathComponent];
    else if (item->IsInProgress()) gApp.status.stringValue = [NSString stringWithFormat:@"Downloading · %d%%", item->GetPercentComplete()];
  }
 private:
  NSString *ID() { return [NSString stringWithUTF8String:identifier_.c_str()]; }
  const std::string identifier_;
  IMPLEMENT_REFCOUNTING(OrbitClient);
  DISALLOW_COPY_AND_ASSIGN(OrbitClient);
};

class OrbitCEFApp final : public CefApp {
 public:
  void OnBeforeCommandLineProcessing(const CefString &process_type, CefRefPtr<CefCommandLine> command_line) override {
    // Automation is opt-in and uses only a disposable data directory in tests.
    const char *port = getenv("ORBIT_TEST_DEBUG_PORT");
    if (port && getenv("ORBIT_DATA_DIR")) command_line->AppendSwitchWithValue("remote-debugging-port", port);
  }
 private:
  IMPLEMENT_REFCOUNTING(OrbitCEFApp);
};

@interface OrbitApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation OrbitApplication
- (BOOL)isHandlingSendEvent { return _handlingSendEvent; }
- (void)sendEvent:(NSEvent *)event {
  CefScopedSendingEvent scope;
  [super sendEvent:event];
}
- (void)terminate:(id)sender { [gApp quit:sender]; }
@end

@interface SidebarView : NSView
@end
@implementation SidebarView
- (void)drawRect:(NSRect)dirtyRect {
  NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
    [NSColor colorWithSRGBRed:.87 green:.88 blue:.94 alpha:1],
    [NSColor colorWithSRGBRed:.93 green:.92 blue:.95 alpha:1],
    [NSColor colorWithSRGBRed:.87 green:.91 blue:.94 alpha:1]]];
  [gradient drawInRect:self.bounds angle:65];
}
@end

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
  NSTextField *label = [NSTextField labelWithString:text];
  label.font = [NSFont systemFontOfSize:size weight:weight]; label.textColor = Ink();
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  return label;
}
static NSButton *Button(NSString *title, NSString *symbol, id target, SEL action) {
  NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
  b.bordered = NO; b.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]; b.contentTintColor=Ink();
  if (symbol.length) { b.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title]; b.imagePosition=NSImageOnly; b.toolTip=title; [b setAccessibilityLabel:title]; }
  return b;
}

@implementation OrbitDelegate
- (NSString *)activeSpace { return self.store.data[@"activeSpace"]; }
- (NSString *)activeTab { return self.focusedTab ?: [self.store space:self.activeSpace][@"activeTab"]; }
- (NSMutableDictionary *)activeRecord { return [self.store tab:self.activeTab]; }
- (BOOL)persist {
  BOOL ok=[self.store save];
  if (!ok) { self.status.stringValue=@"Workspace couldn’t be saved · check free disk space"; NSLog(@"Workspace save failed: %@",self.store.lastError); }
  return ok;
}
- (void)setup {
  self.sessions=[NSMutableDictionary dictionary]; self.spaceButtons=[NSMutableArray array]; self.sidebarControls=[NSMutableArray array];
  self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1280,820)
    styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView
    backing:NSBackingStoreBuffered defer:NO];
  self.window.title=@"Orbit"; self.window.titleVisibility=NSWindowTitleHidden; self.window.titlebarAppearsTransparent=YES;
  self.window.minSize=NSMakeSize(850,560); self.window.delegate=self;
  self.window.backgroundColor=[NSColor colorWithSRGBRed:.96 green:.96 blue:.98 alpha:1];
  self.window.releasedWhenClosed=NO;
  NSString *bounds=self.store.data[@"windowFrame"];
  if (bounds) [self.window setFrame:NSRectFromString(bounds) display:NO]; else [self.window center];
  NSView *root=self.window.contentView;
  self.sidebar=[[SidebarView alloc] init]; [root addSubview:self.sidebar];
  NSTextField *brand=Label(@"◉  Orbit",22,NSFontWeightSemibold); [self.sidebar addSubview:brand]; brand.identifier=@"brand";
  NSButton *newButton=Button(@"New tab",@"plus",self,@selector(newTab:)); newButton.identifier=@"new"; [self.sidebar addSubview:newButton];
  self.spacePicker=[[NSPopUpButton alloc] init]; self.spacePicker.bordered=NO; self.spacePicker.font=[NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  self.spacePicker.target=self; self.spacePicker.action=@selector(selectSpace:); [self.spacePicker setAccessibilityLabel:@"Current Space"]; [self.sidebar addSubview:self.spacePicker];
  NSArray *favorites=@[@[@"Search",@"magnifyingglass",@"https://www.google.com"],@[@"GitHub",@"chevron.left.forwardslash.chevron.right",@"https://github.com"],@[@"Read",@"book",@"https://en.wikipedia.org"]];
  for (NSArray *f in favorites) {
    NSButton *b=Button(f[0],f[1],self,@selector(quickLink:)); b.identifier=f[2];
    b.wantsLayer=YES; b.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:.44].CGColor; b.layer.cornerRadius=13;
    [self.sidebar addSubview:b]; [self.sidebarControls addObject:b];
  }
  NSScrollView *scroll=[[NSScrollView alloc] init]; scroll.identifier=@"tabScroll"; scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES;
  self.tabs=[[NSTableView alloc] init]; NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"tab"];
  [self.tabs addTableColumn:column]; self.tabs.headerView=nil; self.tabs.backgroundColor=NSColor.clearColor;
  self.tabs.rowHeight=37; self.tabs.intercellSpacing=NSMakeSize(0,4); self.tabs.style=NSTableViewStyleFullWidth;
  scroll.contentView.drawsBackground=NO;
  self.tabs.dataSource=self; self.tabs.delegate=self; self.tabs.target=self; self.tabs.doubleAction=@selector(renameTab:);
  [self.tabs setAccessibilityLabel:@"Tabs in this Space"];
  [self.tabs registerForDraggedTypes:@[@"dev.orbit.tab"]];
  NSMenu *context=[[NSMenu alloc] initWithTitle:@"Tab"];
  for (NSArray *entry in @[@[@"Pin / Unpin Tab",NSStringFromSelector(@selector(pinTab:))],@[@"Rename Tab…",NSStringFromSelector(@selector(renameTab:))],@[@"Open in Split View",NSStringFromSelector(@selector(splitWithSelected:))],@[@"Archive Tab",NSStringFromSelector(@selector(archiveTab:))]]) {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target=self; [context addItem:item];
  }
  self.tabs.menu=context; scroll.documentView=self.tabs; [self.sidebar addSubview:scroll];
  self.profileButton=Button(@"Default profile",@"person.crop.circle",self,@selector(showProfile:)); self.profileButton.imagePosition=NSImageLeft; [self.sidebar addSubview:self.profileButton];
  NSButton *addSpace=Button(@"New Space",@"plus.circle",self,@selector(newSpace:)); addSpace.identifier=@"addSpace"; [self.sidebar addSubview:addSpace];
  self.backButton=Button(@"Go back",@"chevron.left",self,@selector(goBack:)); [root addSubview:self.backButton];
  self.forwardButton=Button(@"Go forward",@"chevron.right",self,@selector(goForward:)); [root addSubview:self.forwardButton];
  self.reloadButton=Button(@"Reload page",@"arrow.clockwise",self,@selector(reload:)); [root addSubview:self.reloadButton];
  self.address=Button(@"Search or enter a URL   ⌘L",@"",self,@selector(command:)); self.address.wantsLayer=YES;
  self.address.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:.8].CGColor; self.address.layer.cornerRadius=9;
  self.address.alignment=NSTextAlignmentLeft; self.address.lineBreakMode=NSLineBreakByTruncatingMiddle; [root addSubview:self.address];
  self.splitButton=Button(@"Toggle Split View",@"rectangle.split.2x1",self,@selector(toggleSplit:)); [root addSubview:self.splitButton];
  self.progress=[[NSProgressIndicator alloc] init]; self.progress.style=NSProgressIndicatorStyleBar; self.progress.indeterminate=YES; self.progress.displayedWhenStopped=NO; [root addSubview:self.progress];
  self.split=[[NSSplitView alloc] init]; self.split.vertical=YES; self.split.dividerStyle=NSSplitViewDividerStyleThin; self.split.delegate=self;
  self.split.wantsLayer=YES; self.split.layer.cornerRadius=12; self.split.layer.masksToBounds=YES; [root addSubview:self.split];
  self.status=Label(@"Your browser. Your space.",10,NSFontWeightRegular); self.status.textColor=NSColor.secondaryLabelColor; [root addSubview:self.status];
  [self buildMenus]; [self refresh]; [self layout];
  [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
  self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(saveTick:) userInfo:nil repeats:YES];
}
- (void)buildMenus {
  NSMenu *main=[[NSMenu alloc] init]; NSApp.mainMenu=main;
  NSArray *menus=@[@[@"Orbit",@[@[@"About Orbit",@"about:",@""],@[@"Export Workspace…",@"exportWorkspace:",@""],@[@"Show Data Folder",@"showData:",@""],@[@"Quit Orbit",@"quit:",@"q"]]],
    @[@"File",@[@[@"New Tab",@"newTab:",@"t"],@[@"New Space…",@"newSpace:",@""],@[@"Archive Tab",@"archiveTab:",@"w"],@[@"Restore Archived Tab",@"restoreTab:",@"T"],@[@"Open Location…",@"command:",@"l"]]],
    @[@"Edit",@[@[@"Undo",@"undo:",@"z"],@[@"Redo",@"redo:",@"Z"],@[@"Cut",@"cut:",@"x"],@[@"Copy",@"copy:",@"c"],@[@"Paste",@"paste:",@"v"],@[@"Select All",@"selectAll:",@"a"]]],
    @[@"View",@[@[@"Reload",@"reload:",@"r"],@[@"Split View",@"toggleSplit:",@"\\"],@[@"Pin / Unpin Tab",@"pinTab:",@"d"],@[@"Developer Tools",@"devTools:",@""],@[@"Chromium Settings",@"browserSettings:",@""]]]];
  for (NSArray *entry in menus) {
    NSMenuItem *top=[[NSMenuItem alloc] initWithTitle:entry[0] action:nil keyEquivalent:@""]; NSMenu *sub=[[NSMenu alloc] initWithTitle:entry[0]];
    for (NSArray *e in entry[1]) {
      NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:e[0] action:NSSelectorFromString(e[1]) keyEquivalent:e[2]];
      if (![entry[0] isEqual:@"Edit"]) item.target=self;
      [sub addItem:item];
    }
    top.submenu=sub; [main addItem:top];
  }
}
- (void)layout {
  NSRect b=self.window.contentView.bounds; CGFloat h=b.size.height, w=b.size.width;
  self.sidebar.frame=NSMakeRect(0,0,248,h);
  for (NSView *v in self.sidebar.subviews) {
    if ([v.identifier isEqual:@"brand"]) v.frame=NSMakeRect(22,h-100,160,32);
    if ([v.identifier isEqual:@"new"]) v.frame=NSMakeRect(202,h-98,28,28);
    if ([v.identifier isEqual:@"tabScroll"]) v.frame=NSMakeRect(12,92,224,MAX(100,h-335));
    if ([v.identifier isEqual:@"addSpace"]) v.frame=NSMakeRect(210,17,24,28);
  }
  self.spacePicker.frame=NSMakeRect(16,h-158,218,30);
  for (NSUInteger i=0;i<self.sidebarControls.count;i++) self.sidebarControls[i].frame=NSMakeRect(20+i*72,h-218,64,44);
  self.profileButton.frame=NSMakeRect(18,58,208,26);
  for (NSUInteger i=0;i<self.spaceButtons.count;i++) self.spaceButtons[i].frame=NSMakeRect(18+i*42,17,34,28);
  self.backButton.frame=NSMakeRect(260,h-48,28,28); self.forwardButton.frame=NSMakeRect(291,h-48,28,28); self.reloadButton.frame=NSMakeRect(322,h-48,28,28);
  self.address.frame=NSMakeRect(366,h-47,MAX(160,w-430),30); self.splitButton.frame=NSMakeRect(w-51,h-47,30,30);
  self.progress.frame=NSMakeRect(262,h-60,w-276,2); self.split.frame=NSMakeRect(258,26,w-270,h-88);
  self.status.frame=NSMakeRect(267,5,w-285,16);
  [self.split adjustSubviews];
}
- (void)windowDidResize:(NSNotification *)n { [self layout]; }
- (void)windowDidMove:(NSNotification *)n { self.store.data[@"windowFrame"]=NSStringFromRect(self.window.frame); }
- (CGFloat)splitView:(NSSplitView *)s constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index { return 200; }
- (CGFloat)splitView:(NSSplitView *)s constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)index { return s.bounds.size.width-200; }
- (void)saveTick:(id)sender { self.store.data[@"windowFrame"]=NSStringFromRect(self.window.frame); [self persist]; }
- (void)refresh {
  self.refreshing=YES;
  [self.spacePicker removeAllItems];
  for (NSDictionary *s in self.store.spaces) { [self.spacePicker addItemWithTitle:s[@"name"]]; self.spacePicker.lastItem.representedObject=s[@"id"]; }
  for (NSMenuItem *item in self.spacePicker.itemArray) if ([item.representedObject isEqual:self.activeSpace]) [self.spacePicker selectItem:item];
  NSMutableArray *rows=[NSMutableArray array]; NSArray *tabs=[self.store tabsIn:self.activeSpace];
  for (NSNumber *pinned in @[@YES,@NO]) {
    [rows addObject:@{@"heading":[pinned boolValue]?@"PINNED":@"TODAY"}];
    for (NSDictionary *t in tabs) if ([t[@"pinned"] boolValue]==pinned.boolValue) [rows addObject:t];
  }
  self.rows=rows; [self.tabs reloadData];
  for (NSUInteger i=0;i<rows.count;i++) if ([rows[i][@"id"] isEqual:self.activeTab]) [self.tabs selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
  NSDictionary *space=[self.store space:self.activeSpace]; NSString *profileName=@"Default";
  for (NSDictionary *p in self.store.profiles) if ([p[@"id"] isEqual:space[@"profileID"]]) profileName=p[@"name"];
  self.profileButton.title=[profileName stringByAppendingString:@" profile"]; self.profileButton.imagePosition=NSImageLeft;
  [self.profileButton setAccessibilityLabel:self.profileButton.title];
  for (NSButton *b in self.spaceButtons) [b removeFromSuperview]; [self.spaceButtons removeAllObjects];
  for (NSDictionary *s in self.store.spaces) {
    NSButton *b=Button([s[@"name"] substringToIndex:MIN((NSUInteger)1,[s[@"name"] length])],@"",self,@selector(spaceDock:)); b.identifier=s[@"id"]; b.toolTip=s[@"name"];
    b.wantsLayer=YES; b.layer.cornerRadius=9; b.layer.backgroundColor=([s[@"id"] isEqual:self.activeSpace]?[NSColor colorWithWhite:1 alpha:.8]:NSColor.clearColor).CGColor;
    [self.spaceButtons addObject:b]; [self.sidebar addSubview:b];
  }
  self.refreshing=NO; [self displayTabs]; [self layout];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return table==self.tabs ? self.rows.count : self.commandResults.count; }
- (CGFloat)tableView:(NSTableView *)table heightOfRow:(NSInteger)row { return table==self.tabs && self.rows[row][@"heading"] ? 27 : (table==self.tabs ? 37 : 48); }
- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row { return table!=self.tabs || !self.rows[row][@"heading"]; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
  NSDictionary *item=table==self.tabs ? self.rows[row] : self.commandResults[row];
  NSView *view=[[NSView alloc] initWithFrame:NSMakeRect(0,0,table.bounds.size.width,table==self.tabs?37:48)];
  if (item[@"heading"]) {
    NSTextField *text=Label(item[@"heading"],9,NSFontWeightSemibold); text.textColor=[Ink() colorWithAlphaComponent:.43]; text.frame=NSMakeRect(11,7,200,14); [view addSubview:text];
  } else {
    NSString *symbol=table==self.tabs ? ([item[@"pinned"] boolValue]?@"pin.fill":@"globe") : (item[@"symbol"] ?: @"arrow.up.right");
    if ([item[@"url"] isEqual:@"orbit://home"]) symbol=@"circle.dotted";
    NSImageView *icon=[[NSImageView alloc] initWithFrame:NSMakeRect(10,table==self.tabs?10:17,16,16)];
    icon.image=[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]; icon.contentTintColor=[Ink() colorWithAlphaComponent:.65]; [view addSubview:icon];
    NSTextField *text=Label(item[@"title"] ?: @"New Tab",12,NSFontWeightMedium); text.frame=NSMakeRect(36,table==self.tabs?9:24,table.bounds.size.width-48,19); [view addSubview:text];
    if (table!=self.tabs) { NSTextField *detail=Label(item[@"detail"] ?: @"",10,NSFontWeightRegular); detail.textColor=NSColor.secondaryLabelColor; detail.frame=NSMakeRect(36,6,table.bounds.size.width-48,16); [view addSubview:detail]; }
  }
  return view;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if (notification.object!=self.tabs || self.refreshing || self.tabs.selectedRow<0) return;
  NSDictionary *t=self.rows[self.tabs.selectedRow]; if (!t[@"id"]) return;
  self.focusedTab=t[@"id"]; [self.store activate:self.focusedTab];
  if (![self.store.data[@"splitTabs"] containsObject:self.focusedTab]) [self.store.data[@"splitTabs"] removeAllObjects];
  [self persist]; [self displayTabs];
}
- (id<NSPasteboardWriting>)tableView:(NSTableView *)table pasteboardWriterForRow:(NSInteger)row {
  if (table!=self.tabs || !self.rows[row][@"id"]) return nil;
  NSPasteboardItem *p=[[NSPasteboardItem alloc] init]; [p setString:self.rows[row][@"id"] forType:@"dev.orbit.tab"]; return p;
}
- (NSDragOperation)tableView:(NSTableView *)table validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op {
  return table==self.tabs && info.draggingSource==self.tabs && op==NSTableViewDropAbove ? NSDragOperationMove : NSDragOperationNone;
}
- (BOOL)tableView:(NSTableView *)table acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op {
  NSMutableDictionary *tab=[self.store tab:[info.draggingPasteboard stringForType:@"dev.orbit.tab"]]; if (!tab) return NO;
  NSDictionary *target=row<self.rows.count ? self.rows[row] : nil;
  BOOL pinned=target[@"heading"] ? [target[@"heading"] isEqual:@"PINNED"] : [target[@"pinned"] boolValue];
  tab[@"pinned"]=@(pinned); NSMutableArray *all=self.store.data[@"tabs"]; [all removeObject:tab];
  NSUInteger index=target[@"id"] ? [all indexOfObject:target] : NSNotFound;
  if (index==NSNotFound) [all addObject:tab]; else [all insertObject:tab atIndex:index];
  [self persist]; [self refresh]; return YES;
}
- (BrowserSession *)ensureSession:(NSString *)identifier {
  BrowserSession *session=self.sessions[identifier]; if (session) return session;
  NSMutableDictionary *tab=[self.store tab:identifier]; if (!tab) return nil;
  session=[[BrowserSession alloc] init]; session.container=[[NSView alloc] initWithFrame:self.split.bounds];
  session.container.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; self.sessions[identifier]=session;
  NSString *profile=[self.store space:tab[@"spaceID"]][@"profileID"]; std::string key=profile.UTF8String;
  CefRefPtr<CefRequestContext> context=contexts[key];
  if (!context) {
    NSString *profilePath=[self.storageRoot stringByAppendingPathComponent:[@"Profile-" stringByAppendingString:profile]];
    NSError *error=nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:profilePath withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
      self.status.stringValue=@"Profile storage could not be opened"; [self.sessions removeObjectForKey:identifier]; return nil;
    }
    CefRequestContextSettings settings; CefString(&settings.cache_path)=CS(profilePath);
    settings.persist_session_cookies=true; context=CefRequestContext::CreateContext(settings,nullptr); contexts[key]=context;
    if (!context) { self.status.stringValue=@"Browser profile could not start"; [self.sessions removeObjectForKey:identifier]; return nil; }
  }
  CefWindowInfo windowInfo; windowInfo.SetAsChild((__bridge CefWindowHandle)session.container,CefRect(0,0,(int)session.container.bounds.size.width,(int)session.container.bounds.size.height));
  windowInfo.runtime_style=CEF_RUNTIME_STYLE_ALLOY;
  CefBrowserSettings settings; settings.background_color=CefColorSetARGB(255,250,250,252);
  session->client=new OrbitClient(identifier);
  NSString *url=tab[@"url"]; if ([url isEqual:@"orbit://home"]) url=[self homeURL];
  if (!CefBrowserHost::CreateBrowser(windowInfo,session->client,CS(url),settings,nullptr,context)) {
    [self.sessions removeObjectForKey:identifier]; self.status.stringValue=@"Browser could not start. Your saved tabs are intact.";
  }
  return session;
}
- (NSString *)homeURL {
  NSString *path=[NSBundle.mainBundle pathForResource:@"home" ofType:@"html"];
  return DataURL([NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"<h1>Orbit</h1>");
}
- (void)displayTabs {
  NSString *active=self.activeTab;
  NSMutableArray *visible=[NSMutableArray arrayWithObject:active]; NSArray *saved=self.store.data[@"splitTabs"];
  if (saved.count==2 && [saved containsObject:active] && [[self.store tab:saved[0]][@"spaceID"] isEqual:self.activeSpace] && [[self.store tab:saved[1]][@"spaceID"] isEqual:self.activeSpace]) visible=[saved mutableCopy];
  NSArray *old=[self.split.subviews copy]; for (NSView *v in old) [v removeFromSuperview];
  for (NSString *identifier in visible) {
    BrowserSession *s=[self ensureSession:identifier]; if (s) [self.split addArrangedSubview:s.container];
  }
  self.splitButton.contentTintColor=visible.count==2?Accent():Ink(); [self.split adjustSubviews]; [self updateAddress];
  BrowserSession *focused=self.sessions[active];
  if (focused && focused->browser) focused->browser->GetHost()->SetFocus(true);
}
- (void)updateAddress {
  NSDictionary *tab=self.activeRecord; NSString *url=tab[@"url"] ?: @"orbit://home";
  self.address.title=[url isEqual:@"orbit://home"]?@"    Search or enter a URL                                      ⌘L":[@"    " stringByAppendingString:url];
  self.window.title=[NSString stringWithFormat:@"%@ — Orbit",tab[@"title"] ?: @"New Tab"];
  BrowserSession *s=self.sessions[self.activeTab];
  self.backButton.enabled=s && s->browser && s->browser->CanGoBack(); self.forwardButton.enabled=s && s->browser && s->browser->CanGoForward();
}
- (void)didCreate:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier {
  BrowserSession *s=self.sessions[identifier];
  if (!s || s.closing || self.quitting) { browser->GetHost()->CloseBrowser(true); return; }
  s->browser=browser;
  browser->GetHost()->SetAccessibilityState(STATE_ENABLED);
  NSView *view=(__bridge NSView *)browser->GetHost()->GetWindowHandle();
  view.frame=s.container.bounds; view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
  NSString *desired=[self.store tab:identifier][@"url"];
  if (desired && ![desired isEqual:@"orbit://home"] && ![NS(browser->GetMainFrame()->GetURL()) isEqual:desired]) browser->GetMainFrame()->LoadURL(CS(desired));
  [self updateAddress];
}
- (void)allowClose:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier {
  // This browser is a child NSView, not an independently closable NSWindow.
  // Destroy only its host view after Chromium has approved beforeunload.
  NSView *view=(__bridge NSView *)browser->GetHost()->GetWindowHandle();
  [view removeFromSuperview];
}
- (void)cancelClose:(NSString *)identifier {
  BrowserSession *s=self.sessions[identifier]; s.closing=NO; s.archivePending=NO;
  if (self.quitting) {
    self.quitting=NO;
    self.saveTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(saveTick:) userInfo:nil repeats:YES];
    [self refresh];
  }
}
- (void)didClose:(CefRefPtr<CefBrowser>)browser tab:(NSString *)identifier {
  BrowserSession *s=self.sessions[identifier];
  if (s) {
    if (s.archivePending && !self.quitting) [self.store archive:identifier];
    s->browser=nullptr; s->client=nullptr; [s.container removeFromSuperview]; [self.sessions removeObjectForKey:identifier];
  }
  if (!self.quitting) { self.focusedTab=[self.store space:self.activeSpace][@"activeTab"]; [self persist]; [self refresh]; }
}
- (void)didNavigate:(NSString *)url title:(NSString *)title tab:(NSString *)identifier {
  NSMutableDictionary *t=[self.store tab:identifier]; if (!t || self.quitting) return;
  if (url.length && ![url hasPrefix:@"data:"]) t[@"url"]=url;
  if (title.length && !t[@"customTitle"]) t[@"title"]=[t[@"url"] isEqual:@"orbit://home"]?@"New Tab":title;
  [self.tabs reloadData]; [self updateAddress];
}
- (void)didLoad:(BOOL)loading back:(BOOL)back forward:(BOOL)forward tab:(NSString *)identifier {
  if (![identifier isEqual:self.activeTab]) return;
  if (loading) { [self.progress startAnimation:nil]; self.status.stringValue=@"Loading…"; }
  else { [self.progress stopAnimation:nil]; self.status.stringValue=@""; }
  self.backButton.enabled=back; self.forwardButton.enabled=forward;
}
- (void)focusTab:(NSString *)identifier {
  if (![self.store tab:identifier] || self.quitting) return;
  self.focusedTab=identifier; [self.store activate:identifier]; [self updateAddress];
  self.refreshing=YES;
  for (NSUInteger i=0;i<self.rows.count;i++) if ([self.rows[i][@"id"] isEqual:identifier]) [self.tabs selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
  self.refreshing=NO;
}
- (void)loadFailure:(NSString *)message tab:(NSString *)identifier { if ([identifier isEqual:self.activeTab]) self.status.stringValue=message; }
- (void)newTab:(id)sender {
  [self.store.data[@"splitTabs"] removeAllObjects]; NSMutableDictionary *t=[self.store addTab:@"orbit://home" space:self.activeSpace]; self.focusedTab=t[@"id"]; [self persist]; [self refresh]; [self command:sender];
}
- (void)quickLink:(NSButton *)sender { [self openURL:sender.identifier newTab:YES]; }
- (void)openURL:(NSString *)input newTab:(BOOL)newTab {
  NSString *url=[Workspace normalizedURL:input];
  if (newTab) {
    [self.store.data[@"splitTabs"] removeAllObjects]; NSMutableDictionary *t=[self.store addTab:url space:self.activeSpace]; self.focusedTab=t[@"id"]; [self refresh];
  } else {
    NSMutableDictionary *t=self.activeRecord; t[@"url"]=url;
    BrowserSession *s=[self ensureSession:self.activeTab]; if (s->browser) s->browser->GetMainFrame()->LoadURL(CS([url isEqual:@"orbit://home"]?[self homeURL]:url));
    [self updateAddress];
  }
  [self persist];
}
- (void)selectSpace:(id)sender { [self switchSpace:self.spacePicker.selectedItem.representedObject]; }
- (void)spaceDock:(NSButton *)sender { [self switchSpace:sender.identifier]; }
- (void)switchSpace:(NSString *)identifier {
  self.store.data[@"activeSpace"]=identifier; self.focusedTab=[self.store space:identifier][@"activeTab"]; [self.store.data[@"splitTabs"] removeAllObjects]; [self persist]; [self refresh];
}
- (void)newSpace:(id)sender {
  NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"A new Space"; a.informativeText=@"Share the Default profile, or keep logins and cookies separate.";
  NSTextField *name=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,300,28)]; name.placeholderString=@"Space name"; a.accessoryView=name;
  [a addButtonWithTitle:@"Shared profile"]; [a addButtonWithTitle:@"Separate profile"]; [a addButtonWithTitle:@"Cancel"];
  [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response==NSAlertThirdButtonReturn || !name.stringValue.length) return;
    NSDictionary *s=[self.store addSpace:name.stringValue isolated:response==NSAlertSecondButtonReturn]; [self switchSpace:s[@"id"]];
  }];
}
- (NSString *)contextTab {
  NSInteger row=self.tabs.clickedRow>=0?self.tabs.clickedRow:self.tabs.selectedRow;
  return row>=0 && row<self.rows.count ? self.rows[row][@"id"] : self.activeTab;
}
- (void)pinTab:(id)sender {
  NSString *identifier=[sender isKindOfClass:NSMenuItem.class] && ((NSMenuItem *)sender).menu==self.tabs.menu ? self.contextTab:self.activeTab;
  NSMutableDictionary *t=[self.store tab:identifier]; if (!t) return; t[@"pinned"]=@(![t[@"pinned"] boolValue]);
  if ([t[@"pinned"] boolValue]) t[@"pinnedURL"]=t[@"url"]; [self persist]; [self refresh];
}
- (void)renameTab:(id)sender {
  NSMutableDictionary *t=[self.store tab:self.contextTab]; if (!t) return;
  NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"Rename tab"; NSTextField *field=[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,300,28)]; field.stringValue=t[@"title"]; a.accessoryView=field;
  [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Cancel"];
  [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) { if (response==NSAlertFirstButtonReturn && field.stringValue.length) { t[@"title"]=field.stringValue; t[@"customTitle"]=@YES; [self persist]; [self refresh]; } }];
}
- (void)archiveTab:(id)sender {
  NSString *identifier=[sender isKindOfClass:NSMenuItem.class] && ((NSMenuItem *)sender).menu==self.tabs.menu ? self.contextTab:self.activeTab;
  if (!identifier) return;
  BrowserSession *s=self.sessions[identifier];
  if (s) { s.closing=YES; s.archivePending=YES; if (s->browser) s->browser->GetHost()->CloseBrowser(false); }
  else { [self.store archive:identifier]; self.focusedTab=[self.store space:self.activeSpace][@"activeTab"]; [self persist]; [self refresh]; }
}
- (void)restoreTab:(id)sender {
  NSMutableDictionary *t=[self.store restoreLastArchived]; if (!t) { self.status.stringValue=@"No archived tabs yet"; return; }
  self.focusedTab=t[@"id"]; [self persist]; [self refresh];
}
- (void)toggleSplit:(id)sender {
  NSMutableArray *split=self.store.data[@"splitTabs"];
  if (split.count==2) { [split removeAllObjects]; [self persist]; [self displayTabs]; return; }
  NSString *active=self.activeTab; NSString *other=nil;
  for (NSDictionary *t in [self.store tabsIn:self.activeSpace]) if (![t[@"id"] isEqual:active]) { other=t[@"id"]; break; }
  if (!other) other=[self.store addTab:@"orbit://home" space:self.activeSpace][@"id"];
  self.focusedTab=active; [self.store activate:active]; [split setArray:@[active,other]]; [self persist]; [self refresh];
}
- (void)splitWithSelected:(id)sender {
  NSString *other=self.contextTab;
  if (!other || [other isEqual:self.activeTab]) { [self toggleSplit:sender]; return; }
  [self.store.data[@"splitTabs"] setArray:@[self.activeTab,other]]; [self persist]; [self refresh];
}
- (void)goBack:(id)sender { BrowserSession *s=self.sessions[self.activeTab]; if (s && s->browser) s->browser->GoBack(); }
- (void)goForward:(id)sender { BrowserSession *s=self.sessions[self.activeTab]; if (s && s->browser) s->browser->GoForward(); }
- (void)reload:(id)sender { BrowserSession *s=self.sessions[self.activeTab]; if (s && s->browser) s->browser->Reload(); }
- (void)devTools:(id)sender {
  BrowserSession *s=self.sessions[self.activeTab]; if (!s || !s->browser) return;
  CefWindowInfo info; CefString(&info.window_name)="Orbit Developer Tools"; info.bounds=CefRect(0,0,1000,700); CefBrowserSettings settings;
  s->browser->GetHost()->ShowDevTools(info,nullptr,settings,CefPoint());
}
- (void)browserSettings:(id)sender { [self openURL:@"chrome://settings" newTab:YES]; }
- (void)showProfile:(id)sender {
  NSAlert *a=[[NSAlert alloc] init]; a.messageText=self.profileButton.title;
  NSString *profile=[self.store space:self.activeSpace][@"profileID"]; NSMutableArray *names=[NSMutableArray array];
  for (NSDictionary *s in self.store.spaces) if ([s[@"profileID"] isEqual:profile]) [names addObject:s[@"name"]];
  a.informativeText=[NSString stringWithFormat:@"Shared by: %@.\n\nSpaces in this profile share cookies, logins and browsing data. Other profiles are stored separately.",[names componentsJoinedByString:@", "]];
  [a beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)command:(id)sender {
  if (!self.commandPanel) {
    self.commandPanel=[[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,600,365) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    self.commandPanel.titleVisibility=NSWindowTitleHidden; self.commandPanel.titlebarAppearsTransparent=YES; self.commandPanel.backgroundColor=[NSColor colorWithSRGBRed:.97 green:.97 blue:.99 alpha:1];
    self.commandInput=[[NSTextField alloc] initWithFrame:NSMakeRect(24,294,552,42)]; self.commandInput.bordered=NO; self.commandInput.drawsBackground=NO; self.commandInput.font=[NSFont systemFontOfSize:23 weight:NSFontWeightMedium];
    self.commandInput.placeholderString=@"Where would you like to go?"; self.commandInput.delegate=self; self.commandInput.target=self; self.commandInput.action=@selector(submitCommand:);
    [self.commandInput setAccessibilityLabel:@"Search, enter a URL, or find a tab"]; [self.commandPanel.contentView addSubview:self.commandInput];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,32,576,248)]; scroll.drawsBackground=NO; scroll.hasVerticalScroller=YES;
    self.suggestions=[[NSTableView alloc] init]; [self.suggestions addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"suggestion"]]; self.suggestions.headerView=nil;
    self.suggestions.backgroundColor=NSColor.clearColor; self.suggestions.dataSource=self; self.suggestions.delegate=self; self.suggestions.rowHeight=48; self.suggestions.target=self; self.suggestions.doubleAction=@selector(submitCommand:); scroll.documentView=self.suggestions; [self.commandPanel.contentView addSubview:scroll];
    NSTextField *hint=Label(@"↑ ↓ to choose     ↵ to open                                         esc to close",10,NSFontWeightRegular); hint.textColor=NSColor.secondaryLabelColor; hint.frame=NSMakeRect(26,10,550,16); [self.commandPanel.contentView addSubview:hint];
  }
  self.commandInput.stringValue=[self.activeRecord[@"url"] isEqual:@"orbit://home"]?@"":self.activeRecord[@"url"];
  [self updateSuggestions];
  NSRect window=self.window.frame; [self.commandPanel setFrameOrigin:NSMakePoint(NSMidX(window)-300,NSMaxY(window)-450)];
  [self.window beginSheet:self.commandPanel completionHandler:nil]; [self.commandPanel makeFirstResponder:self.commandInput]; [self.commandInput selectText:nil];
}
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object==self.commandInput) [self updateSuggestions]; }
- (void)updateSuggestions {
  NSString *query=self.commandInput.stringValue; NSMutableArray *results=[NSMutableArray array];
  if (query.length) [results addObject:@{@"title":query,@"detail":[Workspace normalizedURL:query],@"action":@"navigate",@"symbol":@"arrow.up.right"}];
  for (NSDictionary *t in self.store.data[@"tabs"]) {
    if (!query.length || [t[@"title"] localizedCaseInsensitiveContainsString:query] || [t[@"url"] localizedCaseInsensitiveContainsString:query])
      [results addObject:@{@"title":t[@"title"],@"detail":[NSString stringWithFormat:@"Switch to tab · %@",[self.store space:t[@"spaceID"]][@"name"]],@"action":@"tab",@"id":t[@"id"],@"symbol":@"rectangle.on.rectangle"}];
  }
  NSArray *actions=@[@{@"title":@"Toggle Split View",@"action":@"split",@"detail":@"Browse two tabs side by side",@"symbol":@"rectangle.split.2x1"},@{@"title":@"Restore Archived Tab",@"action":@"restore",@"detail":@"Bring back your most recently archived tab",@"symbol":@"arrow.uturn.backward"},@{@"title":@"New Space",@"action":@"space",@"detail":@"Shared or separate browsing profile",@"symbol":@"square.grid.2x2"},@{@"title":@"New Tab",@"action":@"new",@"detail":@"A fresh place to begin",@"symbol":@"plus"}];
  for (NSDictionary *a in actions) if (!query.length || [a[@"title"] localizedCaseInsensitiveContainsString:query]) [results addObject:a];
  self.commandResults=results; [self.suggestions reloadData]; if (results.count) [self.suggestions selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)selector {
  if (control!=self.commandInput) return NO;
  if (selector==@selector(cancelOperation:)) { [self dismissCommand]; return YES; }
  if (selector==@selector(moveDown:) || selector==@selector(moveUp:)) {
    NSInteger row=self.suggestions.selectedRow+(selector==@selector(moveDown:)?1:-1); row=MAX(0,MIN(row,(NSInteger)self.commandResults.count-1));
    if (self.commandResults.count) { [self.suggestions selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [self.suggestions scrollRowToVisible:row]; } return YES;
  }
  if (selector==@selector(insertNewline:)) { [self submitCommand:nil]; return YES; }
  return NO;
}
- (void)dismissCommand { [self.window endSheet:self.commandPanel]; [self.commandPanel orderOut:nil]; }
- (void)submitCommand:(id)sender {
  NSInteger row=self.suggestions.selectedRow; if (row<0 || row>=self.commandResults.count) { [self dismissCommand]; return; }
  NSDictionary *r=self.commandResults[row]; NSString *query=self.commandInput.stringValue; [self dismissCommand];
  NSString *action=r[@"action"];
  if ([action isEqual:@"navigate"]) [self openURL:query newTab:NO];
  if ([action isEqual:@"tab"]) { self.focusedTab=r[@"id"]; [self.store activate:self.focusedTab]; [self.store.data[@"splitTabs"] removeAllObjects]; [self persist]; [self refresh]; }
  if ([action isEqual:@"split"]) [self toggleSplit:nil];
  if ([action isEqual:@"restore"]) [self restoreTab:nil];
  if ([action isEqual:@"space"]) [self newSpace:nil];
  if ([action isEqual:@"new"]) [self newTab:nil];
}
- (void)exportWorkspace:(id)sender {
  NSSavePanel *panel=[NSSavePanel savePanel]; panel.nameFieldStringValue=@"Orbit-workspace.json";
  [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
    if (response!=NSModalResponseOK) return;
    NSError *error=nil; NSData *bytes=[NSJSONSerialization dataWithJSONObject:self.store.data options:NSJSONWritingPrettyPrinted error:&error];
    if (![bytes writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) self.status.stringValue=error.localizedDescription;
    else self.status.stringValue=@"Workspace exported · passwords and cookies are not included";
  }];
}
- (void)showData:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:self.storageRoot]]; }
- (void)about:(id)sender {
  NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"Orbit · Developer Preview 0.1";
  a.informativeText=@"An independent, local-first Chromium browser.\n\nChromium 156 · native macOS shell\n\nThis first milestone includes Spaces, separate Profiles, tabs, pins, split browsing, archive recovery and workspace export. Extension compatibility, Arc import, Boosts, sync and AI are still on the roadmap.";
  [a addButtonWithTitle:@"Done"]; [a addButtonWithTitle:@"Licenses"];
  [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) { if (response==NSAlertSecondButtonReturn) [self openURL:@"chrome://credits" newTab:YES]; }];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { [self quit:nil]; return NO; }
- (void)quit:(id)sender {
  if (self.quitting) return;
  if (![self persist]) { NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"Your workspace has not been saved"; a.informativeText=@"Free some disk space or export the workspace before quitting."; [a beginSheetModalForWindow:self.window completionHandler:nil]; return; }
  self.quitting=YES; [self.saveTimer invalidate];
  if (self.commandPanel.sheetParent) [self dismissCommand];
  // Snapshot: CloseBrowser may synchronously invoke callbacks that mutate this map.
  auto browsers=liveBrowsers; for (auto &entry:browsers) entry.second->GetHost()->CloseBrowser(false);
  if (liveBrowsers.empty()) CefQuitMessageLoop();
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)flag { [self.window makeKeyAndOrderFront:nil]; return NO; }
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }
@end

int main(int argc,char *argv[]) {
  CefScopedLibraryLoader loader; if (!loader.LoadInMain()) return 1;
  @autoreleasepool {
    [OrbitApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    gApp=[[OrbitDelegate alloc] init];
    const char *override=getenv("ORBIT_DATA_DIR");
    gApp.storageRoot=override ? [NSString stringWithUTF8String:override] : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/OrbitPreview"];
    gApp.storageRoot=[gApp.storageRoot stringByStandardizingPath];
    NSError *error=nil; [NSFileManager.defaultManager createDirectoryAtPath:gApp.storageRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error];
    if (error) { NSLog(@"Cannot open data folder: %@",error); return 1; }
    @try { gApp.store=[[Workspace alloc] initWithURL:[NSURL fileURLWithPath:[gApp.storageRoot stringByAppendingPathComponent:@"workspace.json"]]]; }
    @catch (NSException *e) { NSAlert *a=[[NSAlert alloc] init]; a.messageText=@"Orbit could not restore your workspace"; a.informativeText=e.reason; [a runModal]; return 1; }
    CefMainArgs args(argc,argv); CefSettings settings;
    CefString(&settings.root_cache_path)=CS(gApp.storageRoot);
    CefString(&settings.cache_path)=CS([gApp.storageRoot stringByAppendingPathComponent:@"Global"]);
    CefString(&settings.log_file)=CS([gApp.storageRoot stringByAppendingPathComponent:@"engine.log"]);
    settings.log_severity=LOGSEVERITY_WARNING;
    settings.persist_session_cookies=true;
    CefRefPtr<OrbitCEFApp> cefApp=new OrbitCEFApp;
    if (!CefInitialize(args,settings,cefApp,nullptr)) return CefGetExitCode();
    NSApp.delegate=gApp;
    [gApp performSelectorOnMainThread:@selector(setup) withObject:nil waitUntilDone:NO];
    CefRunMessageLoop();
    [gApp.window orderOut:nil]; [gApp.sessions removeAllObjects]; contexts.clear(); liveBrowsers.clear();
    CefShutdown(); cefApp=nullptr; NSApp.delegate=nil; gApp=nil;
  }
  return 0;
}
