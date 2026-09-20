import 'dart:async';

import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/repository.dart';
import 'api_client.dart';
import 'enum_index.dart';

/// Two-way sync between the phone's Drift database and the AgentKhata server.
///
/// ## The shape, and why it survived the move off Supabase
///
/// Only the transport changed. The engine still is:
///
///   push   every row with `dirty = 1`, carrying the `version` it last saw.
///   pull   every row whose server cursor is newer than the one we hold.
///
/// Ids are generated on the phone, so a push that succeeds and whose response
/// is lost can be sent again without creating duplicates. That property is why
/// the sync can be this simple, and it is worth protecting: nothing here may
/// depend on the server assigning an identity.
///
/// ## Conflicts
///
/// The server refuses a write whose `baseVersion` is stale and hands back the
/// row it has. Then:
///
///   - if the phone's change touched `status` (a void, an accept) the phone
///     re-pushes on the new version, because a person decided that about money;
///   - otherwise the server row is adopted.
///
/// Either way the losing value is already recorded server-side as
/// `conflict_lost`, so "who changed my number" always has an answer. This is
/// deliberately NOT last-writer-wins on a timestamp: these phones cost six
/// thousand taka and their clocks are routinely days out, so comparing clocks
/// would hand the argument to whichever device is most wrong about the time.
class SyncService {
  SyncService(this.repo, this.api);

  final Repository repo;
  final ApiClient api;

  Timer? _debounce;
  bool _running = false;
  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _status.stream;
  SyncStatus last = const SyncStatus.idle();

  static const _tables = ['wallets', 'entries', 'day_closes', 'commission_rules'];

  void stop() {
    _debounce?.cancel();
    _debounce = null;
  }

  void scheduleSync([Duration delay = const Duration(seconds: 3)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    if (_running) return;
    _running = true;
    _emit(const SyncStatus.syncing());
    try {
      await _reconcileWallets();
      await _push();
      await _pull();
      _emit(SyncStatus.ok(DateTime.now()));
    } on ApiException catch (e) {
      if (e.isReadOnly) {
        _emit(const SyncStatus.readOnly());
      } else if (e.isUnauthorised) {
        _emit(const SyncStatus.unpaired());
      } else {
        _emit(SyncStatus.error(e.toString()));
      }
    } catch (e) {
      _emit(SyncStatus.error(e.toString()));
    } finally {
      _running = false;
    }
  }

  void _emit(SyncStatus s) {
    last = s;
    _status.add(s);
  }

  /// Adopt the shop's wallets before pushing anything.
  ///
  /// A phone that ran offline created its own wallets, including a cash
  /// drawer. If the business already has them — because the portal set them up
  /// or another phone did — pushing the local ones produces two bKash wallets
  /// and a cash total that is the sum of two halves of the same drawer.
  ///
  /// So on every sync the phone asks what the counter already has and maps its
  /// local rows onto those ids, matching on (kind, account number) and falling
  /// back to kind alone when only one candidate exists. Anything genuinely
  /// ambiguous is left alone and pushed as a new wallet, which an owner can
  /// merge on the portal — a wrong automatic merge is much worse than a
  /// duplicate somebody can see and fix.
  Future<void> _reconcileWallets() async {
    final body = await api.get('/api/m/bootstrap');
    final remote = (body['wallets'] as List? ?? []).cast<Map<String, dynamic>>();
    if (remote.isEmpty) return;

    final locals = await repo.dirtyWallets();
    for (final local in locals) {
      final kind = local.kind.name;
      final candidates = remote.where((r) => r['kind'] == kind).toList();
      if (candidates.isEmpty) continue;

      Map<String, dynamic>? match;
      if (local.accountNumber != null && local.accountNumber!.isNotEmpty) {
        match = candidates.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['accountNumber'] == local.accountNumber,
              orElse: () => null,
            );
      }
      match ??= candidates.length == 1 ? candidates.first : null;
      if (match == null) continue;

      final remoteId = match['id'] as String;
      if (remoteId == local.id) continue;

      await repo.replaceWalletId(
        from: local.id,
        to: remoteId,
        kind: local.kind,
        label: local.label,
        openingBalance: local.openingBalance,
        openingAt: local.openingAt,
      );
    }
  }

