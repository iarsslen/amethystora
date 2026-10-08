'use strict';

// The little the page may ask of the main process: see main.js for what each one does
const { contextBridge, ipcRenderer, webFrame, webUtils } = require('electron');

contextBridge.exposeInMainWorld('security', {
    // The session's language and its catalog (i18n.js), there before the page's scripts run
    locale: ipcRenderer.sendSync('locale'),
    report: () => ipcRenderer.invoke('report'),
    scanner: () => ipcRenderer.invoke('scanner'),
    history: () => ipcRenderer.invoke('history'),
    palette: () => ipcRenderer.invoke('palette'),
    scanHome: () => ipcRenderer.invoke('scan-home'),
    scanPick: (folders) => ipcRenderer.invoke('scan-pick', Boolean(folders)),
    // A dropped file's path is only known here, not to the page
    scanFiles: (files) => ipcRenderer.invoke('scan-paths', files.map((file) => webUtils.getPathForFile(file))),
    scanAgain: (id) => ipcRenderer.invoke('scan-again', String(id)),
    scanMachine: () => ipcRenderer.invoke('scan-machine'),
    network: () => ipcRenderer.invoke('network'),
    allowRule: (rule) => ipcRenderer.invoke('network-allow', String(rule)),
    inventory: () => ipcRenderer.invoke('inventory'),
    permissions: () => ipcRenderer.invoke('permissions'),
    resetPermissions: (id) => ipcRenderer.invoke('permissions-reset', String(id)),
    flatseal: () => ipcRenderer.invoke('flatseal'),
    upgradeContainers: () => ipcRenderer.invoke('containers-upgrade'),
    stop: () => ipcRenderer.invoke('scan-stop'),
    dismiss: (id) => ipcRenderer.invoke('dismiss', String(id)),
    run: (id) => ipcRenderer.invoke('run', String(id)),
    diagnose: (id) => ipcRenderer.invoke('diagnose', String(id)),
    accept: (id, again) => ipcRenderer.invoke('accept', String(id), Boolean(again)),
    // Every switch, and a change to one, which opens its command in a terminal
    switches: () => ipcRenderer.invoke('switches'),
    change: (kind, key, value, argument) => ipcRenderer.invoke('change', String(kind), String(key), String(value ?? ''), argument ? String(argument) : ''),
    showInFiles: (file) => ipcRenderer.invoke('show-in-files', String(file)),
    copy: (text) => ipcRenderer.invoke('copy', text),
    manual: (page) => ipcRenderer.invoke('manual', String(page)),
    zoom: (step) => webFrame.setZoomLevel(step === 0 ? 0 : webFrame.getZoomLevel() + step),
    onPalette: (callback) => ipcRenderer.on('palette', (_event, colors) => callback(colors)),
    onProgress: (callback) => ipcRenderer.on('scan-progress', (_event, progress) => callback(progress)),
    onFinished: (callback) => ipcRenderer.on('scan-finished', (_event, entry) => callback(entry)),
    onOpen: (callback) => ipcRenderer.on('open', (_event, page) => callback(page)),
    onFocus: (callback) => ipcRenderer.on('focus', () => callback()),
});
