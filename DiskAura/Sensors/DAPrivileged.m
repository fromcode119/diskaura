#import "DAPrivileged.h"
#import <Security/Security.h>

// One AuthorizationRef for the whole app session — holding it is what lets macOS cache the
// granted right, so the user authenticates once instead of once per task.
static AuthorizationRef gAuthRef = NULL;

@implementation DAPrivileged

+ (OSStatus)ensureAuthorized {
    if (gAuthRef == NULL) {
        OSStatus created = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                               kAuthorizationFlagDefaults, &gAuthRef);
        if (created != errAuthorizationSuccess) { return created; }
    }
    AuthorizationItem item = { kAuthorizationRightExecute, 0, NULL, 0 };
    AuthorizationRights rights = { 1, &item };
    AuthorizationFlags flags = kAuthorizationFlagDefaults
        | kAuthorizationFlagInteractionAllowed
        | kAuthorizationFlagPreAuthorize
        | kAuthorizationFlagExtendRights;
    return AuthorizationCopyRights(gAuthRef, &rights, kAuthorizationEmptyEnvironment, flags, NULL);
}

+ (NSString *)run:(NSString *)command status:(int *)status {
    OSStatus auth = [self ensureAuthorized];
    if (auth != errAuthorizationSuccess) {
        if (status) { *status = (auth == errAuthorizationCanceled) ? -2 : -1; }
        return @"";
    }

    char *args[] = { "-c", (char *)[command UTF8String], NULL };
    FILE *pipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus ran = AuthorizationExecuteWithPrivileges(gAuthRef, "/bin/sh",
                                                      kAuthorizationFlagDefaults, args, &pipe);
#pragma clang diagnostic pop
    if (ran != errAuthorizationSuccess) {
        if (status) { *status = (int)ran; }
        return @"";
    }

    NSMutableData *data = [NSMutableData data];
    if (pipe) {
        char buffer[4096];
        size_t n;
        while ((n = fread(buffer, 1, sizeof(buffer), pipe)) > 0) {
            [data appendBytes:buffer length:n];
        }
        fclose(pipe);
    }
    if (status) { *status = 0; }
    NSString *out = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return out ?: @"";
}

@end
