// The Amethystora icon packs: one set of glyphs (icons/glyphs.mjs), each icon in colours of its own, drawn three ways.
//
//   Glass    the glyph filled with its gradient, its details lighter, a glass sheen inside and a shadow below
//   Neon     the glyph's outline and its details lit in a three-colour prism, glowing
//   Duotone  the glyph in its gradient and its details in a contrasting one
//
// They cover Amethystora's apps, GNOME's, the system's and other makers' apps, each drawn by what it does, folders,
// file types, devices, dialogs and categories. An app whose icon is its maker's mark (LOGOS) keeps the one it ships,
// which the packs reach through Inherits (hicolor), and the symbolic icons of the top bar and the menus are Adwaita's.
//
//   node branding/icons.mjs            writes the packs into system_files/shared/usr/share/icons
//   node branding/icons.mjs --preview  also writes a sheet of every icon in every pack, and prints where
import {mkdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DRAW} from './icons/glyphs.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ICONS = join(ROOT, 'system_files/shared/usr/share/icons');

// The colours: each ramp is the gradient the glyph is filled with, the prism Neon lights it in, and the contrasting
// gradient Duotone draws its details in
const RAMPS = {
    sunset: [['#ffb347', '#ff5f6d'], ['#ffe259', '#ffa751', '#ff5f6d'], ['#5be7ff', '#4facfe']],
    ocean: [['#36d1dc', '#5b86e5'], ['#a8ff78', '#36d1dc', '#5b86e5'], ['#ffd86f', '#fc6262']],
    mint: [['#38ef7d', '#11998e'], ['#f9f871', '#38ef7d', '#11998e'], ['#f6d365', '#fda085']],
    orchid: [['#ff6ec4', '#7873f5'], ['#ffd3a5', '#ff6ec4', '#7873f5'], ['#d4fc79', '#96e6a1']],
    amber: [['#ffd200', '#f7971e'], ['#fff6b7', '#ffd200', '#f7971e'], ['#6a11cb', '#2575fc']],
    dusk: [['#b06ab3', '#4568dc'], ['#ff9a9e', '#b06ab3', '#4568dc'], ['#fddb92', '#f6d365']],
    emerald: [['#00f260', '#0575e6'], ['#e0ff4f', '#00f260', '#0575e6'], ['#ffe29f', '#ffa99f']],
    flame: [['#fc466b', '#3f5efb'], ['#ffb199', '#fc466b', '#3f5efb'], ['#c2e9fb', '#a1c4fd']],
    sky: [['#00f2fe', '#4facfe'], ['#c2ffd8', '#00f2fe', '#4facfe'], ['#ffecd2', '#fcb69f']],
    blossom: [['#f093fb', '#f5576c'], ['#ffe0f7', '#f093fb', '#f5576c'], ['#fffde4', '#fbd786']],
    grape: [['#da22ff', '#9733ee'], ['#ffb3ff', '#da22ff', '#9733ee'], ['#f9f871', '#7df9c4']],
    lagoon: [['#00c6ff', '#0072ff'], ['#8fffef', '#00c6ff', '#0072ff'], ['#ffe985', '#fa742b']],
    coral: [['#ff9966', '#ff5e62'], ['#ffd194', '#ff9966', '#ff5e62'], ['#a1ffce', '#5ee7df']],
    lime: [['#a8e063', '#2fb36d'], ['#f9f871', '#a8e063', '#2fb36d'], ['#ffc3f8', '#f093fb']],
    cherry: [['#ff512f', '#dd2476'], ['#ffc371', '#ff512f', '#dd2476'], ['#fdfcfb', '#b8f1ff']],
    royal: [['#4776e6', '#8e54e9'], ['#7ee8fa', '#4776e6', '#8e54e9'], ['#ffd3a5', '#fd6585']],
    aqua: [['#43e97b', '#38f9d7'], ['#f9f871', '#43e97b', '#38f9d7'], ['#5f72ff', '#9a5cff']],
    peach: [['#f6d365', '#fda085'], ['#fff1b8', '#f6d365', '#fda085'], ['#7f7fd5', '#86a8e7']],
    magenta: [['#ec008c', '#fc6767'], ['#ffb3d9', '#ec008c', '#fc6767'], ['#fff6b7', '#f6d365']],
    indigo: [['#667eea', '#764ba2'], ['#a1c4fd', '#667eea', '#8e6bd8'], ['#f9f871', '#ffc371']],
    ice: [['#89f7fe', '#66a6ff'], ['#e0fcff', '#89f7fe', '#66a6ff'], ['#ff9a9e', '#fecfef']],
    gold: [['#f7b733', '#fc4a1a'], ['#fff3b0', '#f7b733', '#fc4a1a'], ['#89f7fe', '#66a6ff']],
};

