#import <Foundation/Foundation.h>

/// One fan's live reading. `rpm`/`minRpm`/`maxRpm` are 0 when unavailable.
@interface DPFanReading : NSObject
@property (nonatomic) NSInteger index;
@property (nonatomic) NSInteger rpm;
@property (nonatomic) NSInteger minRpm;
@property (nonatomic) NSInteger maxRpm;
@end

/// Reads fan RPM from the Apple SMC (AppleSMC IOService, read-only). Returns an empty array on
/// machines with no fans (e.g. MacBook Air) or when the SMC is unreadable. NEVER writes the SMC —
/// fan-speed control is unsupported and unsafe on Apple Silicon.
NSArray<DPFanReading *> *DPReadFans(void);
