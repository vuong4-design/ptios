//
//  ScriptListTableCell.m
//  TLinkauto
//
//  Created by Jason on 2020/12/14.
//

#import "ScriptListTableCell.h"
#import "Socket.h"
#import "Util.h"
#import "TLinkAppDiagnostic.h"

@implementation ScriptListTableCell
{
    NSString* filePath;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
}

- (IBAction)playButtonClick:(id)sender {
    APP_DIAG("A0", "play button tapped path=%s", filePath.UTF8String ?: "(null)");
    
    Socket *springBoardSocket = [[Socket alloc] init];
    APP_DIAG("C0", "before socket connect 127.0.0.1:6000");
    [springBoardSocket connect:@"127.0.0.1" byPort:6000];
    APP_DIAG("C1", "socket connected");
    
    NSString *payload = [NSString stringWithFormat:@"19%@", filePath];
    APP_DIAG("A4", "before socket write type=19 len=%lu", (unsigned long)payload.length);
    [springBoardSocket send:payload];
    APP_DIAG("A5", "socket write done");
    
    APP_DIAG("A5B", "before recv (blocking)");
    NSString* result = [springBoardSocket recv:1024];
    APP_DIAG("A6", "recv returned len=%lu result=%.40s", (unsigned long)result.length, result.UTF8String ?: "(null)");
    
    if ([result characterAtIndex:0] != '0')
    {
        [Util showAlertBoxWithOneOption:_parentViewController title:@"Error" message:[NSString stringWithFormat:@"Cannot play script. Error: %@", result] buttonString:@"OK"];
    }
    [springBoardSocket close];
    APP_DIAG("A7", "socket closed, play flow complete");
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void) setTitle:(NSString*)title{
    _scriptTitle.text = title;
}

- (void) hideButton{
    [_playButton setHidden:YES];
}

- (void) showButton{
    [_playButton setHidden:NO];
}

- (void) setPropertyWithPath:(NSString*)path{
    filePath = path;
    
    BOOL isDir = NO;
    _scriptTitle.text = [path lastPathComponent];
    [self showButton];

    if ([[path pathExtension] isEqualToString:@"bdl"]) // is script. can play
    {
        // Now the image will have been loaded and decoded and is ready to rock for the main thread
        [[self imageView] setImage:[UIImage imageNamed:@"script-icon"]];
        
        return;
    }
    
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    [self hideButton];

    if (!isDir)
    {
        [[self imageView] setImage:[UIImage imageNamed:@"normal-file-icon"]];
    }
    else
    {
        [[self imageView] setImage:[UIImage imageNamed:@"folder-icon"]];
    }
}

@end
