/// Skill Registry — markdown-based instruction sets for local LLM agents.
///
/// Skills are subdirectories (each containing a main `.md` file + auxiliary
/// scripts) under the app's default skills directory. Legacy single `.md`
/// files in the top-level directory are also supported for backward
/// compatibility.
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when importing a skill ZIP whose name conflicts with an existing skill.
class SkillImportConflictException implements Exception {
  final String existingToolName;
  final String displayName;
  SkillImportConflictException(this.existingToolName, this.displayName);

  @override
  String toString() =>
      'SkillImportConflictException: skill "$displayName" ($existingToolName) already exists';
}

/// Describes a single skill parsed from a subdirectory or markdown file.
class SkillDefinition {
  /// Tool name used in function-calling (e.g. `skill_code_review`).
  final String toolName;

  /// Human-readable name extracted from the first `# ` heading.
  final String displayName;

  /// Brief description (first non-blank line after the heading).
  final String description;

  /// Absolute path to the main `.md` file.
  final String filePath;

  /// Absolute path to the skill's subdirectory (or parent dir for legacy files).
  final String directoryPath;

  /// Total number of files in the skill directory.
  final int fileCount;

  const SkillDefinition({
    required this.toolName,
    required this.displayName,
    required this.description,
    required this.filePath,
    required this.directoryPath,
    required this.fileCount,
  });
}

/// Central registry for markdown-based skills.
class SkillRegistry {
  SkillRegistry._();
  static final SkillRegistry instance = SkillRegistry._();

  String _directoryPath = '';
  List<SkillDefinition> _skills = [];

  /// Absolute path to the skills directory.
  String get directoryPath => _directoryPath;

  /// All currently loaded skill definitions.
  List<SkillDefinition> get skills => List.unmodifiable(_skills);

