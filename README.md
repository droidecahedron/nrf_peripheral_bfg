## Goal and Progression Path
```mermaid
graph LR;
  main-->proof_of_life*;
  proof_of_life*-->pmic;
  pmic-->ble;
```
> `*` == your current location

> _If you're really stuck, the `main.c` and `prj.conf` of each branch will be the solution for each step._

### Getting things ready to program
*These instructions assume you are using an nRF54L15-DK as your programmer.*
- 1) Plug in the nRF54L15-DK via USB cable, and turn the POWER switch to the ON position.
- 2) On the Seeed board, press and hold the SHPHLD button for about 1-2 seconds. The red LED should begin blinking, indicating it is out of ship mode.
- 3) Re-enter ship mode by pressing and holding SHPHLD down for about 1-2 seconds. The LED will stop blinking.
- 4) With your 2x5 SWD Ribbon cable, connect the DBG-OUT header of the nRF54L15-DK to the Seeed board's SWD port headers between the two push buttons, matching the silk screens lines with the red line on the swd cable. (Images below for reference).
  
  <img width="462" height="494" alt="image" src="https://github.com/user-attachments/assets/86c697c0-d5e9-47ed-b847-0572cf200179" />

- 5) Press SHPHLD for about 1-2 seconds again as you did to exit ship mode when you first unboxed it. The LED may not flash this time, this is fine.
- 6) From here, you are ready to begin programming the board! Let's get some code going so we can start iterating.

> [!NOTE]
> This is just a quirk to the flow of a fresh unbox of the board. If you've done this once, any time the device is out of ship mode it should program without needing this specific sequence.

So first thing we will want to do is to have our userspace application blink the LED, similarly to the pre-shipped boards.

This is primarily so we have proof of life after we start flashing throughout each step.

### Step 1
We first need to include the gpio driver from Zephyr, done by appending the following to the `main.c` file.
```c
#include <zephyr/drivers/gpio.h>
```

### Step 2
From there, we can use the led0 nodelabel to reference LED0 and initialize and drive it.
Add the following _outside_ the `main()` function in the `main.c` file.

```c
static const struct gpio_dt_spec bt_status_led = GPIO_DT_SPEC_GET(DT_NODELABEL(led0), gpios);
```

### Step 3
Now let's add a blinking LED to the main function.

Within `int main(void)`, append the following above `return 0;`.

```c
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
    gpio_pin_set_dt(&bt_status_led, 0);
    k_msleep(2000);
}
```

This will initialize the LED, have it on for half a second, then off for 2.

### Step 4
Now let's flash this onto the board.
Run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILE="app.overlay"` followed by `west flash --recover` in the terminal in vsc. 

The tail end of the prompt should greet you with some success, and the LED should begin blinking.

<img width="822" height="167" alt="image" src="https://github.com/user-attachments/assets/9826df9b-b1de-4142-9363-e67d3c9b8b0b" />

If this is _not_ the case, you may need to repeat steps 2-6 of the "**Getting things ready to program**" section.

### Step 5
Let's add some logging. 

There isn't a convenient to access UART/serial output to use for logging on the Seeed board. 

That is okay, because we have SWD broken out and a j-link on hand, we have access to [Real Time Transfer (RTT)](https://www.segger.com/products/debug-probes/j-link/technology/about-real-time-transfer/) logging!

RTT essentially relies on some up/down buffers in RAM and a control block and lets you retrieve logs via the SWD interface. 
Although the LED already gives us proof of life, this gives us a valuable other way to see what is going on in the application without getting more wires and a logic analyzer. We will want that later.

In the main directory of the repo (outside src/), there is a `prj.conf`.
Within this file, beneath the `# ~~~~~~~~~ #` ribbon, let's add some configs to enable logging via RTT.

```
#Logging
CONFIG_LOG=y
CONFIG_LOG_BACKEND_RTT=y
CONFIG_USE_SEGGER_RTT=y
CONFIG_LOG_BACKEND_UART=n
CONFIG_REQUIRES_FLOAT_PRINTF=y
CONFIG_SEGGER_RTT_BUFFER_SIZE_UP=2048
CONFIG_LOG_BACKEND_RTT_BUFFER_SIZE=2048
```

Then save the file.

> [!NOTE]
> Flip LOG=n and comment out all the remaining log based configs if you want to save power/processing in the future for a contemporary design.

### Step 6
Now let's start using the logging module in our main application. Within `main.c` again, let's include the logging module.
```c
#include <zephyr/logging/log.h>
```

Then let's register a logging module for this source file. Add the following outside of the main function (somewhere above/below the `bt_status_led` declaration works fine).
```c
LOG_MODULE_REGISTER(main, LOG_LEVEL_INF);
```

### Step 7
From here, we can add a warning log to the `if()` case of our gpio configuration:
```c
LOG_WRN("Configuring BT status LED failed (err %d)", err);
```

And we can add an "I AM ALIVE" message to that infinite `for(;;)` loop.
```c
for (;;)
{
    gpio_pin_set_dt(&bt_status_led, 1);
    k_msleep(500);
    LOG_INF("I am alive");
    gpio_pin_set_dt(&bt_status_led, 0);
    k_msleep(2000);
}
```

Save your changes, and run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILE="app.overlay"` followed by `west flash` in the terminal in vsc. 

### Step 8
Now let's connect to the RTT terminal via the VSC extension. (If you're familiar with RTT viewer and j-link, you can also just open that .exe directly and use your own jlink if you desire).

- Under the "connected devices" pane of the VSC extension, we should see our nRF54L15-DK. Expand the drop down and you should see RTT. Hover over that item to see a "plug" icon towards the right, and click it (labelled "1" in the image below). If you do _not_ see this icon, try power cycling the DK. If you never see it, you may be missing required software from the pre-requisites of the workshop.
  
- Then a pop up on the top middle of VSC should open asking to specify RTT memory address. Select "Search for RTT memory address automatically" (labelled "2" in the image below) and a new pop up should come up.

  <img width="902" height="490" alt="image" src="https://github.com/user-attachments/assets/aa945c01-ebd9-4d98-bd39-540e0be0c9eb" />

- In the new pop-up, type `nrf54l15_m33` into the "Device" column to filter, and select the only option. (image below)
  
  <img width="554" height="199" alt="image" src="https://github.com/user-attachments/assets/d40aee3e-67e4-4626-a4e2-4c606c2cb8de" />

- You should now see your "I am alive" messages in a new terminal that gets spawned in the VSC terminal gui!
  
  <img width="294" height="130" alt="image" src="https://github.com/user-attachments/assets/8d5a4bfa-e870-4421-aac9-bb83b2a12093" />


- You can now kill this RTT instance by hovering over it on the right hand pane of the terminal viewer and clicking the trash can icon. You'll need to kill-restart it a few times depending on resets/power states/flashes throughout the workshop, so it's good to know where this button is.
  
  <img width="196" height="159" alt="image" src="https://github.com/user-attachments/assets/5dfa5b8b-4f9c-4ab3-b6a6-c8a1844bae3c" />
  
_If you're really stuck, the `prj.conf` and `main.c` of this branch have the solutions._

## Move to the pmic branch for the next set of instructions: [➡️LINK](https://github.com/droidecahedron/nrf_peripheral_bfg/tree/pmic).
