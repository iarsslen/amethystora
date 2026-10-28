#!/usr/bin/python3
# A stand-in for UPower on the system bus, for the quick settings suite (19-quick-settings.sh): one laptop battery that
# can keep its charge at 80%, and the display device GNOME reads. EnableChargeThreshold is written to
# /run/upower-standin.log and changes the property, as UPower does. A lab file: it never goes into the image.
# SIGUSR1 plugs the power in (the battery charging) and SIGUSR2 takes it out again, for the sound suite (23).
#
#   upower-standin.py [--unsupported] [--refuse]
#       --unsupported: the battery has no charge limit; --refuse: it has one, and setting it fails
import signal
import sys

from gi.repository import Gio, GLib

LOG = '/run/upower-standin.log'
BATTERY = '/org/freedesktop/UPower/devices/battery_BAT0'
DISPLAY = '/org/freedesktop/UPower/devices/DisplayDevice'
XML = '''<node>
  <interface name="org.freedesktop.UPower">
    <method name="EnumerateDevices"><arg name="devices" type="ao" direction="out"/></method>
    <method name="GetDisplayDevice"><arg name="device" type="o" direction="out"/></method>
    <method name="GetCriticalAction"><arg name="action" type="s" direction="out"/></method>
    <property name="DaemonVersion" type="s" access="read"/>
    <property name="OnBattery" type="b" access="read"/>
    <property name="LidIsClosed" type="b" access="read"/>
    <property name="LidIsPresent" type="b" access="read"/>
  </interface>
  <interface name="org.freedesktop.UPower.Device">
    <method name="EnableChargeThreshold"><arg name="charge_threshold" type="b" direction="in"/></method>
    <method name="Refresh"/>
    <property name="NativePath" type="s" access="read"/>
    <property name="Type" type="u" access="read"/>
    <property name="PowerSupply" type="b" access="read"/>
    <property name="IsPresent" type="b" access="read"/>
    <property name="Online" type="b" access="read"/>
    <property name="Percentage" type="d" access="read"/>
    <property name="State" type="u" access="read"/>
    <property name="TimeToEmpty" type="x" access="read"/>
    <property name="TimeToFull" type="x" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="WarningLevel" type="u" access="read"/>
    <property name="BatteryLevel" type="u" access="read"/>
    <property name="ChargeThresholdSupported" type="b" access="read"/>
    <property name="ChargeStartThreshold" type="u" access="read"/>
    <property name="ChargeEndThreshold" type="u" access="read"/>
    <property name="ChargeThresholdEnabled" type="b" access="read"/>
    <property name="ChargeThresholdSettingsSupported" type="u" access="read"/>
  </interface>
</node>'''
NODE = Gio.DBusNodeInfo.new_for_xml(XML)
MANAGER, DEVICE = NODE.interfaces

supported = '--unsupported' not in sys.argv[1:]
refuse = '--refuse' in sys.argv[1:]
battery = {
    'NativePath': GLib.Variant('s', 'BAT0'), 'Type': GLib.Variant('u', 2), 'PowerSupply': GLib.Variant('b', True),
    'IsPresent': GLib.Variant('b', True), 'Online': GLib.Variant('b', False), 'Percentage': GLib.Variant('d', 86.0),
    'State': GLib.Variant('u', 2), 'TimeToEmpty': GLib.Variant('x', 15000), 'TimeToFull': GLib.Variant('x', 0),
    'IconName': GLib.Variant('s', 'battery-full-symbolic'), 'WarningLevel': GLib.Variant('u', 1),
    'BatteryLevel': GLib.Variant('u', 1), 'ChargeThresholdSupported': GLib.Variant('b', supported),
    'ChargeStartThreshold': GLib.Variant('u', 75), 'ChargeEndThreshold': GLib.Variant('u', 80),
    'ChargeThresholdEnabled': GLib.Variant('b', False), 'ChargeThresholdSettingsSupported': GLib.Variant('u', 3),
}
display = dict(battery, NativePath=GLib.Variant('s', ''), Type=GLib.Variant('u', 2))
manager = {'DaemonVersion': GLib.Variant('s', '1.91.5'), 'OnBattery': GLib.Variant('b', True),
           'LidIsClosed': GLib.Variant('b', False), 'LidIsPresent': GLib.Variant('b', True)}
devices = {BATTERY: battery, DISPLAY: display}
bus = None


def changed(path, props):
    bus.emit_signal(None, path, 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                    GLib.Variant('(sa{sv}as)', ('org.freedesktop.UPower.Device', props, [])))


def device_call(connection, sender, path, interface, method, params, invocation):
    if method == 'EnableChargeThreshold':
        (want,) = params.unpack()
        with open(LOG, 'a') as log:
            log.write(f'EnableChargeThreshold {"true" if want else "false"}\n')
        if not supported or refuse:
            invocation.return_dbus_error('org.freedesktop.UPower.GeneralError', 'not supported')
            return
        for each in (BATTERY, DISPLAY):
            devices[each]['ChargeThresholdEnabled'] = GLib.Variant('b', want)
            changed(each, {'ChargeThresholdEnabled': GLib.Variant('b', want)})
    invocation.return_value(None)


def manager_call(connection, sender, path, interface, method, params, invocation):
    if method == 'EnumerateDevices':
        invocation.return_value(GLib.Variant('(ao)', ([BATTERY],)))
    elif method == 'GetDisplayDevice':
        invocation.return_value(GLib.Variant('(o)', (DISPLAY,)))
    else:
        invocation.return_value(GLib.Variant('(s)', ('PowerOff',)))


def acquired(connection, name):
    global bus
    bus = connection
    connection.register_object('/org/freedesktop/UPower', MANAGER, manager_call,
                               lambda c, s, p, i, prop: manager[prop], None)
    for path in devices:
        connection.register_object(path, DEVICE, device_call,
                                   lambda c, s, p, i, prop: devices[p][prop], None)


def plug(state):
    """1 charging (plugged in), 2 discharging (on the battery), as UPower says it"""
    for each in (BATTERY, DISPLAY):
        devices[each]['State'] = GLib.Variant('u', state)
        devices[each]['Online'] = GLib.Variant('b', state == 1)
        if bus:
            changed(each, {'State': GLib.Variant('u', state)})
    manager['OnBattery'] = GLib.Variant('b', state != 1)
    if bus:
        bus.emit_signal(None, '/org/freedesktop/UPower', 'org.freedesktop.DBus.Properties', 'PropertiesChanged',
                        GLib.Variant('(sa{sv}as)', ('org.freedesktop.UPower', {'OnBattery': manager['OnBattery']}, [])))
    return GLib.SOURCE_CONTINUE


GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, lambda: plug(1))
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, lambda: plug(2))
Gio.bus_own_name(Gio.BusType.SYSTEM, 'org.freedesktop.UPower', Gio.BusNameOwnerFlags.REPLACE, acquired, None,
                 lambda c, n: sys.exit(1))
GLib.MainLoop().run()