  /// All skill tool names.
  Set<String> get allSkillNames => _skills.map((s) => s.toolName).toSet();

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Resolves the default skills directory under the app's documents path
  /// and performs the initial scan. Call once at app startup.
  Future<void> initialize() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final skillsDir =
        Directory(p.join(docsDir.path, 'ai_agent_hub', 'skills'));
    if (!await skillsDir.exists()) {
      await skillsDir.create(recursive: true);
    }
    _directoryPath = skillsDir.path;
    await rescan();
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Re-scans the skills directory for skill packages (subdirectories)
  /// and legacy top-level `.md` files.
  Future<void> rescan() async {
    _skills = [];
    if (_directoryPath.isEmpty) return;

    final dir = Directory(_directoryPath);
    if (!await dir.exists()) return;

    try {
      final seenToolNames = <String>{};

      // 1. Scan subdirectories first — each subdir is a skill package
      final entries = dir.listSync();
      final subDirs = entries.whereType<Directory>().toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final subDir in subDirs) {
        final def = await _parseSkillDirectory(subDir);
        if (def != null && !seenToolNames.contains(def.toolName)) {
          _skills.add(def);
          seenToolNames.add(def.toolName);
        }
      }

      // 2. Legacy fallback: top-level .md files
      final mdFiles = entries.whereType<File>().where(
            (f) => f.path.endsWith('.md'),
          ).toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      for (final file in mdFiles) {
        final def = await _parseSkillFile(file);
        if (def != null && !seenToolNames.contains(def.toolName)) {
          _skills.add(def);
          seenToolNames.add(def.toolName);
        }
      }

      // Sort by display name for stable UI ordering
      _skills.sort((a, b) => a.displayName.compareTo(b.displayName));
    } catch (e) {
      // Silently ignore scan errors (permission issues, etc.)
      print('[SkillRegistry] rescan error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Import / Delete
  // ---------------------------------------------------------------------------

  /// Imports a skill from a ZIP file.
  ///
  /// Extracts the ZIP, finds the main `.md`, and copies files to the skill
  /// directory. Throws [SkillImportConflictException] if a skill with the
  /// same name already exists and [overwrite] is false.
  ///
  /// Returns the new [SkillDefinition] on success.
  Future<SkillDefinition> importSkillZip(
    String zipPath, {
    bool overwrite = false,
  }) async {
    if (_directoryPath.isEmpty) {
      throw Exception('Skill registry not initialized');
    }

    // Extract to a temp directory
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final tempDir = await Directory.systemTemp.createTemp('skill_import_');
    try {
      for (final entry in archive) {
        final filePath = p.join(tempDir.path, entry.name);
        if (entry.isFile) {
          final outFile = File(filePath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(entry.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      // Handle single top-level folder pattern: if there's exactly one
      // subdirectory and no other files at root, use its contents.
      Directory contentDir = tempDir;
      final tempEntries = tempDir.listSync();
      final tempSubDirs = tempEntries.whereType<Directory>().toList();
      final tempFiles = tempEntries.whereType<File>().toList();
      if (tempSubDirs.length == 1 && tempFiles.isEmpty) {
        contentDir = tempSubDirs.first;
      }

      // Find the main .md file (alphabetically first)
      final mdFiles = contentDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      if (mdFiles.isEmpty) {
        throw Exception('No .md file found in the ZIP archive');
      }

      // Parse the main .md to derive the skill name
      final mainMd = mdFiles.first;
      final content = await mainMd.readAsString();
      final displayName = _extractDisplayName(content);
      if (displayName == null) {
        throw Exception('No # heading found in the main .md file');
      }

      final toolName = 'skill_${_sanitizeName(displayName)}';

      // Check for name conflicts
      final existing = getDefinition(toolName);
      if (existing != null && !overwrite) {
        throw SkillImportConflictException(toolName, displayName);
      }

      // Destination directory
      final destName = _sanitizeName(displayName);
      final destDir = Directory(p.join(_directoryPath, destName));

      // If overwriting, remove existing directory first
      if (await destDir.exists()) {
        await destDir.delete(recursive: true);
      }
      await destDir.create(recursive: true);

      // Copy all files from contentDir to destDir
      await _copyDirectory(contentDir, destDir);

      // Rescan to pick up the new skill
      await rescan();

      final newDef = getDefinition(toolName);
      if (newDef == null) {
        throw Exception('Imported skill not found after rescan');
      }
      return newDef;
    } finally {
      // Clean up temp directory
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Deletes a skill by removing its directory and rescanning.
  Future<void> deleteSkill(String toolName) async {
    final def = getDefinition(toolName);
    if (def == null) return;

    final dir = Directory(def.directoryPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    await rescan();
  }

  // ---------------------------------------------------------------------------
  // Lookups
  // ---------------------------------------------------------------------------

  /// Whether [name] is a registered skill tool.
  bool isSkillTool(String name) => _skills.any((s) => s.toolName == name);

  /// Lookup a definition by tool name, or null.
  SkillDefinition? getDefinition(String toolName) {
    for (final s in _skills) {
      if (s.toolName == toolName) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Content reading
  // ---------------------------------------------------------------------------

  /// Reads the full markdown content of a skill at call time (not cached).
  Future<String> readSkillContent(String toolName) async {
    final def = getDefinition(toolName);
    if (def == null) return 'Error: skill "$toolName" not found.';
    try {
      final file = File(def.filePath);
      return await file.readAsString();
    } catch (e) {
      return 'Error reading skill file: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // LLM tool formats
  // ---------------------------------------------------------------------------

  /// Returns skills in OpenAI function-calling format.
  List<Map<String, dynamic>> openAITools({Set<String>? enabledSkills}) {
    return _filteredSkills(enabledSkills)
        .map((s) => <String, dynamic>{
              'type': 'function',
              'function': {
                'name': s.toolName,
                'description':
                    '${s.description} — Call this tool to receive detailed instructions for the "${s.displayName}" skill.',
                'parameters': {'type': 'object', 'properties': {}},
              },
            })
        .toList();
  }

  /// Returns skills in Claude (Anthropic) format.
  List<Map<String, dynamic>> claudeTools({Set<String>? enabledSkills}) {
    return _filteredSkills(enabledSkills)
        .map((s) => <String, dynamic>{
              'name': s.toolName,
              'description':
                  '${s.description} — Call this tool to receive detailed instructions for the "${s.displayName}" skill.',
              'input_schema': {'type': 'object', 'properties': {}},
            })
        .toList();
  }

  /// System prompt suffix describing available skills.
  String systemPromptSuffix(Set<String> enabledSkills) {
    final filtered = _filteredSkills(enabledSkills);
    if (filtered.isEmpty) return '';
    final skillLines = filtered
        .map((s) => '- ${s.toolName}: ${s.description}')
        .join('\n');
    return '''

You also have access to skill tools. Each skill provides detailed step-by-step instructions for a specific task.
When you need to perform one of these tasks, call the corresponding skill tool to receive the full instructions.
Available skills:
$skillLines''';
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Iterable<SkillDefinition> _filteredSkills(Set<String>? enabledSkills) {
    if (enabledSkills == null) return _skills;
    return _skills.where((s) => enabledSkills.contains(s.toolName));
  }

  /// Parses a skill subdirectory into a [SkillDefinition].
  ///
  /// Finds the alphabetically first `.md` file, extracts metadata from it,
  /// and counts all files in the directory recursively.
  Future<SkillDefinition?> _parseSkillDirectory(Directory dir) async {
    try {
      // Find all .md files in the directory (non-recursive — main .md at top level)
      final mdFiles = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      if (mdFiles.isEmpty) return null;

      final mainFile = mdFiles.first;
      final content = await mainFile.readAsString();
      final lines = content.split('\n');

      // Extract display name from first `# ` heading
      String? displayName;
      int headingIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
          displayName = trimmed.substring(2).trim();
          headingIndex = i;
          break;
        }
      }

      if (displayName == null || displayName.isEmpty) return null;

      // Extract description: first non-blank line after the heading
      String description = displayName; // fallback
      for (int i = headingIndex + 1; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.isNotEmpty) {
          description = trimmed;
          break;
        }
      }

      // Derive tool name from display name
      final toolName = 'skill_${_sanitizeName(displayName)}';

      // Count files recursively
      final fileCount = dir
          .listSync(recursive: true)
          .whereType<File>()
          .length;

      return SkillDefinition(
        toolName: toolName,
        displayName: displayName,
        description: description,
        filePath: mainFile.path,
        directoryPath: dir.path,
        fileCount: fileCount,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parses a single legacy `.md` file into a [SkillDefinition].
  Future<SkillDefinition?> _parseSkillFile(File file) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n');

      // Extract display name from first `# ` heading
      String? displayName;
      int headingIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
          displayName = trimmed.substring(2).trim();
          headingIndex = i;
          break;
        }
      }

      if (displayName == null || displayName.isEmpty) return null;

      // Extract description: first non-blank line after the heading
      String description = displayName; // fallback
      for (int i = headingIndex + 1; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.isNotEmpty) {
          description = trimmed;
          break;
        }
      }

      // Build tool name from filename
      final fileName = file.uri.pathSegments.last;
      final baseName = fileName.endsWith('.md')
          ? fileName.substring(0, fileName.length - 3)
          : fileName;
      final toolName = 'skill_${_sanitizeName(baseName)}';

      return SkillDefinition(
        toolName: toolName,
        displayName: displayName,
        description: description,
        filePath: file.path,
        directoryPath: file.parent.path,
        fileCount: 1,
      );
    } catch (e) {
      return null;
    }
  }

  /// Extracts the display name from markdown content (first `# ` heading).
  static String? _extractDisplayName(String content) {
    final lines = content.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
        final name = trimmed.substring(2).trim();
        return name.isEmpty ? null : name;
      }
    }
    return null;
  }

  /// Sanitizes a name into a valid tool name component.
  static String _sanitizeName(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Recursively copies all files from [src] to [dest].
  static Future<void> _copyDirectory(Directory src, Directory dest) async {
    for (final entity in src.listSync()) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        final newDir = Directory(destPath);
        await newDir.create(recursive: true);
        await _copyDirectory(entity, newDir);
      }
    }
  }
}
