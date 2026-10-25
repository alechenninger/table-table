import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../clipboard.dart';

/// AppKit clipboard access without subprocesses or a separately built shim.
/// A name selects a private pasteboard, useful for isolated native tests.
class MacOsClipboard implements Clipboard {
  final String? name;

  static final _AppKit _appKit = _AppKit();

  MacOsClipboard({this.name}) {
    if (!Platform.isMacOS) {
      throw UnsupportedError('AppKit clipboard access requires macOS');
    }
    if (name != null && name!.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  @override
  Future<ClipboardSnapshot> read() async => _withPasteboard((api, pasteboard) {
        // Another application may replace the clipboard between flavor reads.
        // Never return a mixture of different clipboard generations.
        for (var attempt = 0; attempt < 3; attempt++) {
          final before = api.integer(pasteboard, 'changeCount');
          final contents = <ClipboardFormat, String>{};
          for (final format in ClipboardFormat.values) {
            final value = api.objectArgument(
                pasteboard, 'stringForType:', api.types[format]!);
            if (value != nullptr) contents[format] = api.stringValue(value);
          }
          if (api.integer(pasteboard, 'changeCount') == before) {
            return ClipboardSnapshot(contents);
          }
        }
        throw const ClipboardError(
            'clipboard kept changing while reading its formats');
      });

  @override
  Future<void> write(ClipboardSnapshot contents) async =>
      _withPasteboard((api, pasteboard) {
        // Prepare all flavors locally, then publish them together on one item.
        final item = api.autoreleasedInstance('NSPasteboardItem');
        for (final entry in contents.representations.entries) {
          final string = api.string(entry.value);
          if (!api.booleanArguments(
              item, 'setString:forType:', string, api.types[entry.key]!)) {
            throw const ClipboardError('could not prepare clipboard contents');
          }
        }
        final items = api.objectArgument(
            api.classObject('NSArray'), 'arrayWithObject:', item);
        if (items == nullptr) {
          throw const ClipboardError('could not prepare clipboard items');
        }
        api.integer(pasteboard, 'clearContents');
        if (contents.representations.isNotEmpty &&
            !api.booleanArgument(pasteboard, 'writeObjects:', items)) {
          throw const ClipboardError('could not write clipboard contents');
        }
      });

  /// Release a private named pasteboard after use. The general clipboard cannot
  /// be released through this method.
  Future<void> release() async {
    if (name == null) {
      throw const ClipboardError('cannot release the general clipboard');
    }
    _withPasteboard(
        (api, pasteboard) => api.voidMessage(pasteboard, 'releaseGlobally'));
  }

  T _withPasteboard<T>(
      T Function(_AppKit api, Pointer<Void> pasteboard) action) {
    try {
      final api = _appKit;
      final pasteboardClass = api.classObject('NSPasteboard');
      // A Dart static lock would be isolate-local. The Objective-C class object
      // is shared by every isolate. Include pool draining in the critical
      // section so native object disposal is serialized too. Never await here.
      return api.synchronized(pasteboardClass, () {
        return api.withAutoreleasePool(() {
          final pasteboard = name == null
              ? api.object(pasteboardClass, 'generalPasteboard')
              : api.objectArgument(
                  pasteboardClass, 'pasteboardWithName:', api.string(name!));
          if (pasteboard == nullptr) {
            throw const ClipboardError('could not access the macOS pasteboard');
          }
          return action(api, pasteboard);
        });
      });
    } on ArgumentError catch (error) {
      throw ClipboardError(
          'could not load macOS clipboard API: ${error.message}');
    } on FormatException catch (error) {
      throw ClipboardError('invalid clipboard text: ${error.message}');
    }
  }
}

// objc_msgSend must use each method's fixed C signature. Its historical
// variadic declaration would select the wrong argument ABI on arm64. None of
// these methods returns a struct or float, so normal objc_msgSend also works
// on macOS x86_64 without the stret/fpret entry points.
class _AppKit {
  late final types = {
    ClipboardFormat.plainText:
        _library.lookup<Pointer<Void>>('NSPasteboardTypeString').value,
    ClipboardFormat.html:
        _library.lookup<Pointer<Void>>('NSPasteboardTypeHTML').value,
  };

  static const _utf8Encoding = 4; // Foundation's NSUTF8StringEncoding.

  final DynamicLibrary _library =
      DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');
  final DynamicLibrary _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
  final _selectors = <String, Pointer<Void>>{};
  final _classes = <String, Pointer<Void>>{};

  late final _getClass = _objc.lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)>('objc_getClass');
  late final _registerSelector = _objc.lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>)>('sel_registerName');
  late final _syncEnter = _objc.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('objc_sync_enter');
  late final _syncExit = _objc.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('objc_sync_exit');
  late final _object = _objc.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  late final _objectArgument = _objc.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  late final _integer = _objc.lookupFunction<
      IntPtr Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  late final _unsignedArgument = _objc.lookupFunction<
      UintPtr Function(Pointer<Void>, Pointer<Void>, UintPtr),
      int Function(Pointer<Void>, Pointer<Void>, int)>('objc_msgSend');
  late final _booleanArgument = _objc.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  late final _booleanArguments = _objc.lookupFunction<
      Uint8 Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
          Pointer<Void>)>('objc_msgSend');
  late final _characters = _objc.lookupFunction<
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Uint16>, UintPtr),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Uint16>, int)>('objc_msgSend');
  late final _void = _objc.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');

  Pointer<Void> classObject(String name) => _classes.putIfAbsent(name, () {
        final value = _withCString(name, _getClass);
        if (value == nullptr) {
          throw ClipboardError('macOS class $name is unavailable');
        }
        return value;
      });

  Pointer<Void> object(Pointer<Void> receiver, String selector) =>
      _object(receiver, _selector(selector));

  Pointer<Void> objectArgument(
          Pointer<Void> receiver, String selector, Pointer<Void> argument) =>
      _objectArgument(receiver, _selector(selector), argument);

  int integer(Pointer<Void> receiver, String selector) =>
      _integer(receiver, _selector(selector));

  bool booleanArgument(
          Pointer<Void> receiver, String selector, Pointer<Void> argument) =>
      _booleanArgument(receiver, _selector(selector), argument) != 0;

  bool booleanArguments(Pointer<Void> receiver, String selector,
          Pointer<Void> first, Pointer<Void> second) =>
      _booleanArguments(receiver, _selector(selector), first, second) != 0;

  void voidMessage(Pointer<Void> receiver, String selector) =>
      _void(receiver, _selector(selector));

  Pointer<Void> autoreleasedInstance(String name) {
    final allocated = object(classObject(name), 'alloc');
    final initialized = object(allocated, 'init');
    if (initialized == nullptr) {
      throw ClipboardError('could not create macOS $name');
    }
    return object(initialized, 'autorelease');
  }

  Pointer<Void> string(String value) {
    final characters = calloc<Uint16>(value.length + 1);
    try {
      characters.asTypedList(value.length).setAll(0, value.codeUnits);
      final result = _characters(classObject('NSString'),
          _selector('stringWithCharacters:length:'), characters, value.length);
      if (result == nullptr) {
        throw const ClipboardError('could not create a macOS clipboard string');
      }
      return result;
    } finally {
      calloc.free(characters);
    }
  }

  String stringValue(Pointer<Void> value) {
    final length = _unsignedArgument(
        value, _selector('lengthOfBytesUsingEncoding:'), _utf8Encoding);
    if (length == 0) {
      if (integer(value, 'length') != 0) {
        throw const ClipboardError(
            'clipboard string could not be encoded as UTF-8');
      }
      return '';
    }
    final bytes = object(value, 'UTF8String');
    if (bytes == nullptr) {
      throw const ClipboardError('could not read a macOS clipboard string');
    }
    // Explicit length preserves embedded NULs. Copy before the pool drains;
    // native string pointers never escape into the clipboard abstraction.
    return bytes.cast<Utf8>().toDartString(length: length);
  }

  T withAutoreleasePool<T>(T Function() action) {
    final pool =
        object(object(classObject('NSAutoreleasePool'), 'alloc'), 'init');
    if (pool == nullptr) {
      throw const ClipboardError('could not create a macOS autorelease pool');
    }
    try {
      return action();
    } finally {
      voidMessage(pool, 'drain');
    }
  }

  T synchronized<T>(Pointer<Void> lock, T Function() action) {
    if (_syncEnter(lock) != 0) {
      throw const ClipboardError('could not lock the macOS clipboard API');
    }
    try {
      return action();
    } finally {
      if (_syncExit(lock) != 0) {
        throw const ClipboardError('could not unlock the macOS clipboard API');
      }
    }
  }

  Pointer<Void> _selector(String name) =>
      _selectors.putIfAbsent(name, () => _withCString(name, _registerSelector));

  T _withCString<T>(String value, T Function(Pointer<Utf8>) action) {
    final bytes = value.toNativeUtf8(allocator: calloc);
    try {
      return action(bytes);
    } finally {
      calloc.free(bytes);
    }
  }
}
