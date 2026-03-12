## Goal and Progression Path
```mermaid
graph LR;
  main-->proof_of_life;
  proof_of_life-->pmic*;
  pmic*-->ble;
```
> `*` == your current location

> _If you're really stuck, the `main.c` and `prj.conf` of each branch will be the solution for each step._

### Preface
So now, let's start using the nPM2100 PMIC!

<img width="493" height="153" alt="image" src="https://github.com/user-attachments/assets/b931fa19-923d-4b30-ac20-62ad89cc9dcd" />

On top of being the power distribution network and all the other features it sports, what we really want to do is leverage the fuel gauge to estimate the state of charge of the battery and to retrieve the battery voltage. This would be quite hard to represent and validate on a single LED, so we will rely on RTT logging quite a bit here.




### Step 1
First, let's enable the fuel gauge in `prj.conf` again. Add the following below your logging configs.
```
# Fuel gauge
CONFIG_NRF_FUEL_GAUGE=y
CONFIG_NRF_FUEL_GAUGE_VARIANT_PRIMARY_CELL=y
```

### Step 2
Now add the following libraries to interact with the PMIC via `#include` at the top of `main.c`.
```c
#include <stdint.h>
#include <math.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/drivers/mfd/npm2100.h>
#include <zephyr/drivers/regulator.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/drivers/sensor/npm2100_vbat.h>
#include <zephyr/dt-bindings/regulator/npm2100.h>
#include <zephyr/sys/util.h>

#include <string.h>
#include <zephyr/device.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/drivers/sensor/npm2100_vbat.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/util.h>
#include <nrf_fuel_gauge.h>
```

### Step 3
Now we will add the following globals below our log module register, set up the battery model to be the LR44 that comes on the Seeed board, and instantiate some more devices for the peripherals used to talk to the nPM2100, similar to how we set up the LED in the proof of life section.
```c
static int64_t ref_time;
static bool fuel_gauge_initialized;

static const struct battery_model_primary battery_model = {
#include <battery_models/primary_cell/LR44.inc>
};
#define AVERAGE_CURRENT (CONFIG_ACTIVE_CURRENT_UA * 1e-6f)

static const struct i2c_dt_spec pmic_i2c = I2C_DT_SPEC_GET(DT_NODELABEL(npm2100_pmic));
static const struct device *pmic_regulators = DEVICE_DT_GET(DT_NODELABEL(npm2100_regulators));
static const struct device *vbat = DEVICE_DT_GET(DT_NODELABEL(npm2100_vbat));
```

### Step 4
We will now create 2 threads to work with the PMIC. One to run the fuel gauging, and that will be idle for now but we will later use to handle requests to the PMIC.

Add the following `#define`s near the top of the `main.c` file around where the log module is registered.
```c
#define PMIC_THREAD_STACK_SIZE 1024
#define PMIC_THREAD_PRIORITY 5
#define PMIC_SLEEP_INTERVAL_MS 1000
```

and add the following thread creation defines at the bottom of the `main.c` file, _outside_ the main function.

```c
K_THREAD_DEFINE(pmic_reg_thread_id, PMIC_THREAD_STACK_SIZE, pmic_reg_thread, NULL, NULL, NULL, PMIC_THREAD_PRIORITY, 0,
                1000);
K_THREAD_DEFINE(pmic_fg_thread_id, PMIC_THREAD_STACK_SIZE, pmic_fg_thread, NULL, NULL, NULL, PMIC_THREAD_PRIORITY, 0,
                0);
```

### Step 5
Now, let's add some helper functions above the `main()` function.

- A function to check the SHPHLD state.
```c
static int shphld_state(bool *state)
{
    int ret;
    uint8_t reg;

    ret = i2c_reg_read_byte_dt(&pmic_i2c, 0x16, &reg);
    if (ret)
    {
        LOG_ERR("Could not read STATUS register (%d)", ret);
        return ret;
    }
    *state = reg & 1U;

    return 0;
}
```

