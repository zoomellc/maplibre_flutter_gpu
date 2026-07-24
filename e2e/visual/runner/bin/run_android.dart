import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:visual_e2e_runner/src/android_drive.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

const _maplibreGlVersion = '0.26.2';

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await _run(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exitCode = 2;
  } on ProcessException catch (error) {
    stderr.writeln('error: $error');
    exitCode = 2;
  } catch (error, stackTrace) {
    stderr
      ..writeln('error: $error')
      ..writeln(stackTrace);
    exitCode = 2;
  }
}

Future<int> _run(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('device', abbr: 'd', help: 'Android device serial.')
    ..addOption(
      'scene',
      defaultsTo: 'geometry',
      allowed: const <String>['geometry'],
    )
    ..addOption(
      'minimum-similarity',
      defaultsTo: '0.998',
      help: 'Required substantial-pixel similarity in the range 0..1.',
    )
    ..addOption(
      'color-threshold',
      defaultsTo: '0.05',
      help: 'Pixelmatch YIQ color threshold in the range 0..1.',
    )
    ..addOption(
      'output',
      defaultsTo: 'e2e/visual/report',
      help: 'Report output directory, relative to repository root.',
    )
    ..addOption(
      'maplibre-gl-apk',
      help:
          'Prebuilt maplibre_gl integration-test APK, relative to the '
          'repository root.',
    )
    ..addOption(
      'gpu-apk',
      help:
          'Prebuilt maplibre_flutter_gpu integration-test APK, relative to '
          'the repository root.',
    )
    ..addFlag(
      'include-antialiasing',
      defaultsTo: false,
      help: 'Count detected anti-alias differences as mismatches.',
    )
    ..addFlag(
      'skip-drive',
      defaultsTo: false,
      help: 'Reuse existing images in the output directory.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  final parsed = parser.parse(arguments);
  if (parsed.flag('help')) {
    stdout
      ..writeln('Android MapLibre visual E2E')
      ..writeln(parser.usage);
    return 0;
  }

  final minimumSimilarity = _parseFraction(
    parsed.option('minimum-similarity')!,
    'minimum-similarity',
  );
  final colorThreshold = _parseFraction(
    parsed.option('color-threshold')!,
    'color-threshold',
  );
  final sceneId = parsed.option('scene')!;
  final runnerRoot = path.dirname(path.dirname(Platform.script.toFilePath()));
  final repositoryRoot = path.normalize(path.join(runnerRoot, '../../..'));
  final outputOption = parsed.option('output')!;
  final outputPath = path.isAbsolute(outputOption)
      ? path.normalize(outputOption)
      : path.normalize(path.join(repositoryRoot, outputOption));
  final outputDirectory = Directory(outputPath);
  final imagesDirectory = Directory(path.join(outputPath, 'images'));
  final logsDirectory = Directory(path.join(outputPath, 'logs'));
  final maplibreGlApk = _resolvePrebuiltApk(
    parsed.option('maplibre-gl-apk'),
    repositoryRoot,
  );
  final gpuApk = _resolvePrebuiltApk(parsed.option('gpu-apk'), repositoryRoot);
  if ((maplibreGlApk == null) != (gpuApk == null)) {
    throw const FormatException(
      '--maplibre-gl-apk and --gpu-apk must be provided together',
    );
  }
  for (final apk in <String?>[maplibreGlApk, gpuApk]) {
    if (apk != null && !await File(apk).exists()) {
      throw FormatException('prebuilt APK does not exist: $apk');
    }
  }
  await imagesDirectory.create(recursive: true);
  await logsDirectory.create(recursive: true);

  final skipDrive = parsed.flag('skip-drive');
  String? device = parsed.option('device');
  String? adb;
  String? flutter;

  if (!skipDrive) {
    await Future.wait(<Future<void>>[
      for (final stalePath in <String>[
        path.join(imagesDirectory.path, 'gpu.png'),
        path.join(imagesDirectory.path, 'maplibre_gl.png'),
        path.join(imagesDirectory.path, 'diff.png'),
        path.join(outputDirectory.path, 'index.html'),
        path.join(outputDirectory.path, 'results.json'),
        path.join(logsDirectory.path, 'maplibre_gl-pub-get.log'),
        path.join(logsDirectory.path, 'maplibre_gl-drive.log'),
        path.join(logsDirectory.path, 'maplibre_flutter_gpu-pub-get.log'),
        path.join(logsDirectory.path, 'maplibre_flutter_gpu-drive.log'),
      ])
        _removeStaleFile(File(stalePath)),
    ]);
    flutter = _findFlutter();
    adb = _findAdb();
    device ??= await _selectDevice(adb);

    final applications = <_VisualApplication>[
      _VisualApplication(
        label: 'maplibre_gl',
        root: path.join(repositoryRoot, 'e2e/visual/maplibre_gl_app'),
        applicationId: 'dev.maplibre.fluttergpu.e2e.visual_e2e_maplibre_gl',
        applicationBinary: maplibreGlApk,
      ),
      _VisualApplication(
        label: 'maplibre_flutter_gpu',
        root: path.join(repositoryRoot, 'e2e/visual/gpu_app'),
        applicationId: 'dev.maplibre.fluttergpu.e2e.visual_e2e_gpu',
        applicationBinary: gpuApk,
      ),
    ];

    for (final application in applications) {
      stdout.writeln('\n[${application.label}] resolving dependencies');
      await _runLogged(
        flutter,
        const <String>['pub', 'get'],
        workingDirectory: application.root,
        logFile: File(
          path.join(logsDirectory.path, '${application.label}-pub-get.log'),
        ),
      );
      stdout.writeln('[${application.label}] running Android integration test');
      if (application.applicationBinary != null) {
        stdout.writeln(
          '[${application.label}] using prebuilt APK: '
          '${application.applicationBinary}',
        );
      }
      try {
        await _runLogged(
          flutter,
          buildAndroidDriveArguments(
            device: device,
            sceneId: sceneId,
            applicationBinary: application.applicationBinary,
          ),
          workingDirectory: application.root,
          environment: <String, String>{
            'VISUAL_E2E_SCREENSHOT_DIR': imagesDirectory.path,
          },
          logFile: File(
            path.join(logsDirectory.path, '${application.label}-drive.log'),
          ),
        );
      } finally {
        await _forceStop(adb, device, application.applicationId);
      }
    }
  }

  final referenceFile = File(
    path.join(imagesDirectory.path, 'maplibre_gl.png'),
  );
  final actualFile = File(path.join(imagesDirectory.path, 'gpu.png'));
  if (!await referenceFile.exists() || !await actualFile.exists()) {
    throw StateError(
      'both screenshots are required: '
      '${referenceFile.path}, ${actualFile.path}',
    );
  }

  final comparison = comparePngBytes(
    referencePng: Uint8List.fromList(await referenceFile.readAsBytes()),
    actualPng: Uint8List.fromList(await actualFile.readAsBytes()),
    options: PixelMatchOptions(
      colorThreshold: colorThreshold,
      includeAntiAlias: parsed.flag('include-antialiasing'),
    ),
  );
  final metadata = await _collectMetadata(
    repositoryRoot: repositoryRoot,
    flutter: flutter ?? _findFlutter(required: false),
    adb: adb,
    device: device,
    sceneId: sceneId,
    screenshotWidth: comparison.width,
    screenshotHeight: comparison.height,
  );
  await writeVisualReport(
    outputDirectory: outputDirectory,
    comparison: comparison,
    minimumSimilarity: minimumSimilarity,
    sceneId: sceneId,
    metadata: metadata,
  );

  final reportPath = path.join(outputDirectory.path, 'index.html');
  final similarity = (comparison.similarity * 100).toStringAsFixed(3);
  final strictSimilarity = (comparison.strictSimilarity * 100).toStringAsFixed(
    3,
  );
  final required = (minimumSimilarity * 100).toStringAsFixed(3);
  final primaryLabel = comparison.options.includeAntiAlias
      ? 'Strict similarity'
      : 'AA-adjusted similarity';
  stdout
    ..writeln('\n$primaryLabel: $similarity% (required $required%)')
    ..writeln('Strict similarity: $strictSimilarity%')
    ..writeln('Report: $reportPath');
  return comparison.similarity >= minimumSimilarity ? 0 : 1;
}

String? _resolvePrebuiltApk(String? option, String repositoryRoot) {
  if (option == null) return null;
  return path.isAbsolute(option)
      ? path.normalize(option)
      : path.normalize(path.join(repositoryRoot, option));
}

double _parseFraction(String raw, String optionName) {
  final value = double.tryParse(raw);
  if (value == null || value < 0 || value > 1) {
    throw FormatException('--$optionName must be a number from 0 to 1');
  }
  return value;
}

Future<void> _removeStaleFile(File file) async {
  if (await file.exists()) await file.delete();
}

Future<void> _forceStop(String adb, String device, String applicationId) async {
  try {
    await Process.run(adb, <String>[
      '-s',
      device,
      'shell',
      'am',
      'force-stop',
      applicationId,
    ]);
  } on ProcessException {
    // Preserve the original drive result if cleanup cannot contact the device.
  }
}

String _findFlutter({bool required = true}) {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidates = <String>[
    if (root != null) path.join(root, 'bin', _executableName('flutter')),
    ..._pathCandidates('flutter'),
  ];
  return _firstExecutable(candidates, 'flutter', required: required);
}

String _findAdb() {
  final sdkRoots = <String?>[
    Platform.environment['ANDROID_SDK_ROOT'],
    Platform.environment['ANDROID_HOME'],
    Platform.isMacOS && Platform.environment['HOME'] != null
        ? path.join(Platform.environment['HOME']!, 'Library/Android/sdk')
        : null,
  ];
  final candidates = <String>[
    for (final root in sdkRoots)
      if (root != null)
        path.join(root, 'platform-tools', _executableName('adb')),
    ..._pathCandidates('adb'),
  ];
  return _firstExecutable(candidates, 'adb');
}

String _firstExecutable(
  List<String> candidates,
  String name, {
  bool required = true,
}) {
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  if (!required) return name;
  throw StateError('$name executable not found');
}

Iterable<String> _pathCandidates(String name) sync* {
  final pathValue = Platform.environment['PATH'];
  if (pathValue == null) return;
  for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isNotEmpty) {
      yield path.join(directory, _executableName(name));
    }
  }
}

