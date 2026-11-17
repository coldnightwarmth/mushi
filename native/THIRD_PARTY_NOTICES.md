# Native service references

The native program translator is project code. It generates fixed C++ functions
at build time; the application does not contain an SH instruction decoder, JIT,
MAME executable, MAME machine framework, or CPU interpreter.

The following BSD-3-Clause MAME 0.286 components informed the native peripheral
services. Their algorithms are adapted independently of MAME's device framework:

- `src/mame/cave/cv1k_v.cpp`, `cv1k_v.h`, `cv1k_v_in.ipp`,
  `cv1k_v_pixel.ipp`: David Haywood, Luca Elia, MetalliC.
- `src/devices/sound/ymz770.cpp`, `ymz770.h`: Olivier Galibert,
  R. Belmont, MetalliC.
- `src/devices/machine/rtc9701.cpp`: Angelo Salese, David Haywood.
- SH7709 register maps and exception semantics were checked against the
  BSD-licensed `src/devices/cpu/sh/` reference, including R. Belmont's SH3
  internal-register implementation.

`vendor/mpeg_audio.cpp` and `vendor/mpeg_audio.h` are Olivier Galibert's
BSD-3-Clause MPEG/AMM decoder from MAME tag `mame0286`. The only integration
changes replace `emu.h` with standard C++ headers and add `<cstdint>` to the
header. This is a native audio codec, independent of the CPU and machine runtime.

Upstream: https://github.com/mamedev/mame/tree/mame0286

## BSD 3-Clause license

Copyright holders are listed above and in the individual source files.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
