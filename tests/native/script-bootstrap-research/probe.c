#include <mach/mach.h>
#include <mach/host_priv.h>
#include <mach/host_special_ports.h>
#include <servers/bootstrap.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static void lookup(const char *label, mach_port_t bp) {
    mach_port_t service = MACH_PORT_NULL;
    kern_return_t kr = bootstrap_look_up(bp, "com.apple.coreservices.launchservicesd", &service);
    printf("%s port_valid=%d lookup=%d\n", label, MACH_PORT_VALID(bp), kr);
    if (MACH_PORT_VALID(service)) mach_port_deallocate(mach_task_self(), service);
}
static void observe(const char *stage) {
    mach_port_t bp = MACH_PORT_NULL, parent = MACH_PORT_NULL, lp = MACH_PORT_NULL;
    kern_return_t kr = task_get_bootstrap_port(mach_task_self(), &bp);
    printf("stage=%s task_get=%d task_valid=%d global_valid=%d\n", stage, kr, MACH_PORT_VALID(bp), MACH_PORT_VALID(bootstrap_port));
    lookup("global", bootstrap_port); lookup("task", bp);
    kr = bootstrap_parent(bp, &parent);
    printf("bootstrap_parent=%d valid=%d\n", kr, MACH_PORT_VALID(parent));
    if (MACH_PORT_VALID(parent)) { lookup("parent", parent); mach_port_deallocate(mach_task_self(), parent); }
    mach_port_t host = mach_host_self();
    kr = host_get_launchctl_port(host, &lp);
    printf("host_get_launchctl_port=%d valid=%d\n", kr, MACH_PORT_VALID(lp));
    if (MACH_PORT_VALID(lp)) { lookup("host_launchctl", lp); mach_port_deallocate(mach_task_self(), lp); }
    mach_port_array_t ports = NULL; mach_msg_type_number_t count = 0;
    kr = mach_ports_lookup(mach_task_self(), &ports, &count);
    unsigned valid = 0;
    if (kr == KERN_SUCCESS) {
        for (unsigned i = 0; i < count; i++) if (MACH_PORT_VALID(ports[i])) { valid++; mach_port_deallocate(mach_task_self(), ports[i]); }
        if (count) vm_deallocate(mach_task_self(), (vm_address_t)ports, count * sizeof(*ports));
    }
    printf("mach_ports_lookup=%d count=%u valid=%u\n", kr, count, valid);
    if (MACH_PORT_VALID(bp)) mach_port_deallocate(mach_task_self(), bp);
    if (MACH_PORT_VALID(host)) mach_port_deallocate(mach_task_self(), host);
    fflush(stdout);
}
int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 2) return 64;
    if (!strcmp(argv[1], "observe")) { observe("observe"); return 0; }
    if (!strcmp(argv[1], "global-only")) { bootstrap_port = MACH_PORT_NULL; observe("global-only"); return 0; }
    mach_port_t saved = MACH_PORT_NULL;
    if (task_get_bootstrap_port(mach_task_self(), &saved) != KERN_SUCCESS) return 65;
    kern_return_t kr = task_set_bootstrap_port(mach_task_self(), MACH_PORT_NULL);
    printf("task_set_bootstrap_port_null=%d\n", kr);
    if (kr != KERN_SUCCESS) return 66;
    bootstrap_port = MACH_PORT_NULL;
    if (!strcmp(argv[1], "saved-right")) { observe("removed-with-saved-right"); lookup("saved_before_removal", saved); return 0; }
    if (MACH_PORT_VALID(saved)) mach_port_deallocate(mach_task_self(), saved);
    if (!strcmp(argv[1], "launchctl-clean") || !strcmp(argv[1], "exec-clean") || !strcmp(argv[1], "shell-clean")) {
        kr = mach_ports_register(mach_task_self(), NULL, 0);
        printf("mach_ports_register_empty=%d\n", kr);
        if (kr != KERN_SUCCESS) return 69;
    }
    observe("removed-before-exec");
    if (!strcmp(argv[1], "launchctl") || !strcmp(argv[1], "launchctl-clean")) {
        int fd = open("/dev/null", O_WRONLY);
        if (fd < 0 || dup2(fd, STDOUT_FILENO) < 0) return 70;
        if (fd > STDERR_FILENO) close(fd);
        char *const env[] = {"PATH=/usr/bin:/bin", "LANG=C", NULL};
        char *const next[] = {"/bin/launchctl", "print", "system/com.apple.logd", NULL};
        execve("/bin/launchctl", next, env); perror("execve"); return 71;
    }
    if ((!strcmp(argv[1], "exec") || !strcmp(argv[1], "exec-clean"))) {
        char *const env[] = {"PATH=/usr/bin:/bin", "LANG=C", NULL};
        char *const next[] = {argv[0], "observe", NULL};
        execve(argv[0], next, env); perror("execve"); return 67;
    }
    if ((!strcmp(argv[1], "shell") || !strcmp(argv[1], "shell-clean"))) {
        char *const env[] = {"PATH=/usr/bin:/bin", "LANG=C", NULL};
        char *const next[] = {"/bin/zsh", "-f", "-c", "exec \"$1\" observe", "probe-shell", argv[0], NULL};
        execve("/bin/zsh", next, env); perror("execve"); return 68;
    }
    return 0;
}
