//
//  Lin.m
//  Lin
//
//  Created by Katsuma Tanaka on 2015/02/05.
//  Copyright (c) 2015年 Katsuma Tanaka. All rights reserved.
//

#import "Lin.h"

// Xcode
#import "Xcode.h"

// Models
#import "LINLocalizationParser.h"
#import "LINLocalization.h"
#import "LINTextCompletionItem.h"

#import "LinLocalizedInputController.h"

static id _sharedInstance = nil;

@interface Lin ()

@property (nonatomic, copy) NSArray* configurations;
@property (nonatomic, strong) LINLocalizationParser* parser;
@property (nonatomic, strong) NSMutableDictionary* completionItems;
@property (nonatomic, strong) NSOperationQueue* indexingQueue;

@property (nonatomic, copy) NSString* selectedText;

@property (nonatomic, strong) LinLocalizedInputController* inputCtrl;
@property (strong, nonatomic) NSTextView* currentTextView;
@property (strong, nonatomic) NSArray* localizedStringfilePaths;
@property (assign, nonatomic) NSRange currentSelectedRange;
@property (nonatomic, assign) BOOL notiTag;
@property (nonatomic, assign) BOOL swift;
@property (nonatomic, copy) NSString* currentFilePath;
@property (nonatomic, copy) NSString* currentProjectPath;

@end

@implementation Lin

+ (void)pluginDidLoad:(NSBundle*)bundle
{
    static dispatch_once_t _onceToken;
    dispatch_once(&_onceToken, ^{
        _sharedInstance = [self new];
    });
}

+ (instancetype)sharedInstance
{
    return _sharedInstance;
}

- (instancetype)init
{
    self = [super init];

    if (self) {

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidFinishLaunching:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(localizedTextSetComplete:)
                                                     name:kLocalizedTextInputCompleteNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationLog:) name:NSTextViewDidChangeSelectionNotification object:nil];

        // Load configurations
        NSString* filePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Completions" ofType:@"plist"];
        self.configurations = [NSArray arrayWithContentsOfFile:filePath];

        self.parser = [LINLocalizationParser new];
        self.completionItems = [NSMutableDictionary dictionary];

        // Create indexing queue
        NSOperationQueue* indexingQueue = [NSOperationQueue new];
        indexingQueue.maxConcurrentOperationCount = 1;
        self.indexingQueue = indexingQueue;
    }

    return self;
}

#pragma mark -
#pragma mark select

- (void)notificationLog:(NSNotification*)notify
{
    if (!self.notiTag)
        return;
    if ([notify.name isEqualToString:NSTextViewDidChangeSelectionNotification]) {
        if ([notify.object isKindOfClass:[NSTextView class]]) {
            NSTextView* text = (NSTextView*)notify.object;
            self.currentTextView = text;
        }
    }
    else if ([notify.name isEqualToString:@"IDEEditorDocumentDidChangeNotification"]) {
        //Track the current open paths
        NSObject* array = notify.userInfo[@"IDEEditorDocumentChangeLocationsKey"];
        NSURL* url = [[array valueForKey:@"documentURL"] firstObject];
        if (![url isKindOfClass:[NSNull class]]) {
            NSString* path = [url absoluteString];
            self.currentFilePath = path;
            if ([self.currentFilePath hasSuffix:@"swift"]) {
                self.swift = YES;
            }
            else {
                self.swift = NO;
            }
        }
    }
    else if ([notify.name isEqualToString:@"PBXProjectDidOpenNotification"]) {
        self.currentProjectPath = [notify.object valueForKey:@"path"];
    }
}

- (void)localizedTextSetComplete:(NSNotification*)noti
{
    NSString* text = noti.object;
    [self.currentTextView replaceCharactersInRange:self.currentSelectedRange withString:[NSString stringWithFormat:@"NSLocalizedString(@\"%@\",nil)", text]];
    NSString* outputString = [NSString stringWithFormat:@"\n\"%@\"   = \"%@\";\n", text, self.selectedText];
    for (NSString* filePath in self.localizedStringfilePaths) {
        [self writeString:outputString toFilePath:filePath];
    }
    self.notiTag = YES;
}

- (void)writeString:(NSString*)string toFilePath:(NSString*)filePath
{
    NSFileHandle* outFile;
    NSData* buffer;

    outFile = [NSFileHandle fileHandleForWritingAtPath:filePath];

    if (outFile == nil) {
        NSLog(@"Open of file for writing failed");
    }

    //找到并定位到outFile的末尾位置(在此后追加文件)
    [outFile seekToEndOfFile];

    //读取inFile并且将其内容写到outFile中
    NSString* bs = [NSString stringWithFormat:@"%@", string];
    buffer = [bs dataUsingEncoding:NSUTF8StringEncoding];

    [outFile writeData:buffer];

    //关闭读写文件
    [outFile closeFile];
}

