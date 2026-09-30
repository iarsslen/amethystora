'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('updates', {
    status: () => ipcRenderer.invoke('status'),
    palette: () => ipcRenderer.invoke('palette'),
    update: () => ipcRenderer.invoke('update'),
    automatic: (on) => ipcRenderer.invoke('automatic', Boolean(on)),
    restart: () => ipcRenderer.invoke('restart'),
    releases: () => ipcRenderer.invoke('releases'),
    copy: (text) => ipcRenderer.invoke('copy', String(text)),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onUpdate: (callback) => ipcRenderer.on('update', (_event, update) => callback(update)),
    onStatus: (callback) => ipcRenderer.on('status', (_event, status) => callback(status)),
    onFocus: (callback) => ipcRenderer.on('focus', () => callback()),
});
