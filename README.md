## Goal and Progression Path
```mermaid
graph LR;
  main-->proof_of_life;
  proof_of_life-->pmic;
  pmic-->ble*;
```
> `*` == your current location

> _If you're really stuck, the `main.c` and `prj.conf` of each branch will be the solution for each step._

### Preface

Now that we have the numbers we care about (Battery voltage, battery state of charge) let's start leveraging Bluetooth Low Energy (BLE) to be able to pull those measurements from our phone.

While we're at it, we can also use BLE to allow our phone to issue the command to re-enter ship mode!

For reading the battery voltage and writing the ship mode, we will create custom characteristics. 

For the battery state of charge, there is already work done for us baked into the standard via the GATT Battery Service, so we only need to include it into our build and report to it with our calculated state of charge.

### Step 0
We initially control `bt_status_led` in the `for(;;)` block of the main thread. Now that we are adding BLE, let's use this LED for that instead.

**Remove or comment the `gpio_pin_set_dt` function calls in the `main()` function, as well as the configure_dt fn call and the error catch block around it.**

Your main function should now look as follows:
```c
int main(void)
{
    for (;;)
    {
        k_msleep(500);
        LOG_INF("I am alive");
        k_msleep(2000);
    }
    return 0;
}
```

### Step 1
Let's update our `prj.conf` to add Bluetooth features, below the fuel gauge configs.

Make sure you replace ZX with your first and last initials to make scanning for _your_ device easier.
```
# Bluetooth
CONFIG_BT=y
CONFIG_BT_PERIPHERAL=y
CONFIG_BT_DEVICE_NAME="ZXSeeed nPM2100+nRF54L15"
CONFIG_BT_NSMS=y
CONFIG_BT_BAS=y
```

### Step 2
Add the following `#include`s to the top of `main.c` to add BLE functionality.
```c
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/types.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/services/bas.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/settings/settings.h>
```

### Step 3
Let's define a struct to hold our pmic report, and set up some message queues.
Add the following above all your function definitions in `main.c`.
```c
struct pmic_report_msg
{
    double batt_voltage;
    double temp;
    uint8_t batt_soc;
};
```

As well as a message queue for the PMIC software block to communicate with the BLE block and another message queue for the other direction.
```c
K_MSGQ_DEFINE(pmic_msgq, sizeof(struct pmic_report_msg), 8, 4);
K_MSGQ_DEFINE(ble_cfg_pmic_msgq, sizeof(int32_t), 8, 4);
```

### Step 4
Let's add some global defines for Bluetooth attributes and the Bluetooth thread that will report our PMIC data to the phone.
One characteristic will be for reading the battery voltage as plain text, the other will be for putting the system into ship mode.
For the battery state of charge, the standard battery level characteristic will be used so we don't need to create a custom characteristic.
```c
#define BLE_NOTIFY_INTERVAL K_MSEC(1000)
#define BLE_THREAD_STACK_SIZE 1024
#define BLE_THREAD_PRIORITY 5

#define MAXLEN 19

#define PMIC_HUB_SERVICE_UUID BT_UUID_128_ENCODE(0x2100F600, 0x8445, 0x5fca, 0xb332, 0xc13064b9dea2)
#define PMIC_RD_ALL_CHARACTERISTIC_UUID BT_UUID_128_ENCODE(0x21002EAD, 0xA770, 0x57A7, 0xb333, 0xc13064b9dea2)
#define SHPHLD_WR_MV_CHARACTERISTIC_UUID BT_UUID_128_ENCODE(0x57EED111, 0x217E, 0x4faf, 0x956b, 0xafb01c17d0be)
#define BT_UUID_PMIC_HUB BT_UUID_DECLARE_128(PMIC_HUB_SERVICE_UUID)
#define BT_UUID_PMIC_HUB_RD_ALL BT_UUID_DECLARE_128(PMIC_RD_ALL_CHARACTERISTIC_UUID)
#define BT_UUID_PMIC_HUB_SHPHLD_WR BT_UUID_DECLARE_128(SHPHLD_WR_MV_CHARACTERISTIC_UUID)
#define DEVICE_NAME CONFIG_BT_DEVICE_NAME // from prj.conf
#define DEVICE_NAME_LEN (sizeof(DEVICE_NAME) - 1)
```

and create a connection handler to reference later, as well as set up our advertising parameters and scan data.
```c
struct bt_conn *m_connection_handle = NULL;

static const struct bt_le_adv_param *adv_param =
    BT_LE_ADV_PARAM((BT_LE_ADV_OPT_CONN | BT_LE_ADV_OPT_USE_IDENTITY), /* Connectable advertising and use
                                                                          identity address */
                    800,   /* Min Advertising Interval 500ms (800*0.625ms) 16383 max*/
                    801,   /* Max Advertising Interval 500.625ms (801*0.625ms) 16384 max*/
                    NULL); /* Set to NULL for undirected advertising */

static struct k_work adv_work;
static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA(BT_DATA_NAME_COMPLETE, DEVICE_NAME, DEVICE_NAME_LEN),
};

static const struct bt_data sd[] = {
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, PMIC_HUB_SERVICE_UUID),
};
```

