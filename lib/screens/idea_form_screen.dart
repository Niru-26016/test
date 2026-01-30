import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/idea.dart';
import '../models/feature.dart';
import '../services/ideas_service.dart';
import '../widgets/feature_chip.dart';

/// Form screen for creating or editing an idea
class IdeaFormScreen extends StatefulWidget {
  final Idea? idea;

  const IdeaFormScreen({super.key, this.idea});

  @override
  State<IdeaFormScreen> createState() => _IdeaFormScreenState();
}

class _IdeaFormScreenState extends State<IdeaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  final _ideasService = IdeasService();

  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late IdeaType _selectedType;
  late List<Feature> _features;
  late bool _isPublic;

  bool get _isEditing => widget.idea != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.idea?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.idea?.description ?? '',
    );
    _selectedType = widget.idea?.type ?? IdeaType.both;
    _features = List.from(widget.idea?.features ?? []);
    _isPublic = widget.idea?.isPublic ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveIdea() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return; // Prevent double-tap

    setState(() => _isSaving = true);

    final now = DateTime.now();
    final idea = Idea(
      id: widget.idea?.id ?? _uuid.v4(),
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
      type: _selectedType,
      features: _features,
      createdAt: widget.idea?.createdAt ?? now,
      updatedAt: now,
      isPublic: _isPublic,
      ownerId: widget.idea?.ownerId,
      ownerName: widget.idea?.ownerName,
      stage: widget.idea?.stage ?? IdeaStage.ideation,
    );

    try {
      await _ideasService.saveIdea(idea);

      if (mounted) {
        setState(() => _isSaving = false);
        // Show success SnackBar BEFORE popping
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(_isEditing ? 'Idea updated!' : 'Idea created!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving idea: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'Failed to update idea: $e'
                  : 'Failed to create idea: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Show top toast notification
  void _showTopToast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 200),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -20 * (1 - value)),
                child: child,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(message, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
    });
  }

  void _showAddFeatureDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final nameFocusNode = FocusNode();
    Priority selectedPriority = Priority.medium;
    bool isNameEmpty = true;
    int addedCount = 0;

    // Collect features locally, sync to parent only when dialog closes
    final List<Feature> newFeatures = [];

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismiss
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void addFeature() {
            final feature = Feature(
              id: _uuid.v4(),
              name: nameController.text.trim(),
              description: descController.text.trim(),
              priority: selectedPriority,
              // Status defaults to backlog for new features
            );

            // Add to LOCAL list (not parent's _features yet)
            newFeatures.add(feature);

            // Haptic feedback
            HapticFeedback.lightImpact();

            // Show toast on parent context
            _showTopToast(context, 'Feature added');

            // Clear inputs for next entry
            nameController.clear();
            descController.clear();
            setDialogState(() {
              selectedPriority = Priority.medium;
              isNameEmpty = true;
              addedCount++;
            });

            // Re-focus name field
            nameFocusNode.requestFocus();
          }

          void closeDialog() {
            // Auto-add pending feature if name is filled
            final pendingName = nameController.text.trim();
            if (pendingName.isNotEmpty) {
              final pendingFeature = Feature(
                id: _uuid.v4(),
                name: pendingName,
                description: descController.text.trim(),
                priority: selectedPriority,
                // Status defaults to backlog
              );
              newFeatures.add(pendingFeature);
            }

            // Sync all new features to parent when closing
            if (newFeatures.isNotEmpty) {
              setState(() => _features.addAll(newFeatures));
            }
            nameFocusNode.dispose();
            Navigator.pop(dialogContext);
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(dialogContext).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Add Features'),
              ],
            ),
            content: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom > 0
                      ? 16
                      : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Feature name with helper text
                    TextField(
                      controller: nameController,
                      focusNode: nameFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Feature name',
                        hintText: 'e.g. User login, Dark mode',
                        helperText: 'One small capability of your idea',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) {
                        final empty = value.trim().isEmpty;
                        if (empty != isNameEmpty) {
                          setDialogState(() => isNameEmpty = empty);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Description field
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What does this feature do?',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),

                    // Priority selector
                    const Text('Priority'),
                    const SizedBox(height: 8),
                    Center(
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        isSelected: [
                          selectedPriority == Priority.low,
                          selectedPriority == Priority.medium,
                          selectedPriority == Priority.high,
                        ],
                        onPressed: (index) {
                          setDialogState(() {
                            selectedPriority = Priority.values[index];
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward, size: 16),
                                SizedBox(width: 4),
                                Text('Low'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 16),
                                SizedBox(width: 4),
                                Text('Med'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward, size: 16),
                                SizedBox(width: 4),
                                Text('High'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: closeDialog,
                child: Text(addedCount > 0 ? 'Done' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: isNameEmpty ? null : addFeature,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeFeature(Feature feature) {
    setState(() {
      _features.removeWhere((f) => f.id == feature.id);
    });
  }

  void _showEditFeatureDialog(Feature feature, int index) {
    final nameController = TextEditingController(text: feature.name);
    final descController = TextEditingController(text: feature.description);
    Priority selectedPriority = feature.priority;
    FeatureStatus selectedStatus = feature.status;
    bool isNameEmpty = feature.name.trim().isEmpty;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Edit Feature'),
              ],
            ),
            content: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 16 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Feature name',
                        hintText: 'e.g. User login, Dark mode',
                        helperText: 'One small capability of your idea',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) {
                        final empty = value.trim().isEmpty;
                        if (empty != isNameEmpty) {
                          setDialogState(() => isNameEmpty = empty);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What does this feature do?',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    const Text('Priority'),
                    const SizedBox(height: 8),
                    Center(
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        isSelected: [
                          selectedPriority == Priority.low,
                          selectedPriority == Priority.medium,
                          selectedPriority == Priority.high,
                        ],
                        onPressed: (index) {
                          setDialogState(() {
                            selectedPriority = Priority.values[index];
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward, size: 16),
                                SizedBox(width: 4),
                                Text('Low'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 16),
                                SizedBox(width: 4),
                                Text('Med'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward, size: 16),
                                SizedBox(width: 4),
                                Text('High'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Status selector
                    const Text('Status'),
                    const SizedBox(height: 8),
                    Center(
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        isSelected: [
                          selectedStatus == FeatureStatus.backlog,
                          selectedStatus == FeatureStatus.inProgress,
                          selectedStatus == FeatureStatus.done,
                        ],
                        onPressed: (index) {
                          setDialogState(() {
                            selectedStatus = FeatureStatus.values[index];
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox, size: 16),
                                SizedBox(width: 4),
                                Text('Backlog'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_circle, size: 16),
                                SizedBox(width: 4),
                                Text('Active'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 16),
                                SizedBox(width: 4),
                                Text('Done'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: isNameEmpty
                    ? null
                    : () {
                        final updatedFeature = Feature(
                          id: feature.id,
                          name: nameController.text.trim(),
                          description: descController.text.trim(),
                          priority: selectedPriority,
                          status: selectedStatus,
                        );
                        setState(() => _features[index] = updatedFeature);
                        Navigator.pop(context);
                      },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Idea' : 'New Idea'),
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : TextButton.icon(
                  onPressed: _saveIdea,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero Name field
            TextFormField(
              controller: _nameController,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Idea Name',
                hintText: 'Short, clear title...',
                hintStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey.shade400,
                ),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lightbulb_outline),
                counterText: '', // Hide character counter
              ),
              maxLength: 60,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name';
                }
                return null;
              },
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 4),
            Text(
              'Keep it short & memorable',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Description field with AI button
            Stack(
              children: [
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe your idea...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Type selector
            Text('Platform', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Where will your idea run?',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 12),
            SegmentedButton<IdeaType>(
              segments: const [
                ButtonSegment(
                  value: IdeaType.website,
                  label: Text(' Web'),
                  icon: Icon(Icons.language),
                ),
                ButtonSegment(
                  value: IdeaType.mobile,
                  label: Text(' Mobile'),
                  icon: Icon(Icons.phone_android),
                ),
                ButtonSegment(
                  value: IdeaType.both,
                  label: Text(' Both'),
                  icon: Icon(Icons.devices),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (Set<IdeaType> selected) {
                setState(() => _selectedType = selected.first);
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Share with community toggle
            Card(
              child: SwitchListTile(
                title: const Text('Share with Community'),
                subtitle: Text(
                  _isPublic
                      ? 'Your idea is visible to everyone in Discovery'
                      : 'Only you can see this idea',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _isPublic,
                onChanged: (value) {
                  setState(() => _isPublic = value);
                },
                secondary: Icon(
                  _isPublic ? Icons.public : Icons.lock_outline,
                  color: _isPublic ? Colors.green : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Features section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Features',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter an idea name first'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    _showAddFeatureDialog();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_features.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.featured_play_list_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No features yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Add" to add features to your idea',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _features.length,
                itemBuilder: (context, index) {
                  final feature = _features[index];
                  return Card(
                    key: ValueKey(feature.id),
                    child: ListTile(
                      leading: const Icon(Icons.drag_handle),
                      title: FeatureChip(feature: feature),
                      subtitle: feature.description.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                feature.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _showEditFeatureDialog(feature, index),
                            tooltip: 'Edit feature',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeFeature(feature),
                            tooltip: 'Delete feature',
                          ),
                        ],
                      ),
                      onTap: () => _showEditFeatureDialog(feature, index),
                    ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _features.removeAt(oldIndex);
                    _features.insert(newIndex, item);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
