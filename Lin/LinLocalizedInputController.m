//
//  LinLocalizedInputController.m
//  Lin
//
//  Created by Jaly on 15/10/22.
//  Copyright © 2015年 Katsuma Tanaka. All rights reserved.
//

#import "LinLocalizedInputController.h"

@interface LinLocalizedInputController ()
@property (weak) IBOutlet NSTextField* selectedTextLabel;
@property (weak) IBOutlet NSTextField* inputLocalizedString;

@end

@implementation LinLocalizedInputController

- (void)windowDidLoad
{
    [super windowDidLoad];

    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [self.selectedTextLabel setStringValue:self.selectedString];
}
- (IBAction)submitAction:(id)sender
{

    NSString* text = self.inputLocalizedString.stringValue;
    [self close];
    if (text != nil && text.length > 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kLocalizedTextInputCompleteNotification object:text];
    }
}

@end
