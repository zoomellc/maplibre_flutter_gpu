/// Chooses a visible style layer that makes a useful toggle demonstration.
String? chooseToggleLayer(List<String> layerIds) {
  if (layerIds.isEmpty) return null;
  for (final layerId in layerIds.reversed) {
    final normalized = layerId.toLowerCase();
    if (normalized.contains('label') || normalized.contains('place')) {
      return layerId;
    }
  }
  return layerIds.last;
}