// Every icon: its name, the drawing, the ramp, and the other names it answers to. A file type is named as
// shared-mime-info's generic icons are, so it covers every type that falls back on that name.
const SET = {
    apps: [
        ['amethystora-docs', 'manual', 'dusk'],
        ['amethystora-security-status', 'security', 'emerald'],
        ['amethystora-control', 'control', 'flame'],
        ['amethystora-update', 'update', 'lagoon', ['system-software-update', 'system-software-install', 'software-update-available']],
        ['amethystora-logs', 'logs', 'aqua', ['utilities-log-viewer', 'org.gnome.Logs']],
        ['amethystora-notes', 'notes', 'gold', ['accessories-notes']],
        ['amethystora-backups', 'backups', 'royal'],
        ['amethystora-phone', 'phone-link', 'grape'],
        ['amethystora-community', 'community', 'magenta'],
        ['org.gnome.Nautilus', 'files', 'sunset', ['system-file-manager']],
        ['org.gnome.Settings', 'settings', 'ocean', ['preferences-system', 'preferences-desktop', 'gnome-control-center']],
        ['org.gnome.Ptyxis', 'terminal', 'mint', ['utilities-terminal', 'org.gnome.Terminal', 'org.gnome.Console']],
        ['org.gnome.SystemMonitor', 'monitor', 'cherry', ['utilities-system-monitor', 'gnome-system-monitor']],
        ['org.gnome.DiskUtility', 'drive', 'indigo', ['disk-utility', 'gnome-disks']],
        ['org.gnome.Tour', 'compass', 'peach'],
        ['org.gnome.tweaks', 'wrench', 'lime'],
        ['org.freedesktop.MalcontentControl', 'guardian', 'grape'],
        ['firewall-config', 'wall', 'coral'],
        ['input-remapper', 'keyboard', 'dusk'],
        ['gnome-color-manager', 'palette', 'blossom', ['preferences-color']],
        ['rygel', 'broadcast', 'lagoon'],
        ['help-browser', 'lifebuoy', 'cherry', ['org.gnome.Yelp', 'help-contents', 'yelp']],
        ['org.gnome.Calculator', 'calculator', 'amber', ['accessories-calculator', 'gnome-calculator']],
        ['org.gnome.Calendar', 'calendar', 'cherry', ['office-calendar']],
        ['org.gnome.Characters', 'smile', 'peach', ['accessories-character-map']],
        ['org.gnome.Connections', 'remote', 'royal', ['preferences-desktop-remote-desktop']],
        ['org.gnome.Contacts', 'contact', 'coral', ['office-address-book']],
        ['org.gnome.FileRoller', 'archive', 'gold', ['file-roller']],
        ['org.gnome.Firmware', 'chip', 'lime'],
        ['org.gnome.Loupe', 'photo', 'magenta', ['image-viewer', 'multimedia-photo-viewer']],
        ['org.gnome.Maps', 'map', 'aqua'],
        ['org.gnome.Papers', 'pages', 'flame', ['document-viewer', 'org.gnome.Evince']],
        ['org.gnome.Showtime', 'play', 'grape', ['multimedia-video-player', 'video-player', 'org.gnome.Totem']],
        ['org.gnome.SimpleScan', 'scanner', 'ice'],
        ['org.gnome.Snapshot', 'camera', 'indigo', ['accessories-camera']],
        ['org.gnome.Decibels', 'notes2', 'blossom', ['multimedia-audio-player', 'audio-player']],
        ['org.gnome.TextEditor', 'editor', 'orchid', ['accessories-text-editor', 'text-editor', 'org.gnome.gedit']],
        ['org.gnome.Weather', 'weather', 'sky'],
        ['org.gnome.baobab', 'pie', 'gold', ['disk-usage-analyzer', 'baobab']],
        ['org.gnome.clocks', 'alarm', 'lagoon', ['preferences-system-time']],
        ['org.gnome.font-viewer', 'letter', 'dusk', ['preferences-desktop-font']],
        ['org.gnome.Builder', 'code', 'royal'],
        ['application-default-icon', 'app', 'royal'],

        // Other makers' apps, each drawn by what it does
        ['org.kde.dolphin', 'files', 'sunset', ['thunar', 'org.xfce.thunar', 'nemo', 'caja', 'pcmanfm', 'pcmanfm-qt']],
        ['org.kde.konsole', 'terminal', 'mint', ['konsole', 'xfce4-terminal', 'org.xfce.terminal', 'com.gexperts.Tilix', 'tilix',
            'com.raggesilver.BlackBox', 'app.devsuite.Prompt', 'gnome-terminal', 'mate-terminal', 'lxterminal', 'qterminal']],
        ['org.kde.kwrite', 'editor', 'orchid', ['kwrite', 'org.xfce.mousepad', 'mousepad', 'pluma', 'xed', 'org.x.editor', 'gedit',
            'org.gnome.gitlab.somas.Apostrophe', 'com.github.fabiocolacio.marker']],
        ['org.kde.kcalc', 'calculator', 'amber', ['kcalc', 'galculator', 'qalculate', 'qalculate-gtk', 'io.github.Qalculate', 'mate-calc']],
        ['io.missioncenter.MissionCenter', 'monitor', 'cherry', ['net.nokyan.Resources', 'org.kde.plasma-systemmonitor', 'ksysguard', 'htop',
            'btop', 'nvtop', 'org.xfce.taskmanager', 'xfce4-taskmanager']],
        ['org.kde.systemsettings', 'settings', 'ocean', ['systemsettings', 'org.xfce.settings.manager', 'xfce4-settings-manager',
            'ca.desrt.dconf-editor', 'dconf-editor']],
        ['org.gnome.Software', 'store', 'peach', ['gnome-software', 'io.github.kolunmi.Bazaar', 'org.kde.discover', 'plasmadiscover']],
        ['io.github.flattool.Warehouse', 'package', 'gold'],
        ['com.github.tchx84.Flatseal', 'toggles', 'emerald'],
        ['io.github.flattool.Ignition', 'rocket', 'coral'],
        ['gparted', 'drive', 'indigo', ['org.gnome.GParted', 'org.kde.partitionmanager', 'partitionmanager']],
        ['org.gnome.DejaDup', 'drive', 'emerald', ['deja-dup', 'org.gnome.World.PikaBackup', 'timeshift', 'com.borgbase.Vorta']],
        ['io.gitlab.adhami3310.Impression', 'usb', 'gold'],
        ['io.gitlab.metadatacleaner.metadatacleaner', 'broom', 'lime', ['org.bleachbit.BleachBit', 'bleachbit', 'org.kde.sweeper']],
        ['de.leopoldluley.Clapgrep', 'search', 'sky', ['catfish', 'org.xfce.catfish', 'org.kde.kfind', 'io.github.cboxdoerfer.FSearch', 'system-search']],
        ['io.github.getnf.embellish', 'letter', 'dusk', ['org.gnome.FontManager', 'font-manager']],
        ['me.iepure.devtoolbox', 'toolbox', 'gold'],
        ['com.mattjakeman.ExtensionManager', 'addon', 'lime', ['org.gnome.Shell.Extensions', 'org.gnome.Extensions']],
        ['it.mijorus.smile', 'smile', 'peach', ['com.tomjwatson.Emote']],
        ['page.tesk.Refine', 'wrench', 'lime'],
        ['com.ranfdev.DistroShelf', 'containers', 'ocean', ['io.github.dvlv.boxbuddyrs', 'distrobox']],
        ['org.gnome.Boxes', 'vm', 'indigo', ['gnome-boxes', 'virt-manager', 'org.virt_manager.virt-manager']],
        ['re.sonny.Workbench', 'code', 'royal', ['org.gnome.Meld', 'meld', 'org.gnome.GHex', 'ghex']],
        ['org.gnome.gitg', 'branch', 'coral', ['gitg', 'org.kde.kommit']],
        ['org.gnome.Geary', 'mail', 'lagoon', ['geary', 'org.gnome.Evolution', 'evolution', 'org.kde.kmail2', 'kmail', 'internet-mail']],
        ['org.gnome.Fractal', 'chat', 'aqua', ['org.gnome.Polari', 'polari', 'dev.geopjr.Tuba', 'org.kde.tokodon', 'org.kde.neochat',
            'internet-chat', 'internet-group-chat', 'empathy']],
        ['io.gitlab.news_flash.NewsFlash', 'feed', 'amber', ['com.gitlab.newsflash', 'org.gabmus.gfeeds', 'org.kde.akregator', 'akregator',
            'liferea', 'net.sourceforge.liferea', 'internet-news-reader']],
        ['de.haeckerfelix.Fragments', 'download', 'emerald', ['com.transmissionbt.Transmission', 'transmission', 'transmission-gtk',
            'transmission-qt', 'org.kde.ktorrent', 'ktorrent', 'io.github.giantpinkrobots.varia', 'org.nickvision.tubeconverter']],
        ['org.gnome.seahorse.Application', 'key', 'gold', ['seahorse', 'org.gnome.World.Secrets', 'com.belmoussaoui.Authenticator',
            'kwalletmanager', 'org.kde.kwalletmanager5']],
        ['com.github.johnfactotum.Foliate', 'book', 'peach', ['info.febvre.Komikku', 'com.calibre_ebook.calibre', 'calibre-gui',
            'com.github.babluboy.bookworm', 'org.kde.arianna', 'accessories-dictionary', 'org.gnome.Dictionary']],
        ['com.github.PintaProject.Pinta', 'brush', 'blossom', ['com.github.maoschanz.drawing', 'org.kde.kolourpaint', 'kolourpaint', 'com.github.flxzt.rnote']],
        ['be.alexandervanhee.gradia', 'screenshot', 'flame', ['org.gnome.Screenshot', 'gnome-screenshot', 'org.kde.spectacle', 'spectacle',
            'org.ksnip.ksnip', 'applets-screenshooter']],
        ['io.github.seadve.Kooha', 'record', 'cherry'],
        ['org.gnome.SoundRecorder', 'microphone', 'cherry', ['gnome-sound-recorder']],
        ['com.github.finefindus.eyedropper', 'eyedropper', 'magenta', ['nl.hjdskes.gcolor3', 'gcolor3', 'org.kde.kcolorchooser']],
        ['io.github.nate_xyz.Paleta', 'palette', 'blossom'],
        ['app.drey.Dialect', 'translate', 'sky'],
        ['org.gnome.Music', 'notes2', 'blossom', ['gnome-music', 'org.gnome.Rhythmbox3', 'rhythmbox', 'org.gnome.Lollypop', 'lollypop',
            'io.bassi.Amberol', 'org.kde.elisa', 'elisa', 'com.github.neithern.g4music']],
        ['de.haeckerfelix.Shortwave', 'radio', 'coral'],
        ['org.gnome.Podcasts', 'broadcast', 'lagoon', ['org.kde.kasts', 'kasts']],
        ['io.github.celluloid_player.Celluloid', 'play', 'grape', ['celluloid', 'org.kde.haruna', 'haruna', 'com.github.rafostar.Clapper',
            'org.kde.dragonplayer', 'org.xfce.Parole', 'parole']],
        ['org.pitivi.Pitivi', 'film', 'flame', ['pitivi', 'org.gnome.gitlab.YaLTeR.VideoTrimmer', 'io.github.jliljebl.Flowblade']],
        ['org.gnome.eog', 'photo', 'magenta', ['eog', 'org.gnome.gThumb', 'gthumb', 'org.kde.gwenview', 'gwenview', 'org.xfce.ristretto',
            'ristretto', 'org.gnome.Shotwell', 'shotwell', 'org.gnome.Photos', 'gnome-photos', 'com.github.huluti.Curtail',
            'io.gitlab.theevilskeleton.Upscaler', 'io.gitlab.adhami3310.Converter']],
        ['org.kde.okular', 'pages', 'flame', ['okular', 'evince', 'atril', 'org.x.reader', 'xreader']],
        ['org.gnome.Cheese', 'camera', 'indigo', ['cheese', 'org.kde.kamoso']],
        ['org.kde.korganizer', 'calendar', 'cherry', ['korganizer']],
        ['org.kde.kaddressbook', 'contact', 'coral', ['kaddressbook']],
        ['org.gnome.Notes', 'notepad', 'amber', ['bijiben', 'org.gnome.Gnote', 'gnote', 'org.gnome.World.Iotas', 'com.toolstack.Folio']],
        ['io.github.alainm23.planify', 'tasks', 'emerald', ['io.github.mrvladus.List', 'org.gnome.Todo', 'org.gnome.Endeavour']],
        ['org.gnome.Solanum', 'alarm', 'lagoon', ['io.gitlab.idevecore.Pomodoro']],
        ['org.kde.ark', 'archive', 'gold', ['ark', 'xarchiver', 'engrampa']],
        ['org.gnome.Mines', 'gamepad', 'flame', ['gnome-mines', 'org.gnome.Sudoku', 'gnome-sudoku', 'org.gnome.Quadrapassel', 'org.gnome.Tali',
            'org.gnome.SwellFoop', 'org.gnome.TwentyFortyEight', 'org.gnome.Nibbles', 'org.gnome.Robots', 'org.gnome.Klotski',
            'org.gnome.Reversi', 'org.gnome.Taquin', 'org.gnome.Tetravex', 'org.gnome.LightsOff', 'org.gnome.Atomix', 'org.gnome.Hitori',
            'org.gnome.five-or-more', 'org.gnome.Four-in-a-row']],
        ['org.gnome.Aisleriot', 'cards', 'cherry', ['gnome-aisleriot', 'sol', 'org.gnome.Mahjongg', 'gnome-mahjongg', 'org.kde.kpat', 'kpat']],
        ['org.gnome.Chess', 'chess', 'dusk', ['gnome-chess', 'org.kde.knights']],
        ['com.usebottles.bottles', 'bottle', 'magenta'],
        ['orca', 'access', 'ocean', ['org.gnome.Orca', 'preferences-desktop-accessibility']],
        ['ibus', 'keyboard', 'indigo', ['ibus-setup', 'org.freedesktop.IBus.Setup', 'org.gnome.Tecla', 'preferences-desktop-keyboard']],
        ['org.freedesktop.Piper', 'mouse', 'sky', ['piper', 'preferences-desktop-peripherals']],
        ['org.pulseaudio.pavucontrol', 'speaker', 'sunset', ['pavucontrol', 'multimedia-volume-control', 'com.saivert.pwvucontrol', 'com.rafaelmardojai.Blanket']],
        ['com.github.wwmm.easyeffects', 'equalizer', 'grape', ['easyeffects']],
        ['nm-connection-editor', 'wifi', 'lagoon', ['preferences-system-network']],
        ['system-config-printer', 'printer', 'coral'],
        ['org.gnome.PowerStats', 'battery', 'lime', ['gnome-power-statistics', 'preferences-system-power']],
        ['org.gnome.Epiphany', 'globe', 'lagoon', ['epiphany', 'internet-web-browser', 'web-browser', 'org.gnome.Shell.CaptivePortal']],
        ['org.kde.krdc', 'remote', 'royal', ['krdc']],
        ['org.kde.skanpage', 'scanner', 'ice', ['skanlite', 'xsane']],
        ['abiword', 'document', 'ocean'],
        ['gnumeric', 'spreadsheet', 'emerald', ['org.gnome.Gnumeric']],
        ['preferences-desktop-display', 'computer', 'ocean'],
        ['preferences-desktop-wallpaper', 'photo', 'sunset'],
        ['preferences-desktop-theme', 'palette', 'orchid'],
        ['preferences-desktop-locale', 'globe', 'emerald'],
    ],
    places: [
        ['folder', 'folder', 'sky', ['inode-directory', 'folder-open', 'folder-drag-accept', 'folder-visiting']],
        ['folder-documents', 'folder-documents', 'sky'],
        ['folder-download', 'folder-download', 'sky'],
        ['folder-music', 'folder-music', 'sky'],
        ['folder-pictures', 'folder-pictures', 'sky'],
        ['folder-videos', 'folder-videos', 'sky'],
        ['folder-templates', 'folder-templates', 'sky'],
        ['folder-publicshare', 'folder-publicshare', 'sky'],
        ['user-desktop', 'folder-desktop', 'sky', ['folder-desktop']],
        ['folder-remote', 'folder-remote', 'sky', ['folder-network']],
        ['folder-saved-search', 'search', 'sky'],
        ['folder-locked', 'folder-locked', 'sky'],
        ['user-home', 'home', 'peach', ['folder-home']],
        ['user-trash', 'trash', 'ice'],
        ['user-trash-full', 'trash-full', 'ice'],
        ['network-server', 'server', 'indigo', ['network-workgroup']],
        ['user-bookmarks', 'bookmark', 'gold'],
        ['avatar-default', 'avatar', 'orchid', ['system-users']],
    ],
    mimetypes: [
        ['text-x-generic', 'text', 'blossom'],
        ['text-x-script', 'script', 'mint'],
        ['text-html', 'html', 'lagoon'],
        ['application-x-executable', 'app', 'royal'],
        ['image-x-generic', 'image', 'sunset'],
        ['audio-x-generic', 'audio', 'orchid'],
        ['video-x-generic', 'video', 'grape'],
        ['package-x-generic', 'package', 'gold'],
        ['application-pdf', 'pdf', 'cherry'],
        ['x-office-document', 'document', 'ocean'],
        ['x-office-spreadsheet', 'spreadsheet', 'emerald'],
        ['x-office-presentation', 'presentation', 'coral'],
        ['x-office-drawing', 'drawing', 'magenta'],
        ['x-office-address-book', 'contact', 'coral'],
        ['x-office-calendar', 'calendar', 'cherry', ['text-calendar']],
        ['font-x-generic', 'font', 'dusk'],
        ['text-x-generic-template', 'template', 'ice'],
        ['application-x-addon', 'addon', 'lime'],
        ['application-x-firmware', 'chip', 'lime'],
        ['application-x-cd-image', 'disc', 'indigo', ['application-x-iso9660-image', 'application-x-raw-disk-image',
            'application-x-raw-disk-image-xz-compressed', 'application-x-qemu-disk', 'application-vnd.efi.iso', 'application-x-apple-diskimage']],
        ['application-zip', 'zip', 'gold', ['application-x-zip', 'application-x-tar', 'application-x-compressed-tar', 'application-x-bzip',
            'application-x-bzip-compressed-tar', 'application-gzip', 'application-x-gzip', 'application-x-xz', 'application-x-xz-compressed-tar',
            'application-x-7z-compressed', 'application-vnd.rar', 'application-x-rar', 'application-zstd', 'application-x-zstd-compressed-tar',
            'application-x-lzma', 'application-x-archive', 'application-x-cpio']],
        ['application-x-rpm', 'package', 'amber', ['application-vnd.debian.binary-package', 'application-vnd.flatpak', 'application-vnd.flatpak.ref',
            'application-vnd.flatpak.repo', 'application-x-java-archive']],
        ['application-vnd.appimage', 'app', 'lagoon', ['application-x-ms-dos-executable', 'application-x-msdownload', 'application-x-msi',
            'application-x-sharedlib', 'application-x-desktop']],
        ['application-pgp-keys', 'key-file', 'gold', ['application-pgp-encrypted', 'application-pgp-signature', 'application-x-keepass2', 'application-x-pem-key']],
        ['application-x-x509-ca-cert', 'certificate', 'emerald', ['application-pkcs12', 'application-x-pkcs12', 'application-pkix-cert',
            'application-x-pkcs7-certificates']],
        ['application-x-bittorrent', 'download-file', 'emerald'],
        ['application-epub+zip', 'book-file', 'peach', ['application-x-mobipocket-ebook', 'application-vnd.comicbook+zip',
            'application-vnd.comicbook-rar', 'application-x-fictionbook+xml']],
        ['font-ttf', 'font', 'dusk', ['font-otf', 'font-woff', 'font-woff2', 'font-collection', 'application-x-font-ttf']],
        ['application-vnd.oasis.opendocument.text', 'document', 'ocean', ['application-vnd.openxmlformats-officedocument.wordprocessingml.document',
            'application-msword', 'application-rtf']],
        ['application-vnd.oasis.opendocument.spreadsheet', 'spreadsheet', 'emerald', ['application-vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application-vnd.ms-excel']],
        ['application-vnd.oasis.opendocument.presentation', 'presentation', 'coral', ['application-vnd.openxmlformats-officedocument.presentationml.presentation',
            'application-vnd.ms-powerpoint']],
        ['application-vnd.oasis.opendocument.graphics', 'drawing', 'magenta'],
        ['image-png', 'image', 'sunset', ['image-jpeg', 'image-gif', 'image-webp', 'image-tiff', 'image-bmp', 'image-avif', 'image-heif', 'image-jxl', 'image-x-icon']],
        ['image-svg+xml', 'label-SVG', 'orchid'],
        ['audio-mpeg', 'audio', 'orchid', ['audio-flac', 'audio-x-wav', 'audio-ogg', 'audio-x-vorbis+ogg', 'audio-x-opus+ogg', 'audio-mp4', 'audio-aac', 'audio-x-m4a']],
        ['video-mp4', 'video', 'grape', ['video-x-matroska', 'video-webm', 'video-quicktime', 'video-x-msvideo', 'video-mpeg', 'video-ogg']],
        ['text-plain', 'text', 'blossom', ['application-x-subrip', 'text-vtt', 'text-x-readme', 'text-x-changelog', 'text-x-copying', 'text-x-log']],
        ['message-rfc822', 'mail-file', 'lagoon', ['application-mbox']],
        ['text-vcard', 'contact', 'coral', ['text-x-vcard']],
        ['application-x-shellscript', 'script', 'mint', ['text-x-makefile', 'text-x-cmake', 'text-x-meson']],
        ['text-x-csrc', 'label-C', 'ocean', ['text-x-c']],
        ['text-x-chdr', 'label-H', 'ice'],
        ['text-x-c++src', 'label-C++', 'royal', ['text-x-c++hdr']],
        ['text-x-csharp', 'label-C#', 'grape'],
        ['text-x-go', 'label-GO', 'aqua'],
        ['text-rust', 'label-RS', 'coral', ['text-x-rust']],
        ['text-x-python', 'label-PY', 'amber', ['text-x-python3', 'application-x-python-bytecode']],
        ['application-javascript', 'label-JS', 'gold', ['text-javascript', 'application-x-javascript']],
        ['application-x-typescript', 'label-TS', 'lagoon', ['text-x-typescript']],
        ['text-css', 'label-CSS', 'sky'],
        ['application-x-php', 'label-PHP', 'indigo', ['text-x-php']],
        ['application-x-ruby', 'label-RB', 'cherry', ['text-x-ruby']],
        ['text-x-lua', 'label-LUA', 'royal'],
        ['text-x-kotlin', 'label-KT', 'dusk'],
        ['text-x-java', 'label-JAVA', 'sunset'],
        ['application-sql', 'label-SQL', 'emerald', ['text-x-sql']],
        ['text-markdown', 'label-MD', 'ice', ['text-x-markdown']],
        ['application-x-yaml', 'label-YML', 'lime', ['application-yaml', 'text-x-yaml']],
        ['application-toml', 'label-TOML', 'peach', ['text-x-toml']],
        ['application-xml', 'label-XML', 'flame', ['text-xml']],
        ['text-x-tex', 'label-TEX', 'mint'],
        ['text-x-haskell', 'label-HS', 'orchid'],
        ['application-x-perl', 'label-PL', 'blossom', ['text-x-perl']],
        ['text-csv', 'label-CSV', 'emerald'],
        ['application-octet-stream', 'label-01', 'indigo'],
        ['application-json', 'json', 'lime', ['application-x-ipynb+json', 'application-schema+json']],
        ['text-x-patch', 'diff', 'coral', ['text-x-diff']],
        ['application-x-sqlite3', 'database', 'emerald', ['application-vnd.sqlite3', 'application-x-sqlite2']],
        ['application-x-trash', 'trash', 'ice'],
    ],
    devices: [
        ['computer', 'computer', 'ocean', ['video-display']],
        ['computer-laptop', 'laptop', 'royal'],
        ['phone', 'phone', 'grape', ['smartphone']],
        ['drive-harddisk', 'drive', 'indigo', ['drive-harddisk-system', 'drive-multidisk']],
        ['drive-removable-media', 'usb', 'gold', ['drive-harddisk-usb', 'media-removable']],
        ['media-flash', 'card', 'amber'],
        ['media-optical', 'disc', 'ice', ['drive-optical']],
        ['camera-photo', 'camera', 'indigo'],
        ['camera-web', 'webcam', 'lagoon'],
        ['printer', 'printer', 'coral'],
        ['scanner', 'scanner', 'ice'],
        ['input-keyboard', 'keyboard', 'dusk'],
        ['input-mouse', 'mouse', 'sky'],
        ['input-gaming', 'gamepad', 'flame'],
        ['input-tablet', 'tablet', 'orchid'],
        ['audio-headphones', 'headphones', 'magenta', ['audio-headset']],
        ['audio-speakers', 'speaker', 'sunset', ['audio-card']],
        ['audio-input-microphone', 'microphone', 'cherry'],
        ['network-wired', 'plug', 'mint'],
        ['network-wireless', 'wifi', 'lagoon'],
        ['battery', 'battery', 'lime', ['uninterruptible-power-supply']],
        ['input-touchpad', 'touchpad', 'sky'],
        ['media-floppy', 'floppy', 'indigo'],
        ['multimedia-player', 'player', 'magenta'],
        ['camera-video', 'webcam', 'lagoon'],
        ['printer-network', 'printer', 'coral'],
    ],
    status: [
        ['dialog-information', 'info', 'sky'],
        ['dialog-warning', 'warning', 'amber'],
        ['dialog-error', 'error', 'cherry'],
        ['dialog-question', 'question', 'royal'],
        ['dialog-password', 'key', 'gold'],
        ['security-medium', 'shield-alert', 'amber'],
        ['security-low', 'shield-alert', 'cherry'],
    ],
    categories: [
        ['applications-system', 'settings', 'ocean'],
        ['applications-utilities', 'wrench', 'lime', ['applications-accessories']],
        ['applications-multimedia', 'play', 'grape'],
        ['applications-graphics', 'palette', 'blossom'],
        ['applications-internet', 'globe', 'lagoon'],
        ['applications-office', 'document', 'ocean'],
        ['applications-development', 'code', 'royal'],
        ['applications-games', 'gamepad', 'flame'],
        ['applications-science', 'flask', 'aqua'],
        ['applications-education', 'cap', 'peach'],
        ['applications-other', 'app', 'royal'],
        ['applications-fonts', 'letter', 'dusk'],
    ],
};

