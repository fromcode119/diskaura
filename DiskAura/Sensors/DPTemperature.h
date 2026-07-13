#import <Foundation/Foundation.h>

/// Average of the Mac's thermal sensors in °C (0 if none could be read). Uses IOKit's HID
/// event-system temperature sensors, which are readable on Apple Silicon without root or a
/// privileged helper — unlike the legacy Intel SMC keys.
double DPReadAverageTemperature(void);

/// The single hottest thermal sensor in °C — the "how hot is it right now" figure.
double DPReadPeakTemperature(void);
