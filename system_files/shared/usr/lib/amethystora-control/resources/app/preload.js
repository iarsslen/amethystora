'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('control', {
    // The session's language and its catalog (i18n.js), there before the page's scripts run
    locale: ipcRenderer.sendSync('locale'),
    list: () => ipcRenderer.invoke('list'),
    change: (id, value) => ipcRenderer.invoke('change', String(id), String(value)),
    act: (id) => ipcRenderer.invoke('act', String(id)),
    widget: (action, widget) => ipcRenderer.invoke('widget', String(action), String(widget ?? '')),
    newWidget: (id, example) => ipcRenderer.invoke('new-widget', String(id), String(example)),
    webapp: (action, name) => ipcRenderer.invoke('webapp', String(action), String(name ?? '')),
    pool: (action, id) => ipcRenderer.invoke('pool', String(action), String(id)),
    chooseKey: () => ipcRenderer.invoke('choose-key'),
    trustImage: (repository) => ipcRenderer.invoke('trust-image', String(repository)),
    setup: (action) => ipcRenderer.invoke('setup', String(action)),
    setupDiff: () => ipcRenderer.invoke('setup-diff'),
    open: (link) => ipcRenderer.invoke('open', String(link)),
    palette: () => ipcRenderer.invoke('palette'),
    copy: (text) => ipcRenderer.invoke('copy', String(text)),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onOpen: (callback) => ipcRenderer.on('open', (_event, page) => callback(page)),
    onFocus: (callback) => ipcRenderer.on('focus', () => callback()),
});
