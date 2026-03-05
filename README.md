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


### Step 1

## Step 7
Now, let's build and program the board.

Run `west build -b seeed_nrf54l15_npm2100/nrf54l15/cpuapp -p -- -DBOARD_ROOT="." -DDTC_OVERLAY_FILE="app.overlay"` followed by `west flash`.

Now, if you connect via RTT, you should see some statistics such as battery voltage, die temp, and battery state of charge along with your "i am alive" messages!

<img width="445" height="96" alt="image" src="https://github.com/user-attachments/assets/16643a50-bd20-4c8e-8726-7935948c7754" />


_If you're really stuck, the `prj.conf` and `main.c` of this branch have the solutions._

## 🎊 You have reached the end of the workshop! 🎊
