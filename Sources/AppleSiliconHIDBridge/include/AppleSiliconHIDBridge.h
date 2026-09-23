#ifndef AppleSiliconHIDBridge_h
#define AppleSiliconHIDBridge_h

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*CDHIDTemperatureVisitor)(const char *name, double celsius, void *context);

/// Visits the temperature services exposed by Apple Silicon's HID event system.
/// This interface is read-only and never sends a report or changes hardware state.
size_t CDVisitAppleSiliconTemperatures(CDHIDTemperatureVisitor visitor, void *context);

#ifdef __cplusplus
}
#endif

#endif
