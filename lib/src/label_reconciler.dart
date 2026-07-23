import 'native/maplibre_ffi.dart';

const int _invalidCrossTileId = 0xffffffff;

/// Mutable presentation state for one MapLibre-placed symbol.
class LabelReconcileEntry {
  LabelData data;
  bool visible;
  bool appeared;

  LabelReconcileEntry({
    required this.data,
    required this.visible,
    this.appeared = false,
  });
}

/// Reconciles a placement snapshot using MapLibre's cross-tile identity.
///
/// Valid identities use `layerID:crossTileID` exactly. MapLibre reserves zero
/// and UINT32_MAX as invalid identities. Those values receive a negative,
/// generation-scoped key so duplicate invalid symbols never collide and a
/// later snapshot can never reuse a fading entry as a different symbol.
void reconcileLabelEntries(
  Map<String, LabelReconcileEntry> entries,
  Iterable<LabelData> labels, {
  required int fallbackGeneration,
}) {
  assert(fallbackGeneration >= 0);

  // Missing symbols stay for one placement snapshot so the overlay can fade
  // them out. A symbol outside the viewport has no fade widget, though, so its
  // completion callback never runs. Expire entries that were already missing,
  // unless this snapshot revives them, to bound the cache to two snapshots.
  final expiringKeys = entries.entries
      .where((entry) => !entry.value.visible)
      .map((entry) => entry.key)
      .toList(growable: false);
  final seen = <String>{};
  var fallbackOrdinal = 0;

  for (final label in labels) {
    final id = label.crossTileId;
    final hasStableId = id != 0 && id != _invalidCrossTileId;
    final String key;
    if (hasStableId) {
      key = '${label.layer}:$id';
    } else {
      // The final key segment is negative, while every valid uint32 ID is
      // positive. This remains collision-free even if a layer ID has colons.
      key = '${label.layer}:-${fallbackGeneration + 1}-$fallbackOrdinal';
      fallbackOrdinal++;
    }

    final existing = entries[key];
    if (existing == null) {
      entries[key] = LabelReconcileEntry(data: label, visible: true);
    } else {
      // The latest placement is authoritative. In particular, anchors and
      // text/icon placement flags must not be retained or OR-ed across frames.
      existing
        ..data = label
        ..visible = true;
    }
    seen.add(key);
  }

  for (final key in expiringKeys) {
    if (!seen.contains(key)) entries.remove(key);
  }
  for (final entry in entries.entries) {
    if (!seen.contains(entry.key)) entry.value.visible = false;
  }
}
