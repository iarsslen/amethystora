'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame } = require('electron');

contextBridge.exposeInMainWorld('logs', {
    // The session's language and its catalog (i18n.js), there before the page's scripts run
    locale: ipcRenderer.sendSync('locale'),
    overview: () => ipcRenderer.invoke('overview'),
    sources: () => ipcRenderer.invoke('sources'),
    query: (request) => ipcRenderer.invoke('query', request),
    follow: (request) => ipcRenderer.invoke('follow', request),
    stopFollowing: () => ipcRenderer.invoke('stop-following'),
    exportLogs: (request) => ipcRenderer.invoke('export', request),
    terminal: (request, live) => ipcRenderer.invoke('terminal', request, Boolean(live)),
    agent: () => ipcRenderer.invoke('agent'),
    diagnose: (target) => ipcRenderer.invoke('diagnose', target),
    palette: () => ipcRenderer.invoke('palette'),
    copy: (text) => ipcRenderer.invoke('copy', String(text)),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onLive: (callback) => ipcRenderer.on('live', (_event, entries) => callback(entries)),
    onLiveEnded: (callback) => ipcRenderer.on('live-ended', () => callback()),
    onOpen: (callback) => ipcRenderer.on('open', (_event, view) => callback(view)),
    onFocus: (callback) => ipcRenderer.on('focus', () => callback()),
});
