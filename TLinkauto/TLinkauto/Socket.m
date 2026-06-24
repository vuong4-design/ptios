//
//  Socket.m
//  TLinkauto
//
//  Created by Jason on 2020/12/11.
//

#import "Socket.h"
#import "TLinkAppDiagnostic.h"


@implementation Socket
{
    int socketHandle;
}

/**
 Connect to a server, return -1 if fail
 */
-(int) connect: (NSString*) ip byPort:(int) port
{
    APP_DIAG("SK-C0", "socket() creating SOCK_STREAM");
    //NSLog(@"ip: %@, and port: %d", ip, port);
    int sock = 0;
    struct sockaddr_in serv_addr;

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob:  Socket creation error");
        APP_DIAG("SK-C0E", "socket() failed");
        return -1;
        
    }
    APP_DIAG("SK-C1", "socket() created fd=%d", sock);
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    // Convert IPv4 and IPv6 addresses from text to binary form
    if(inet_pton(AF_INET, [ip UTF8String], &serv_addr.sin_addr)<=0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: Invalid address. Address not supported");
        return -1;
    }

    APP_DIAG("SK-C2", "before connect() to %s:%d", [ip UTF8String], port);
    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0)
    {
        NSLog(@"### com.tlinkauto.tlinkautob: \nConnection Failed \n");
        APP_DIAG("SK-C2E", "connect() failed errno=%d", errno);
        return -1;
    }
    APP_DIAG("SK-C3", "connect() succeeded fd=%d", sock);
    socketHandle = sock;
    return 0;
}

-(BOOL) isConnected {
    return socketHandle != 0;
}

-(void) send: (NSString*)msg
{
    const char *buffer = [msg UTF8String];
    size_t len = strlen(buffer);
    APP_DIAG("SK-W0", "before send() len=%zu fd=%d", len, socketHandle);
    ssize_t sent = send(socketHandle , buffer, len , 0);
    APP_DIAG("SK-W1", "send() returned=%zd", sent);
}

-(void) sendChar: (char*)msg
{
    send(socketHandle , msg, strlen(msg) , 0);
}

-(NSString*) recv:(int)length
{
    char buffer[length];
    memset(buffer, 0, sizeof(buffer));
    APP_DIAG("SK-R0", "before recv() maxlen=%d fd=%d", length, socketHandle);
    ssize_t received = recv(socketHandle, buffer, length, 0);
    APP_DIAG("SK-R1", "recv() returned=%zd", received);
    return [NSString stringWithUTF8String:buffer];
}

-(void)close {
    if (!socketHandle)
        return;
    close(socketHandle);
    socketHandle = 0;
}

-(void)dealloc {
    [self close];
}

@end
