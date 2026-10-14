#ifndef ROV_OTA_H
#define ROV_OTA_H

#if defined(CONFIG_BOOTLOADER_MCUBOOT)
int ota_init(void);
void ota_tick(void);
#else
static inline int ota_init(void) { return 0; }
static inline void ota_tick(void) {}
#endif
#endif
