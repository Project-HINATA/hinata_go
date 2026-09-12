import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/services/arcadelink_invocation_service.dart';
import 'package:hinata_go/services/arcadelink_api.dart';

void main() {
  final service = ArcadeLinkInvocationService.instance;

  tearDown(service.clear);

  test(
    'legacy web hints remain readable without deciding native capabilities',
    () {
      final legacy = {
        'publicId': 'device',
        'name': 'Device',
        'shop': {'name': 'Store'},
      };
      expect(ArcadeLinkMachine.fromJson(legacy).webOnly, isFalse);
      expect(
        ArcadeLinkMachine.fromJson({...legacy, 'webOnly': true}).webOnly,
        isTrue,
      );
    },
  );

  test('parses the shop and machine ids from an invocation URL', () {
    service.handleURL('https://link.neri.moe/t/shop_abc/machine_123');

    expect(service.pendingShopCode, 'shop_abc');
    expect(service.pendingPublicId, 'machine_123');
  });

  test('rejects the old machine-only URL shape', () {
    service.handleURL('https://link.neri.moe/t/machine_123');

    expect(service.pendingShopCode, isNull);
    expect(service.pendingPublicId, isNull);
  });
}