String _executableName(String name) => Platform.isWindows ? '$name.bat' : name;

Future<String> _selectDevice(String adb) async {
  final result = await Process.run(adb, const <String>['devices', '-l']);
  if (result.exitCode != 0) {
    throw ProcessException(adb, const <String>['devices', '-l'], result.stderr);
  }
  final devices = LineSplitter.split(result.stdout as String)
      .skip(1)
      .where((line) => line.contains(RegExp(r'\sdevice(?:\s|$)')))
      .map((line) => line.split(RegExp(r'\s+')).first)
      .toList(growable: false);
  if (devices.length != 1) {
    throw StateError(
      devices.isEmpty
          ? 'no Android device is connected'
          : 'multiple Android devices are connected; pass --device',
    );
  }
  return devices.single;
}

Future<void> _runLogged(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required File logFile,
  Map<String, String> environment = const <String, String>{},
}) async {
  await logFile.parent.create(recursive: true);
  final sink = logFile.openWrite();
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).forEach((chunk) {
    stdout.write(chunk);
    sink.write(chunk);
  });
  final stderrFuture = process.stderr.transform(utf8.decoder).forEach((chunk) {
    stderr.write(chunk);
    sink.write(chunk);
  });
  final processExitCode = await process.exitCode;
  await Future.wait(<Future<void>>[stdoutFuture, stderrFuture]);
  await sink.flush();
  await sink.close();
  if (processExitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      'command failed; see ${logFile.path}',
      processExitCode,
    );
  }
}

