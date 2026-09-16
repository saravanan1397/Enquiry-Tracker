import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/sales_record.dart';
import 'services/export_file_downloader.dart';
import 'services/firebase_sales_backend.dart';
import 'services/sales_export_service.dart';

class SalesTrackerScreen extends StatefulWidget {
  const SalesTrackerScreen({
    super.key,
    required this.backend,
    required this.ownerUid,
    required this.ownerName,
  });

  final FirebaseSalesBackend backend;
  final String ownerUid;
  final String ownerName;

  @override
  State<SalesTrackerScreen> createState() => _SalesTrackerScreenState();
}

class _SalesTrackerScreenState extends State<SalesTrackerScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _salespersonSearch = TextEditingController();
  TextEditingController? _name;
  SalesPerson? _selectedPerson;
  SalesRecord? _editing;
  String? _filterPersonId;
  DateTime? _filterDate;
  DateTimeRange? _filterDateRange;
  late DateTime _selectedDate;
  late DateTime _selectedMonth;
  bool _busy = false;
  bool _backupBusy = false;
  int _visibleRecordCount = 20;

  @override
  void initState() {
    super.initState();
    final now = indiaNow();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _salespersonSearch.dispose();
    super.dispose();
  }

  String get _monthKey => salesMonthKey(_selectedMonth);

  void _changeMonth(int offset) {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    final now = indiaNow();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() {
      _selectedMonth = next;
      _selectedDate = next.year == now.year && next.month == now.month
          ? DateTime(now.year, now.month, now.day)
          : DateTime(next.year, next.month, 1);
      _cancelEdit(clearPerson: true);
      _filterPersonId = null;
      _salespersonSearch.clear();
      _filterDate = null;
      _filterDateRange = null;
      _visibleRecordCount = 20;
    });
  }

  Future<void> _pickFilterDate() async {
    final now = indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final lastDate = monthEnd.isAfter(today) ? today : monthEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? lastDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _filterDate = picked;
        _filterDateRange = null;
        _visibleRecordCount = 20;
      });
    }
  }

  Future<void> _pickFilterDateRange() async {
    final now = indiaNow();
    final today = DateTime(now.year, now.month, now.day);
    final firstDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final lastDate = monthEnd.isAfter(today) ? today : monthEnd;
    final fromDate = await showDatePicker(
      context: context,
      initialDate: _filterDateRange?.start ?? firstDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select From date',
    );
    if (fromDate == null || !mounted) return;
    final toDate = await showDatePicker(
      context: context,
      initialDate: _filterDateRange?.end.isBefore(fromDate) == false
          ? _filterDateRange!.end
          : fromDate,
      firstDate: fromDate,
      lastDate: lastDate,
      helpText: 'Select To date',
    );
    if (toDate != null && mounted) {
      setState(() {
        _filterDateRange = DateTimeRange(start: fromDate, end: toDate);
        _filterDate = null;
        _visibleRecordCount = 20;
      });
    }
  }

  void _cancelEdit({bool clearPerson = false}) {
    _editing = null;
    _amount.clear();
    _reference.clear();
    if (clearPerson) {
      _selectedPerson = null;
      _name?.clear();
    }
  }

  Future<void> _pickDate() async {
    if (_editing != null) return;
    final now = indiaNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = picked;
      _selectedMonth = DateTime(picked.year, picked.month);
    });
  }

  Future<bool> _confirmUpdate(SalesRecord existing) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update existing entry?'),
          content: Text(
            '${existing.personName} already has a sales entry for ${_displayDate(existing.salesDate)}. The previous amount will be retained in the edit history.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update existing'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addSalesperson(List<SalesPerson> people) async {
    final controller = TextEditingController();
    final requestedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add salesperson'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Salesperson name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add salesperson'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleanName = requestedName?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName == null || cleanName.isEmpty || !mounted) return;
    if (people.any(
      (person) => person.normalizedName == cleanName.toLowerCase(),
    )) {
      _message('$cleanName is already in the salesperson list.');
      return;
    }
    try {
      await widget.backend.ensurePerson(cleanName);
      if (mounted) _message('$cleanName added to the salesperson list.');
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _renameSalesperson(SalesPerson person) async {
    final controller = TextEditingController(text: person.name);
    final requestedName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit salesperson name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Salesperson name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    controller.dispose();
    final cleanName = requestedName?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName == null || cleanName.isEmpty || !mounted) return;
    try {
      await widget.backend.renamePerson(
        person: person,
        requestedName: cleanName,
      );
      if (!mounted) return;
      if (_selectedPerson?.id == person.id) {
        setState(() {
          _selectedPerson = SalesPerson(
            id: person.id,
            name: cleanName,
            normalizedName: cleanName.toLowerCase(),
            createdAt: person.createdAt,
          );
          _name?.text = cleanName;
        });
      }
      _message('Salesperson name updated. Historical sales remain linked.');
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _deactivateSalesperson(SalesPerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete salesperson?'),
        content: Text(
          'Remove ${person.name} from the active salesperson list? Existing sales records, totals, exports and backups will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Delete salesperson'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.backend.deactivatePerson(
        person: person,
        ownerUid: widget.ownerUid,
      );
      if (!mounted) return;
      if (_selectedPerson?.id == person.id) {
        setState(() {
          _selectedPerson = null;
          _name?.clear();
        });
      }
      _message(
        '${person.name} removed. Historical sales records were preserved.',
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _viewSalespersons() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salespersons'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: StreamBuilder<List<SalesPerson>>(
            stream: widget.backend.watchPeople(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final people = snapshot.data ?? const <SalesPerson>[];
              if (people.isEmpty) {
                return const Center(child: Text('No salespersons added yet.'));
              }
              return ListView.separated(
                itemCount: people.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final person = people[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        person.name.isEmpty
                            ? '?'
                            : person.name.substring(0, 1).toUpperCase(),
                      ),
                    ),
                    title: Text(person.name),
                    subtitle: Text('Person ID: ${person.id}'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Edit name',
                          onPressed: () => _renameSalesperson(person),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete salesperson',
                          onPressed: () => _deactivateSalesperson(person),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(List<SalesPerson> people, bool finalized) async {
    if (_busy || finalized) return;
    final amountMilli = parseAmountMilli(_amount.text);
    if (amountMilli == null) {
      _message('Enter a positive amount with up to 3 decimal places.');
      return;
    }
    final requestedName = _name?.text.trim() ?? '';
    if (requestedName.isEmpty) {
      _message('Enter the salesperson name.');
      return;
    }
    setState(() => _busy = true);
    try {
      final exact = people
          .where(
            (person) => person.normalizedName == requestedName.toLowerCase(),
          )
          .toList();
      final person = _editing != null
          ? _selectedPerson!
          : exact.isNotEmpty
              ? exact.first
              : await widget.backend.ensurePerson(requestedName);
      final existing = await widget.backend.findDailyRecord(
        person.id,
        _selectedDate,
      );
      var updateExisting = existing != null;
      if (existing != null && _editing?.id != existing.id) {
        updateExisting = await _confirmUpdate(existing);
        if (!updateExisting) return;
      }
      await widget.backend.saveDailyRecord(
        person: person,
        salesDate: _selectedDate,
        amountMilli: amountMilli,
        reference: _reference.text,
        ownerUid: widget.ownerUid,
        ownerName: widget.ownerName,
        updateExisting: updateExisting,
      );
      if (!mounted) return;
      setState(() {
        _selectedPerson = null;
        _name?.clear();
        _cancelEdit();
      });
      _message(
        updateExisting
            ? 'Daily sales entry updated.'
            : 'Daily sales entry saved.',
      );
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(SalesRecord record, List<SalesPerson> people) {
    final matches = people.where((person) => person.id == record.personId);
    setState(() {
      _editing = record;
      _selectedPerson = matches.isEmpty
          ? SalesPerson(
              id: record.personId,
              name: record.personName,
              normalizedName: record.personName.toLowerCase(),
            )
          : matches.first;
      _name?.text = record.personName;
      _selectedDate = record.salesDate;
      _amount.text = formatAmountMilli(record.amountMilli);
      _reference.text = record.reference;
    });
  }

  Future<void> _deleteRecord(SalesRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete sales entry?'),
        content: Text(
          'Permanently delete ${record.personName} — ${_displayDate(record.salesDate)} from the application and Firestore? GitHub backups will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.backend.deleteRecord(record.id, record.monthKey);
      if (mounted) _message('Sales entry permanently deleted from Firestore.');
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    }
  }

  Future<void> _setFinalized(bool value) async {
    await widget.backend.setFinalized(
      monthKey: _monthKey,
      finalized: value,
      ownerUid: widget.ownerUid,
    );
    if (!mounted) return;
    _message(
      value
          ? 'Month locked. Data remains available until you delete it.'
          : 'Month reopened for editing.',
    );
    if (!value) return;
    final deleteNow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep or delete this month?'),
        content: Text(
          'Incentives for $_monthKey are marked completed. Previous-month data will remain available unless you choose permanent deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep data'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to deletion'),
          ),
        ],
      ),
    );
    if (deleteNow == true && mounted) await _deleteMonth();
  }

  Future<void> _deleteMonth() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $_monthKey permanently?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This removes the selected month from the application and Firestore. GitHub backups remain until you delete them manually.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Type $_monthKey to confirm',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep data'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim() == _monthKey),
            child: const Text('Delete month'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.deleteMonth(_monthKey);
      if (mounted) _message('$_monthKey permanently deleted from Firestore.');
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(List<SalesRecord> records) async {
    if (records.isEmpty) {
      _message('There are no records to export for $_monthKey.');
      return;
    }
    final now = indiaNow();
    final bytes = SalesExportService().buildWorkbook(
      records: records,
      exportedAt: now,
    );
    final fileName =
        'Sales_Tracker_${_monthKey}_${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}.xlsx';
    await downloadExcelExport(bytes, fileName);
    if (mounted) _message('Sales Excel export downloaded.');
  }

  Future<void> _requestBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await widget.backend.requestBackup(
        monthKey: _monthKey,
        ownerUid: widget.ownerUid,
        ownerName: widget.ownerName,
      );
      if (mounted) {
        _message(
          'Backup requested. The encrypted GitHub backup will be created within about 5 minutes.',
        );
      }
    } catch (error) {
      if (mounted) _message(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SalesPerson>>(
        stream: widget.backend.watchPeople(),
        builder: (context, peopleSnapshot) {
          final people = peopleSnapshot.data ?? const <SalesPerson>[];
          return StreamBuilder<SalesMonthState>(
            stream: widget.backend.watchMonthState(_monthKey),
            builder: (context, monthSnapshot) {
              final month =
                  monthSnapshot.data ?? SalesMonthState(monthKey: _monthKey);
              return StreamBuilder<List<SalesRecord>>(
                stream: widget.backend.watchMonth(_monthKey),
                builder: (context, recordsSnapshot) {
                  final records = recordsSnapshot.data ?? const <SalesRecord>[];
                  return StreamBuilder<SalesBackupStatus?>(
                    stream: widget.backend.watchBackupStatus(),
                    builder: (context, backupSnapshot) => _body(
                      people,
                      month,
                      records,
                      backupStatus: backupSnapshot.data,
                      loading: recordsSnapshot.connectionState ==
                          ConnectionState.waiting,
                    ),
                  );
                },
              );
            },
          );
        },
      );

  Widget _body(
    List<SalesPerson> people,
    SalesMonthState month,
    List<SalesRecord> records, {
    required SalesBackupStatus? backupStatus,
    required bool loading,
  }) {
    final filteredRecords = filterSalesRecords(
      records,
      personId: _filterPersonId,
      personNameQuery: _salespersonSearch.text.trim().isEmpty
          ? null
          : _salespersonSearch.text.trim(),
      dateKey: _filterDate == null ? null : salesDateKey(_filterDate!),
      fromDateKey: _filterDateRange == null
          ? null
          : salesDateKey(_filterDateRange!.start),
      toDateKey:
          _filterDateRange == null ? null : salesDateKey(_filterDateRange!.end),
    );
    final personGroups = groupSalesRecordsByPerson(filteredRecords);
    final orderedRecords =
        personGroups.expand((group) => group.records).toList(growable: false);
    final visibleRecords =
        orderedRecords.take(_visibleRecordCount).toList(growable: false);
    final visibleRecordIds = visibleRecords.map((record) => record.id).toSet();
    final visiblePersonGroups = personGroups
        .map((group) => SalesPersonRecordGroup(
              personId: group.personId,
              personName: group.personName,
              records: group.records
                  .where((record) => visibleRecordIds.contains(record.id))
                  .toList(growable: false),
              totalMilli: group.totalMilli,
            ))
        .where((group) => group.records.isNotEmpty)
        .toList(growable: false);
    final hasMoreRecords = visibleRecords.length < orderedRecords.length;
    final serialByRecordId = <String, int>{
      for (var index = 0; index < orderedRecords.length; index++)
        orderedRecords[index].id: index + 1,
    };
    final alphabeticPeople = List<SalesPerson>.of(people)
      ..sort((a, b) {
        final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return name != 0 ? name : a.id.compareTo(b.id);
      });
    final currentMonth = indiaNow();
    final canMoveNext = _selectedMonth.isBefore(
      DateTime(currentMonth.year, currentMonth.month),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SALES TRACKER',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.2),
                ),
                SizedBox(height: 4),
                Text(
                  'Daily salesperson sales',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            SegmentedButton<int>(
              segments: [
                const ButtonSegment(value: -1, icon: Icon(Icons.chevron_left)),
                ButtonSegment(
                  value: 0,
                  label: Text(_displayMonth(_selectedMonth)),
                ),
                ButtonSegment(
                  value: 1,
                  enabled: canMoveNext,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
              selected: const {0},
              onSelectionChanged: (selection) {
                final value = selection.first;
                if (value != 0) _changeMonth(value);
              },
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (month.finalized)
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  const Text('Incentives finalized — this month is locked.'),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _setFinalized(false),
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Reopen month'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _deleteMonth,
                        icon: const Icon(Icons.delete_forever_outlined),
                        label: const Text('Delete month'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editing == null ? 'Enter daily sales' : 'Edit daily sales',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final fieldWidth = width < 900 ? width : (width - 24) / 3;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: Autocomplete<SalesPerson>(
                            displayStringForOption: (person) => person.name,
                            optionsBuilder: (value) {
                              final query = value.text.trim().toLowerCase();
                              if (query.isEmpty) return people;
                              return people.where(
                                (person) =>
                                    person.name.toLowerCase().contains(query),
                              );
                            },
                            onSelected: (person) => _selectedPerson = person,
                            fieldViewBuilder:
                                (context, controller, focusNode, onSubmitted) {
                              _name = controller;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                readOnly: month.finalized || _editing != null,
                                decoration: const InputDecoration(
                                  labelText: 'Salesperson name',
                                  hintText: 'Select or enter a new name',
                                  border: OutlineInputBorder(),
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: InkWell(
                            onTap: month.finalized ? null : _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Sales date',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.calendar_month_outlined),
                              ),
                              child: Text(_displayDate(_selectedDate)),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: TextField(
                            controller: _amount,
                            readOnly: month.finalized,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [_AmountInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Daily sales amount',
                              prefixText: '₹ ',
                              hintText: '0.000',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TextField(
                            controller: _reference,
                            readOnly: month.finalized,
                            maxLength: 250,
                            decoration: const InputDecoration(
                              labelText: 'Reference / remarks (optional)',
                              hintText:
                                  'POS report, sales sheet or correction note',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy || month.finalized
                          ? null
                          : () => _save(people, month.finalized),
                      icon: Icon(
                        _editing == null
                            ? Icons.save_outlined
                            : Icons.edit_outlined,
                      ),
                      label: Text(
                        _editing == null ? 'Save daily sales' : 'Save changes',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _addSalesperson(people),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add salesperson'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _viewSalespersons,
                      icon: const Icon(Icons.people_outline),
                      label: const Text('View salespersons'),
                    ),
                    if (_editing != null)
                      TextButton(
                        onPressed: () =>
                            setState(() => _cancelEdit(clearPerson: true)),
                        child: const Text('Cancel edit'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final headingAndFilters = Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_displayMonth(_selectedMonth)} records',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: _salespersonSearch,
                            decoration: InputDecoration(
                              labelText: 'Search salesperson',
                              hintText: 'Enter a name',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _salespersonSearch.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear search',
                                      onPressed: () => setState(() {
                                        _salespersonSearch.clear();
                                        _visibleRecordCount = 20;
                                      }),
                                      icon: const Icon(Icons.close),
                                    ),
                            ),
                            onChanged: (value) => setState(() {
                              if (value.trim().isNotEmpty) {
                                _filterPersonId = null;
                              }
                              _visibleRecordCount = 20;
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_filterPersonId),
                            initialValue: _filterPersonId ?? '',
                            decoration: const InputDecoration(
                              labelText: 'Filter by salesperson',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('All salespeople'),
                              ),
                              ...alphabeticPeople.map(
                                (person) => DropdownMenuItem(
                                  value: person.id,
                                  child: Text(person.name),
                                ),
                              ),
                            ],
                            onChanged: (value) => setState(() {
                              _salespersonSearch.clear();
                              _filterPersonId =
                                  value == null || value.isEmpty ? null : value;
                              _visibleRecordCount = 20;
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: OutlinedButton.icon(
                            onPressed: _pickFilterDate,
                            icon: const Icon(Icons.event_outlined),
                            label: Text(
                              _filterDate == null
                                  ? 'Single date'
                                  : _displayDate(_filterDate!),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 265,
                          child: OutlinedButton.icon(
                            onPressed: _pickFilterDateRange,
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(
                              _filterDateRange == null
                                  ? 'From – To date'
                                  : '${_displayDate(_filterDateRange!.start)} – ${_displayDate(_filterDateRange!.end)}',
                            ),
                          ),
                        ),
                        if (_salespersonSearch.text.trim().isNotEmpty ||
                            _filterPersonId != null ||
                            _filterDate != null ||
                            _filterDateRange != null)
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _salespersonSearch.clear();
                              _filterPersonId = null;
                              _filterDate = null;
                              _filterDateRange = null;
                              _visibleRecordCount = 20;
                            }),
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Clear filters'),
                          ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _backupBusy || (backupStatus?.isActive ?? false)
                                  ? null
                                  : _requestBackup,
                          icon: _backupBusy || (backupStatus?.isActive ?? false)
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _backupBusy
                                ? 'Requesting'
                                : backupStatus?.status == 'pending'
                                    ? 'Backup queued'
                                    : backupStatus?.status == 'processing'
                                        ? 'Backing up'
                                        : 'Back up now',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: filteredRecords.isEmpty
                              ? null
                              : () => _export(filteredRecords),
                          icon: const Icon(Icons.table_view_outlined),
                          label: const Text('Export Excel'),
                        ),
                        if (!month.finalized)
                          FilledButton.tonalIcon(
                            onPressed: records.isEmpty || _busy
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text(
                                          'Finalize incentives?',
                                        ),
                                        content: Text(
                                          'Lock $_monthKey after incentive processing? Data will remain available until you manually delete it.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Not yet'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text(
                                              'Finalize and lock',
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await _setFinalized(true);
                                    }
                                  },
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Mark incentives completed'),
                          ),
                      ],
                    );
                    if (constraints.maxWidth >= 1500) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: headingAndFilters),
                          const SizedBox(width: 16),
                          actions,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        headingAndFilters,
                        const SizedBox(height: 12),
                        actions,
                      ],
                    );
                  },
                ),
                if (backupStatus != null) ...[
                  const SizedBox(height: 12),
                  _backupStatusBanner(backupStatus),
                ],
                const SizedBox(height: 14),
                if (loading) const LinearProgressIndicator(),
                if (!loading && filteredRecords.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text('No sales records match these filters.'),
                    ),
                  ),
                if (filteredRecords.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final tableWidth = constraints.maxWidth < 1080
                          ? 1080.0
                          : constraints.maxWidth;
                      final contentWidth = tableWidth - (24 * 2) - (52 * 4);
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: tableWidth),
                          child: DataTable(
                            horizontalMargin: 24,
                            columnSpacing: 52,
                            headingRowColor: WidgetStatePropertyAll(
                              Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                                  .withValues(alpha: 0.32),
                            ),
                            columns: [
                              DataColumn(
                                label: SizedBox(
                                  width: contentWidth * 0.08,
                                  child: const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('SNo'),
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: contentWidth * 0.32,
                                  child: const Text('Name'),
                                ),
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: contentWidth * 0.17,
                                  child: const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('Amount'),
                                  ),
                                ),
                                numeric: true,
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: contentWidth * 0.28,
                                  child: const Text('Date'),
                                ),
                              ),
                              DataColumn(
                                label: SizedBox(
                                  width: contentWidth * 0.15,
                                  child: const Text('Action buttons'),
                                ),
                              ),
                            ],
                            rows: [
                              for (final group in visiblePersonGroups) ...[
                                for (final record in group.records)
                                  DataRow(
                                    cells: [
                                      DataCell(
                                        Text('${serialByRecordId[record.id]}'),
                                      ),
                                      DataCell(
                                        Tooltip(
                                          message: record.reference.isEmpty
                                              ? record.personId
                                              : '${record.personId}\n${record.reference}',
                                          child: Text(record.personName),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '₹${_groupedAmount(record.amountMilli)}',
                                        ),
                                      ),
                                      DataCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _displayDate(record.salesDate),
                                            ),
                                            if (record.createdAt != null)
                                              Text(
                                                _displayTime(record.createdAt!),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                          ],
                                        ),
                                      ),
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'Edit',
                                              onPressed: month.finalized
                                                  ? null
                                                  : () => _edit(record, people),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete permanently',
                                              onPressed: month.finalized
                                                  ? null
                                                  : () => _deleteRecord(record),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                DataRow(
                                  color: WidgetStatePropertyAll(
                                    Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.45),
                                  ),
                                  cells: [
                                    const DataCell(SizedBox.shrink()),
                                    DataCell(
                                      Text(
                                        '${group.personName} total',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '₹${_groupedAmount(group.totalMilli)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const DataCell(SizedBox.shrink()),
                                    const DataCell(SizedBox.shrink()),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                if (hasMoreRecords)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Align(
                      alignment: Alignment.center,
                      child: FilledButton.tonalIcon(
                        onPressed: () => setState(
                          () => _visibleRecordCount += 20,
                        ),
                        icon: const Icon(Icons.expand_more),
                        label: Text(
                          'Load more (${orderedRecords.length - visibleRecords.length} remaining)',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _displayDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _displayMonth(DateTime value) {
    final month = const [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ][value.month - 1];
    return '$month ${value.year}';
  }

  String _displayTime(DateTime value) {
    final local = indiaDateTime(value);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _displayDateTimeIst(DateTime value) {
    final local = indiaDateTime(value);
    return '${_displayDate(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')} IST';
  }

  Widget _backupStatusBanner(SalesBackupStatus backup) {
    final scheme = Theme.of(context).colorScheme;
    late final IconData icon;
    late final String title;
    late final String detail;
    late final Color foreground;
    late final Color background;

    switch (backup.status) {
      case 'pending':
        icon = Icons.schedule_outlined;
        title = 'Manual backup queued';
        detail = 'Waiting for the GitHub backup process to start.';
        foreground = scheme.onSecondaryContainer;
        background = scheme.secondaryContainer;
      case 'processing':
        icon = Icons.cloud_sync_outlined;
        title = 'Manual backup in progress';
        detail = backup.startedAt == null
            ? 'The complete Sales Tracker backup is being created.'
            : 'Started ${_displayDateTimeIst(backup.startedAt!)}.';
        foreground = scheme.onTertiaryContainer;
        background = scheme.tertiaryContainer;
      case 'completed':
        icon = Icons.check_circle_outline;
        title = 'Manual backup successful';
        final completed = backup.completedAt == null
            ? ''
            : 'Completed ${_displayDateTimeIst(backup.completedAt!)}.';
        final assets = backup.assetNames.isEmpty
            ? ''
            : ' File: ${backup.assetNames.join(', ')}';
        detail = '$completed$assets'.trim();
        foreground = scheme.onPrimaryContainer;
        background = scheme.primaryContainer;
      case 'failed':
        icon = Icons.error_outline;
        title = 'Manual backup failed';
        detail = backup.error?.trim().isNotEmpty == true
            ? backup.error!.trim()
            : 'Open GitHub Actions to inspect the failed backup run.';
        foreground = scheme.onErrorContainer;
        background = scheme.errorContainer;
      default:
        icon = Icons.info_outline;
        title = 'Manual backup status unavailable';
        detail = 'Current status: ${backup.status}';
        foreground = scheme.onSurfaceVariant;
        background = scheme.surfaceContainerHighest;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(detail, style: TextStyle(color: foreground)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _groupedAmount(int milli) {
    final raw = formatAmountMilli(milli);
    final parts = raw.split('.');
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$grouped.${parts.last}';
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('FormatException: ', '');

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final value = newValue.text.replaceAll(',', '');
    return RegExp(r'^\d*(\.\d{0,3})?$').hasMatch(value)
        ? newValue.copyWith(text: value)
        : oldValue;
  }
}
