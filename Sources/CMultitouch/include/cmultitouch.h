#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdint.h>

/// One contact as delivered by the system multitouch frame callback.
/// The layout is fixed at 96 bytes; the assertion below guards it at compile time.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    float nx, ny, nvx, nvy;
    float total;
    float pressure;
    float angle;
    float majorAxis;
    float minorAxis;
    float ax, ay, avx, avy;
    int32_t reserved0, reserved1;
    float density;
} MTTouch;

_Static_assert(sizeof(MTTouch) == 96, "MTTouch must be 96 bytes");

/// Opaque handle to a multitouch device.
typedef void *MTDeviceRef;

/// Frame callback: device, contacts, contact count, timestamp (seconds), frame number.
typedef void (*MTFrameCallback)(MTDeviceRef, MTTouch *, int32_t, double, int32_t);

#endif