Future<Map<String, Object?>> _collectMetadata({
  required String repositoryRoot,
  required String flutter,
  required String? adb,
  required String? device,
  required String sceneId,
  required int screenshotWidth,
  required int screenshotHeight,
}) async {
  final styleFile = File(
    path.join(repositoryRoot, 'e2e/visual/shared/assets/scenes/$sceneId.json'),
  );
  final metadata = <String, Object?>{
    'scene': sceneId,
    'styleSha256': sha256.convert(await styleFile.readAsBytes()).toString(),
    'maplibreGlVersion': _maplibreGlVersion,
    'repositoryCommit': await _commandOutput('git', const <String>[
      'rev-parse',
      'HEAD',
    ], workingDirectory: repositoryRoot),
    'maplibreFlutterGpuVersion': await _readPackageVersion(
      File(path.join(repositoryRoot, 'pubspec.yaml')),
    ),
    'gpuMapLibreNativeRevision': await _commandOutput(
      'git',
      const <String>['rev-parse', 'HEAD'],
      workingDirectory: path.join(repositoryRoot, 'vendor/maplibre-native'),
      fallback: 'public prebuilt / unavailable',
    ),
    'screenshotSize': '${screenshotWidth}x$screenshotHeight',
    'controlHandling': '64 logical px symmetric overscan clips native controls',
  };

  final flutterMachine = await _commandOutput(flutter, const <String>[
    '--version',
    '--machine',
  ], fallback: '');
  if (flutterMachine.isNotEmpty) {
    try {
      final decoded = jsonDecode(flutterMachine) as Map<String, dynamic>;
      metadata['flutterVersion'] = decoded['frameworkVersion'];
      metadata['dartVersion'] = decoded['dartSdkVersion'];
      metadata['flutterEngineRevision'] = decoded['engineRevision'];
    } on FormatException {
      metadata['flutterVersion'] = flutterMachine;
    }
  }

  if (adb != null && device != null) {
    metadata['deviceSerial'] = device;
    metadata['deviceModel'] = await _adbOutput(adb, device, const <String>[
      'shell',
      'getprop',
      'ro.product.model',
    ]);
    metadata['androidApi'] = await _adbOutput(adb, device, const <String>[
      'shell',
      'getprop',
      'ro.build.version.sdk',
    ]);
    metadata['displaySize'] = await _adbOutput(adb, device, const <String>[
      'shell',
      'wm',
      'size',
    ]);
    metadata['displayDensity'] = await _adbOutput(adb, device, const <String>[
      'shell',
      'wm',
      'density',
    ]);
    metadata['glesRenderer'] = await _adbOutput(adb, device, const <String>[
      'shell',
      'getprop',
      'ro.hardware.egl',
    ]);
  }
  return metadata;
}

Future<String> _readPackageVersion(File pubspec) async {
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(await pubspec.readAsString());
  return match?.group(1) ?? 'unknown';
}

Future<String> _adbOutput(String adb, String device, List<String> arguments) {
  return _commandOutput(adb, <String>['-s', device, ...arguments]);
}

Future<String> _commandOutput(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String fallback = 'unknown',
}) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode == 0) {
      return (result.stdout as String).trim();
    }
  } on ProcessException {
    // Metadata collection must not hide the visual comparison result.
  }
  return fallback;
}

class _VisualApplication {
  const _VisualApplication({
    required this.label,
    required this.root,
    required this.applicationId,
    required this.applicationBinary,
  });

  final String label;
  final String root;
  final String applicationId;
  final String? applicationBinary;
}
