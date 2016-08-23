// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of commandline;

/// Implements a command line interface.
class CommandLine {
  CommandLine(this.term, this._root, { this.prompt : '> '}) {
    _root._commandLine = this;
    _in = term.consoleIn;
    _out = term.consoleOut;
    _in.echoMode = false;
    _in.lineMode = false;
    _writePrompt();
    _inputSubscription =
      _in.transform(UTF8.decoder).listen(_handleText,
                                         onError:_inputError,
                                         onDone:_inputDone);
    _dumbMode = term.isDumb;
    _resize();
  }

  // Ctrl keys
  static const int _runeCtrlA       = 0x01;
  static const int _runeCtrlB       = 0x02;
  static const int _runeCtrlD       = 0x04;
  static const int _runeCtrlE       = 0x05;
  static const int _runeCtrlF       = 0x06;
  static const int _runeTAB         = 0x09;
  static const int _runeNewline     = 0x0a;
  static const int _runeCtrlK       = 0x0b;
  static const int _runeCtrlL       = 0x0c;
  static const int _runeCtrlN       = 0x0e;
  static const int _runeCtrlP       = 0x10;
  static const int _runeCtrlU       = 0x15;
  static const int _runeCtrlY       = 0x19;
  static const int _runeESC         = 0x1b;
  static const int _runeA           = 0x41;
  static const int _runeB           = 0x42;
  static const int _runeC           = 0x43;
  static const int _runeD           = 0x44;
  static const int _runeLeftBracket = 0x5b;
  static const int _runeDEL         = 0x7F;

  RootCommand get rootCommand => _root;
  final RootCommand _root;
  bool _dumbMode;

  bool get _promptShown => _hideDepth == 0;

  Future<Null> quit() async {
    await _closeInput();
  }

  Completer<Null> _inputCompleter = new Completer<Null>();
  Future<Null> get onInputDone => _inputCompleter.future;

  void _inputDone() {
    _closeInput().then((_) {
      _inputCompleter.complete();
    });
  }

  void _inputError(dynamic e, StackTrace st) {
    print('Unexpected error reading input: $e\n$st');
    _closeInput().then((_) {
      _inputCompleter.complete();
    });
  }

  Future<Null> _closeInput() {
    assert(_inputSubscription != null);
    _in.echoMode = true;
    _in.lineMode = true;
    Future<Null> future = _inputSubscription.cancel();
    _inputSubscription = null;
    if (future != null) {
      return future;
    } else {
      return new Future<Null>.value();
    }
  }

  void _resize() {
    _screenWidth = term.cols - 1;
  }

  void _handleText(String text) {
    try {
      if (!_promptShown) {
        _bufferedInput.write(text);
        return;
      }

      List<int> runes = text.runes.toList();
      int pos = 0;
      while (pos < runes.length) {
        if (!_promptShown) {
          // A command was processed which hid the prompt.  Buffer
          // the rest of the input.
          _bufferedInput.write(
              new String.fromCharCodes(runes.skip(pos)));
          return;
        }

        int rune = runes[pos];

        // Count consecutive tabs because double-tab is meaningful.
        if (rune == _runeTAB) {
          _tabCount++;
        } else {
          _tabCount = 0;
        }

        if (_isControlRune(rune)) {
          if (_dumbMode) {
            pos += _handleControlSequenceDumb(runes, pos);
          } else {
            pos += _handleControlSequence(runes, pos);
          }
        } else {
          pos += _handleRegularSequence(runes, pos);
        }
      }
    } catch(e, st) {
      print('Unexpected error: $e\n$st');
    }
  }

  bool _matchRunes(List<int> runes, int pos, List<int> match) {
    if (runes.length < pos + match.length) {
      return false;
    }
    for (int i = 0; i < match.length; i++) {
      if (runes[pos + i] != match[i]) {
        return false;
      }
    }
    return true;
  }

