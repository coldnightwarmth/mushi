#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void *FutariGame;
FutariGame futari_create(const char *resources,const char *settings);
void futari_destroy(FutariGame game);
const char *futari_error(FutariGame game);
int futari_frame(FutariGame game,uint8_t port_c,uint8_t port_d);
void futari_pixels(FutariGame game,uint8_t *rgba);
const float *futari_audio(FutariGame game,unsigned *count);
uint64_t futari_frame_number(FutariGame game);
int futari_save_settings(FutariGame game);
void futari_test_switch(FutariGame game,int enabled);
int futari_restart(FutariGame game);
int futari_restart_stage(FutariGame game);
int futari_title(FutariGame game);
typedef struct {
    int phase,stage,stage_count,mode,all_clear,can_restart_stage;
} FutariStatus;
FutariStatus futari_status(FutariGame game);
// 0 startup, 1 attract, 2 selections, 3 gameplay, 4 operator,
// 5 ending, 6 game over, 7 ranking, 8 transition/loading.
int futari_scene(FutariGame game);
#ifdef __cplusplus
}
#endif
