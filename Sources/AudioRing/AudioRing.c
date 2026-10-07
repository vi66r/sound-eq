#include "AudioRing.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

struct EQRing {
    float *samples;
    uint32_t capacity, prefill;
    _Atomic uint64_t write, read, received, dropped, underruns;
    _Atomic float peak;
    // Only the consumer accesses primed.
    bool primed;
};

EQRing *eq_ring_create(uint32_t capacity, uint32_t prefill) {
    if (capacity < 2 || prefill >= capacity) return NULL;
    EQRing *r = calloc(1, sizeof(EQRing));
    if (!r) return NULL;
    r->samples = calloc((size_t)capacity * 2, sizeof(float));
    if (!r->samples) { free(r); return NULL; }
    r->capacity = capacity; r->prefill = prefill;
    atomic_init(&r->write, 0); atomic_init(&r->read, 0);
    atomic_init(&r->received, 0); atomic_init(&r->dropped, 0);
    atomic_init(&r->underruns, 0); atomic_init(&r->peak, 0);
    return r;
}

void eq_ring_destroy(EQRing *r) { if (r) { free(r->samples); free(r); } }

void eq_ring_write(EQRing *r, const AudioBufferList *input) {
    if (!r || !input || !input->mNumberBuffers) return;
    const AudioBuffer *a = &input->mBuffers[0];
    const AudioBuffer *b = input->mNumberBuffers > 1 ? &input->mBuffers[1] : a;
    if (!a->mData || !b->mData || !a->mNumberChannels || !b->mNumberChannels) return;
    uint32_t frames = a->mDataByteSize / (sizeof(float) * a->mNumberChannels);
    uint32_t bframes = b->mDataByteSize / (sizeof(float) * b->mNumberChannels);
    if (bframes < frames) frames = bframes;
    uint64_t w = atomic_load_explicit(&r->write, memory_order_relaxed);
    uint64_t rd = atomic_load_explicit(&r->read, memory_order_acquire);
    uint32_t available = r->capacity - (uint32_t)(w - rd);
    uint32_t count = frames < available ? frames : available;
    float peak = 0;
    const float *left = a->mData, *right = b->mData;
    uint32_t rightOffset = a == b && a->mNumberChannels > 1 ? 1 : 0;
    for (uint32_t i = 0; i < count; ++i) {
        float l = left[i * a->mNumberChannels];
        float rr = right[i * b->mNumberChannels + rightOffset];
        if (!isfinite(l)) l = 0;
        if (!isfinite(rr)) rr = 0;
        uint32_t index = (uint32_t)((w + i) % r->capacity) * 2;
        r->samples[index] = l; r->samples[index + 1] = rr;
        peak = fmaxf(peak, fmaxf(fabsf(l), fabsf(rr)));
    }
    atomic_store_explicit(&r->write, w + count, memory_order_release);
    atomic_store_explicit(&r->peak, peak, memory_order_relaxed);
    atomic_fetch_add_explicit(&r->received, frames, memory_order_relaxed);
    atomic_fetch_add_explicit(&r->dropped, frames - count, memory_order_relaxed);
}

void eq_ring_read(EQRing *r, AudioBufferList *output, uint32_t frames) {
    for (uint32_t b = 0; b < output->mNumberBuffers; ++b) {
        if (output->mBuffers[b].mData)
            memset(output->mBuffers[b].mData, 0, output->mBuffers[b].mDataByteSize);
    }
    if (!r) return;
    uint64_t rd = atomic_load_explicit(&r->read, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&r->write, memory_order_acquire);
    uint64_t available = w - rd;
    if (!r->primed) {
        if (available < r->prefill || available < frames) return;
        r->primed = true;
    }
    // Bound latency if the output was stalled. Only the consumer moves read.
    if (available > r->capacity / 2 && available > frames + r->prefill) {
        uint64_t skip = available - frames - r->prefill;
        rd += skip; available -= skip;
        atomic_fetch_add_explicit(&r->dropped, skip, memory_order_relaxed);
    }
    uint32_t count = available < frames ? (uint32_t)available : frames;
    for (uint32_t b = 0, channel = 0; b < output->mNumberBuffers; ++b) {
        AudioBuffer *out = &output->mBuffers[b];
        if (!out->mNumberChannels) continue;
        uint32_t size = out->mDataByteSize / (sizeof(float) * out->mNumberChannels);
        uint32_t safeCount = count < size ? count : size;
        if (out->mData) {
            float *data = out->mData;
            for (uint32_t i = 0; i < safeCount; ++i)
                for (uint32_t c = 0; c < out->mNumberChannels; ++c)
                    data[i * out->mNumberChannels + c] = r->samples[((rd + i) % r->capacity) * 2 + ((channel + c) % 2)];
        }
        channel += out->mNumberChannels;
    }
    atomic_store_explicit(&r->read, rd + count, memory_order_release);
    if (count < frames) {
        r->primed = false;
        atomic_fetch_add_explicit(&r->underruns, 1, memory_order_relaxed);
    }
}

float eq_ring_peak(EQRing *r) { return atomic_load_explicit(&r->peak, memory_order_relaxed); }
uint64_t eq_ring_received(EQRing *r) { return atomic_load_explicit(&r->received, memory_order_relaxed); }
uint64_t eq_ring_dropped(EQRing *r) { return atomic_load_explicit(&r->dropped, memory_order_relaxed); }
uint64_t eq_ring_underruns(EQRing *r) { return atomic_load_explicit(&r->underruns, memory_order_relaxed); }
