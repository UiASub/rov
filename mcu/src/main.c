#include <app_version.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include "ota.h"

LOG_MODULE_REGISTER(blinky, LOG_LEVEL_INF);

static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

int main(void)
{
	if (!gpio_is_ready_dt(&led)) {
		LOG_ERR("LED device is not ready");
		return 0;
	}

	int ret = gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE);

	if (ret < 0) {
		LOG_ERR("LED configuration failed: %d", ret);
		return 0;
	}

	ret = ota_init();
	if (ret < 0) {
		LOG_ERR("OTA startup failed: %d", ret);
		return 0;
	}

	LOG_INF("ROV blinky %s on %s", APP_VERSION_STRING, CONFIG_BOARD_TARGET);
	while (true) {
		ret = gpio_pin_toggle_dt(&led);
		if (ret < 0) {
			LOG_ERR("LED toggle failed: %d", ret);
			return 0;
		}
		ota_tick();
		k_sleep(K_MSEC(500));
	}
	return 0;
}
