/* Reboot with a command string (default "bootloader"): reboot(2)
 * LINUX_REBOOT_CMD_RESTART2. The OnePlus 3.10 kernel turns "bootloader" into
 * the IMEM fastboot magic, so LK stays in fastboot mode. */
#include <linux/reboot.h>
#include <sys/syscall.h>
#include <unistd.h>
int main(int argc, char **argv)
{
	const char *cmd = argc > 1 ? argv[1] : "bootloader";
	sync();
	return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		       LINUX_REBOOT_CMD_RESTART2, cmd);
}
