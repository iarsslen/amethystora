'use strict';

// The little the page may ask of the main process: see main.js for what each one reads
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('manual', {
    toc: () => ipcRenderer.invoke('toc'),
    page: (file) => ipcRenderer.invoke('page', file),
    palette: () => ipcRenderer.invoke('palette'),
    openExternal: (url) => ipcRenderer.invoke('open-external', url),
    copy: (text) => ipcRenderer.invoke('copy', text),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onOpen: (callback) => ipcRenderer.on('open', (_event, page) => callback(page)),
});
