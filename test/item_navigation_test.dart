import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/providers/item_navigation_provider.dart';

void main() {
  test('parses task and event targets from the existing locus link', () {
    expect(
      itemTargetFromUri(Uri.parse('locus://open?kind=task&id=T7')),
      const ItemTarget(kind: ItemKind.task, id: 'T7'),
    );
    expect(
      itemTargetFromUri(Uri.parse('locus://open?kind=event&id=E1')),
      const ItemTarget(kind: ItemKind.event, id: 'E1'),
    );
  });

  test('ignores unknown, incomplete and unrelated links', () {
    expect(itemTargetFromUri(Uri.parse('locus://open?kind=note&id=1')), isNull);
    expect(itemTargetFromUri(Uri.parse('locus://open?id=T1')), isNull);
    expect(
      itemTargetFromUri(Uri.parse('https://open?kind=task&id=T1')),
      isNull,
    );
    expect(itemTargetFromUri(Uri.parse('locus://snooze?id=x')), isNull);
  });

  test('a repeated activation for the same item is observable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(itemActivationProvider.notifier);
    const target = ItemTarget(kind: ItemKind.task, id: 'T1');
    notifier.activate(target);
    final first = container.read(itemActivationProvider)!;
    notifier.activate(target);
    final second = container.read(itemActivationProvider)!;
    expect(first.target, target);
    expect(second.target, target);
    expect(second.sequence, greaterThan(first.sequence));
  });

  test('the shell publishes only after the lock is open', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(itemOpenRequestProvider.notifier)
        .publish(const ItemTarget(kind: ItemKind.event, id: 'E1'));
    final delivered = container.read(itemOpenRequestProvider)!;
    expect(delivered.target.id, 'E1');
    container
        .read(itemOpenRequestProvider.notifier)
        .consume(delivered.sequence);
    expect(container.read(itemOpenRequestProvider), isNull);
  });
}
