# Kernel features for container virtualization and privilege separation

## PID and mount namespaces

## Prepare a busybox environment  
`./create-busybox.sh`

## Show PID namespaces  
Still old /proc mount  
```sh
sudo unshare -p -f /container/1/sh
ps w
cd /proc/self; pwd -P
```

Show process in root namespace  
`ps -q <PID in root ns>  

/proc mount in new process namespace  
`chroot /container/1`  
`mount -t proc  proc /proc`  
`ps w`  

Do the same stuff in container 2, show which processes are visible where  

## Add mount namespaces  
1. Make sure / is mounted private:  
`sudo mount --make-private /`  
2. Create new mount and PID namespace:  
`sudo unshare -p -m -f /container/1/sh` 
3. Chroot and mount /proc  
`chroot /container/1; mount -t proc  proc /proc`  
4. List mounts in root and container namespace  
`ls /proc` in new namespace  
`ls /container/1/proc/` should be empty  
5. Example with shared root mount  


# Capabilities

* restrict access to several permission (not dependent on implementation)
* similar to permissions on Android or iOS

# Example for Network Admin Capability

We will shoe that the root user in a docker container can not bring its network device down
1. Start docker  
`docker run -t -i debian:jessie /bin/bash`  
2. eth0 down
`ip l s eth0 down`
-> `RTNETLINK answers: Operation not permitted`
3. capsh --print
-> cap_net_admin missing in Current set, therefore no access to network management functions (NB no limit to single syscall, but messages on netlink socket)

### Capabilities w/o Docker

* capsh forks bash with a limited set of capabilities
* TODO: explain permissive, inheritable, effective and bounding set
* TODO: explain securebits
* example for capabilites

1. Show different output for root and normal user  
2. Remove cap_net_admin capability for root user
-> `capsh --secbits=1 --caps=all,cap_net_admin-eip --`  
-> `ip l s eth0 up`  
RTNETLINK answers: Operation not permitted

3. Grant normal users cap_net_admin

* KEEP_CAPS works only once -> have to execve() iproute2 directly
-> `./capsh --keep=1 --uid=1000 --caps=all+eip  -- /usr/bin/touch /var/foo`
--> should work, but does not, strange...

## Tools
* pscap gives a good overview of processes and their current capabilites
* filecap list all files with special capabilities

# seccomp
### Strict mode
Filter all syscalls, except for read, write, \_exit and sigreturn  

* only read or write to open file descriptors
* no dynamic memory allocation possible, normal binaries won't work

### Filter mode: Filter syscalls and their arguments via BPF
* filter on syscall no and its arguments
* uses the same filter framework as iptables  
* used by many applications, e.g. Chrome and SSH
* TODO write own example

Examples can be found in ssh source code, eg:

'''
...
SC_DENY(open, EACCES),
SC_DENY(stat, EACCES),
SC_ALLOW(getpid),
SC_ALLOW(gettimeofday),
...
'''

TODO Usernamespaces and capabilities
TODO Example with network namespace and veth dev/special routing of packets from there

# Cgroups
* allow to limit resource usage for single processes
* Subsystems

## Example:  limit memory
Assume cgroups fs is mounted

1. Create new group 
`mkdir /sys/fs/cgroup/memory/memcg1`
`cd /sys/fs/cgroup/memory/memcg1`  
2. Set limit in bytes:
`echo 102400 > memory.limit_in_bytes`  
3. Add our shell to cgroup
`echo $$ > tasks`  
From here on, the shell and its children are not allowed to consume more than 10KB
4. pwd still works (shell builtin)
`pwd`
5. But child is reaped
`free -m`
-> Killed
6. Show memory failcnt
`cat /sys/fs/cgroup/memory/memcg1/memory.failcnt`  
7. Show kernel output

## Example: CPU shares and sets
1. Create cpuset to bind on CPU core 1
`mkdir /sys/fs/cgroup/cpuset/cpuset1`  
`cd !$`
2. Set cgroup to bind to CPU 1 and memory node 0 (non-NUMA)
`echo 0 > cpuset.cpus`  
`echo 0 > cpuset.mems`
3. Run two CPU-consuming taks
`alias heat='dd if=/dev/zero of=/dev/null'`  
`(heat & heat) &`  
4. Show htop  
Both processes are bound to same CPU, only using ~50% each
5. Create group with quarter CPU share (1024 is default)
`mkdir /sys/fs/cgroup/cpu/cpucg1`  
6. Set shares
`echo 256 > /sys/fs/cgroup/cpu,cpuacct/cpucg1/cpu.shares`  
7. Add our own shell to cgroup
`echo $$ > tasks`  
8. Spawn another CPU heater
`heat`  
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
`systemctl daemon-reload`
3. Start the service
`systemctl start heat.service`
4. Enter mount namespace of pid
'''
eval `systemctl show -p ExecMainPID heat.service`
nsenter -t $ExecMainPID -m
ls /home /dev /tmp
'''

## Other examples of containers in applications

# Chrom(e/ium)
* each renderer of a web page is put in its own sandbox
* reduces attack surface to system
* user namespaces
* seccomp-bpf 

# Firefox
* same as for Chrome, but no seperate processes by default (switch on Electrolysis)

# Gnome Sandbox
* provide a sandbox for each process
* mount namespace, only required system parts and dependencies are mounted
* net namespace allows network filtering/routing for each app
* (k)dbus proxy filtering
-> a lot like iOS/Android

# lxc
* all mentioned features configurable

# SELinux
* can be combined with all mentioned separation methods
* used with Docker on Centos/RHEL
* proposal: talk about Docker security and SELinux

## TODO
1. Wrapper for capsetp
2. Shell completion for capsh