  int _handleControlSequence(List<int> runes, int pos) {
    int runesConsumed = 1;  // Most common result.
    int char = runes[pos];
    switch (char) {
      case _runeCtrlA:
        _home();
        break;

      case _runeCtrlB:
        _leftArrow();
        break;

      case _runeCtrlD:
        if (_currentLine.length == 0) {
          // ^D on an empty line means quit.
          _out.writeln("^D");
          _inputDone();
        } else {
          _delete();
        }
        break;

      case _runeCtrlE:
        _end();
        break;

      case _runeCtrlF:
        _rightArrow();
        break;

      case _runeTAB:
        _complete(_tabCount > 1);
        break;

      case _runeNewline:
        _newline();
        break;

      case _runeCtrlK:
        _kill();
        break;

      case _runeCtrlL:
        _clearScreen();
        break;

      case _runeCtrlN:
        _historyNext();
        break;

      case _runeCtrlP:
        _historyPrevious();
        break;

      case _runeCtrlU:
        _clearLine();
        break;

      case _runeCtrlY:
        _yank();
        break;

      case _runeESC:
        if (pos + 1 < runes.length) {
          if (_matchRunes(runes, pos + 1, <int>[_runeLeftBracket, _runeA])) {
            // ^[[A = up arrow
            _historyPrevious();
            runesConsumed = 3;
            break;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeB])) {
            // ^[[B = down arrow
            _historyNext();
            runesConsumed = 3;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeC])) {
            // ^[[C = right arrow
            _rightArrow();
            runesConsumed = 3;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeD])) {
            // ^[[D = left arrow
            _leftArrow();
            runesConsumed = 3;
          } else {
            HotKey hotKey = _root.matchHotKey(runes.skip(pos).toList());
            if (hotKey != null) {
              runesConsumed = hotKey.runes.length;
              List<int> line = hotKey.expansion.runes.toList();
              _update(line, line.length);
              _newline();
            }
          }
        }
        break;

      case _runeDEL:
        _backspace();
        break;

      default:
        // Ignore the escape character.
        break;
    }
    return runesConsumed;
  }

  int _handleControlSequenceDumb(List<int> runes, int pos) {
    int runesConsumed = 1;  // Most common result.
    int char = runes[pos];
    switch (char) {
      case _runeCtrlD:
        if (_currentLine.length == 0) {
          // ^D on an empty line means quit.
          _out.writeln("^D");
          _inputDone();
        }
        break;

      case _runeTAB:
        _complete(_tabCount > 1);
        break;

      case _runeNewline:
        _newline();
        break;

      case _runeCtrlN:
        _historyNext();
        break;

      case _runeCtrlP:
        _historyPrevious();
        break;

      case _runeCtrlU:
        _clearLine();
        break;

      case _runeESC:
        if (pos + 1 < runes.length) {
          if (_matchRunes(runes, pos + 1, <int>[_runeLeftBracket, _runeA])) {
            // ^[[A = up arrow
            _historyPrevious();
            runesConsumed = 3;
            break;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeB])) {
            // ^[[B = down arrow
            _historyNext();
            runesConsumed = 3;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeC])) {
            // ^[[C = right arrow - Ignore.
            runesConsumed = 3;
          } else if (_matchRunes(runes, pos + 1,
                                 <int>[_runeLeftBracket, _runeD])) {
            // ^[[D = left arrow - Ignore.
            runesConsumed = 3;
          } else {
            HotKey hotKey = _root.matchHotKey(runes.skip(pos).toList());
            if (hotKey != null) {
              runesConsumed = hotKey.runes.length;
              List<int> line = hotKey.expansion.runes.toList();
              _update(line, line.length);
              _newline();
            }
          }
        }
        break;

      case _runeDEL:
        _backspace();
        break;

      default:
        // Ignore the escape character.
        break;
    }
    return runesConsumed;
  }

  int _handleRegularSequence(List<int> runes, int pos) {
    int len = pos + 1;
    while (len < runes.length && !_isControlRune(runes[len])) {
      len++;
    }
    _addChars(runes.getRange(pos, len));
    return len;
  }

  bool _isControlRune(int char) {
    return (char >= 0x00 && char < 0x20) || (char == 0x7f);
  }

  void _writePromptAndLine() {
    _writePrompt();
    int pos = _writeRange(_currentLine, 0, _currentLine.length);
    _cursorPos = _move(pos, _cursorPos);
  }

  void _writePrompt() {
    _resize();
    _out.write(term.toBold(prompt));
  }

  void _addChars(Iterable<int> chars) {
    List<int> newLine = <int>[];
    newLine..addAll(_currentLine.take(_cursorPos))
           ..addAll(chars)
           ..addAll(_currentLine.skip(_cursorPos));
    _update(newLine, (_cursorPos + chars.length));
  }

  void _backspace() {
    if (_cursorPos == 0) {
      return;
    }
    List<int> newLine = <int>[];
    newLine..addAll(_currentLine.take(_cursorPos - 1))
           ..addAll(_currentLine.skip(_cursorPos));
    _update(newLine, (_cursorPos - 1));
  }

  void _delete() {
    if (_cursorPos == _currentLine.length) {
      return;
    }
    List<int> newLine = <int>[];
    newLine..addAll(_currentLine.take(_cursorPos))
           ..addAll(_currentLine.skip(_cursorPos + 1));
    _update(newLine, _cursorPos);
  }

  void _home() {
    _updatePos(0);
  }

  void _end() {
    _updatePos(_currentLine.length);
  }

  void _clearScreen() {
    _out.write(term.clearScreen);
    _writePromptAndLine();
  }

  void _kill() {
    List<int> newLine = <int>[];
    newLine.addAll(_currentLine.take(_cursorPos));
    _killBuffer = _currentLine.skip(_cursorPos).toList();
    _update(newLine, _cursorPos);
  }

  void _clearLine() {
    _update(<int>[], 0);
  }

  void _yank() {
    List<int> newLine = <int>[];
    newLine..addAll(_currentLine.take(_cursorPos))
           ..addAll(_killBuffer)
           ..addAll(_currentLine.skip(_cursorPos));
    _update(newLine, (_cursorPos + _killBuffer.length));
  }

  static String _commonPrefix(String a, String b) {
    int pos = 0;
    while (pos < a.length && pos < b.length) {
      if (a.codeUnitAt(pos) != b.codeUnitAt(pos)) {
        break;
      }
      pos++;
    }
    return a.substring(0, pos);
  }

  static String _foldCompletions(List<String> values) {
    if (values.length == 0) {
      return '';
    }
    String prefix = values[0];
    for (int i = 1; i < values.length; i++) {
      prefix = _commonPrefix(prefix, values[i]);
    }
    return prefix;
  }

  Future<Null> _complete(bool showCompletions) async {
    List<int> linePrefix = _currentLine.take(_cursorPos).toList();
    String lineAsString = new String.fromCharCodes(linePrefix);
    List<String> completions = await _root.completeCommand(lineAsString);
    String completion;
    if (completions.length == 0) {
      // No completions.  Leave the line alone.
      return;
    } else if (completions.length == 1) {
      // Unambiguous completion.
      completion = completions[0];
    } else {
      // Ambiguous completion.
      completions = completions.map((String s) => s.trimRight()).toList();
      completion = _foldCompletions(completions);
    }

    if (showCompletions) {
      // User hit double-TAB.  Show them all possible completions.
      completions.sort((String a, String b) => a.compareTo(b));
      _move(_cursorPos, _currentLine.length);
      _out.writeln();
      _out.writeln(completions);
      _writePromptAndLine();
      return;

    } else {
      // Apply the current completion.
      List<int> completionRunes = completion.runes.toList();
      List<int> newLine = <int>[];
      newLine..addAll(completionRunes)
             ..addAll(_currentLine.skip(_cursorPos));
      _update(newLine, completionRunes.length);
      return;
    }
  }

  Future<Null> _newline() async {
    _end();
    _out.writeln();

    // Prompt is implicitly hidden at this point.
    _hideDepth++;

    String text = new String.fromCharCodes(_currentLine);
    _currentLine = <int>[];
    _cursorPos = 0;
    try {
      await _root.runCommand(text);
    } catch (e) {
      print('$e');
    }

    // Reveal the prompt.
    show();
  }

  void _leftArrow() {
    _updatePos(_cursorPos - 1);
  }

  void _rightArrow() {
    _updatePos(_cursorPos + 1);
  }

  void _historyPrevious() {
    String text = new String.fromCharCodes(_currentLine);
    List<int> newLine = _root.historyPrev(text).runes.toList();
    _update(newLine, newLine.length);
  }

  void _historyNext() {
    String text = new String.fromCharCodes(_currentLine);
    List<int> newLine = _root.historyNext(text).runes.toList();
    _update(newLine, newLine.length);
  }

  void _updatePos(int newCursorPos) {
    if (newCursorPos < 0) {
      return;
    }
    if (newCursorPos > _currentLine.length)
      return;

    _cursorPos = _move(_cursorPos, newCursorPos);
  }

  void _update(List<int> newLine, int newCursorPos) {
    int pos = _cursorPos;
    int sharedLen = min(_currentLine.length, newLine.length);

    // Find first difference.
    int diffPos;
    for (diffPos = 0; diffPos < sharedLen; diffPos++) {
      if (_currentLine[diffPos] != newLine[diffPos]) {
        break;
      }
    }

    if (_dumbMode) {
      assert(_cursorPos == _currentLine.length);
      assert(newCursorPos == newLine.length);
      if (diffPos == _currentLine.length) {
        // Write the new text.
        int pos = _writeRange(newLine, _cursorPos, newLine.length);
        assert(pos == newCursorPos);
        _cursorPos = newCursorPos;
        _currentLine = newLine;
      } else {
        // We can't erase, so just move forward.
        _out.writeln();
        _currentLine = newLine;
        _cursorPos = newCursorPos;
        _writePromptAndLine();
      }
      return;
    }

    // Move the cursor to where the difference begins.
    pos = _move(pos, diffPos);

    // Write the new text.
    pos = _writeRange(newLine, pos, newLine.length);

    // Clear any extra characters at the end.
    pos = _clearRange(pos, _currentLine.length);

    // Move the cursor back to the input point.
    _cursorPos = _move(pos, newCursorPos);
    _currentLine = newLine;
  }

  void print(String text, { bool bold: false }) {
    hide();
    _out.writeln(text);
    show();
  }

  void hide() {
    if (_hideDepth > 0) {
      _hideDepth++;
      return;
    }
    _hideDepth++;
    if (_dumbMode) {
      _out.writeln();
      return;
    }
    // We need to erase everything, including the prompt.
    int curLine = _getLine(_cursorPos);
    int lastLine = _getLine(_currentLine.length);

    // Go to last line.
    if (curLine < lastLine) {
      for (int i = 0; i < (lastLine - curLine); i++) {
        // This moves us to column 0.
        _out.write(term.cursorDown);
      }
      curLine = lastLine;
    } else {
      // Move to column 0.
      _out.write('\r');
    }

    // Work our way up, clearing lines.
    while (true) {
      _out.write(term.clearEOL);
      if (curLine > 0) {
        _out.write(term.cursorUp);
      } else {
        break;
      }
    }
  }

  void show() {
    if (_inputSubscription == null) {
      // No more input to process.
      return;
    }
    assert(_hideDepth > 0);
    _hideDepth--;
    if (_hideDepth > 0) {
      return;
    }
    _writePromptAndLine();

    // If input was buffered while the prompt was hidden, process it
    // now.
    if (_bufferedInput.isNotEmpty) {
      String input = _bufferedInput.toString();
      _bufferedInput.clear();
      _handleText(input);
    }
  }

  int _writeRange(List<int> text, int pos, int writeToPos) {
    if (pos >= writeToPos) {
      return pos;
    }
    while (pos < writeToPos) {
      int margin = _nextMargin(pos);
      int limit = min(writeToPos, margin);
      _out.write(new String.fromCharCodes(text.getRange(pos, limit)));
      pos = limit;
      if (pos == margin) {
        _out.write('\n');
      }
    }
    return pos;
  }

  int _clearRange(int pos, int clearToPos) {
    if (pos >= clearToPos) {
      return pos;
    }
    while (true) {
      int limit = _nextMargin(pos);
      _out.write(term.clearEOL);
      if (limit >= clearToPos) {
        return pos;
      }
      _out.write('\n');
      pos = limit;
    }
  }

  int _move(int pos, int newPos) {
    if (pos == newPos) {
      return pos;
    }
    int curCol = _getCol(pos);
    int curLine = _getLine(pos);
    int newCol = _getCol(newPos);
    int newLine = _getLine(newPos);

    if (curLine > newLine) {
      for (int i = 0; i < (curLine - newLine); i++) {
        _out.write(term.cursorUp);
      }
    }
    if (curLine < newLine) {
      for (int i = 0; i < (newLine - curLine); i++) {
        _out.write(term.cursorDown);
      }

      // Moving down resets column to zero, oddly.
      curCol = 0;
    }
    if (curCol > newCol) {
      for (int i = 0; i < (curCol - newCol); i++) {
        _out.write(term.cursorBack);
      }
    }
    if (curCol < newCol) {
      for (int i = 0; i < (newCol - curCol); i++) {
        _out.write(term.cursorForward);
      }
    }

    return newPos;
  }

  int _nextMargin(int pos) {
    int truePos = pos + prompt.length;
    return ((truePos ~/ _screenWidth) + 1) * _screenWidth - prompt.length;
  }

  int _getLine(int pos) {
    int truePos = pos + prompt.length;
    return truePos ~/ _screenWidth;
  }

  int _getCol(int pos) {
    int truePos = pos + prompt.length;
    return truePos % _screenWidth;
  }

  Stdin _in;
  StreamSubscription<String> _inputSubscription;
  IOSink _out;
  final String prompt;
  int _hideDepth = 0;
  final Terminal term;

  int _screenWidth;
  List<int> _currentLine = <int>[];  // A list of runes.
  StringBuffer _bufferedInput = new StringBuffer();
  int _cursorPos = 0;
  int _tabCount = 0;
  List<int> _killBuffer = <int>[];
}

