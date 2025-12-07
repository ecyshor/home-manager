# Enabling Hibernation with a Swap File on Ubuntu

This document outlines the steps to create a swap file and configure the system to use it for hibernation.
This requires secure boot to be off.

## 1. Create the Swap File

We will create a 64GB swap file at `/swapfile`.

```bash
sudo fallocate -l 64G /swapfile
```

## 2. Set Permissions

Next, we need to set the correct permissions on the swap file to ensure it's only accessible by root.

```bash
sudo chmod 600 /swapfile
```

## 3. Format as Swap

Now, we'll format the file as swap.

```bash
sudo mkswap /swapfile
```

## 4. Enable the Swap File

Next, we enable the swap file.

```bash
sudo swapon /swapfile
```

## 5. Make the Swap File Permanent

To make the swap file permanent, we need to add it to `/etc/fstab`.

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 6. Configure GRUB for Hibernation

To allow hibernation, we need to tell the kernel where the swap file is. We do this by adding a kernel parameter to GRUB.

### 6.1. Find the UUID of the root filesystem

First, find the UUID of your root filesystem (`/`).

```bash
findmnt -no UUID -T /
```

### 6.2. Find the physical offset of the swap file

Next, find the physical offset of the swap file.

```bash
sudo filefrag -v /swapfile
```

The output will look something like this:

```
Filesystem type is: ef53
File size of /swapfile is 68719476736 (16777216 blocks of 4096 bytes)
 ext:     logical_offset:        physical_offset: length:   expected: flags:
   0:        0..       0:      34816..     34816:      1:
   1:        1..    8191:      36864..     45055:   8191:      34817:
   2:     8192..   16383:      53248..     61439:   8192:      45056:
...
```

The value we need is from the first line under `physical_offset`. In this example, it's `34816`.

### 6.3. Edit the GRUB configuration file

Run the following command to automatically update the GRUB configuration file.

```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash resume=UUID=ca0b725a-1153-4d34-b805-c4bd8f538033 resume_offset=168359936"/' /etc/default/grub
```

### 6.4. Update GRUB

Finally, update GRUB to apply the changes.

```bash
sudo update-grub
```

## 7. Enable Hibernation

By default, hibernation is disabled. To enable it, we need to create a polkit rule.

First, create the file `/etc/polkit-1/rules.d/10-enable-hibernate.rules` and add the following content:

```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.upower.hibernate" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit")
    {
        return polkit.Result.YES;
    }
});
```

You can create this file with the following command:

```bash
sudo bash -c 'cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules <<EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.upower.hibernate" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit")
    {
        return polkit.Result.YES;
    }
});
EOF'
```

After a reboot, you should be able to hibernate.

## 8. Adjusting Swappiness (Optional)

Swappiness is a Linux kernel parameter that controls how aggressively the kernel will use swap space. A high value means the kernel will swap more often, while a low value tells the kernel to avoid swapping as much as possible.

Since we have a large swap file primarily for hibernation, we can lower the swappiness value to ensure the swap is only used in extreme cases of low memory. A recommended value for this scenario is 10.

### 8.1. Set the new swappiness value for the current session

```bash
sudo sysctl vm.swappiness=10
```

### 8.2. Make the change permanent

To make this change permanent, we'll create a new sysctl configuration file.

```bash
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
```

## 9. Enable Suspend-then-Hibernate and Hibernation (Optional)

Suspend-then-hibernate is a power-saving mode where the system first suspends to RAM (a low-power state with fast resume) and then, after a specified delay, hibernates to disk (a zero-power state that doesn't drain the battery). This gives you the best of both worlds: a quick resume if you get back to your computer soon, and no battery drain if you're away for longer.

To enable this, and to allow direct hibernation, we need to edit the systemd login manager configuration.

### 9.1. Edit `/etc/systemd/logind.conf`

We need to uncomment the `SleepOperation` option in `/etc/systemd/logind.conf` and set it to `suspend-then-hibernate suspend hibernate`.

You can use the following command to uncomment the line and set the value:

```bash
sudo sed -i 's/#SleepOperation=.*/SleepOperation=suspend-then-hibernate suspend hibernate/' /etc/systemd/logind.conf
```

### 9.2. Restart the systemd-logind service

For the changes to take effect, you need to restart the `systemd-logind` service.

```bash
sudo systemctl restart systemd-logind
```
