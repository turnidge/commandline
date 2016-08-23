// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show UTF8;
import 'dart:io';

String _tputGetSequence(String capName, { String orElse }) {
  if (Terminal._testMode)
    return '[$capName]';

  if (Platform.isWindows)
    return orElse;

  ProcessResult result =
      Process.runSync('tput',  <String>['$capName'], stdoutEncoding:UTF8);
  if (result.exitCode != 0)
    return orElse;

  return result.stdout;
}

class Terminal {
  Terminal();

  // Used during development to see all special characters in output.
  static final bool _testMode = false;

  bool get isDumb {
    return (cursorBack == null ||
            cursorForward == null ||
            cursorUp == null ||
            cursorDown == null ||
            clearEOL == null ||
            clearScreen == null);
  }

  // Function keys.
  final String keyF1  = _tputGetSequence('kf1',  orElse: '\u001BOP');
  final String keyF5  = _tputGetSequence('kf5',  orElse: '\u001B[15~');
  final String keyF6  = _tputGetSequence('kf6',  orElse: '\u001B[17~');
  final String keyF10 = _tputGetSequence('kf10', orElse: '\u001B[21~');

  // Back one character.
  final String cursorBack = _tputGetSequence('cub1');

  // Forward one character.
  final String cursorForward = _tputGetSequence('cuf1');

  // Up one character.
  final String cursorUp = _tputGetSequence('cuu1');

  // Down one character.
  final String cursorDown = _tputGetSequence('cud1');

  // Clear to end of line.
  final String clearEOL = _tputGetSequence('el');

  // Clear screen and home cursor.
  final String clearScreen = _tputGetSequence('clear', orElse: '\n\n');

  // Enter bold text mode.
  final String boldText = _tputGetSequence('bold', orElse: '');

  // Exit text attributes.
  final String resetText = _tputGetSequence('sgr0', orElse: '');

  int get cols => stdout.terminalColumns;

  bool supportsColor;

  // Convenience method for bolding text.
  String toBold(String str) => '$boldText$str$resetText';
}