// Apps whose icon is their maker's mark (a logo, a mascot, a letter of theirs) keep the one they ship: redrawn in the
// packs' style it would be a changed trademark, and drawn as a pictogram it would no longer say whose app it is. The
// packs refuse to draw any of these names
const LOGOS = /^(firefox|org\.mozilla\..*|thunderbird|waydroid|io\.podman_desktop\..*|steam|com\.valvesoftware\..*|codium|vscodium|com\.vscodium\..*|code|com\.visualstudio\..*|google-chrome|com\.google\..*|chromium.*|org\.chromium\..*|brave.*|com\.brave\..*|com\.microsoft\..*|discord|com\.discordapp\..*|spotify.*|com\.spotify\..*|telegram.*|org\.telegram\..*|signal.*|org\.signal\..*|com\.slack\..*|us\.zoom\..*|libreoffice.*|org\.libreoffice\..*|vlc|org\.videolan\..*|obs|com\.obsproject\..*|blender|org\.blender\..*|gimp|org\.gimp\..*|inkscape|org\.inkscape\..*|krita|org\.kde\.krita|kdenlive|org\.kde\.kdenlive|kate|org\.kde\.kate|audacity|org\.audacityteam\..*|net\.lutris\..*|com\.heroicgameslauncher\..*|kitty|alacritty|org\.wezfurlong\..*|com\.mitchellh\..*|org\.qbittorrent\..*|org\.mozilla|com\.jetbrains\..*|jetbrains-.*|net\.opentabletdriver\..*|solaar|org\.fedoraproject\..*|fedora.*)$/i;

