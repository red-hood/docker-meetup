# Kernel features for container virtualization and privilege separation

## PID and mount namespaces

1. Prepare a busybox environment  

    ```sh
    ./create-busybox.sh`
    ```

2. Show PID namespaces  
/proc mount is still the one from parent NS, can get PID there

    ```sh
    sudo unshare -p -f /container/1/sh
    ps w
    cd /proc/self; pwd -P
    ```

3. Show process in root namespace  

    ```sh
    ps -q <PID in root ns>  
    ```

4. /proc mount in new process namespace  

    ```sh
    chroot /container/1  
    mount -t proc  proc /proc  
    ps w  
    ```

Do the same stuff in container 2, show which processes are visible where  

## Add mount namespaces  
1. Make sure / is mounted private:

   ```sh
   sudo mount --make-private /  
   ```
2. Create new mount and PID namespace:

   ```sh
   sudo unshare -p -m -f /container/1/sh 
   ```
3. Chroot and mount /proc

    ```sh
    chroot /container/1; mount -t proc  proc /proc  
    ```
4. List mounts in root and container namespace

    ```sh
    ls /proc in new namespace  
    ls /container/1/proc/ should be empty  
    ```
5. Example with shared root mount


# Capabilities

* restrict access to several permission (not dependent on implementation)
* similar to permissions on Android or iOS

## Example for Network Admin Capability in Docker

We will show that the root user in a docker container can not bring its network device down.

1. Start docker container (Debian)

    ```sh
    docker run -t -i debian:jessie /bin/bash  
    ```
2. Try to bring eth0 down 

    ```sh
    ip l s eth0 down
    -> `RTNETLINK answers: Operation not permitted`
    ```
3. Print current capabilities

    ```sh
    capsh --print
    -> cap_net_admin missing in Current set, therefore no access to network management functions 
    ```
4. Set capabilities for docker container
TODO
NB no limit to single syscall, but messages on netlink socket


## Capabilities w/o Docker

* capabilities are stored in extended file attributes: not user-specific, but related to executable
* restrictions per user possible via inherited bounding set
* examples for capabilites: cap_net_admin, cap_sys_admin (many in one), cap_net_bind_service
* explain permissive, inheritable, effective and bounding set
* explain securebits
* capsh forks bash with a limited set of capabilities

1. Show different output for root and normal user, man page
2. Remove cap_net_admin capability for root user

    ```sh
    capsh --secbits=1 --caps=all,cap_net_admin-eip --
    ip l s eth0 up
    -> RTNETLINK answers: Operation not permitted
    ```

3. Grant normal users cap_net_admin
* KEEP_CAPS works only once -> have to execve() iproute2 directly
* we use a modified version of capsh that executes the last argument directly

     ```sh
    ./capsh --keep=1 --uid=1000 --caps=all+eip  -- /usr/bin/touch /var/foo
    --> should work, but does not, strange...
    ```

## useful Tools (libcap-ng)
* pscap gives a good overview of processes and their current capabilites
* filecap list all files with special capabilities

# seccomp (Secure computing)
## Strict mode (legacy)
Filter all syscalls, except for read, write, \_exit and sigreturn  

* only read or write to open file descriptors
* no dynamic memory allocation possible, normal binaries won't work

### Filter mode: Filter syscalls and their arguments via BPF
* filter on syscall number and its arguments
* uses the same filter framework as iptables  
* used by many applications, e.g. Chrome and SSH
* best used by application it self (e.g. first has to open socket, then filter syscall to socket())

Examples can be found in ssh source code, eg:

```
...
SC_DENY(open, EACCES),
SC_DENY(stat, EACCES),
SC_ALLOW(getpid),
SC_ALLOW(gettimeofday),
...
```

TODO User Namespaces and capabilities
TODO Example with network namespace and veth dev/special routing of packets from there

## Cgroups
* allow to limit resource usage for groups of processes attached to a cgroup
* defines generic API for different subsystems that implement the actual resource control

### Subsystems
* memory: limit process memory and buffers used by process in kernel
* cpu: limit cpu quota (absolute usage) and cpu shares (like nice
* blkio: limit IOPs and data rate (like ionice, eg used by libvirt)
* freezer: freeze all processes in the group at once (suspend/resume container)

### Example: limit memory
Assume cgroups fs is mounted

1. Create new group 

    ```sh
    mkdir /sys/fs/cgroup/memory/memcg1
    cd /sys/fs/cgroup/memory/memcg1
    ```  
2. Set limit in bytes:

    ```sh
    echo 102400 > memory.limit_in_bytes
    ```  
3. Add our shell to cgroup

    ```sh
    echo $$ > tasks
    ```  
From here on, the shell and its children are not allowed to consume more than 10KB
4. pwd still works (shell builtin)

    ```sh
    pwd
    ```
5. But child is reaped

    ```sh
    free -m
    -> Killed
    ```
6. Show memory failcnt

    ```sh
    cat /sys/fs/cgroup/memory/memcg1/memory.failcnt
    ```  
7. Show kernel output

## Example: CPU shares and sets
1. Create cpuset to bind on CPU core 1

    ```sh
    mkdir /sys/fs/cgroup/cpuset/cpuset1
    cd !$
    ```
2. Set cgroup to bind to CPU 1 and memory node 0 (non-NUMA)

    ```sh
    echo 0 > cpuset.cpus
    echo 0 > cpuset.mems
    ```
3. Run two CPU-consuming taks

    ```sh
    alias heat='dd if=/dev/zero of=/dev/null'
    (heat & heat) &
    ```  
4. Show htop  
Both processes are bound to same CPU, only using ~50% each
5. Create group with quarter CPU share (1024 is default)

    ```sh
    mkdir /sys/fs/cgroup/cpu/cpucg1
    ```  
6. Set shares

    ```sh
    echo 256 > /sys/fs/cgroup/cpu,cpuacct/cpucg1/cpu.shares
    ```  
7. Add our own shell to cgroup

    ```sh
    echo $$ > tasks
    ```  
8. Spawn another CPU heater

    ```sh
    heat
    ```  
htop should show both tasks started first with 40%, the new one with about ~20% (why?). The new heater can be adjusted by writing to cpu.shares.

# Lightweight containers with systemd
* Systemd allows to start processes with constraints for all mentioned security features
* Settings in service unit files
* Every service (not process) gets the same CPU share
* more in man 5 systemd.resource-control

## Example: Run our heat as systemd service
1. Create unit file with cgroups, capabilies and seccomp filter
See file 'heat.service' in the repository. Needed system calls can be found by strace.
2. Reload the service file

    ```sh
    systemctl daemon-reload
    ```
3. Start the service

    ```sh
    systemctl start heat.service
    ```
4. Enter mount namespace of pid
    ```sh
    eval `systemctl show -p ExecMainPID heat.service`
    nsenter -t $ExecMainPID -m
    ls /home /dev /tmp
    ```

## Other examples of containers in applications

### Chrom(e/ium)
* each renderer of a web page is put in its own sandbox
* reduces attack surface to system
* user namespaces
* seccomp-bpf 

### Firefox
* same as for Chrome, but no seperate processes by default (switch on Electrolysis)

# Gnome Sandbox
* provide a sandbox for each process
* mount namespace, only required system parts and dependencies are mounted
* net namespace allows network filtering/routing for each app
* (k)dbus proxy filtering
-> a lot like iOS/Android

### lxc
* all mentioned features configurable

## SELinux
* can be combined with all mentioned separation methods
* used with Docker on Centos/RHEL
* proposal: talk about Docker security and SELinux
