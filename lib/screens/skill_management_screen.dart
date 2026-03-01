import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/skill_registry.dart';

/// Dedicated management screen for skill packages.
class SkillManagementScreen extends StatefulWidget {
  const SkillManagementScreen({super.key});

  @override
  State<SkillManagementScreen> createState() => _SkillManagementScreenState();
}

class _SkillManagementScreenState extends State<SkillManagementScreen> {
  bool _importing = false;

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _importZip() async {
    final l10n = AppLocalizations.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    setState(() => _importing = true);
    try {
      final def = await SkillRegistry.instance.importSkillZip(filePath);
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.skillMgmt_importSuccess(def.displayName)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on SkillImportConflictException catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      // Show replace dialog
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l10n.skillMgmt_conflictTitle),
            content: Text(l10n.skillMgmt_conflictContent(e.displayName)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.common_cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l10n.skillMgmt_replace,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          );
        },
      );

      if (replace == true) {
        setState(() => _importing = true);
        try {
          final def = await SkillRegistry.instance
              .importSkillZip(filePath, overwrite: true);
          if (mounted) {
            setState(() => _importing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.skillMgmt_importSuccess(def.displayName)),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e2) {
          if (mounted) {
            setState(() => _importing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.skillMgmt_importFailed('$e2')),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.skillMgmt_importFailed('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> _deleteSkill(SkillDefinition skill) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.skillMgmt_deleteTitle),
          content: Text(l10n.skillMgmt_deleteContent(skill.displayName)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l10n.common_delete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await SkillRegistry.instance.deleteSkill(skill.toolName);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.skillMgmt_deleted(skill.displayName)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.skillMgmt_deleteFailed('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Rescan
  // ---------------------------------------------------------------------------

  Future<void> _rescan() async {
    await SkillRegistry.instance.rescan();
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final skills = SkillRegistry.instance.skills;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.skillMgmt_title),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.skillMgmt_rescan,
            onPressed: _rescan,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ----- Import button -----
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _importing ? null : _importZip,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_upload_outlined),
              label: Text(
                _importing
                    ? l10n.skillMgmt_importing
                    : l10n.skillMgmt_importZip,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ----- Skills list or empty state -----
          if (skills.isEmpty)
            _buildEmptyState(
              context,
              icon: Icons.auto_stories_outlined,
              message: l10n.skillMgmt_noSkills,
              hint: l10n.skillMgmt_noSkillsHint,
            )
          else ...[
            // Skill count header
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.skillMgmt_skillCount(skills.length),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Skill cards
            ...skills.map((skill) => _buildSkillCard(context, skill)),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String message,
    required String hint,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 64, color: colorScheme.outline.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillCard(BuildContext context, SkillDefinition skill) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_stories, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    skill.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: colorScheme.error),
                  tooltip: l10n.common_delete,
                  onPressed: () => _deleteSkill(skill),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              skill.description,
              style: TextStyle(fontSize: 13, color: colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    skill.toolName,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (skill.fileCount > 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.skillMgmt_fileCount(skill.fileCount),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
