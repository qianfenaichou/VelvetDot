// hello_identity.c — 交付物 1.1「环境部署验证」的身份镜像（nexus-am 裸机，ARCH=riscv64-xs）
//
// 判据输出（单行；官方 1.1 示例的格式为「hello xiangshan, / I am Team_A, IP: <ip>」，
//   本文件把团队名与 IP 换成实际值）：
//     hello xiangshan, I am XinXiangXiangRong, IP: <IP>
//   团队名 XinXiangXiangRong（中文名「芯芯像绒」）固定写在源码里；IP 为构建机注入值。
//
// IP 为什么在编译期注入（不是运行时探测）：
//   nexus-am 是裸机 AM 环境（am.h + klib），镜像里没有内核网络栈，也没有 getifaddrs/ioctl，
//   运行时拿不到本机地址；因此 IP 由构建机以字符串宏 TARGET_IP 在编译时注入。
//   注入必须写在**应用 Makefile** 里（见下方构建段），不要在命令行写 `make CFLAGS+=...`：
//   实测在本机 GNU make 上，命令行的 `+=` 等同 `=`，会把 AM 自带的 CFLAGS（-march/-mabi/-I…）
//   整个覆盖掉（`make CFLAGS+=-DEXTRA=1` → 生效的 CFLAGS 只剩 `-DEXTRA=1`）。
//   未注入 TARGET_IP（或注入的就是 0.0.0.0）时输出占位 0.0.0.0 并额外打印一行 WARN：
//   占位输出**不得**当 1.1 证据提交。
//
/* 构建（build_cases.sh 已内置 TARGET_IP 注入）：
 *
 *   HOST_IP="$(hostname -I | awk '{print $1}')" AM_HOME=... \
 *     bash design/verify/cases/build_cases.sh [输出目录]
 *   会在生成的 app Makefile 里写入：
 *        HOST_IP ?= <HOST_IP>
 *        CFLAGS += -DTARGET_IP='"$(HOST_IP)"'
 *   并把 HOST_IP 透传给 make。未给 HOST_IP 时默认 0.0.0.0 ⇒ 镜像打印占位并走下方 WARN，
 *   **不得**当 1.1 证据（10-build-emu.sh 的 smoke_hello_identity 会拒收 0.0.0.0）。
 *
 *   备选（绕开 build_cases.sh，手工建 AM 应用）：
 *        d=$AM_HOME/apps/hello_identity
 *        mkdir -p "$d" && cp design/verify/cases/hello_identity.c "$d/main.c"
 *        cat > "$d/Makefile" <<'MK'
 *        NAME = hello_identity
 *        SRCS = main.c
 *        HOST_IP ?= 0.0.0.0
 *        CFLAGS += -DTARGET_IP='"$(HOST_IP)"'
 *        include $(AM_HOME)/Makefile.app
 *        MK
 *        make -C "$d" AM_HOME="$AM_HOME" ARCH=riscv64-xs \
 *             CROSS_COMPILE=riscv64-unknown-elf- \
 *             MARCH=rv64gcv_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt \
 *             HOST_IP="$(hostname -I | awk '{print $1}')" image
 *      产物：$d/build/hello_identity-riscv64-xs.bin（build_cases.sh 会把它拷成 $OUT/hello_identity.bin）
 *      （MARCH 必须带 _v，理由同 build_cases.sh 头注释：AM 的 riscv64-xs.mk 默认 MARCH 无 V。）
 *
 *   引号层次：HOST_IP 是 make 变量，`$(HOST_IP)` 先由 make 展开，单引号被 shell 吃掉，
 *   双引号原样进到编译器 → -DTARGET_IP="<ip>" 成为字符串字面量。
 */
// 运行：<emu> --diff <nemu-so> -i hello_identity-riscv64-xs.bin
//   本用例不发任何向量指令，无需 mstatus.VS 设置；main 返回 0 后 AM 走 halt(0)，
//   模拟器打印 HIT GOOD TRAP（1.1 冒烟的 good-trap 判据）。
#include <am.h>
#include <klib.h>

// 团队名（官方 1.1 要求的团队标识）：XinXiangXiangRong = 芯芯像绒。
#define TEAM_NAME "XinXiangXiangRong"

// 构建注入的 IP；未注入时退化为占位（见文件头）。
#ifdef TARGET_IP
#define IDENTITY_IP TARGET_IP
#else
#define IDENTITY_IP "0.0.0.0"
#endif

// 占位判定：与 "0.0.0.0" 逐字符比较（不依赖 klib 的 strcmp，裸机环境下自证最小）。
static int is_placeholder_ip(const char *ip) {
  static const char ph[] = "0.0.0.0";
  unsigned i = 0;
  while (ph[i] != '\0' && ip[i] == ph[i]) i++;
  return ph[i] == '\0' && ip[i] == '\0';
}

int main(void) {
  printf("hello xiangshan, I am %s, IP: %s\n", TEAM_NAME, IDENTITY_IP);
  if (is_placeholder_ip(IDENTITY_IP)) {
    // 占位提示：0.0.0.0 不是真实 IP，不能当 1.1 证据（判据要求"真实终端输出含团队标识与 IP"）。
    printf("WARN hello_identity: IP is the 0.0.0.0 placeholder (TARGET_IP not injected); "
           "this run is NOT valid 1.1 evidence; rebuild with -DTARGET_IP='\"<ip>\"'\n");
  }
  return 0;
}