- (void)applicationDidFinishLaunching:(NSNotification*)noti
{
    self.notiTag = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(selectionDidChange:)
                                                 name:NSTextViewDidChangeSelectionNotification
                                               object:nil];
    NSMenuItem* editMenuItem = [[NSApp mainMenu] itemWithTitle:@"Edit"];
    if (editMenuItem) {
        [[editMenuItem submenu] addItem:[NSMenuItem separatorItem]];
        NSMenuItem* newMenuItem = [[NSMenuItem alloc] initWithTitle:@"本地化" action:@selector(showSelected:) keyEquivalent:@"L"];
        [newMenuItem setTarget:self];
        [newMenuItem setKeyEquivalentModifierMask:NSAlphaShiftKeyMask | NSControlKeyMask];
        [[editMenuItem submenu] addItem:newMenuItem];
    }
}

- (void)selectionDidChange:(NSNotification*)noti
{
    if ([[noti object] isKindOfClass:[NSTextView class]]) {
        NSTextView* textView = (NSTextView*)[noti object];

        NSArray* selectedRanges = [textView selectedRanges];
        if (selectedRanges.count == 0) {
            return;
        }

        NSRange selectedRange = [[selectedRanges objectAtIndex:0] rangeValue];

        if (self.notiTag) {
            self.currentSelectedRange = selectedRange;
            self.currentTextView = textView;
            NSString* text = textView.textStorage.string;
            self.selectedText = [text substringWithRange:selectedRange];
        }
    }
    //Hello, welcom to OneV's Den
}

- (void)showSelected:(NSNotification*)noti
{

    if (!self.selectedText || self.selectedText.length < 1 || ![self matchString:self.selectedText]) {
        self.notiTag = YES;
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error:选择内容应为【@\"....\"】"];
        [alert runModal];
    }
    else {
        self.notiTag = NO;
        self.selectedText = [self.selectedText substringWithRange:NSMakeRange(2, self.selectedText.length - 3)];
        self.inputCtrl = [[LinLocalizedInputController alloc] initWithWindowNibName:@"LinLocalizedInputController"];
        //self.inputCtrl.delegate = self;
        self.inputCtrl.selectedString = self.selectedText;
        [self.inputCtrl showWindow:self.inputCtrl];
    }
}

- (BOOL)matchString:(NSString*)string
{
    NSString* pattern = @"@\".*\"";
    NSRegularExpression* regularExpression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray* matches = [regularExpression matchesInString:string options:0 range:NSMakeRange(0, string.length)];
    if (matches && matches.count > 0) {
        return YES;
    }
    return NO;
}

#pragma mark - Indexing Localizations

- (void)indexNeedsUpdate:(IDEIndex*)index
{
    IDEWorkspace* workspace = [index valueForKey:@"_workspace"];
    NSString* workspaceFilePath = workspace.representingFilePath.pathString;
    if (workspaceFilePath == nil)
        return;

    // Add indexing operation
    NSBlockOperation* operation = [NSBlockOperation new];

    __weak __typeof(self) weakSelf = self;
    __weak NSBlockOperation* weakOperation = operation;

    [operation addExecutionBlock:^{
        // Find strings files
        IDEIndexCollection* indexCollection = [index filesContaining:@".strings" anchorStart:NO anchorEnd:NO subsequence:NO ignoreCase:YES cancelWhen:nil];

        IDEIndexCollection* localizedCollection = [index filesContaining:@"Localizable.strings" anchorStart:NO anchorEnd:NO subsequence:NO ignoreCase:YES cancelWhen:nil];

        if ([weakOperation isCancelled])
            return;

        NSMutableArray* files = [NSMutableArray new];
        for (DVTFilePath* filePath in localizedCollection) {
            if ([filePath.fileName isEqualToString:@"Localizable.strings"]) {
                [files addObject:filePath.pathString];
            }
        }
        self.localizedStringfilePaths = files.copy;

        // Classify localizations by key
        NSMutableDictionary* localizationsByKey = [NSMutableDictionary dictionary];

        for (DVTFilePath* filePath in indexCollection) {
            if ([weakOperation isCancelled])
                return;

            NSArray* parsedLocalizations = [self.parser localizationsFromContentsOfFile:filePath.pathString];

            for (LINLocalization* localization in parsedLocalizations) {
                NSMutableArray* localizations = localizationsByKey[localization.key];

                if (localizations) {
                    [localizations addObject:localization];
                }
                else {
                    localizations = [NSMutableArray array];
                    [localizations addObject:localization];
                    localizationsByKey[localization.key] = localizations;
                }
            }
        }

        if ([weakOperation isCancelled])
            return;

        // Convert localizations to completions
        NSMutableArray* completionItems = [NSMutableArray array];

        for (NSString* key in [localizationsByKey allKeys]) {
            if ([weakOperation isCancelled])
                return;

            NSMutableArray* localizations = localizationsByKey[key];

            // Sort localizations
            [localizations sortUsingComparator:^NSComparisonResult(LINLocalization* lhs, LINLocalization* rhs) {
                return [[lhs languageDesignation] caseInsensitiveCompare:[rhs languageDesignation]];
            }];

            // Create completion item
            LINTextCompletionItem* completionItem = [[LINTextCompletionItem alloc] initWithLocalizations:localizations];
            [completionItems addObject:completionItem];
        }

        if ([weakOperation isCancelled])
            return;

        // Sort completions
        [completionItems sortUsingComparator:^NSComparisonResult(LINTextCompletionItem* lhs, LINTextCompletionItem* rhs) {
            return [[lhs key] caseInsensitiveCompare:[rhs key]];
        }];

        if ([weakOperation isCancelled])
            return;

        weakSelf.completionItems[workspaceFilePath] = completionItems;
    }];

    [self.indexingQueue cancelAllOperations];
    [self.indexingQueue addOperation:operation];
}

