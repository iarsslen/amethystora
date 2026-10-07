'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('backups', {
    // The session's language and its catalog (i18n.js), there before the page's scripts run
    locale: ipcRenderer.sendSync('locale'),
    start: () => ipcRenderer.invoke('start'),
    status: () => ipcRenderer.invoke('status'),
    points: () => ipcRenderer.invoke('points'),
    ls: (id, folder) => ipcRenderer.invoke('ls', String(id), String(folder)),
    versions: (file) => ipcRenderer.invoke('versions', String(file)),
    putBack: (id, files, mode) => ipcRenderer.invoke('put-back', String(id), [...files].map(String), String(mode)),
    look: (id, file) => ipcRenderer.invoke('look', String(id), String(file)),
    backupNow: () => ipcRenderer.invoke('backup-now'),
    lastLines: () => ipcRenderer.invoke('last-lines'),
    setUp: () => ipcRenderer.invoke('set-up'),
    daily: (on) => ipcRenderer.invoke('daily', Boolean(on)),
    security: () => ipcRenderer.invoke('security'),
    diagnose: () => ipcRenderer.invoke('diagnose'),
    palette: () => ipcRenderer.invoke('palette'),
    copy: (text) => ipcRenderer.invoke('copy', String(text)),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onOpen: (callback) => ipcRenderer.on('open', (_event, where) => callback(where)),
    onFocus: (callback) => ipcRenderer.on('focus', () => callback()),
    onBackupLine: (callback) => ipcRenderer.on('backup-line', (_event, line) => callback(line)),
    onBackupDone: (callback) => ipcRenderer.on('backup-done', (_event, result) => callback(result)),
});
