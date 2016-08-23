// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'package:commandline/commandline.dart';

class QuitCommand extends HelpableCommand {
  QuitCommand() : super('quit', null);

  @override
  Future<Null> run(List<String> args) async {
    if (args.length != 0) {
      commandLine.print("'$name' expects no arguments");
      return;
    }
    await commandLine.quit();
    exit(0);
  }

  @override
  String helpShort = 'Quit the flutter application';

  @override
  String helpLong =
      'Quit the application.\n'
      '\n'
      'Syntax: quit\n';
}

List<Command> buildCommandList() {
  List<Command> cmds = <Command>[];
  cmds.add(new HelpCommand());
  cmds.add(new QuitCommand());
  return cmds;
}

// TODO(turnidge): Figure out why we need to exit(0).
void registerSignalHandlers(CommandLine commandLine) {
  ProcessSignal.SIGINT.watch().listen((ProcessSignal signal) async {
    commandLine.hide();
    await commandLine.quit();
    exit(0);
  });
  ProcessSignal.SIGTERM.watch().listen((ProcessSignal signal) async {
    commandLine.hide();
    await commandLine.quit();
    exit(0);
  });
  commandLine.onInputDone.then((_) async {
    commandLine.hide();
    await commandLine.quit();
    exit(0);
  });
}

void main() {
  Terminal terminal = new Terminal(stdin, stdout);
  RootCommand root = new RootCommand(buildCommandList());
  CommandLine commandLine = new CommandLine(terminal, root);
  registerSignalHandlers(commandLine);
}
