#include <zephyr/dfu/mcuboot.h>
#include <zephyr/drivers/watchdog.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/mgmt/mcumgr/transport/smp_udp.h>
#include <zephyr/net/net_config.h>
#include <zephyr/net/net_if.h>
#include <zephyr/sys/reboot.h>

#include "ota.h"
#include "ota_policy.h"

LOG_MODULE_REGISTER(ota, LOG_LEVEL_INF);

static const struct device *const watchdog = DEVICE_DT_GET(DT_ALIAS(watchdog0));
static struct ota_policy policy;

int ota_init(void)
{
	/* MCUboot starts IWDG and feeds it during swaps; the app driver restarts
	 * its 8 s timeout during init. Only the successful main loop feeds it. */
	if (!device_is_ready(watchdog)) {
		return -ENODEV;
	}
	policy = (struct ota_policy) {
		.start_ms = k_uptime_get(), .ready_since_ms = -1,
	};
	int ret = net_config_init("ROV Ethernet OTA", NET_CONFIG_NEED_IPV4, 0);

	if (ret < 0) {
		return ret;
	}
	ret = smp_udp_open();
	if (ret < 0) {
		return ret;
	}
	LOG_INF("MCUmgr on %s:1337; confirmed=%d",
		CONFIG_NET_CONFIG_MY_IPV4_ADDR, boot_is_img_confirmed());
	return 0;
}

void ota_tick(void)
{
	struct net_if *iface = net_if_get_default();
	bool healthy = iface != NULL && net_if_is_up(iface) &&
		       net_if_is_carrier_ok(iface) &&
		       net_if_ipv4_get_global_addr(iface, NET_ADDR_PREFERRED) != NULL;
	enum ota_action action = ota_policy_step(&policy, k_uptime_get(),
		boot_is_img_confirmed(), healthy, IS_ENABLED(CONFIG_ROV_OTA_CONFIRM));

	if (action == OTA_REVERT) {
		LOG_ERR("Trial image did not become healthy; resetting for rollback");
		sys_reboot(SYS_REBOOT_COLD);
	} else if (action == OTA_CONFIRM) {
		int ret = boot_write_img_confirmed();

		if (ret < 0) {
			LOG_ERR("Image confirmation failed: %d", ret);
		} else {
			LOG_INF("Image confirmed after healthy startup and Ethernet link");
		}
	}
	wdt_feed(watchdog, 0);
}
