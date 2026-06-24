#ifndef TLINKAUTO_JS_RUNTIME_H
#define TLINKAUTO_JS_RUNTIME_H

#import <Foundation/Foundation.h>

@interface TLinkautoJSRuntime : NSObject

@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) NSString *runId;

@class TLinkTaskExecutionContext;

- (BOOL)runScriptAtPath:(NSString *)scriptPath bundlePath:(NSString *)bundlePath manifest:(NSDictionary *)manifest context:(TLinkTaskExecutionContext *)context error:(NSError **)error;
- (void)requestStop;
- (BOOL)isAborted;

@end

#endif
