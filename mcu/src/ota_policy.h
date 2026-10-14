#ifndef ROV_OTA_POLICY_H
#define ROV_OTA_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#define OTA_HEALTH_MS 5000
#define OTA_TRIAL_MS 60000

enum ota_action { OTA_WAIT, OTA_CONFIRM, OTA_REVERT };

struct ota_policy {
	int64_t start_ms;
	int64_t ready_since_ms;
};

static inline enum ota_action ota_policy_step(struct ota_policy *policy,
		int64_t now, bool confirmed, bool healthy, bool allow_confirm)
{
	if (confirmed) {
		return OTA_WAIT;
	}
	if (now - policy->start_ms >= OTA_TRIAL_MS) {
		return OTA_REVERT;
	}
	if (!healthy) {
		policy->ready_since_ms = -1;
	} else if (policy->ready_since_ms < 0) {
		policy->ready_since_ms = now;
	} else if (allow_confirm && now - policy->ready_since_ms >= OTA_HEALTH_MS) {
		return OTA_CONFIRM;
	}
	return OTA_WAIT;
}
#endif
