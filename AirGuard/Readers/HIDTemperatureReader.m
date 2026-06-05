#import "HIDTemperatureReader.h"
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

#define IOHIDEventFieldBase(type) (type << 16)

enum {
    kAirSentryIOHIDEventTypeTemperature = 15
};

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

NSDictionary<NSString *, NSNumber *> *AirSentryAppleSiliconSensors(int32_t page, int32_t usage, int32_t type) {
    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(page),
        @"PrimaryUsage": @(usage)
    };

    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (system == nil) {
        return @{};
    }

    IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)matching);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == nil) {
        CFRelease(system);
        return @{};
    }

    NSMutableDictionary<NSString *, NSNumber *> *sensors = [NSMutableDictionary dictionary];
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex index = 0; index < count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        NSString *name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        if (name.length == 0) {
            continue;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, type, 0, 0);
        if (event == nil) {
            continue;
        }

        double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type));
        sensors[name] = @(value);
        CFRelease(event);
    }

    CFRelease(services);
    CFRelease(system);
    return sensors;
}