- A function to grab the battery voltage.
```c
static int read_sensors(const struct device *vbat, float *voltage, float *temp)
{
    struct sensor_value value;
    int ret;

    ret = sensor_sample_fetch(vbat);
    if (ret < 0)
    {
        return ret;
    }

    sensor_channel_get(vbat, SENSOR_CHAN_GAUGE_VOLTAGE, &value);
    *voltage = (float)value.val1 + ((float)value.val2 / 1000000);

    sensor_channel_get(vbat, SENSOR_CHAN_DIE_TEMP, &value);
    *temp = (float)value.val1 + ((float)value.val2 / 1000000);

    return 0;
}
```

- A function to initialize the fuel gauge.
```c
int fuel_gauge_init(const struct device *vbat, char *bat_name, size_t n)
{
    int err;
    bool state;

    if (!device_is_ready(pmic_regulators))
    {
        LOG_ERR("PMIC device is not ready (init_res: %d)", pmic_regulators->state->init_res);
        return -ENODEV;
    }
    LOG_INF("PMIC device ok");

    // check if we are in shphld. if it's high, we are "awake", so engage fuel gauge and typical operation.
    err = shphld_state(&state);
    if (err)
    {
        return err;
    }
    struct nrf_fuel_gauge_init_parameters parameters = {
        .model_primary = &battery_model,
        .i0 = AVERAGE_CURRENT,
        .opt_params = NULL,
    };
    struct nrf_fuel_gauge_runtime_parameters rt_params = {
        .a = NAN,
        .b = NAN,
        .c = NAN,
        .d = NAN,
        .discard_positive_deltaz = true,
    };
    int ret;

    ret = read_sensors(vbat, &parameters.v0, &parameters.t0);
    if (ret < 0)
    {
        return ret;
    }

    ret = nrf_fuel_gauge_init(&parameters, NULL);
    if (ret < 0)
    {
        return ret;
    }

    ref_time = k_uptime_get();
    nrf_fuel_gauge_param_adjust(&rt_params);
    strncpy(bat_name, battery_model.name, n);
    err = 0;

    return err;
}
```

- And a function to update the fuel gauge.
```c
int fuel_gauge_update(const struct device *vbat, uint8_t *soc)
{
    float voltage;
    float temp;
    float delta;
    int ret;

    ret = read_sensors(vbat, &voltage, &temp);
    if (ret < 0)
    {
        return ret;
    }

    delta = (float)k_uptime_delta(&ref_time) / 1000.f;

    *soc = (uint8_t)nrf_fuel_gauge_process(voltage, AVERAGE_CURRENT, temp, delta, NULL);

    LOG_INF("PMIC Thread sending: V: %.3f, T: %.2f, SoC: %d", (double)voltage, (double)temp, *soc);

    return 0;
}
```

## Step 6

Now let's define the PMIC relevant threads that will use these helpers!
```c
int pmic_fg_thread(void)
{

    fuel_gauge_initialized = false;
    uint8_t soc;

    for (;;)
    {
        if (!fuel_gauge_initialized)
        {
            int err;
            char bat_name[16];
            err = fuel_gauge_init(vbat, bat_name, 16);
            if (err < 0)
            {
                LOG_INF("Could not initialise fuel gauge.");
                return 0;
            }
            LOG_INF("Fuel gauge initialised for %s battery.", bat_name);

            fuel_gauge_initialized = true;
        }
        fuel_gauge_update(vbat, &soc);
        k_msleep(PMIC_SLEEP_INTERVAL_MS);
    }
}

int pmic_reg_thread(void)
{
    int request;

    for (;;)
    {
        k_msleep(2000);
    }
}
```

### Step 7
Now, let's build and program the board.

Run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILE="app.overlay"` followed by `west flash`.

Now, if you connect via RTT, you should see some statistics such as battery voltage, die temp, and battery state of charge along with your "i am alive" messages!

<img width="445" height="96" alt="image" src="https://github.com/user-attachments/assets/16643a50-bd20-4c8e-8726-7935948c7754" />

You can now kill the RTT terminal and move to the next step.

_If you're really stuck, the `prj.conf` and `main.c` of this branch have the solutions._

## Move to the ble branch for the next set of instructions: [➡️LINK](https://github.com/droidecahedron/nrf_peripheral_bfg/tree/ble).
