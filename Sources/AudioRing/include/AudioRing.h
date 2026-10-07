#ifndef AUDIO_RING_H
#define AUDIO_RING_H
#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

typedef struct EQRing EQRing;
// One producer and one consumer. Destroy only after both callbacks have stopped.
EQRing *eq_ring_create(uint32_t capacity, uint32_t prefill);
void eq_ring_destroy(EQRing *ring);
void eq_ring_write(EQRing *ring, const AudioBufferList *input);
void eq_ring_read(EQRing *ring, AudioBufferList *output, uint32_t frames);
float eq_ring_peak(EQRing *ring);
uint64_t eq_ring_received(EQRing *ring);
uint64_t eq_ring_dropped(EQRing *ring);
uint64_t eq_ring_underruns(EQRing *ring);
#endif
