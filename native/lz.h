#ifndef MUSHI_LZ_H
#define MUSHI_LZ_H
#include <stddef.h>
#include <stdint.h>
/* Returns zero on success, -1 on malformed input or inadequate output capacity.
 * This is a native resource service, not a gameplay emulator.
 * Neither output bytes nor consumed bytes are valid after an error. */
int mushi_lz_decode(const uint8_t *src, size_t src_size, uint8_t *dst,
                    size_t dst_capacity, size_t *written, size_t *consumed);
#endif
