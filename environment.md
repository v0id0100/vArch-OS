# Environment

Once you had booted, to set the folders you have to set the following on: **.config/user-dirs.dirs**

```text
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG_PROJECTS_DIR="$HOME/Projects"
```

Once set it, you have to create them:

```bash
mkdir -p {Desktop,Downloads,Templates,Public,Documents,Music,Pictures,Videos,Projects}
```

And then change the "Dolphin" configuration like:

1. Opening Dolphin
2. In Sites right click the folder name
3. Edit it
4. In the ubication select the folder you had create it
5. That's it