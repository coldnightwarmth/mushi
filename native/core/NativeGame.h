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
FutariStatus futari_world_status(FutariGame game,unsigned world);
// 0 startup, 1 attract, 2 selections, 3 gameplay, 4 operator,
// 5 ending, 6 game over, 7 ranking, 8 transition/loading.
int futari_scene(FutariGame game);
typedef struct {
    int infinite_credits,infinite_bombs,protection,formation,combined;
    int exploration,boost,horizontal,rewind_enabled,random_trails;
} FutariCustomOptions;
typedef struct {
    int credits,lives,bombs,character,shot,player_x,player_y,wing_active;
    unsigned rewind_frames,worlds;
    uint64_t rewind_bytes,absorbed;
} FutariCustomStatus;
void futari_configure(FutariGame game,FutariCustomOptions options);
void futari_boost(FutariGame game,int held);
FutariCustomStatus futari_custom_status(FutariGame game);
int futari_rewind(FutariGame game,unsigned frames);
int futari_presentation_ready(FutariGame game);
// Layers: 0 native composition, 1 scenery, 2 actors, 3 HUD, 4 burst effects,
// 5 observed sprite variants for Random trails (presentation only).
// Width <= 304 and height <= 384 reveal the original rendered overscan.
void futari_layer_pixels(FutariGame game,unsigned world,int layer,int width,int height,uint8_t *rgba);
#ifdef __cplusplus
}
#endif
