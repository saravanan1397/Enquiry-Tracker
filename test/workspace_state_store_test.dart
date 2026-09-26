import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/workspace_state_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('admin workspace reopens the last selected widget', () async {
    const store = WorkspaceStateStore();

    expect(await store.readOwnerView(), OwnerWorkspaceView.dashboard);
    await store.writeOwnerView(OwnerWorkspaceView.sales);

    expect(await store.readOwnerView(), OwnerWorkspaceView.sales);
  });

  test('admin logout resets the next login to the widgets home page', () async {
    const store = WorkspaceStateStore();

    await store.writeOwnerView(OwnerWorkspaceView.sales);
    await store.writeSalesRecycleBin(true);
    await store.writeFollowupRecycleBin(true);
    await store.writePromoterRecycleBin(true);
    await store.resetAdminWorkspace();

    expect(await store.readOwnerView(), OwnerWorkspaceView.dashboard);
    expect(await store.readSalesRecycleBin(), isFalse);
    expect(await store.readFollowupRecycleBin(), isFalse);
    expect(await store.readPromoterRecycleBin(), isFalse);
  });

  test('sales month and recycle-bin view survive reload state restoration',
      () async {
    const store = WorkspaceStateStore();

    await store.writeSalesMonth('2026-08');
    await store.writeSalesRecycleBin(true);
    await store.writeFollowupRecycleBin(true);
    await store.writePromoterRecycleBin(true);

    expect(await store.readSalesMonth(), '2026-08');
    expect(await store.readSalesRecycleBin(), isTrue);
    expect(await store.readFollowupRecycleBin(), isTrue);
    expect(await store.readPromoterRecycleBin(), isTrue);
  });
}
