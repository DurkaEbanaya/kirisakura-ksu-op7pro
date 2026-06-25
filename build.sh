#!/bin/bash
set -e

# ============================================================
# OnePlus 7 Pro (guacamole) Kirisakura + KSU-Next kernel build
# Kernel: Kirisakura 4.14.243 (freak07/Kirisakura_OP7Pro_A11)
# + 161 security patches from linux-4.14.244..4.14.336
# KSU-Next: v3.1.0-legacy (version 33024, manual hooks)
# Toolchain: Clang 14, LLD 14, GNU cross GCC 11
# ============================================================

# --- Config ---
KERNEL_REPO="https://github.com/freak07/Kirisakura_OP7Pro_A11.git"
KERNEL_BRANCH="master_stock_caf_linux-upstream_vdso32_sched_final_2"
DEFCONFIG="stock_defconfig"
KSU_REPO="https://github.com/rifsxd/KernelSU-Next.git"
KSU_TAG="v3.1.0-legacy"
STABLE_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
STABLE_BRANCH="linux-4.14.y"
IMAGE_NAME="op7-kernel-builder"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)/kirisakura-build-work}"
CONTAINER_KERNEL_DIR="/build/kernel"
STABLE_DIR="/build/linux-stable"

mkdir -p "${WORK_DIR}"
cp "${SCRIPT_DIR}/manual-hooks.patch" "${WORK_DIR}/manual-hooks.patch"
cp "${SCRIPT_DIR}/security-patches-shas.txt" "${WORK_DIR}/security-patches-shas.txt"

# --- Docker builder image setup ---
if docker image inspect ${IMAGE_NAME} >/dev/null 2>&1; then
    if ! docker run --rm ${IMAGE_NAME} bash -lc 'command -v clang >/dev/null && command -v ld.lld >/dev/null && command -v cpio >/dev/null && command -v curl >/dev/null && command -v xz >/dev/null'; then
        echo "[*] Existing Docker image ${IMAGE_NAME} is missing required tools; rebuilding..."
        docker rm -f op7-build ksu-builder-setup 2>/dev/null || true
        docker image rm ${IMAGE_NAME}
    fi
fi

if ! docker image inspect ${IMAGE_NAME} >/dev/null 2>&1; then
    echo "[*] Building Docker image ${IMAGE_NAME}..."
    docker run -d --name ksu-builder-setup ubuntu:22.04 sleep 3600
    docker exec ksu-builder-setup apt-get update
    docker exec ksu-builder-setup apt-get install -y \
        git build-essential bc bison flex libncurses-dev libssl-dev \
        clang-14 llvm-14 lld-14 llvm-14-dev \
        gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
        python3 ccache device-tree-compiler curl xz-utils cpio
    docker exec ksu-builder-setup ln -sf /usr/bin/clang-14 /usr/bin/clang
    docker exec ksu-builder-setup ln -sf /usr/bin/ld.lld-14 /usr/bin/ld.lld
    docker exec ksu-builder-setup ln -sf /usr/bin/llvm-ar-14 /usr/bin/llvm-ar
    docker exec ksu-builder-setup ln -sf /usr/bin/llvm-nm-14 /usr/bin/llvm-nm
    docker exec ksu-builder-setup ln -sf /usr/bin/llvm-objcopy-14 /usr/bin/llvm-objcopy
    docker exec ksu-builder-setup ln -sf /usr/bin/llvm-objdump-14 /usr/bin/llvm-objdump
    docker exec ksu-builder-setup ln -sf /usr/bin/llvm-strip-14 /usr/bin/llvm-strip
    docker exec ksu-builder-setup ln -sf /usr/bin/python3 /usr/bin/python
    docker commit ksu-builder-setup ${IMAGE_NAME}
    docker rm -f ksu-builder-setup
    echo "[+] Docker image ${IMAGE_NAME} created"
fi

# --- Start build container ---
docker rm -f op7-build 2>/dev/null || true
docker run -d --name op7-build -v "${WORK_DIR}:/mnt" ${IMAGE_NAME} sleep 86400
docker exec op7-build mkdir -p /build