  Future<void> _push() async {
    final db = repo.db;
    String iso(DateTime d) => d.toUtc().toIso8601String();
    String? isoN(DateTime? d) => d == null ? null : iso(d);

    final walletRows = await repo.dirtyWallets();
    final entryRows = await repo.dirtyTransactions();
    final closeRows = await repo.dirtyDayCloses();
    final ruleRows = await repo.dirtyRules();

    if (walletRows.isEmpty && entryRows.isEmpty && closeRows.isEmpty && ruleRows.isEmpty) {
      return;
    }

    final payload = <String, dynamic>{
      'wallets': [
        for (final w in walletRows)
          {
            'id': w.id,
            'baseVersion': w.version,
            'kind': w.kind.name,
            'label': w.label,
            'accountNumber': w.accountNumber,
            'isActive': w.isActive,
            'openingPoisha': w.openingBalance.toString(),
            'openingAt': iso(w.openingAt),
            'sortOrder': w.sortOrder,
            'deletedAt': isoN(w.deletedAt),
          }
      ],
      'entries': [
        for (final t in entryRows)
          {
            'id': t.id,
            'baseVersion': t.version,
            'walletId': t.walletId,
            'type': t.type.wireName,
            'amountPoisha': t.amount.toString(),
            'feePoisha': t.fee.toString(),
            'commissionPoisha': t.commission.toString(),
            'counterparty': t.counterparty,
            'trxId': t.trxId,
            'balanceAfterPoisha': t.balanceAfter?.toString(),
            'occurredAt': iso(t.occurredAt),
            'source': t.source.wireName,
            'note': t.note,
            'partyId': t.customerId,
            'counterWalletId': t.counterWalletId,
            'status': t.status.wireName,
            'deletedAt': isoN(t.deletedAt),
          }
      ],
      'dayCloses': [
        for (final c in closeRows)
          {
            'id': c.id,
            'baseVersion': c.version,
            'walletId': c.walletId,
            'date': c.date.toIso8601String().substring(0, 10),
            'expectedPoisha': c.expected.toString(),
            'actualPoisha': c.actual.toString(),
            'note': c.note,
            'closedAt': iso(c.closedAt),
            'deletedAt': isoN(c.deletedAt),
          }
      ],
      'commissionRules': [
        for (final r in ruleRows)
          {
            'id': r.id,
            'baseVersion': r.version,
            'walletKind': r.walletKind.name,
            'entryType': r.txType.wireName,
            'mode': r.mode.wireName,
            'ratePpm': r.ratePpm,
            'flatPoisha': r.flatPoisha?.toString(),
          }
      ],
    };

    final response = await api.post('/api/m/sync/push', payload);
    final results = response['results'] as Map<String, dynamic>? ?? const {};

    await _settle(db.wallets, results['wallets']);
    await _settle(db.transactions, results['entries']);
    await _settle(db.dayCloses, results['dayCloses']);
    await _settle(db.commissionRules, results['commissionRules']);
  }

  /// Mark accepted rows clean and record the versions the server assigned.
  ///
  /// A row the server reported as a conflict is deliberately left DIRTY. The
  /// pull that follows overwrites it with the server's copy unless the local
  /// change touched `status`, in which case the next push re-sends it on the
  /// version the server just told us about — the status-wins rule, implemented
  /// as one line rather than a branch that can drift.
  Future<void> _settle(TableInfo table, dynamic rawResults) async {
    final results = (rawResults as List? ?? []).cast<Map<String, dynamic>>();
    final clean = <String>[];
    for (final result in results) {
      final id = result['id'] as String?;
      if (id == null) continue;
      final status = result['status'] as String?;
      if (status == 'ok') {
        clean.add(id);
        final version = result['version'];
        if (version is int) await repo.setVersion(table, id, version);
      } else if (status == 'conflict') {
        final version = result['version'];
        if (version is int) await repo.setVersion(table, id, version);
        await repo.resolveConflict(table, id);
      }
      // 'rejected' rows stay dirty and are reported by the next sync. A row the
      // server will never accept would otherwise retry forever in silence.
    }
    await repo.markClean(table, clean);
  }

