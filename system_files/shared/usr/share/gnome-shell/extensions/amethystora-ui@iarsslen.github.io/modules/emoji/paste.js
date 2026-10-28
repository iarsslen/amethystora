// Putting text where the person was typing, once the emoji picker or the search box has given the keyboard back: typed
// straight in through the input method, as GNOME's own on-screen keyboard types an emoji, when the window takes text
// from it; otherwise put on the clipboard and pasted with Shift+Insert, or Ctrl+Shift+V in a terminal. Insert is on
// every keyboard layout, where a V may not be (Mutter finds a key only in the layout in use). The text goes only to
// the window that had the focus when the picker or the box opened, and only if it still has it; otherwise it is left
// on the clipboard. Nothing runs while nothing is being pasted: the wait below lives a second at most.

import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// How long the window has to take the keyboard back, and how often that is looked at meanwhile
const GIVE_UP = 1000;
const LOOK = 20;
// Once it has: time for the window to turn its text input on again
const SETTLE = 60;
// The virtual keyboard is let go once its keys are up
const DISPOSE = 100;

const PENDING = new Set();

// Every wait still running stops (the module that started it stops)
export function cancelPastes() {
    for (const cancel of [...PENDING])
        cancel();
}

function onClipboard(text) {
    if (text)
        St.Clipboard.get_default().set_text(St.ClipboardType.CLIPBOARD, text);
}

function isTerminal(window) {
    if (Main.inputMethod.content_purpose === Clutter.InputContentPurpose.TERMINAL)
        return true;
    const app = window ? Shell.WindowTracker.get_default().get_window_app(window) : null;
    return (app?.get_app_info()?.get_categories() ?? '').split(';').includes('TerminalEmulator');
}

function press(keys) {
    const seat = global.stage.context.get_backend().get_default_seat();
    const device = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
    let time = GLib.get_monotonic_time();
    for (const key of keys)
        device.notify_keyval(time++, key, Clutter.KeyState.PRESSED);
    for (const key of [...keys].reverse())
        device.notify_keyval(time++, key, Clutter.KeyState.RELEASED);
    GLib.timeout_add_once(GLib.PRIORITY_DEFAULT, DISPOSE, () => device.run_dispose());
}

// {text, keysOnly, window}: keysOnly when the clipboard already holds what is to be pasted (a picture, say)
export function paste({text = null, keysOnly = false, window = null}) {
    const started = GLib.get_monotonic_time();
    let source = 0;
    const stop = () => {
        if (source)
            GLib.source_remove(source);
        source = 0;
        PENDING.delete(stop);
    };
    PENDING.add(stop);

    const deliver = () => {
        source = 0;
        stop();
        // The person went to another window meanwhile, or the shell took the keyboard again (the overview, a menu):
        // the text waits on the clipboard
        if (!ready() || !window || !window.get_compositor_private() || global.display.focus_window !== window) {
            onClipboard(text);
            return;
        }
        if (text && !keysOnly && Main.inputMethod.currentFocus &&
            Main.inputMethod.content_purpose !== Clutter.InputContentPurpose.TERMINAL) {
            Main.inputMethod.commit(text);
            return;
        }
        onClipboard(text);
        press(isTerminal(window)
            ? [Clutter.KEY_Control_L, Clutter.KEY_Shift_L, Clutter.KEY_v]
            : [Clutter.KEY_Shift_L, Clutter.KEY_Insert]);
    };

    const ready = () => Main.modalCount === 0 && !global.stage.key_focus;
    const look = () => {
        source = 0;
        if (ready()) {
            // A frame, then the window's text input back on
            const laters = global.compositor.get_laters();
            laters.add(Meta.LaterType.BEFORE_REDRAW, () => {
                if (PENDING.has(stop))
                    source = GLib.timeout_add_once(GLib.PRIORITY_DEFAULT, SETTLE, deliver);
                return GLib.SOURCE_REMOVE;
            });
            return;
        }
        if (GLib.get_monotonic_time() - started > GIVE_UP * 1000) {
            stop();
            onClipboard(text);
            return;
        }
        source = GLib.timeout_add_once(GLib.PRIORITY_DEFAULT, LOOK, look);
    };
    look();
}