### Step 5
Now, let's create some callbacks for the BLE stack to use, as well as define our service.
- Callback for when cccd changes.
```c
/*This function is called whenever the Client Characteristic Control Descriptor
(CCCD) has been changed by the GATT client, for each of the characteristics*/
static void on_cccd_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    ARG_UNUSED(attr);
    switch (value)
    {
    case BT_GATT_CCC_NOTIFY:
        break;
    case 0:
        break;
    default:
        LOG_ERR("Error, CCCD has been set to an invalid value");
    }
}
```
- Callback for when the central (phone) writes to our "ship mode" characteristic. We will use that message queue we defined earlier to notify the PMIC software block.
```c
static ssize_t on_receive_shphld_wr(struct bt_conn *conn, const struct bt_gatt_attr *attr, const void *buf,
                                    uint16_t len, uint16_t offset, uint8_t flags)
{
    static bool request;

    LOG_INF("Received lsldo wr data, handle %d, conn %p, len %d, data: 0x", attr->handle, conn, len);
    LOG_INF("REQUESTED SHIP MODE: %d", request);
    bt_conn_disconnect(m_connection_handle, BT_HCI_ERR_REMOTE_USER_TERM_CONN);
    k_msgq_put(&ble_cfg_pmic_msgq, &request, K_NO_WAIT);

    return len;
}
```
- Define our service with the relevant characteristics.
```c
BT_GATT_SERVICE_DEFINE(
    pmic_hub, BT_GATT_PRIMARY_SERVICE(BT_UUID_PMIC_HUB),
    BT_GATT_CHARACTERISTIC(BT_UUID_PMIC_HUB_RD_ALL, BT_GATT_CHRC_NOTIFY, BT_GATT_PERM_READ, NULL, NULL, NULL),
    BT_GATT_CCC(on_cccd_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
    BT_GATT_CHARACTERISTIC(BT_UUID_PMIC_HUB_SHPHLD_WR, BT_GATT_CHRC_WRITE | BT_GATT_CHRC_WRITE_WITHOUT_RESP,
                           BT_GATT_PERM_READ | BT_GATT_PERM_WRITE, NULL, on_receive_shphld_wr, NULL), );
```
- A work handler for starting avertising
```c
static void adv_work_handler(struct k_work *work)
{
    int err = bt_le_adv_start(adv_param, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err)
    {
        LOG_INF("Advertising failed to start (err %d)", err);
        return;
    }

    LOG_INF("Advertising successfully started");
}

static void advertising_start(void)
{
    k_work_submit(&adv_work);
}
```
- Callback for when a connection object has returned to the pool and can be recycled.
```c
static void recycled_cb(void)
{
    LOG_INF("Connection object available from previous conn. Disconnect complete.");
    advertising_start();
}
```
- Callback for when something connects. (Note: We will now use the LED to indicate our Bluetooth state).
```c
static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err)
    {
        LOG_WRN("Connection failed (err %u)", err);
        return;
    }
    m_connection_handle = bt_conn_ref(conn);

    LOG_INF("Connected");

    struct bt_conn_info info;
    err = bt_conn_get_info(m_connection_handle, &info);
    if (err)
    {
        LOG_ERR("bt_conn_get_info() returned %d", err);
        return;
    }

    gpio_pin_set_dt(&bt_status_led, 1);
}
```
- Callback for when a connection is terminated.
```c
static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    LOG_INF("Disconnected (reason %u)", reason);
    bt_conn_unref(m_connection_handle);
    m_connection_handle = NULL;
    gpio_pin_set_dt(&bt_status_led, 0);
}
```
- Lastly, tie these functions to a connection callback struct.
```c
struct bt_conn_cb connection_callbacks = {
    .connected = connected,
    .disconnected = disconnected,
    .recycled = recycled_cb,
};
```
### Step 6
Let's add some helper functions for notifying the central device (phone) with our BLE data and initializing BT to begin with.
- Bluetooth notification function.
```c
static void ble_report_batt_volt(struct bt_conn *conn, const uint8_t *data, uint16_t len)
{
    const struct bt_gatt_attr *attr = &pmic_hub.attrs[2];
    struct bt_gatt_notify_params params = {
        .uuid = BT_UUID_PMIC_HUB_RD_ALL, .attr = attr, .data = data, .len = len, .func = NULL};

    if (bt_gatt_is_subscribed(conn, attr, BT_GATT_CCC_NOTIFY))
    {
        if (bt_gatt_notify_cb(conn, &params))
        {
            LOG_ERR("Error, unable to send notification");
        }
    }
    else
    {
        LOG_WRN("Warning, notification not enabled for pmic stat characteristic");
    }
}
```
- Bluetooth initialization function.
```c
int bt_init(void)
{
    int err;

    // Setting up Bluetooth
    err = bt_enable(NULL);
    if (err)
    {
        LOG_ERR("Bluetooth init failed (err %d)", err);
        return -1;
    }
    LOG_INF("Bluetooth initialized");
    if (IS_ENABLED(CONFIG_SETTINGS))
    {
        settings_load();
    }
    bt_conn_cb_register(&connection_callbacks);
    k_work_init(&adv_work, adv_work_handler);
    advertising_start();

    return 0;
}
```
### Step 7
Now, let's create a Bluetooth thread that waits to receive a message from the PMIC module and pulse the LED when we're advertising (since the connected/disconnect will handle on/off when a connection is present).
- Define the BLE thread at the bottom of `main.c`, along with the other PMIC thread defines.
```c
K_THREAD_DEFINE(ble_write_thread_id, BLE_THREAD_STACK_SIZE, ble_write_thread, NULL, NULL, NULL, BLE_THREAD_PRIORITY, 0,
                0);
```
- Provide the definition for `ble_write_thread` above the `K_THREAD_DEFINE`s.
```c
void ble_write_thread(void)
{
    int err;
    LOG_INF("ble write thread: entered");

    if (bt_init() != 0)
    {
        LOG_ERR("unable to initialize BLE!");
    }

    err = gpio_pin_configure_dt(&bt_status_led, GPIO_OUTPUT_INACTIVE);
    if (err)
    {
        LOG_WRN("Configuring BT status LED failed (err %d)", err);
    }

    struct pmic_report_msg pmic_msg;
    for (;;)
    {
        // Wait indefinitely for msg's from other modules
        k_msgq_get(&pmic_msgq, &pmic_msg, K_FOREVER);
        LOG_INF("BLE thread rx from PMIC: V: %.2f T: %.2f SoC: %d ", pmic_msg.batt_voltage, pmic_msg.temp,
                pmic_msg.batt_soc);

        if (m_connection_handle) // if ble connection present
        {
            bt_bas_set_battery_level(pmic_msg.batt_soc); // report batt soc via standard service

            static uint8_t ble_batt_volt[MAXLEN]; // report batt volt string via custom service
            int len = snprintf(ble_batt_volt, MAXLEN, "BATT: %.2f V", pmic_msg.batt_voltage);
            if (!(len >= 0 && len < MAXLEN))
            {
                LOG_ERR("ble pmic report too large. (%d)", len);
            }
            else
            {
                ble_report_batt_volt(m_connection_handle, ble_batt_volt, len);
            }
        }
        else
        {
            LOG_INF("BLE Thread does not detect an active BLE connection");
             // toggle the LED while advertising
            gpio_pin_toggle_dt(&bt_status_led);
        }

        k_sleep(BLE_NOTIFY_INTERVAL);
    }
}
```

