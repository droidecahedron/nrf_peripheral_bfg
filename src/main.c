/*
 * nrf_peripheral_bfg
 * main.c
 * Bluetooth fuel gauge seeed board workshop main file
 * SPDX-License-Identifier: LicenseRef-Nordic-5-Clause
 */

#include <zephyr/kernel.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/logging/log.h>


LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);

static const struct gpio_dt_spec bt_status_led = GPIO_DT_SPEC_GET(DT_NODELABEL(led0), gpios);

int main(void)
{
    int err;

    err = gpio_pin_configure_dt(&bt_status_led, GPIO_OUTPUT_INACTIVE);
    if (err)
    {
        LOG_WRN("Configuring BT status LED failed (err %d)", err);
        return -1;
    }

    for (;;)
    {
        gpio_pin_set_dt(&bt_status_led, 1);
        k_msleep(500);
        LOG_INF("I am alive");
        gpio_pin_set_dt(&bt_status_led, 0);
        k_msleep(2000);
    }
    return 0;
}
