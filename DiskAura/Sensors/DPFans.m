#import "DPFans.h"
#import <IOKit/IOKitLib.h>

// Minimal Apple SMC read client — the well-established struct protocol (smcFanControl / iStats).
// Read-only: we only ever issue kSMCReadKey / kSMCGetKeyInfo, never a write.

@implementation DPFanReading
@end

typedef struct { char major, minor, build, reserved[1]; UInt16 release; } SMCVersion;
typedef struct { UInt16 version; UInt16 length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } SMCPLimitData;
typedef struct { UInt32 dataSize; UInt32 dataType; char dataAttributes; } SMCKeyInfoData;
typedef struct {
    UInt32 key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    char result, status, data8;
    UInt32 data32;
    unsigned char bytes[32];
} SMCKeyData;

enum { kSMCUserClientOpen = 0, kSMCUserClientClose = 1, kSMCHandleYPCEvent = 2,
       kSMCReadKey = 5, kSMCGetKeyInfo = 9 };

static UInt32 DPKey(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

static kern_return_t DPCall(io_connect_t conn, SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(SMCKeyData), out, &outSize);
}

// Decode SMC numeric value. Apple Silicon fan keys are IEEE float ("flt "); older are fpe2.
static double DPDecode(SMCKeyData *v) {
    UInt32 type = v->keyInfo.dataType;
    const unsigned char *b = v->bytes;
    if (type == DPKey("flt ")) { float f; memcpy(&f, b, sizeof(f)); return (double)f; }
    if (type == DPKey("fpe2")) { return (double)(((b[0] << 8) | b[1]) >> 2); }
    if (v->keyInfo.dataSize == 2) { return (double)((b[0] << 8) | b[1]); }
    return (double)b[0];
}

static BOOL DPReadKey(io_connect_t conn, const char *key, double *out) {
    SMCKeyData in; SMCKeyData info; SMCKeyData val;
    memset(&in, 0, sizeof(in)); memset(&info, 0, sizeof(info)); memset(&val, 0, sizeof(val));
    in.key = DPKey(key);
    in.data8 = kSMCGetKeyInfo;
    if (DPCall(conn, &in, &info) != kIOReturnSuccess || info.result != 0) return NO;

    val.key = DPKey(key);
    val.keyInfo = info.keyInfo;
    val.data8 = kSMCReadKey;
    if (DPCall(conn, &val, &val) != kIOReturnSuccess || val.result != 0) return NO;
    *out = DPDecode(&val);
    return YES;
}

NSArray<DPFanReading *> *DPReadFans(void) {
    NSMutableArray<DPFanReading *> *fans = [NSMutableArray array];

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                       IOServiceMatching("AppleSMC"));
    if (!service) return fans;

    io_connect_t conn = 0;
    if (IOServiceOpen(service, mach_task_self(), 0, &conn) != kIOReturnSuccess) {
        IOObjectRelease(service);
        return fans;
    }

    double count = 0;
    if (DPReadKey(conn, "FNum", &count) && count >= 1) {
        for (int i = 0; i < (int)count && i < 8; i++) {
            char acKey[5], mnKey[5], mxKey[5];
            snprintf(acKey, sizeof(acKey), "F%dAc", i);
            snprintf(mnKey, sizeof(mnKey), "F%dMn", i);
            snprintf(mxKey, sizeof(mxKey), "F%dMx", i);
            double ac = 0, mn = 0, mx = 0;
            if (!DPReadKey(conn, acKey, &ac)) continue;
            DPReadKey(conn, mnKey, &mn);
            DPReadKey(conn, mxKey, &mx);
            DPFanReading *r = [DPFanReading new];
            r.index = i;
            r.rpm = (NSInteger)llround(ac);
            r.minRpm = (NSInteger)llround(mn);
            r.maxRpm = (NSInteger)llround(mx);
            [fans addObject:r];
        }
    }

    IOServiceClose(conn);
    IOObjectRelease(service);
    return fans;
}
