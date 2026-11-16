/* CV1000 resource LZ: bounded native implementation of the decoded format.
 * Original Futari decompressor entry: 0x0c002ac4. See reverse-engineering notes.
 * Format reference: buffis/cv1k_research U4_Utils/compress.py.
 */
#include "lz.h"

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

int mushi_lz_decode(const uint8_t *src, size_t src_size, uint8_t *dst,
                    size_t dst_capacity, size_t *written, size_t *consumed) {
    if (!src || !dst || !written || !consumed || src_size < 12) return -1;
    *written = 0; *consumed = 0;
    size_t size = be32(src), count = be32(src + 4), cursor = be32(src + 8);
    if (size > dst_capacity || count > size || cursor > src_size ||
        12 + (count + 7) / 8 > cursor) return -1;
    size_t out = 0;
    for (size_t op = 0; op < count; ++op) {
        int reference = (src[12 + op / 8] >> (7 - op % 8)) & 1;
        if (src_size - cursor < (size_t)(reference ? 2 : 1)) return -1;
        if (reference) {
            unsigned token = ((unsigned)src[cursor] << 8) | src[cursor + 1];
            size_t distance = token >> 5, length = (token & 31) + 3;
            if (distance == 0 || distance > out || length > size - out) return -1;
            for (size_t i = 0; i < length; ++i) {
                dst[out] = dst[out - distance];
                ++out;
            }
            cursor += 2;
        } else {
            if (out == size) return -1;
            dst[out++] = src[cursor++];
        }
    }
    if (out != size) return -1;
    *written = out; *consumed = cursor;
    return 0;
}
