#import "DPTemperature.h"
#import <IOKit/IOKitLib.h>

// Private IOKit HID event-system symbols — exported by IOKit.framework but not in the public
// headers. The same approach open-source sensor tools (Stats, macmon) use to read Apple Silicon
// temperatures without a privileged helper.
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type,
                                                 int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kIOHIDEventTypeTemperature 15
#define DPTemperatureField (kIOHIDEventTypeTemperature << 16)

// Collect all plausible temperature readings (°C). `outPeak` receives the hottest.
static NSArray<NSNumber *> *DPCollectTemperatures(double *outPeak) {
    NSMutableArray<NSNumber *> *temps = [NSMutableArray array];
    double peak = 0;

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!system) { if (outPeak) *outPeak = 0; return temps; }

    // PrimaryUsagePage 0xff00 / PrimaryUsage 5 == the AppleARM temperature sensors.
    NSDictionary *matching = @{ @"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(5) };
    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services) {
        for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            if (!service) continue;
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
            if (event) {
                double t = IOHIDEventGetFloatValue(event, DPTemperatureField);
                if (t > 1.0 && t < 130.0) {
                    [temps addObject:@(t)];
                    if (t > peak) peak = t;
                }
                CFRelease(event);
            }
        }
        CFRelease(services);
    }
    CFRelease(system);
    if (outPeak) *outPeak = peak;
    return temps;
}

double DPReadAverageTemperature(void) {
    NSArray<NSNumber *> *temps = DPCollectTemperatures(NULL);
    if (temps.count == 0) return 0;
    double sum = 0;
    for (NSNumber *n in temps) sum += n.doubleValue;
    return sum / (double)temps.count;
}

double DPReadPeakTemperature(void) {
    double peak = 0;
    DPCollectTemperatures(&peak);
    return peak;
}
