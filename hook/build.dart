// Copyright (c) 2025, Your Name. All rights reserved.
// Build hook for aubio native assets integration

import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:yaml/yaml.dart';

/// Implements the protocol from `package:native_assets_cli` by building
/// the aubio C library and reporting what native assets it built.
final logger = Logger("")
  ..level = Level.ALL
  ..onRecord.listen((record) => stderr.writeln(record.message));
void main(List<String> args) async {
  await build(args, _builder);
}

Future<void> _builder(BuildInput input, BuildOutputBuilder output) async {
  final packageName = input.packageName;
  final packagePath = Uri.directory(await getPackagePath(packageName));
  final sourceDir = packagePath.resolve('src/');

  // Parse configuration from pubspec.yaml
  final config = _parseConfig(packagePath);

  // Get platform-specific defines
  final defines = _getPlatformDefines(input.config.code.targetOS, config);
  final options = (config['options'] as YamlMap?)?.value ?? {};

  logger.info("Building aubio with defines: $defines");
  logger.info("Build options: $options");

  // Create CMake builder
  final builder = CMakeBuilder.create(
    name: packageName,
    sourceDir: sourceDir,
    generator: input.config.code.targetOS == OS.android
        ? Generator.ninja
        : Generator.ninja,
    targets: ['install'],
    defines: {
      'CMAKE_INSTALL_PREFIX': input.outputDirectory
          .resolve('install')
          .toFilePath()
          .replaceAll(r'\', '/'),
      ...defines,
    },
    buildLocal: options['build_local'] as bool? ?? false,
  );

  // Build the native library
  await builder.run(input: input, output: output, logger: logger);

  // Find and register the built library
  await output.findAndAddCodeAssets(
    input,
    outDir: input.outputDirectory.resolve('install'),
    // names: {r'(lib)?aubio\..*': 'aubio_bindings.dart'},
    names: {
      // Match aubio library files with various possible names
      r'(lib)?aubio(\.dll|\.so|\.dylib)$': 'aubio_bindings.dart',
      r'aubio\.dll$': 'aubio.dart',
      r'libaubio\.so$': 'aubio.dart',
      r'libaubio\.dylib$': 'aubio.dart',
    },
    regExp: true,
  );
}

/// Parse configuration from pubspec.yaml
YamlMap _parseConfig(Uri packagePath) {
  final pubspecFile = File(packagePath.resolve('pubspec.yaml').toFilePath());
  if (!pubspecFile.existsSync()) {
    return YamlMap();
  }

  final content = pubspecFile.readAsStringSync();
  final yaml = loadYaml(content) as Map;
  return yaml['aubio_config'] as YamlMap? ?? YamlMap();
}

/// Get platform-specific CMake defines
Map<String, String> _getPlatformDefines(OS targetOS, YamlMap config) {
  final defines = <String, String>{};

  // Add common defines
  final commonDefines = (config['defines']?['common'] as YamlMap?)?.value ?? {};
  commonDefines.forEach((key, value) {
    defines[key] = value.toString();
  });

  // Add platform-specific defines
  final platformKey = switch (targetOS) {
    OS.android => 'android',
    OS.iOS => 'ios',
    OS.linux => 'linux',
    OS.macOS => 'macos',
    OS.windows => 'windows',
    _ => null,
  };

  if (platformKey != null) {
    final platformDefines =
        (config['defines']?[platformKey] as YamlMap?)?.value ?? {};
    platformDefines.forEach((key, value) {
      defines[key] = value.toString();
    });
  }

  return defines;
}
