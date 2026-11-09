import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Start-with-Windows and connect-on-launch.
///
/// The app manifest asks for administrator rights, so a Run-key entry would
/// raise a UAC prompt at every logon. A Task Scheduler task with the highest
/// run level starts it elevated without one. The task passes `--autostart`,
/// which keeps the window hidden in the tray (see windows/runner).
class AutostartService {
  static const taskName = 'FixTrusty';
  static const autostartArg = '--autostart';
  static const _autoConnectKey = 'auto_connect';

  static bool get isSupported => Platform.isWindows;

  /// Whether the logon task exists.
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final r = await Process.run('schtasks', ['/Query', '/TN', taskName]);
      return r.exitCode == 0;
    } catch (e) {
      debugPrint('schtasks query failed: $e');
      return false;
    }
  }

  /// Create (or replace) the logon task, or delete it. Throws on failure.
  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    if (!enabled) {
      final r = await Process.run('schtasks', ['/Delete', '/F', '/TN', taskName]);
      // Exit 1 with nothing to delete is fine.
      if (r.exitCode != 0 && await isEnabled()) {
        throw Exception('Could not remove the startup task: ${r.stderr}'.trim());
      }
      return;
    }

    final xmlFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}fixtrusty_task.xml',
    );
    await xmlFile.writeAsBytes(_utf16le(_taskXml()));
    try {
      final r = await Process.run('schtasks', [
        '/Create',
        '/F',
        '/TN',
        taskName,
        '/XML',
        xmlFile.path,
      ]);
      if (r.exitCode != 0) {
        throw Exception(
          'Could not create the startup task: ${r.stderr}${r.stdout}'.trim(),
        );
      }
    } finally {
      try {
        await xmlFile.delete();
      } catch (_) {}
    }
  }

  /// Re-register the task when the app was moved, so it never points at a
  /// stale path. No-op when autostart is off.
  static Future<void> refreshIfEnabled() async {
    if (await isEnabled()) {
      try {
        await setEnabled(true);
      } catch (e) {
        debugPrint('Autostart refresh failed: $e');
      }
    }
  }

  static Future<bool> isAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoConnectKey) ?? false;
  }

  static Future<void> setAutoConnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoConnectKey, value);
  }

  static String _taskXml() {
    final exe = Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    final user = '${Platform.environment['USERDOMAIN'] ?? ''}\\'
        '${Platform.environment['USERNAME'] ?? ''}';
    // ExecutionTimeLimit PT0S: the default would kill the app after 72h.
    // Battery flags off: on a laptop the default refuses to start unplugged.
    return '''<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Start FixTrusty VPN at logon</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>${_xml(user)}</UserId>
      <Delay>PT10S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>${_xml(user)}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>${_xml(exe)}</Command>
      <Arguments>$autostartArg</Arguments>
      <WorkingDirectory>${_xml(dir)}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
''';
  }

  static String _xml(String s) => const HtmlEscape(HtmlEscapeMode.element)
      .convert(s);

  /// schtasks wants the XML in UTF-16 with a BOM.
  static Uint8List _utf16le(String s) {
    final units = s.codeUnits;
    final out = Uint8List(2 + units.length * 2);
    out[0] = 0xFF;
    out[1] = 0xFE;
    for (var i = 0; i < units.length; i++) {
      out[2 + i * 2] = units[i] & 0xFF;
      out[3 + i * 2] = units[i] >> 8;
    }
    return out;
  }
}
