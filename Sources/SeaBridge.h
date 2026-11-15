#ifndef VIETVIDEO_SEA_BRIDGE
#define VIETVIDEO_SEA_BRIDGE
typedef struct SeaG2p sea_g2p;
int sea_g2p_abi_version(void);
sea_g2p *sea_g2p_open(const char *path);
void sea_g2p_close(sea_g2p *handle);
char *sea_g2p_phonemize(const sea_g2p *handle, const char *text, int punctuation);
const char *sea_g2p_last_error(void);
void sea_g2p_string_free(char *value);
#endif
