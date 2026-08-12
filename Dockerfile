# nRF Connect SDK v3.4.0 build container for nrf_peripheral_bfg.
#
# To move to another NCS version, change all THREE of the following:
#   1. the FROM tag
#   2. the sdk install / sdk register version
#   3. NCS_TOOLCHAIN_BASE + ZEPHYR_BASE below
# Find the new toolchain hash inside the container with:
#   ls /root/ncs/toolchains        (or: nrfutil sdk-manager list --all-fields)

FROM ghcr.io/embeddedcontainers/ncs:v3.4.0SDK

# Install + register the SDK, then strip modules this workshop never touches.
# The pruning is not cosmetic: image size lands directly on Codespaces storage
# quota and on prebuild snapshot size.
RUN nrfutil sdk-manager sdk install v3.4.0 \
    && nrfutil sdk-manager sdk register v3.4.0 \
    && rm -rf /root/ncs/downloads /root/ncs/tmp \
    && SDK=/root/ncs/v3.4.0 \
    && rm -rf \
        "$SDK/modules/lib/matter" \
        "$SDK/modules/lib/gui" \
        "$SDK/modules/lib/openthread" \
        "$SDK/modules/lib/loramac-node" \
        "$SDK/modules/lib/azure-sdk-for-c" \
        "$SDK/modules/lib/chre" \
        "$SDK/modules/lib/cmsis-nn" \
        "$SDK/modules/lib/cmsis-dsp" \
        "$SDK/modules/lib/hostap" \
        "$SDK/modules/lib/picolibc" \
        "$SDK/modules/hal/cirrus-logic" \
        "$SDK/modules/hal/st" \
        "$SDK/modules/crypto/mldsa-native"

# Put the NCS toolchain on PATH so `west build` works in a plain terminal,
# without `nrfutil sdk-manager toolchain launch`.
ENV NCS_TOOLCHAIN_BASE=/root/ncs/toolchains/fbf7391cab
ENV PATH="${NCS_TOOLCHAIN_BASE}/bin:${NCS_TOOLCHAIN_BASE}/usr/bin:${NCS_TOOLCHAIN_BASE}/usr/local/bin:${NCS_TOOLCHAIN_BASE}/opt/bin:${NCS_TOOLCHAIN_BASE}/opt/nanopb/generator-bin:${NCS_TOOLCHAIN_BASE}/nrfutil/bin:${NCS_TOOLCHAIN_BASE}/opt/zephyr-sdk/gnu/arm-zephyr-eabi/bin:${NCS_TOOLCHAIN_BASE}/opt/zephyr-sdk/gnu/riscv64-zephyr-elf/bin:${PATH}"
ENV LD_LIBRARY_PATH="${NCS_TOOLCHAIN_BASE}/lib:${NCS_TOOLCHAIN_BASE}/lib/x86_64-linux-gnu:${NCS_TOOLCHAIN_BASE}/usr/local/lib"
ENV ZEPHYR_SDK_INSTALL_DIR="${NCS_TOOLCHAIN_BASE}/opt/zephyr-sdk"
ENV ZEPHYR_TOOLCHAIN_VARIANT=zephyr/gnu
ENV PYTHONHOME="${NCS_TOOLCHAIN_BASE}/usr/local"
ENV PYTHONPATH="${NCS_TOOLCHAIN_BASE}/usr/local/lib/python3.12:${NCS_TOOLCHAIN_BASE}/usr/local/lib/python3.12/site-packages"

# Freestanding-application layout: west locates the workspace via ZEPHYR_BASE,
# which is what makes `west build` work from /workspaces/<repo>.
ENV ZEPHYR_BASE=/root/ncs/v3.4.0/zephyr
