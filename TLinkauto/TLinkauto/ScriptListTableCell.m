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
    [_playButton addTarget:self action:@selector(playTouchDown:) forControlEvents:UIControlEventTouchDown];
}

- (void)playTouchDown:(UIButton *)sender {
    APP_DIAG("UI-DOWN", "play touch down path=%s", filePath.UTF8String ?: "(null)");
}

- (IBAction)playButtonClick:(id)sender {
    APP_DIAG("A0", "play button tapped path=%s", filePath.UTF8String ?: "(null)");
    
    // Capture values needed by the block
    NSString *path = [filePath copy];
    __weak UIViewController *weakParent = _parentViewController;
    
    // Disable button immediately to prevent double-tap
    _playButton.enabled = NO;
    
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        APP_DIAG("A1", "entered background queue");
        
        Socket *springBoardSocket = [[Socket alloc] init];
        APP_DIAG("C0", "before socket connect 127.0.0.1:6000");
        int connectResult = [springBoardSocket connect:@"127.0.0.1" byPort:6000];
        APP_DIAG("C1", "socket connected result=%d", connectResult);
        
        if (connectResult < 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_playButton.enabled = YES;
                UIViewController *parent = weakParent;
                if (parent) {
                    [Util showAlertBoxWithOneOption:parent title:@"Error" message:@"Cannot connect to SpringBoard socket." buttonString:@"OK"];
                }
            });
            return;
        }
        
        NSString *payload = [NSString stringWithFormat:@"19%@", path];
        APP_DIAG("A4", "before socket write type=19 len=%lu", (unsigned long)payload.length);
        [springBoardSocket send:payload];
        APP_DIAG("A5", "socket write done");
        
        APP_DIAG("A5B", "before recv");
        NSString *result = [springBoardSocket recv:1024];
        APP_DIAG("A6", "recv returned len=%lu result=%.40s", (unsigned long)result.length, result.UTF8String ?: "(null)");
        
        [springBoardSocket close];
        APP_DIAG("A7", "socket closed, play flow complete");
        
        APP_DIAG("UI-R0", "before enqueue result block");
        dispatch_async(dispatch_get_main_queue(), ^{
            APP_DIAG("UI-R1", "entered result block");
            self->_playButton.enabled = YES;
            APP_DIAG("UI-R2", "button re-enabled");
            if (result.length > 0 && [result characterAtIndex:0] != '0') {
                UIViewController *parent = weakParent;
                if (parent) {
                    [Util showAlertBoxWithOneOption:parent title:@"Error" message:[NSString stringWithFormat:@"Cannot play script. Error: %@", result] buttonString:@"OK"];
                }
            }
        });
    });
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
