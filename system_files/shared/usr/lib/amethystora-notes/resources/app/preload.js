'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('notes', {
    palette: () => ipcRenderer.invoke('palette'),
    state: () => ipcRenderer.invoke('state'),
    create: (passphrase) => ipcRenderer.invoke('create', passphrase ? String(passphrase) : null),
    unlock: (passphrase) => ipcRenderer.invoke('unlock', String(passphrase)),
    lock: () => ipcRenderer.invoke('lock'),
    encryption: (change) => ipcRenderer.invoke('encryption', change),
    put: (kind, items) => ipcRenderer.invoke('put', String(kind), items),
    drop: (kind, ids) => ipcRenderer.invoke('drop', String(kind), ids),
    settings: (values) => ipcRenderer.invoke('settings', values),
    attach: () => ipcRenderer.invoke('attach'),
    attachData: (name, mime, data) => ipcRenderer.invoke('attach-data', String(name), String(mime), data),
    saveResource: (id) => ipcRenderer.invoke('save-resource', String(id)),
    exportMarkdown: () => ipcRenderer.invoke('export'),
    backup: () => ipcRenderer.invoke('backup'),
    import: () => ipcRenderer.invoke('import'),
    importBackup: (passphrase) => ipcRenderer.invoke('import-backup', String(passphrase)),
    pdf: (title) => ipcRenderer.invoke('pdf', String(title)),
    openExternal: (url) => ipcRenderer.invoke('open-external', String(url)),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    active: () => ipcRenderer.send('active'),
    flushed: () => ipcRenderer.send('flushed'),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onLocked: (callback) => ipcRenderer.on('locked', () => callback()),
    onFlush: (callback) => ipcRenderer.on('flush', () => callback()),
    onOpen: (callback) => ipcRenderer.on('open', (_event, page) => callback(page)),
    onTask: (callback) => ipcRenderer.on('task', (_event, id) => callback(id)),
    onProblem: (callback) => ipcRenderer.on('problem', (_event, text) => callback(text)),
});