### Step 8
Now, we need to go update some of those old PMIC threads to populate and pass relevant PMIC data to the BLE module, as well as be ready to receive the ship mode command from BLE!
- modify `pmic_reg_thread`'s `for(;;)` block to wait for a message from the BLE module, then enter ship mode if it receives one.
```c
k_msgq_get(&ble_cfg_pmic_msgq, &request, K_FOREVER); // suspend till msg avail
regulator_parent_ship_mode(pmic_regulators);
```
- modify fuel_gauge_update to send a message to the BLE module with the PMIC report! We can add this below the final `LOG_INF` line in the function.
```c
struct pmic_report_msg pmic_ble_report;
pmic_ble_report.batt_voltage = voltage;
pmic_ble_report.temp = temp;
pmic_ble_report.batt_soc = *soc;
k_msgq_put(&pmic_msgq, &pmic_ble_report, K_FOREVER);
```
### Step 9
Now, let's build and program the board.

Run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILpmic_msgqE="app.overlay"` followed by `west flash`.

Now, if you use your nRF Connect for Mobile app on your android/iOS device, and filter for "ZXSeeed" (the prefix for our Bluetooth device name in `prj.conf`, where ZX were your initials), you should see your device!

<img width="13%" height="1334" alt="image" src="https://github.com/user-attachments/assets/351d0fce-6dff-44aa-ba6e-a2be12563e90" />

If you tap the device and choose connect, you'll be able to see the attributes. Battery Level holds the state of charge, and the unknown characteristic with the prefix `2100-2EAD` is the battery voltage as a UTF-8 string.

<img width="13%" height="1334" alt="image" src="https://github.com/user-attachments/assets/8637d031-caf7-4eef-aeb0-60a9dfb450d0" />

If you write to the `57EED111` characteristic, you can put the device into ship mode! It will terminate the connection and then go to sleep.

<img width="240" height="108" alt="image" src="https://github.com/user-attachments/assets/14602079-d95a-4688-908c-91226e7eaefe" />

<img width="214" height="169" alt="image" src="https://github.com/user-attachments/assets/2abf9c22-4c56-4fd2-b7b7-81a0e87b19bc" />

From there, you won't be able to see it advertising to reconnect.
If you want to wake the device back up, hold the shipmode for about half a second like when you first got the device. You should now be able to see it blinking again, indicating it is advertising!

_If you're really stuck, the `prj.conf` and `main.c` of this branch have the solutions._

## 🎊 You have reached the end of the workshop! 🎊
