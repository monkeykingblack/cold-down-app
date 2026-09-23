#include "AppleSiliconHIDBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <math.h>

typedef struct __IOHIDEvent *IOHIDEventRef;

// These read-only event APIs are present in IOKit but are not part of the
// module's Swift surface. Keep them confined to this narrow bridge.
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(
    IOHIDServiceClientRef service,
    int64_t type,
    int32_t options,
    int64_t timestamp
);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static const int32_t CDTemperatureEventType = 15;
static const int32_t CDAppleVendorUsagePage = 0xff00;
static const int32_t CDTemperatureSensorUsage = 0x0005;

size_t CDVisitAppleSiliconTemperatures(CDHIDTemperatureVisitor visitor, void *context) {
    if (visitor == NULL) {
        return 0;
    }

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return 0;
    }

    CFNumberRef usagePage = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &CDAppleVendorUsagePage
    );
    CFNumberRef usage = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &CDTemperatureSensorUsage
    );
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[] = { usagePage, usage };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(usagePage);
    CFRelease(usage);

    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return 0;
    }

    size_t count = 0;
    CFIndex serviceCount = CFArrayGetCount(services);
    for (CFIndex index = 0; index < serviceCount; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, CDTemperatureEventType, 0, 0);

        if (product != NULL &&
            CFGetTypeID(product) == CFStringGetTypeID() &&
            event != NULL) {
            char name[256];
            double value = IOHIDEventGetFloatValue(
                event,
                CDTemperatureEventType << 16
            );
            if (isfinite(value) &&
                CFStringGetCString((CFStringRef)product, name, sizeof(name), kCFStringEncodingUTF8)) {
                visitor(name, value, context);
                count++;
            }
        }

        if (event != NULL) {
            CFRelease(event);
        }
        if (product != NULL) {
            CFRelease(product);
        }
    }

    CFRelease(services);
    CFRelease(client);
    return count;
}
