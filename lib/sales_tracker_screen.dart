import 'dart:async';

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
  bool _showRecycleBin = false;
  int _visibleRecordCount = 20;
  Timer? _backupSuccessTimer;
  String? _scheduledBackupSuccessKey;
  String? _dismissedBackupSuccessKey;

  @override
  void initState() {
    super.initState();
    final now = indiaNow();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _selectedMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _backupSuccessTimer?.cancel();
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

  Future<void> _recycleSalesperson(SalesPerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move salesperson to recycle bin?'),
        content: Text(
          'Remove ${person.name} from the active salesperson list? The profile can be restored from Recycle Bin. Existing sales records, totals, exports and backups will remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('Move to recycle bin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.backend.recyclePerson(
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
        '${person.name} moved to Recycle Bin. Historical sales records were preserved.',
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
                          tooltip: 'Move salesperson to recycle bin',
                          onPressed: () => _recycleSalesperson(person),
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
        title: const Text('Move sales entry to recycle bin?'),
        content: Text(
          'Move ${record.personName} — ${_displayDate(record.salesDate)} to Recycle Bin? It can be restored until permanently deleted there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to recycle bin'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.backend.recycleRecord(
        entryId: record.id,
        monthKey: record.monthKey,
        ownerUid: widget.ownerUid,
      );
      if (mounted) _message('Sales entry moved to Recycle Bin.');
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
        title: const Text('Keep or recycle this month?'),
        content: Text(
          'Incentives for $_monthKey are marked completed. You can keep the data here or move the month to Recycle Bin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep data'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue to recycle'),
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
        title: Text('Move $_monthKey to Recycle Bin?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The selected month will leave Sales Tracker but remain in Firebase until you permanently delete it from Recycle Bin. GitHub backups are unchanged.',
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
            child: const Text('Move month'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.recycleMonth(_monthKey, widget.ownerUid);
      if (mounted) _message('$_monthKey moved to Recycle Bin.');
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

  String _backupSuccessKey(SalesBackupStatus backup) =>
      '${backup.completedAt?.microsecondsSinceEpoch ?? 0}:'
      '${backup.assetNames.join('|')}';

  void _scheduleBackupSuccessDismissal(SalesBackupStatus? backup) {
    if (backup == null || backup.status != 'completed') return;
    final key = _backupSuccessKey(backup);
    if (_scheduledBackupSuccessKey == key ||
        _dismissedBackupSuccessKey == key) {
      return;
    }
    _backupSuccessTimer?.cancel();
    _scheduledBackupSuccessKey = key;
    _backupSuccessTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _scheduledBackupSuccessKey != key) return;
      setState(() => _dismissedBackupSuccessKey = key);
    });
  }

  SalesBackupStatus? _visibleBackupStatus(SalesBackupStatus? backup) {
    if (backup == null || backup.status != 'completed') return backup;
    return _dismissedBackupSuccessKey == _backupSuccessKey(backup)
        ? null
        : backup;
  }

  @override
  Widget build(BuildContext context) {
    if (_showRecycleBin) {
      return _SalesTrackerRecycleBin(
        backend: widget.backend,
        onBack: () => setState(() => _showRecycleBin = false),
      );
    }
    return StreamBuilder<List<SalesPerson>>(
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
                  builder: (context, backupSnapshot) {
                    final backupStatus = backupSnapshot.data;
                    _scheduleBackupSuccessDismissal(backupStatus);
                    return _body(
                      people,
                      month,
                      records,
                      backupStatus: _visibleBackupStatus(backupStatus),
                      loading: recordsSnapshot.connectionState ==
                          ConnectionState.waiting,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

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
    final monthlyPersonGroups = groupSalesRecordsByPerson(records);
    final orderedRecords =
        personGroups.expand((group) => group.records).toList(growable: false);
    final visibleRecords =
        orderedRecords.take(_visibleRecordCount).toList(growable: false);
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
                        label: const Text('Move month to Recycle Bin'),
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
        LayoutBuilder(
          builder: (context, sectionConstraints) {
            final recordsPanel = Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final options = Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
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
                                      value == null || value.isEmpty
                                          ? null
                                          : value;
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
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _showRecycleBin = true),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Sales recycle bin'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _backupBusy ||
                                      (backupStatus?.isActive ?? false)
                                  ? null
                                  : _requestBackup,
                              icon: _backupBusy ||
                                      (backupStatus?.isActive ?? false)
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
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Not yet'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
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
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_displayMonth(_selectedMonth)} records',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            options,
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
                          if (constraints.maxWidth < 720) {
                            return _mobileRecordsList(
                              visibleRecords,
                              serialByRecordId,
                              people,
                              monthFinalized: month.finalized,
                            );
                          }
                          final tableWidth = constraints.maxWidth;
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
                                  for (final record in visibleRecords)
                                    DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                              '${serialByRecordId[record.id]}'),
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
                                                  _displayTime(
                                                      record.createdAt!),
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
                                                    : () =>
                                                        _edit(record, people),
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Move to recycle bin',
                                                onPressed: month.finalized
                                                    ? null
                                                    : () =>
                                                        _deleteRecord(record),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
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
            );
            final totalsPanel = _salespersonTotalsPanel(
              monthlyPersonGroups,
              monthLabel: _displayMonth(_selectedMonth),
            );
            if (sectionConstraints.maxWidth >= 1080) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: recordsPanel),
                  const SizedBox(width: 16),
                  SizedBox(width: 320, child: totalsPanel),
                ],
              );
            }
            return Column(
              children: [
                recordsPanel,
                const SizedBox(height: 16),
                totalsPanel,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _salespersonTotalsPanel(
    List<SalesPersonRecordGroup> groups, {
    required String monthLabel,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.leaderboard_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Salesperson totals',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(monthLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live totals',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: scheme.outlineVariant),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'No salesperson totals for this month.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              for (var index = 0; index < groups.length; index++) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
                        child: Text(
                          groups[index].personName.trim().isEmpty
                              ? '?'
                              : groups[index]
                                  .personName
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groups[index].personName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${groups[index].records.length} daily ${groups[index].records.length == 1 ? 'entry' : 'entries'}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹${_groupedAmount(groups[index].totalMilli)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index != groups.length - 1)
                  Divider(height: 1, color: scheme.outlineVariant),
              ],
            const SizedBox(height: 10),
            Text(
              'Totals update automatically when a daily entry is saved, edited, recycled or restored.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileRecordsList(
    List<SalesRecord> records,
    Map<String, int> serialByRecordId,
    List<SalesPerson> people, {
    required bool monthFinalized,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        for (final record in records)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${serialByRecordId[record.id]}',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        record.personName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '₹${_groupedAmount(record.amountMilli)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        record.createdAt == null
                            ? _displayDate(record.salesDate)
                            : '${_displayDate(record.salesDate)} · ${_displayTime(record.createdAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          monthFinalized ? null : () => _edit(record, people),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Move to recycle bin',
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          monthFinalized ? null : () => _deleteRecord(record),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
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

class _SalesTrackerRecycleBin extends StatelessWidget {
  const _SalesTrackerRecycleBin({
    required this.backend,
    required this.onBack,
  });

  final FirebaseSalesBackend backend;
  final VoidCallback onBack;

  Future<bool> _confirm(
          BuildContext context, String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Delete forever'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _heading(
    BuildContext context,
    String title,
    String emptyMessage,
    int count,
  ) =>
      Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (count == 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(emptyMessage,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ],
        ),
      );

  Widget _salespeople(BuildContext context) => StreamBuilder<List<SalesPerson>>(
        stream: backend.watchDeletedPeople(),
        builder: (context, snapshot) {
          final people = snapshot.data ?? const [];
          return Column(children: [
            _heading(context, 'Salespersons',
                'No salesperson profiles in this recycle bin.', people.length),
            ...people.map((person) => Card(
                  child: ListTile(
                    title: Text(person.name),
                    subtitle: Text('Person ID: ${person.id}'),
                    trailing: Wrap(children: [
                      TextButton(
                          onPressed: () async {
                            await backend.restorePerson(person.id);
                            if (context.mounted) {
                              _message(context, '${person.name} restored.');
                            }
                          },
                          child: const Text('Restore')),
                      IconButton(
                          tooltip: 'Delete permanently',
                          onPressed: () async {
                            final confirmed = await _confirm(
                              context,
                              'Delete salesperson permanently?',
                              '${person.name} will be removed from Firebase. Historical sales entries remain unchanged.',
                            );
                            if (confirmed) {
                              await backend.permanentlyDeletePerson(person);
                            }
                          },
                          icon: const Icon(Icons.delete_forever_outlined)),
                    ]),
                  ),
                )),
          ]);
        },
      );

  Widget _entries(BuildContext context) => StreamBuilder<List<SalesRecord>>(
        stream: backend.watchDeletedEntries(),
        builder: (context, snapshot) {
          final records = snapshot.data ?? const [];
          return Column(children: [
            _heading(
                context,
                'Individual sales entries',
                'No individual sales entries in this recycle bin.',
                records.length),
            ...records.map((record) => Card(
                  child: ListTile(
                    title: Text(record.personName),
                    subtitle: Text(
                        '${record.salesDateKey} · ₹${formatAmountMilli(record.amountMilli)}'),
                    trailing: Wrap(children: [
                      TextButton(
                          onPressed: () => backend.restoreRecord(record.id),
                          child: const Text('Restore')),
                      IconButton(
                          tooltip: 'Delete permanently',
                          onPressed: () async {
                            final confirmed = await _confirm(
                              context,
                              'Delete sales entry permanently?',
                              '${record.personName} · ${record.salesDateKey} and its edit history will be removed from Firebase.',
                            );
                            if (confirmed) {
                              await backend.permanentlyDeleteRecord(record.id);
                            }
                          },
                          icon: const Icon(Icons.delete_forever_outlined)),
                    ]),
                  ),
                )),
          ]);
        },
      );

  Widget _months(BuildContext context) => StreamBuilder<List<SalesMonthState>>(
        stream: backend.watchDeletedMonths(),
        builder: (context, snapshot) {
          final months = snapshot.data ?? const [];
          return Column(children: [
            _heading(context, 'Sales months',
                'No sales months in this recycle bin.', months.length),
            ...months.map((month) => Card(
                  child: ListTile(
                    title: Text(month.monthKey),
                    subtitle: const Text('Complete Sales Tracker month'),
                    trailing: Wrap(children: [
                      TextButton(
                          onPressed: () => backend.restoreMonth(month.monthKey),
                          child: const Text('Restore')),
                      IconButton(
                          tooltip: 'Delete permanently',
                          onPressed: () async {
                            final confirmed = await _confirm(
                              context,
                              'Delete ${month.monthKey} permanently?',
                              'Every sales entry and audit record for this month will be removed from Firebase. GitHub backups remain.',
                            );
                            if (confirmed) {
                              await backend
                                  .permanentlyDeleteMonth(month.monthKey);
                            }
                          },
                          icon: const Icon(Icons.delete_forever_outlined)),
                    ]),
                  ),
                )),
          ]);
        },
      );

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            IconButton(
                tooltip: 'Back to Sales Tracker',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Sales Tracker recycle bin',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
              'Only Sales Tracker records are displayed here. Permanent deletion removes Firebase data; GitHub backups remain.'),
          _salespeople(context),
          _entries(context),
          _months(context),
        ],
      );
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