const CONTEXTS = {apps: 'Applications', places: 'Places', mimetypes: 'MimeTypes', devices: 'Devices', status: 'Status', categories: 'Categories'};

const mixWhite = (hex, s) => '#' + [1, 3, 5].map(i => Math.round(parseInt(hex.slice(i, i + 2), 16) * (1 - s) + 255 * s)
    .toString(16).padStart(2, '0')).join('');
const gradient = (id, colours) => `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1">${
    colours.map((c, i) => `<stop offset="${i / (colours.length - 1)}" stop-color="${c}"/>`).join('')}</linearGradient>`;
const shadow = (id, colour, opacity, dy, blur) => `<filter id="${id}" x="-25%" y="-25%" width="150%" height="150%">` +
    `<feDropShadow dx="0" dy="${dy}" stdDeviation="${blur}" flood-color="${colour}" flood-opacity="${opacity}"/></filter>`;
const svg = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 256 256"><defs>${defs}</defs>${body}</svg>\n`;

const PACKS = {
    glass: {
        name: 'Amethystora Glass',
        comment: 'Amethystora\'s own icons, each in its own gradient with a glass sheen',
        draw: (glyph, [fill]) => {
            const soft = fill.map(c => mixWhite(c, 0.55));
            return svg(gradient('g', fill) + gradient('h', soft) +
                '<linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="0.55" stop-color="#fff" stop-opacity="0"/></linearGradient>' +
                `<mask id="m">${glyph({ink: '#fff', soft: '#fff'})}</mask>` + shadow('f', '#1a0b2e', 0.55, 10, 9),
            `<g filter="url(#f)">${glyph({ink: 'url(#g)', soft: 'url(#h)'})}</g>` +
                '<rect width="256" height="150" fill="url(#s)" fill-opacity="0.55" mask="url(#m)"/>');
        },
    },
    neon: {
        name: 'Amethystora Neon',
        comment: 'Amethystora\'s own icons, their outlines lit in colours of their own',
        draw: (glyph, [, prism, detail]) => {
            // What the glyph draws in its third ink, `over` (glyphs/glyphs.mjs): the shapes in the body's ink on top of a
            // soft one, which the soft layer would paint over. They are lit last, in the details' colour
            const lit = glyph({ink: 'none', soft: 'none', over: 'url(#d)'}), over = lit.includes('url(#d)') ? lit : '';
            return svg(gradient('g', prism) + (over ? gradient('d', detail) : '') +
            // The body's outline: its alpha eroded and taken from it leaves a ring, blurred twice under itself
            '<filter id="n" x="-25%" y="-25%" width="150%" height="150%"><feMorphology in="SourceAlpha" operator="erode" radius="6" result="inner"/>' +
            '<feComposite in="SourceGraphic" in2="inner" operator="out" result="ring"/><feGaussianBlur in="ring" stdDeviation="5" result="glow"/>' +
            '<feMerge><feMergeNode in="glow"/><feMergeNode in="glow"/><feMergeNode in="ring"/></feMerge></filter>' +
            '<filter id="l" x="-25%" y="-25%" width="150%" height="150%"><feGaussianBlur stdDeviation="4" result="glow"/>' +
            '<feMerge><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        `<g filter="url(#n)">${glyph({ink: 'url(#g)', soft: 'none', over: 'none'})}</g><g filter="url(#l)">${glyph({ink: 'none', soft: 'url(#g)', over: 'none'})}</g>` +
            (over && `<g filter="url(#l)">${over}</g>`));
        },
    },
    duotone: {
        name: 'Amethystora Duotone',
        comment: 'Amethystora\'s own icons, each in its own gradient with its details in a contrasting one',
        draw: (glyph, [fill, , contrast]) => svg(gradient('g', fill) + gradient('h', contrast) + shadow('f', fill[1], 0.45, 6, 7),
            `<g filter="url(#f)">${glyph({ink: 'url(#g)', soft: 'url(#h)'})}</g>`),
    },
};

function indexTheme(pack) {
    const dirs = Object.keys(SET).map(context => `${context}/scalable`);
    return `[Icon Theme]\nName=${pack.name}\nComment=${pack.comment}\nInherits=Adwaita,hicolor\nExample=folder\n` +
        `Directories=${dirs.join(',')}\n` + Object.entries(CONTEXTS).map(([dir, context]) =>
        `\n[${dir}/scalable]\nContext=${context}\nSize=128\nMinSize=8\nMaxSize=512\nType=Scalable\n`).join('');
}

// A name is drawn once, and never one of a maker's mark
const names = Object.values(SET).flat().flatMap(([name, , , also = []]) => [name, ...also]);
for (const name of names) {
    if (LOGOS.test(name))
        throw new Error(`${name}: its icon is its maker's mark, which the packs leave as it ships`);
    if (names.indexOf(name) !== names.lastIndexOf(name))
        throw new Error(`${name}: drawn twice`);
}

// Each name an icon answers to is a file of its own rather than a link, since the image build's rsync of
// system_files leaves links out
for (const [id, pack] of Object.entries(PACKS)) {
    const dir = join(ICONS, `amethystora-${id}`);
    rmSync(dir, {recursive: true, force: true});
    for (const [context, icons] of Object.entries(SET)) {
        mkdirSync(join(dir, context, 'scalable'), {recursive: true});
        for (const [name, glyph, ramp, also = []] of icons) {
            if (!DRAW[glyph] || !RAMPS[ramp])
                throw new Error(`${name}: no glyph ${glyph} or ramp ${ramp}`);
            const file = pack.draw(DRAW[glyph], RAMPS[ramp]);
            for (const each of [name, ...also])
                writeFileSync(join(dir, context, 'scalable', `${each}.svg`), file);
        }
    }
    writeFileSync(join(dir, 'index.theme'), indexTheme(pack));
    console.log(`wrote ${dir}`);
}

// The two launchers of Amethystora's own that have no artwork of theirs in hicolor (branding/generate.mjs draws
// the others), in the Glass style: every icon theme falls back on hicolor, and the Security app draws its shield
// from this file as it runs
for (const [name, glyph, ramp] of SET.apps.filter(([name]) => ['amethystora-security-status', 'amethystora-notes'].includes(name))) {
    mkdirSync(join(ICONS, 'hicolor/scalable/apps'), {recursive: true});
    writeFileSync(join(ICONS, 'hicolor/scalable/apps', `${name}.svg`), PACKS.glass.draw(DRAW[glyph], RAMPS[ramp]));
}

if (process.argv.includes('--preview')) {
    const out = join(tmpdir(), 'amethystora-icons');
    mkdirSync(out, {recursive: true});
    const all = Object.values(SET).flat();
    const rows = (id, size) => all.map(([name, glyph, ramp]) =>
        `<img title="${name}" width="${size}" height="${size}" src="data:image/svg+xml;base64,${Buffer.from(PACKS[id].draw(DRAW[glyph], RAMPS[ramp])).toString('base64')}">`).join('');
    const ground = (bg, ink) => Object.keys(PACKS).map(id =>
        `<section style="background:${bg};color:${ink};padding:18px 24px"><h2 style="margin:0 0 10px;font:600 18px sans-serif">${PACKS[id].name}</h2>` +
        `<div style="display:flex;flex-wrap:wrap;gap:10px">${rows(id, 64)}</div>` +
        `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:12px">${rows(id, 24)}</div></section>`).join('');
    writeFileSync(join(out, 'sheet.html'), `<!doctype html><meta charset="utf-8"><body style="margin:0;width:1500px">` +
        ground('radial-gradient(ellipse at 20% 0%, #3a1470 0%, #16042c 55%, #0b0418 100%)', '#e8e0f2') +
        ground('linear-gradient(180deg,#fdf8ff,#e9e1f5)', '#3d3450') + '</body>');
    console.log(join(out, 'sheet.html'));
}
