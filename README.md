## Goal and Progression Path
There are a few branches in this repo, here is the intended progression path for you as you walk through this workshop.
```mermaid
graph LR;
  main-->proof_of_life*;
  proof_of_life*-->pmic;
  pmic-->ble;
```
> `*` == your current location


### Getting things ready to program.
*These instructions assume you are using an nRF54L15-DK as your programmer.*
- 1) Plug in the nRF54L15-DK via USB cable, and turn the POWER switch to the ON position.
- 2) On the Seeed board, press and hold the SHPHLD button for about 1 second. The red LED should begin blinking, indicating it is out of ship mode.
- 3) Re-enter ship mode by pressing and holding SHPHLD down for about 2 seconds. The LED will stop blinking.
- 4) With your 2x5 SWD Ribbon cable, connect the DBG-OUT header of the nRF54L15-DK to the Seeed board's SWD port headers between the two push buttons, matching the silk screens lines with the red line on the swd cable. (Images below for reference).
  
  <img width="462" height="494" alt="image" src="https://github.com/user-attachments/assets/86c697c0-d5e9-47ed-b847-0572cf200179" />

- 5) Press SHPHLD for about 1 second again as you did to exit ship mode when you first unboxed it.
- 6) From here, you are ready to begin programming the board! Let's get some code going so we can start iterating.

> [!NOTE]
> This is just a quirk to the flow of a fresh unbox of the board. If you've done this once, any time the device is out of ship mode it should program without needing this specific sequence.

### Adding some blinking
So first thing we will want to do is to have our userspace application blink the LED, similarly to the pre-shipped boards.
This is primarily so we have proof of life after we start flashing throughout each step.

We first need to include the gpio driver from Zephyr, done by appending the following to the `main.c` file.
```c
#include <zephyr/drivers/gpio.h>
```

From there, we can use the led0 nodelabel to reference LED0 and initialize and drive it.
Add the following _outside_ the `main()` function in the `main.c` file.

```c
static const struct gpio_dt_spec bt_status_led = GPIO_DT_SPEC_GET(DT_NODELABEL(led0), gpios);
```

Now let's add a blinking LED to the main function.
Within `int main(void)`, append the following above `return 0;`:
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

This will initialize the LED, have it on for half a secnod, then off for 2.
Now let's flash this onto the board.

Run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILE="app.overlay"` followed by `west flash` in the terminal in vsc. 

The tail end of the prompt should greet you with some success, and the LED should begin blinking.

<img width="822" height="167" alt="image" src="https://github.com/user-attachments/assets/9826df9b-b1de-4142-9363-e67d3c9b8b0b" />

If this is _not_ the case, you may need to repeat steps 2-6 of the "Getting things ready to program" section.