abstract class HelpableCommand extends Command {
  HelpableCommand(String name, List<Command> children)
    : super(name, children);

  String get helpShort;
  String get helpLong;
}

int _sortCommands(Command a, Command b) => a.name.compareTo(b.name);

/// A default implementation of a help command, provided for convenience.
class HelpCommand extends HelpableCommand {
  HelpCommand([ String name = 'help', List<Command> children ])
    : super(name, children);

  String _nameAndAlias(Command cmd) {
    if (cmd.alias == null) {
      return cmd.fullName;
    } else {
      return '${cmd.fullName}, ${cmd.alias}';
    }
  }

  @override
  Future<Null> run(List<String> args) async {
    if (args.length == 0) {
      // Print list of all top-level commands.
      List<Command> commands =
          commandLine.rootCommand.matchCommand(<String>[], false);
      commands.sort(_sortCommands);
      commandLine.print('Commands:\n', bold: true);
      for (Command command in commands) {
        if (command is HelpableCommand) {
          HelpableCommand helpable = command;
          commandLine.print('${_nameAndAlias(command).padRight(12)} '
                            '- ${helpable.helpShort}');
        }
      }
      commandLine.print("\nHotkeys:", bold: true);
      commandLine.print(
          "\n"
          "[TAB]        - complete a command (try 'p[TAB][TAB]')\n"
          "[Up Arrow]   - history previous\n"
          "[Down Arrow] - history next\n"
          "[^L]         - clear screen");
      List<HotKey> keys = commandLine.rootCommand.hotKeys;
      for (int i = 0; i < keys.length; i++) {
        HotKey key = keys[i];
        commandLine.print(
            "${key.userName.padRight(12)} - '${key.expansion}'");
      }
      commandLine.print(
          "\nFor more information on a specific command type "
          "'help <command>'\n"
          "Command prefixes are accepted (e.g. 'h' for 'help')\n");
    } else {
      // Print any matching commands.
      List<Command> commands = commandLine.rootCommand.matchCommand(args, true);
      commands.sort(_sortCommands);
      if (commands.isEmpty) {
        String line = args.join(' ');
        commandLine.print("No command matches '$line'");
        return;
      }
      commandLine.print('');
      for (Command command in commands) {
        if (command is! HelpableCommand) {
          continue;
        }
        HelpableCommand helpable = command;
        commandLine.print(_nameAndAlias(command), bold: true);
        commandLine.print(helpable.helpLong);

        List<String> newArgs = <String>[];
        newArgs.addAll(args.take(args.length - 1));
        newArgs.add(command.name);
        newArgs.add('');
        List<Command> subCommands =
            commandLine.rootCommand.matchCommand(newArgs, false);
        subCommands.remove(command);
        if (subCommands.isNotEmpty) {
          subCommands.sort(_sortCommands);
          commandLine.print('Subcommands:\n');
          for (Command subCommand in subCommands) {
            if (subCommand is HelpableCommand) {
              HelpableCommand subHelpable = subCommand;
              commandLine.print('    ${subCommand.fullName.padRight(16)} '
                             '- ${subHelpable.helpShort}');
            }
          }
          commandLine.print('');
        }
      }
    }
  }

  @override
  Future<List<String>> complete(List<String> args) {
    List<Command> commands = commandLine.rootCommand.matchCommand(args, false);
    List<String> result = commands.map((Command cmd) => '${cmd.fullName} ');
    return new Future<List<String>>.value(result);
  }

  @override
  final String helpShort =
      'List commands or provide details about a specific command';

  @override
  final String helpLong =
      'List commands or provide details about a specific command.\n'
      '\n'
      'Syntax: help            - Show a list of all commands\n'
      '        help <command>  - Help for a specific command\n';
}
