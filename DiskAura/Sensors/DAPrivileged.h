#import <Foundation/Foundation.h>

/// Runs privileged shell commands behind ONE session-cached authorization. The first call prompts
/// for a password; subsequent calls in the same app session reuse the cached grant (no re-prompt).
/// Lives in Objective-C because AuthorizationExecuteWithPrivileges is unavailable from Swift.
@interface DAPrivileged : NSObject

/// Runs `command` via `/bin/sh -c` as root. Returns captured output. On return, `status` is:
/// 0 = ran, -2 = user cancelled the password prompt, other = failure.
+ (NSString *)run:(NSString *)command status:(int *)status;

@end
