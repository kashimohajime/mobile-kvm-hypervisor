// lib/screens/vm_snapshots_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/vm_model.dart';
import '../providers/vm_provider.dart';

class VmSnapshotsScreen extends StatefulWidget {
  final String vmName;

  const VmSnapshotsScreen({super.key, required this.vmName});

  @override
  State<VmSnapshotsScreen> createState() => _VmSnapshotsScreenState();
}

class _VmSnapshotsScreenState extends State<VmSnapshotsScreen> {
  @override
  void initState() {
    super.initState();
    // Charger les snapshots au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmProvider>().fetchSnapshots(widget.vmName);
    });
  }

  Future<void> _createSnapshot() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau Snapshot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Nom du snapshot',
                hintText: 'ex: backup-pre-update',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty) {
      if (!mounted) return;
      try {
        final provider = context.read<VmProvider>();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Création du snapshot en cours...')),
        );
        await provider.createSnapshot(
          widget.vmName,
          nameController.text,
          descController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot créé avec succès')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _revertSnapshot(VmSnapshot snapshot) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurer le snapshot ?'),
        content: Text(
            'Attention : L\'état actuel de la VM "${widget.vmName}" sera perdu et remplacé par l\'état du snapshot "${snapshot.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        await context
            .read<VmProvider>()
            .revertSnapshot(widget.vmName, snapshot.name);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VM restaurée avec succès')),
        );
        Navigator.pop(
            context); // Retour à l'écran détail car la VM a pu changer d'état
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur de restauration: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSnapshot(VmSnapshot snapshot) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le snapshot ?'),
        content: Text(
            'Voulez-vous vraiment supprimer le snapshot "${snapshot.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      try {
        await context
            .read<VmProvider>()
            .deleteSnapshot(widget.vmName, snapshot.name);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot supprimé')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur suppression: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Snapshots : ${widget.vmName}'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createSnapshot,
        child: const Icon(Icons.add_a_photo),
      ),
      body: Consumer<VmProvider>(
        builder: (context, provider, child) {
          if (provider.snapshotsState == LoadingState.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.snapshotsState == LoadingState.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Erreur : ${provider.snapshotsError}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => provider.fetchSnapshots(widget.vmName),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }

          if (provider.snapshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_album_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Aucun snapshot disponible'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.snapshots.length,
            itemBuilder: (context, index) {
              final snap = provider.snapshots[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.history),
                  ),
                  title: Text(snap.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${snap.formattedDate} • ${snap.state}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (snap.isCurrent)
                        const Chip(
                            label: Text('Actuel'),
                            backgroundColor: Colors.greenAccent),
                      if (!snap.isCurrent) ...[
                        IconButton(
                          icon: const Icon(Icons.restore, color: Colors.orange),
                          tooltip: 'Restaurer',
                          onPressed: () => _revertSnapshot(snap),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Supprimer',
                          onPressed: () => _deleteSnapshot(snap),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