# --- Clone kernel source ---
echo "[*] Cloning Kirisakura kernel source (${KERNEL_BRANCH})..."
docker exec op7-build bash -c "
    if [ ! -f ${CONTAINER_KERNEL_DIR}/Makefile ]; then
        rm -rf ${CONTAINER_KERNEL_DIR}
        git clone --depth=1 --branch ${KERNEL_BRANCH} ${KERNEL_REPO} ${CONTAINER_KERNEL_DIR}
    fi
"

# --- Clone linux-stable 4.14.y and cherry-pick security patches ---
echo "[*] Cloning linux-stable 4.14.y for security patches..."
docker exec op7-build bash -c "
    if [ ! -f ${STABLE_DIR}/Makefile ]; then
        rm -rf ${STABLE_DIR}
        git clone --shallow-since='2021-07-01' --single-branch --branch ${STABLE_BRANCH} ${STABLE_REPO} ${STABLE_DIR}
    fi
"

echo "[*] Adding linux-stable as remote and fetching..."
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    git remote remove stable 2>/dev/null || true
    git remote add stable ${STABLE_DIR}
    git fetch stable --tags 2>/dev/null || true
"

echo "[*] Cherry-picking 161 security patches (4.14.244 -> 4.14.336)..."
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    if git log --oneline | head -1 | grep -q 'binder: use euid'; then
        echo '[*] Security patches already applied'
    else
        SUCCESS=0; SKIPPED=0
        while read -r sha; do
            [ -z \"\${sha}\" ] && continue
            if git cherry-pick \"\${sha}\" 2>/dev/null; then
                SUCCESS=\$((SUCCESS + 1))
            else
                CONFLICTED=\$(git diff --name-only --diff-filter=U 2>/dev/null)
                if [ -z \"\${CONFLICTED}\" ]; then
                    git cherry-pick --skip 2>/dev/null
                    SKIPPED=\$((SKIPPED + 1))
                else
                    # Check if all conflicts are docs only
                    ALL_DOCS=true
                    for f in \${CONFLICTED}; do
                        case \"\${f}\" in
                            Documentation/*|*.txt|*.rst|*.md) ;;
                            *) ALL_DOCS=false; break ;;
                        esac
                    done
                    if [ \"\${ALL_DOCS}\" = true ]; then
                        for f in \${CONFLICTED}; do
                            git checkout --theirs \"\${f}\" 2>/dev/null
                            git add \"\${f}\" 2>/dev/null
                        done
                        git cherry-pick --continue --no-edit 2>/dev/null
                        SUCCESS=\$((SUCCESS + 1))
                    else
                        git cherry-pick --abort 2>/dev/null
                        SKIPPED=\$((SKIPPED + 1))
                        echo \"[!] SKIP: \$(echo \${sha} | cut -c1-12) \$(git log -1 --format='%s' \${sha} 2>/dev/null | head -c 50)\"
                    fi
                fi
            fi
        done < /mnt/security-patches-shas.txt
        echo \"[+] Cherry-picked: \${SUCCESS} success, \${SKIPPED} skipped\"
    fi
"

# --- Clone KSU-Next and checkout legacy tag ---
echo "[*] Cloning KernelSU-Next (${KSU_TAG})..."
docker exec op7-build bash -c "
    cd /build
    if [ ! -d KernelSU-Next ]; then
        git clone --depth=1 ${KSU_REPO} KernelSU-Next
    fi
    cd KernelSU-Next
    git fetch --tags --depth=1 origin ${KSU_TAG}
    git checkout ${KSU_TAG}
"

# --- Integrate KSU-Next into kernel tree ---
echo "[*] Integrating KSU-Next into kernel tree..."
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    ln -sf /build/KernelSU-Next/kernel drivers/kernelsu
    grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || \
        sed -i '/^endmenu/i\source \"drivers/kernelsu/Kconfig\"' drivers/Kconfig
    grep -q 'kernelsu' drivers/Makefile || \
        echo 'obj-\$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
"

# --- Apply manual hooks ---
echo "[*] Applying manual hooks..."
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    if git apply --reverse --check /mnt/manual-hooks.patch >/dev/null 2>&1; then
        echo '[*] manual-hooks.patch already applied'
    else
        git apply /mnt/manual-hooks.patch 2>/dev/null || patch -p1 < /mnt/manual-hooks.patch
        echo '[+] Manual hooks applied'
    fi
"

# --- Apply build fixes ---
echo "[*] Applying build fixes..."

# Fix 1: gcc-wrapper.py Python 2 -> Python 3
docker exec op7-build bash -c 'cat > /build/kernel/scripts/gcc-wrapper.py << '\''PYEOF'\''
#!/usr/bin/env python3
import errno, re, os, sys, subprocess
ofile = None
warning_re = re.compile(r"""(.*/|)([^/]+\.[a-z]+:\d+):(\d+:)? warning:""")
def interpret_warning(line):
    line = line.rstrip("\n")
    m = warning_re.match(line)
    if m:
        print("warning:", m.group(2), file=sys.stderr)
def run_gcc():
    args = sys.argv[1:]
    global ofile
    try:
        i = args.index("-o"); ofile = args[i+1]
    except (ValueError, IndexError): pass
    try:
        proc = subprocess.Popen(args, stderr=subprocess.PIPE, universal_newlines=True)
        for line in proc.stderr:
            print(line, end="", file=sys.stderr)
            interpret_warning(line)
        result = proc.wait()
    except OSError as e:
        result = e.errno
        if result == errno.ENOENT:
            print(args[0] + ":", e.strerror, file=sys.stderr)
            print("Is your PATH set correctly?", file=sys.stderr)
        else:
            print(" ".join(args), str(e), file=sys.stderr)
    return result
if __name__ == "__main__":
    sys.exit(run_gcc())
PYEOF
chmod +x /build/kernel/scripts/gcc-wrapper.py'

# Fix 2: Relax -Werror flags globally
docker exec op7-build bash -c 'python3 << '\''PYEOF'\''
from pathlib import Path
import re

root = Path("/build/kernel")
paths = [p for p in root.rglob("Makefile") if p.is_file()]
paths += [p for p in root.rglob("Kbuild") if p.is_file()]

for path in paths:
    text = path.read_text(errors="ignore")
    new = text
    new = new.replace("-Werror-implicit-function-declaration", "-Wno-error=implicit-function-declaration")
    new = re.sub(r"(?<![A-Za-z0-9_-])-Werror=([A-Za-z0-9_-]+)", r"-Wno-error=\1", new)
    new = re.sub(r"(?<![A-Za-z0-9_-])-Werror(?![=A-Za-z0-9_-])", "-Wno-error", new)
    if new != text:
        path.write_text(new)
PYEOF'

# Fix 3: selinux_state __rticdata relocation overflow
docker exec op7-build bash -c "
    sed -i 's/struct selinux_state selinux_state __rticdata;/struct selinux_state selinux_state;/' ${CONTAINER_KERNEL_DIR}/security/selinux/hooks.c
"

# Fix 4: ipa_hw_stats.c copy_from_user missing size guard
docker exec op7-build bash -c "
    sed -i 's/copy_from_user(dbg_buff, ubuf, count)/copy_from_user(dbg_buff, ubuf, min_t(size_t, count, sizeof(dbg_buff)))/g' ${CONTAINER_KERNEL_DIR}/drivers/platform/msm/ipa/ipa_v3/ipa_hw_stats.c
"

# Fix 5: techpack/audio broken symlinks -> real file copies
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    rm -f techpack/audio/soc/core.h techpack/audio/soc/pinctrl-utils.h techpack/audio/include/soc/internal.h
    cp drivers/pinctrl/core.h techpack/audio/soc/core.h
    cp drivers/pinctrl/pinctrl-utils.h techpack/audio/soc/pinctrl-utils.h
    cp drivers/base/regmap/internal.h techpack/audio/include/soc/internal.h
"

# Fix 6: oneplus_healthinfo missing timer declaration
docker exec op7-build bash -c "
    grep -q 'task_load_info_timer' ${CONTAINER_KERNEL_DIR}/drivers/oneplus/oneplus_healthinfo/oneplus_healthinfo.c || \
    sed -i '/^static struct proc_dir_entry \*oneplus_healthinfo;/a static struct timer_list task_load_info_timer;' \
        ${CONTAINER_KERNEL_DIR}/drivers/oneplus/oneplus_healthinfo/oneplus_healthinfo.c
"

# Fix 7: event_timer timerqueue_head init (CVE-2021-20317 changed struct)
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    if grep -q '\.head = RB_ROOT' drivers/soc/qcom/event_timer.c 2>/dev/null; then
        sed -i 's/\.head = RB_ROOT,/\.rb_root = RB_ROOT_CACHED,/' drivers/soc/qcom/event_timer.c
        sed -i '/\.next = NULL,/d' drivers/soc/qcom/event_timer.c
        echo '[+] Fix 7: event_timer timerqueue init'
    fi
"

# Fix 8: KALLSYMS_BASE_RELATIVE overflow (kernel too large with security patches + WiFi built-in)
docker exec op7-build bash -c "
    cd ${CONTAINER_KERNEL_DIR}
    sed -i 's/default !IA64 && !(TILE && 64BIT)/default n/' init/Kconfig
    echo '[+] Fix 8: KALLSYMS_BASE_RELATIVE disabled in Kconfig'
"

# --- Update defconfig ---
echo "[*] Updating defconfig..."
docker exec op7-build bash -c "
    DEFCONFIG=${CONTAINER_KERNEL_DIR}/arch/arm64/configs/${DEFCONFIG}

    # Disable MODULE_SIG_FORCE and MODULE_SIG_ALL
    sed -i 's/CONFIG_MODULE_SIG_FORCE=y/# CONFIG_MODULE_SIG_FORCE is not set/' \$DEFCONFIG
    sed -i 's/CONFIG_MODULE_SIG_ALL=y/# CONFIG_MODULE_SIG_ALL is not set/' \$DEFCONFIG

    # Enable ZRAM features (code uses ac_time without ifdef guard)
    sed -i 's/# CONFIG_ZRAM_DEDUP is not set/CONFIG_ZRAM_DEDUP=y/' \$DEFCONFIG
    sed -i 's/# CONFIG_ZRAM_WRITEBACK is not set/CONFIG_ZRAM_WRITEBACK=y/' \$DEFCONFIG

    # Add KSU, WiFi driver, ZRAM_MEMORY_TRACKING
    cat >> \$DEFCONFIG << 'DEOF'

# KernelSU-Next
CONFIG_KSU=y

# WiFi driver (qcacld-3.0 built-in)
CONFIG_QCA_CLD_WLAN=y

# ZRAM memory tracking (required by zram_drv.c)
CONFIG_ZRAM_MEMORY_TRACKING=y
DEOF
"

# --- Build ---
echo "[*] Configuring kernel..."
docker exec op7-build bash -c "
    set -e
    cd ${CONTAINER_KERNEL_DIR}
    export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
    export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    export CLANG_TRIPLE=aarch64-linux-gnu- CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    export OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip

    make O=out ${DEFCONFIG}
"

echo "[*] Building kernel (this takes 20-40 min)..."
docker exec op7-build bash -c "
    set -e
    cd ${CONTAINER_KERNEL_DIR}
    export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
    export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    export CLANG_TRIPLE=aarch64-linux-gnu- CC=clang LD=ld.lld AR=llvm-ar NM=llvm-nm
    export OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip

    make O=out -j\$(nproc)
    cp out/arch/arm64/boot/Image /mnt/Image
    cp out/.config /mnt/kernel.config
"

echo ""
echo "[+] Kernel built: ${WORK_DIR}/Image"
echo "[+] Final config: ${WORK_DIR}/kernel.config"
echo ""
echo "[*] To pack boot.img, you need:"
echo "    1. Stock OOS11 boot.img (from OTA payload-dumper-go)"
echo "    2. magiskboot (unpack stock, replace kernel, repack)"
echo "    See README.md for details"