  /// Pull each table from where this phone left off.
  ///
  /// The cursor is stored and re-sent as the exact STRING the server returned.
  /// It carries microsecond precision, which a Dart `DateTime` also holds but
  /// `toIso8601String()` renders inconsistently across platforms — and a
  /// cursor that loses precision matches the row it came from, so every sync
  /// re-downloads the whole table while appearing to work. Treat it as an
  /// opaque token; never parse it.
  Future<void> _pull() async {
    for (final table in _tables) {
      var cursor = await repo.meta('cursor_$table') ?? '1970-01-01T00:00:00Z';
      while (true) {
        final body = await api.get('/api/m/sync/pull', {
          'table': table,
          'since': cursor,
          'limit': '500',
        });
        final rows = (body['rows'] as List? ?? []).cast<Map<String, dynamic>>();
        if (rows.isEmpty) break;

        for (final row in rows) {
          await _applyRemote(table, row);
        }

        final next = body['next'] as String?;
        if (next == null || next == cursor) break;
        cursor = next;
        await repo.setMeta('cursor_$table', cursor);
        if (rows.length < 500) break;
      }
    }
  }

  Future<void> _applyRemote(String table, Map<String, dynamic> r) async {
    final db = repo.db;
    DateTime dt(dynamic v) => DateTime.parse(v as String).toLocal();
    DateTime? dtN(dynamic v) => v == null ? null : dt(v);
    int money(dynamic v) => v == null ? 0 : int.parse(v.toString());
    int? moneyN(dynamic v) => v == null ? null : int.parse(v.toString());

    switch (table) {
      case 'wallets':
        await repo.applyRemote(
          db.wallets,
          WalletsCompanion(
            id: Value(r['id'] as String),
            kind: Value(WalletKindIndex.ofName(r['kind'])),
            label: Value(r['label'] as String),
            accountNumber: Value(r['accountNumber'] as String?),
            isActive: Value(r['isActive'] as bool? ?? true),
            openingBalance: Value(money(r['openingPoisha'])),
            openingAt: Value(dt(r['openingAt'])),
            sortOrder: Value((r['sortOrder'] as num?)?.toInt() ?? 0),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
      case 'entries':
        await repo.applyRemote(
          db.transactions,
          TransactionsCompanion(
            id: Value(r['id'] as String),
            walletId: Value(r['walletId'] as String),
            type: Value(TxTypeIndex.ofName(r['type'])),
            amount: Value(money(r['amountPoisha'])),
            fee: Value(money(r['feePoisha'])),
            commission: Value(money(r['commissionPoisha'])),
            counterparty: Value(r['counterparty'] as String?),
            trxId: Value(r['trxId'] as String?),
            balanceAfter: Value(moneyN(r['balanceAfterPoisha'])),
            occurredAt: Value(dt(r['occurredAt'])),
            source: Value(TxSourceIndex.ofName(r['source'])),
            note: Value(r['note'] as String?),
            customerId: Value(r['partyId'] as String?),
            counterWalletId: Value(r['counterWalletId'] as String?),
            status: Value(TxStatusIndex.ofName(r['status'])),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
      case 'day_closes':
        await repo.applyRemote(
          db.dayCloses,
          DayClosesCompanion(
            id: Value(r['id'] as String),
            date: Value(DateTime.parse(r['date'] as String)),
            walletId: Value(r['walletId'] as String),
            expected: Value(money(r['expectedPoisha'])),
            actual: Value(money(r['actualPoisha'])),
            note: Value(r['note'] as String?),
            closedAt: Value(dt(r['closedAt'])),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
      case 'commission_rules':
        await repo.applyRemote(
          db.commissionRules,
          CommissionRulesCompanion(
            id: Value(r['id'] as String),
            walletKind: Value(WalletKindIndex.ofName(r['walletKind'])),
            txType: Value(TxTypeIndex.ofName(r['entryType'])),
            mode: Value(RateModeIndex.ofName(r['mode'])),
            ratePpm: Value((r['ratePpm'] as num?)?.toInt() ?? 0),
            flatPoisha: Value(moneyN(r['flatPoisha'])),
            effectiveFrom: Value(dtN(r['effectiveFrom'])),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
    }
  }
}

class SyncStatus {
  const SyncStatus._(this.state, {this.at, this.message});
  const SyncStatus.idle() : this._('idle');
  const SyncStatus.syncing() : this._('syncing');
  const SyncStatus.ok(DateTime at) : this._('ok', at: at);
  const SyncStatus.error(String m) : this._('error', message: m);

  /// The subscription lapsed. The books are safe and nothing was lost; the
  /// phone keeps capturing and pushes when the bill is paid.
  const SyncStatus.readOnly() : this._('read_only');

  /// The device token was revoked. The app must pair again.
  const SyncStatus.unpaired() : this._('unpaired');

  final String state;
  final DateTime? at;
  final String? message;
}
