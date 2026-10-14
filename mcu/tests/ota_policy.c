#include <assert.h>
#include "ota_policy.h"

int main(void)
{
	struct ota_policy policy = { .start_ms = 0, .ready_since_ms = -1 };
	assert(ota_policy_step(&policy, 0, false, true, true) == OTA_WAIT);
	assert(ota_policy_step(&policy, 4999, false, true, true) == OTA_WAIT);
	assert(ota_policy_step(&policy, 5000, false, true, true) == OTA_CONFIRM);
	/* Dropping the link discards the healthy interval. */
	assert(ota_policy_step(&policy, 5500, false, false, true) == OTA_WAIT);
	assert(ota_policy_step(&policy, 6000, false, true, true) == OTA_WAIT);
	assert(ota_policy_step(&policy, 10999, false, true, true) == OTA_WAIT);
	assert(ota_policy_step(&policy, 11000, false, true, true) == OTA_CONFIRM);
	assert(ota_policy_step(&policy, 60000, false, true, true) == OTA_REVERT);
	/* A confirmed image may operate offline indefinitely. */
	assert(ota_policy_step(&policy, 90000, true, false, true) == OTA_WAIT);
	policy = (struct ota_policy) { .start_ms = 1000, .ready_since_ms = -1 };
	assert(ota_policy_step(&policy, 1000, false, true, false) == OTA_WAIT);
	assert(ota_policy_step(&policy, 60999, false, true, false) == OTA_WAIT);
	assert(ota_policy_step(&policy, 61000, false, true, false) == OTA_REVERT);
	/* Failed confirmation writes remain unconfirmed and eventually revert. */
	policy = (struct ota_policy) { .start_ms = 0, .ready_since_ms = 0 };
	assert(ota_policy_step(&policy, 59999, false, true, true) == OTA_CONFIRM);
	assert(ota_policy_step(&policy, 60000, false, true, true) == OTA_REVERT);
	return 0;
}
