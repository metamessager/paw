import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/model_routing_config.dart';
import '../widgets/model_routing_config_card.dart';

/// Full-page screen for configuring multi-modal model routing.
///
/// Receives the current routing map and returns the updated map
/// via [Navigator.pop].
class ModelRoutingConfigScreen extends StatefulWidget {
  final Map<ModalityType, ModelRouteConfig> routes;

  const ModelRoutingConfigScreen({super.key, required this.routes});

  @override
  State<ModelRoutingConfigScreen> createState() =>
      _ModelRoutingConfigScreenState();
}

class _ModelRoutingConfigScreenState extends State<ModelRoutingConfigScreen> {
  late Map<ModalityType, ModelRouteConfig> _routes;

  @override
  void initState() {
    super.initState();
    _routes = Map<ModalityType, ModelRouteConfig>.from(widget.routes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addAgent_configureModelRouting),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _routes),
            child: Text(l10n.common_save),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ModelRoutingConfigCard(
          routes: _routes,
          onChanged: (routes) {
            setState(() {
              _routes = routes;
            });
          },
        ),
      ),
    );
  }
}
