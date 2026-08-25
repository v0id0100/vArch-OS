# Desktop Customization:

### Booting:

- Once booted you should see the "GRUB":

![alt text](./images/.image4.png)

- Enter your password:

![alt text](./images/.image5.png)

- You are in:

![alt text](./images/.image6.png)

---

### Connecting to Internet:

- You have to enable NetworkManager:
```bash
sudo systemctl enable NetworkManager && sudo systemctl start NetworkManager
```

- Test Internet Connection:
```bash
ping -c 3 google.com
```

---

### Starting bluetooth modules:
```bash
sudo modprobe btusb && sudo systemctl start bluetooth && sudo systemctl enable bluetooth
```

---

### Installing video drivers:

- First you need to edit you pacman settings file:
- Remove the "#" on Multilib repository: /etc/pacman.conf
```txt
[multilib]
Include = /etc/pacman.d/mirrorlist
```

- Update:
```bash
sudo pacman -Syu && sudo pacman -S mesa lib32-mesa vulkan-intel intel-media-driver
```

---

### Installing audio drivers:

```bash
sudo pacman -S pipewire pipewire-alsa pipewire-pulse wireplumber
```

---

### Installing kde-plasma desktop environment:

- Install ***plasma-meta***, this is because "meta" keeps updating unlike plasma.

```bash
sudo pacman -S plasma-meta

# Then choose option 1: qt6-multimedia-ffmpeg

# then choose option 2: pipewire-jack

# Then choose noto-fonts.

# Then press 30.
```

- Press enter to install.

- Now the kde-applications:
```bash
sudo pacman -S kde-applications

# On the first option select = ALL (ENTER)

# On the second question choose 1.

# On the third one choose 1.

# On the fourth one choose 30 (English)
```
- Login manager:
```bash
sudo pacman -S plasma-login-manager && sudo systemctl enable plasmalogin
```

- Reiniciar amb ***"reboot"***

---

### Initial Interface:

- The initial interface is thisone:

![alt text](./images/.image7.png)

![alt text](./images/.image8.png)

### Custom the interface:

- First I installed some things: [packages.sh](./src/packages.sh)

- Change your terminal:
```bash
chsh
# Put your password

# Change to [/bin/zsh]
```

- Once this script executed load the effect:

![alt text](./images/.image-16.png)

- I selected these themes:

![alt text](./images/.image-9.png)

- And installed those:

![alt text](./images/.image-10.png)

- It is taking shape:

![alt text](./images/.image-11.png)

![alt text](./images/.image-12.png)

- Add some plugins:
    - Gemini (must set your Google API in config (right click on it))
    - CPU cat
    - Bluetooth
    - Apps Interface

- Install web app hub to use web like apps. Ex: Netflix.

![alt text](./images/.image-13.png)

- Final shape:

<h2>Before:</h2>

![alt text](./images/.image7.png)

<h2>After:</h2>

![alt text](./images/.image-14.png)