#pragma mark - Auto Completion

- (NSArray*)completionItemsForWorkspace:(IDEWorkspace*)workspace
{
    NSString* workspaceFilePath = workspace.representingFilePath.pathString;
    if (workspaceFilePath == nil)
        return nil;

    return self.completionItems[workspaceFilePath];
}

- (BOOL)shouldAutoCompleteInTextView:(DVTCompletingTextView*)textView
{
    NSRange keyRange = [self replacableKeyRangeInTextView:textView];
    return (keyRange.location != NSNotFound);
}

- (NSRange)replacableKeyRangeInTextView:(DVTCompletingTextView*)textView
{
    if (textView == nil)
        return NSMakeRange(NSNotFound, 0);

    DVTTextStorage* textStorage = (DVTTextStorage*)textView.textStorage;
    DVTSourceCodeLanguage* language = textStorage.language;
    NSString* string = textStorage.string;
    NSRange selectedRange = textView.selectedRange;
    //selectedRange.location += 1;
    for (NSDictionary* configuration in self.configurations) {
        for (NSDictionary* patterns in configuration[@"LINKeyCompletionPatterns"]) {
            NSString* pattern = patterns[language.languageName];

            if (pattern && pattern.length > 0) {
                NSRegularExpression* regularExpression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
                NSArray* matches = [regularExpression matchesInString:string options:0 range:NSMakeRange(0, string.length)];

                for (NSTextCheckingResult* match in matches) {
                    if (match.numberOfRanges == 0)
                        continue;
                    NSRange keyRange = [match rangeAtIndex:match.numberOfRanges - 1];
                    if (NSMaxRange(keyRange) == NSMaxRange(selectedRange)) {
                        return keyRange;
                    }
                    if (NSLocationInRange(selectedRange.location, match.range)) {
                        return keyRange;
                    }
                }
            }
        }
    }

    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)replacableTableNameRangeInTextView:(DVTCompletingTextView*)textView
{
    if (textView == nil)
        return NSMakeRange(NSNotFound, 0);

    DVTTextStorage* textStorage = (DVTTextStorage*)textView.textStorage;
    DVTSourceCodeLanguage* language = textStorage.language;
    NSString* string = textStorage.string;
    NSRange selectedRange = textView.selectedRange;

    for (NSDictionary* configuration in self.configurations) {
        for (NSDictionary* patterns in configuration[@"LINTableNameCompletionPatterns"]) {
            NSString* pattern = patterns[language.languageName];

            if (pattern && pattern.length > 0) {
                NSRegularExpression* regularExpression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
                NSArray* matches = [regularExpression matchesInString:string options:0 range:NSMakeRange(0, string.length)];

                for (NSTextCheckingResult* match in matches) {
                    if (match.numberOfRanges == 0)
                        continue;
                    NSRange tableNameRange = [match rangeAtIndex:match.numberOfRanges - 1];

                    if (NSLocationInRange(selectedRange.location, match.range)) {
                        return tableNameRange;
                    }
                }
            }
        }
    }

    return NSMakeRange(NSNotFound, 0);
}

@end
