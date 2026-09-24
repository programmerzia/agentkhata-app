import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/core.dart' as core;
import '../data/database.dart';
import '../data/repository.dart';
import '../platform/message_channel.dart';
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
  Timer? _retry;
  bool _running = false;
  bool _again = false;
  int _failures = 0;
  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _status.stream;
  SyncStatus last = const SyncStatus.idle();

  static const _tables = ['wallets', 'entries', 'day_closes', 'commission_rules', 'parties'];

  /// How long to wait after the n-th consecutive failure.
  ///
  /// A phone in a basement bazaar fails every sync for an hour. Retrying every
  /// few seconds drains the battery and the data pack for nothing; waiting
  /// five minutes after the first failure makes a phone that got signal back
  /// look broken. So: quick at first, then patient, never beyond fifteen
  /// minutes — and connectivity returning cuts straight through the wait.
  static const _backoff = [Duration(seconds: 5), Duration(seconds: 20), Duration(minutes: 1), Duration(minutes: 5), Duration(minutes: 15)];

  void stop() {
    _debounce?.cancel();
    _debounce = null;
    _retry?.cancel();
    _retry = null;
  }

  void scheduleSync([Duration delay = const Duration(seconds: 3)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    // A trigger that arrives mid-sync is remembered, not dropped: the write
    // that caused it happened after this sync read its dirty rows.
    if (_running) {
      _again = true;
      return;
    }
    // The other engine is syncing. It will pick up these rows too; look again
    // shortly in case it finished before seeing them.
    if (!await MessageChannel.tryLock('sync', const Duration(seconds: 90))) {
      scheduleSync(const Duration(seconds: 15));
      return;
    }
    _running = true;
    _again = false;
    _emit(const SyncStatus.syncing());
    try {
      await _adopt();
      await _refreshShopSettings();
      await _push();
      await _pull();
      _failures = 0;
      _retry?.cancel();
      _emit(SyncStatus.ok(DateTime.now()));
    } on ApiException catch (e) {
      if (e.isReadOnly) {
        _emit(const SyncStatus.readOnly());
        _scheduleRetry(const Duration(minutes: 30));
      } else if (e.isUnauthorised) {
        _emit(const SyncStatus.unpaired());
      } else {
        _emit(SyncStatus.error(e.toString()));
        _fail();
      }
    } catch (e) {
      _emit(SyncStatus.error(e.toString()));
      _fail();
    } finally {
      _running = false;
      await MessageChannel.unlock('sync');
      if (_again) scheduleSync(const Duration(seconds: 1));
    }
  }

  void _fail() {
    _failures++;
    _scheduleRetry(_backoff[math.min(_failures, _backoff.length) - 1]);
  }

  void _scheduleRetry(Duration after) {
    _retry?.cancel();
    _retry = Timer(after, syncNow);
  }

  void _emit(SyncStatus s) {
    last = s;
    _status.add(s);
  }

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  /// Join this phone's own wallets to the shop's.
  ///
  /// Only wallets the shop has never seen go through here — made during this
  /// phone's setup, or added in its settings. The server decides which shop
  /// wallet each one IS: the one cash drawer, the account with that number, or
  /// a new wallet; and when the shop holds two accounts of the same operator
  /// it asks, and this phone keeps the question until a person answers it
  /// (see [pendingChoices]). Entries posted to an unanswered wallet wait.
  Future<void> _adopt() async {
    final locals = await repo.unadoptedWallets();
    if (locals.isEmpty) return;

    final choicesRaw = await repo.meta('adopt_choices');
    final identity = await MessageChannel.identity();
    final body = await api.post('/api/m/devices/adopt', {
      'wallets': [
        for (final w in locals)
          {
            'localId': w.id,
            'kind': w.kind.name,
            'label': w.label,
            'accountNumber': w.accountNumber,
            'openingPoisha': w.openingBalance.toString(),
            'openingAt': _iso(w.openingAt),
            'captures': w.kind != core.WalletKind.cash,
          }
      ],
      'choices': choicesRaw == null ? const <String, String>{} : jsonDecode(choicesRaw),
      'device': {
        if (identity != null) 'model': identity.model,
        if (identity != null) 'appVersion': identity.appVersion,
      },
    });

    final mapping = (body['mapping'] as Map? ?? const {}).cast<String, String>();
    final shopWallets = (body['wallets'] as List? ?? const []).cast<Map<String, dynamic>>();
    final byId = {for (final w in shopWallets) w['id'] as String: w};

    for (final entry in mapping.entries) {
      final server = byId[entry.value];
      if (server != null) await repo.adoptWallet(localId: entry.key, server: _walletRow(server));
    }
    // The rest of the shop's wallets, so this phone's books are whole — its
    // cash total includes the Upay phone's takings, because it is one drawer.
    for (final w in shopWallets) {
      if (mapping.containsValue(w['id'])) continue;
      await repo.applyRemote(repo.db.wallets, _walletRow(w), id: w['id'] as String, remoteVersion: (w['version'] as num?)?.toInt() ?? 1);
    }

    final captured = (body['captures'] as List? ?? const []).cast<String>();
    final already = await repo.captures() ?? <String>{};
    await repo.setCaptures({...already, ...captured});

    final needsChoice = body['needsChoice'] as List? ?? const [];
    await repo.setMeta('adopt_pending', jsonEncode(needsChoice));
  }

  /// The shop's trading hours and low-float threshold, as set on the portal.
  ///
  /// Every half hour at most: they change a few times a year, and bootstrap is
  /// a request the phone need not make on every sync.
  Future<void> _refreshShopSettings() async {
    final last = DateTime.tryParse(await repo.meta('settings_at') ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 30)) return;
    final body = await api.get('/api/m/bootstrap');
    final settings = body['settings'] as Map<String, dynamic>? ?? const {};
    final prefs = await SharedPreferences.getInstance();
    final hours = (settings['businessHoursPerDay'] as num?)?.toInt();
    final low = (settings['lowFloatHours'] as num?)?.toInt();
    if (hours != null && hours > 0) await prefs.setInt('agentkhata.business_hours', hours);
    if (low != null && low > 0) await prefs.setInt('agentkhata.low_float_hours', low);
    // Receipts print the business's name until the agent types their own.
    final shop = body['shopName'] as String?;
    if (shop != null && shop.isNotEmpty) await prefs.setString('agentkhata.shop_name_remote', shop);
    // The counter name was printed before the shop name existed; drop it.
    await prefs.remove('agentkhata.counter_name');
    await repo.setMeta('settings_at', DateTime.now().toIso8601String());
  }

  /// The shop's wallets, for a phone about to join it.
  Future<List<Map<String, dynamic>>> shopWallets() async {
    final body = await api.get('/api/m/bootstrap');
    return (body['wallets'] as List? ?? const []).cast<Map<String, dynamic>>();
  }

  /// Join a shop that already runs AgentKhata on another phone.
  ///
  /// The phone takes the shop's wallets as they are — with the shop's opening
  /// balances, because there is one set of books — records which of them it
  /// captures, and reports that at once so the portal's coverage is right
  /// before the first transaction arrives. The cash drawer this phone made for
  /// itself at first start is folded into the shop's by the adoption that
  /// runs inside the sync.
  Future<void> joinShop({required List<Map<String, dynamic>> wallets, required Set<String> captures}) async {
    for (final w in wallets) {
      await repo.applyRemote(repo.db.wallets, _walletRow(w), id: w['id'] as String, remoteVersion: (w['version'] as num?)?.toInt() ?? 1);
    }
    await repo.setCaptures(captures);
    await repo.setMeta('last_device_report', '');
    // The local join is done; the upload can finish whenever the network does.
    unawaited(syncNow());
  }

  /// Questions the shop asked while adopting: "which of your two bKash numbers
  /// is on this phone?" Answered by [answerChoice].
  Future<List<PendingChoice>> pendingChoices() async {
    final raw = await repo.meta('adopt_pending');
    if (raw == null) return const [];
    return [
      for (final item in (jsonDecode(raw) as List).cast<Map<String, dynamic>>())
        PendingChoice(
          localId: item['localId'] as String,
          kind: WalletKindIndex.ofName(item['kind']),
          candidates: [
            for (final c in (item['candidates'] as List).cast<Map<String, dynamic>>())
              (id: c['id'] as String, label: c['label'] as String, accountNumber: c['accountNumber'] as String?),
          ],
        ),
    ];
  }

  Future<void> answerChoice({required String localId, required String serverWalletId}) async {
    final raw = await repo.meta('adopt_choices');
    final choices = raw == null ? <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
    choices[localId] = serverWalletId;
    await repo.setMeta('adopt_choices', jsonEncode(choices));
    scheduleSync(Duration.zero);
  }

  Future<void> _push() async {
    final db = repo.db;
    String iso(DateTime d) => d.toUtc().toIso8601String();
    String? isoN(DateTime? d) => d == null ? null : iso(d);

    // Rows that point at a wallet the shop has not placed yet wait for it:
    // pushed now, they would name an id the server has never heard of.
    final waiting = {for (final w in await repo.unadoptedWallets()) w.id};
    bool placed(String? walletId) => walletId == null || !waiting.contains(walletId);

    final walletRows = (await repo.dirtyWallets()).where((w) => w.version > 0).toList();
    final entryRows = (await repo.dirtyTransactions()).where((t) => placed(t.walletId) && placed(t.counterWalletId)).toList();
    final closeRows = (await repo.dirtyDayCloses()).where((c) => placed(c.walletId)).toList();
    final ruleRows = await repo.dirtyRules();
    final customerRows = await repo.dirtyCustomers();

    final nothingDirty = walletRows.isEmpty && entryRows.isEmpty && closeRows.isEmpty && ruleRows.isEmpty && customerRows.isEmpty;

    /*
     * The phone reports on itself with every push, and at least every ten
     * minutes when there is nothing else to send — that heartbeat is how the
     * portal can say "the Rocket phone has been silent since 11:40" before the
     * owner finds out from a drawer that does not balance.
     */
    final lastReport = DateTime.tryParse(await repo.meta('last_device_report') ?? '');
    final reportDue = lastReport == null || DateTime.now().difference(lastReport) > const Duration(minutes: 10);
    if (nothingDirty && !reportDue) return;

    final payload = <String, dynamic>{
      'device': await _deviceReport(),
      'parties': [
        for (final c in customerRows)
          {
            'id': c.id,
            'name': c.name,
            'phone': c.phone,
          }
      ],
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
            'commissionInCash': t.commissionInCash,
            'billerName': t.billerName,
            'billerAccount': t.billerAccount,
            'billerToken': t.billerToken,
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
            'takenInCash': r.takenInCash,
            'billerMatch': r.billerMatch,
          }
      ],
    };

    final response = await api.post('/api/m/sync/push', payload);
    final results = response['results'] as Map<String, dynamic>? ?? const {};

    final rejected = <String, String>{};
    await _settle(db.customers, results['parties'], rejected);
    await _settle(db.wallets, results['wallets'], rejected);
    await _settle(db.transactions, results['entries'], rejected);
    await _settle(db.dayCloses, results['dayCloses'], rejected);
    await _settle(db.commissionRules, results['commissionRules'], rejected);
    await repo.setMeta('rejections', jsonEncode(rejected));
    await repo.setMeta('last_device_report', DateTime.now().toIso8601String());
  }

  Future<Map<String, dynamic>> _deviceReport() async {
    final health = await MessageChannel.health();
    final identity = await MessageChannel.identity();
    final captures = await repo.captures();
    return {
      if (identity != null) 'model': identity.model,
      if (identity != null) 'appVersion': identity.appVersion,
      if (captures != null) 'captures': captures.toList(),
      if (health?.lastCaptureAt != null) 'lastCaptureAt': _iso(health!.lastCaptureAt!),
      if (health != null) 'health': health.toJson(),
    };
  }

  /// Mark accepted rows clean and record the versions the server assigned.
  ///
  /// A row the server reported as a conflict is deliberately left DIRTY. The
  /// pull that follows overwrites it with the server's copy unless the local
  /// change touched `status`, in which case the next push re-sends it on the
  /// version the server just told us about — the status-wins rule, implemented
  /// as one line rather than a branch that can drift.
  ///
  /// A MERGED row was the same thing as one the shop already had — the same
  /// operator transaction from another phone, a second copy of a default rate.
  /// This phone gives up its own id for the shop's.
  ///
  /// A REJECTED row stays dirty and its reason is kept, so the sync screen can
  /// say "3 entries are waiting: unknown customer" instead of retrying in
  /// silence.
  Future<void> _settle(TableInfo table, dynamic rawResults, Map<String, String> rejected) async {
    final results = (rawResults as List? ?? []).cast<Map<String, dynamic>>();
    final clean = <String>[];
    for (final result in results) {
      final id = result['id'] as String?;
      if (id == null) continue;
      final status = result['status'] as String?;
      final version = result['version'];
      switch (status) {
        case 'ok':
          clean.add(id);
          if (version is int) await repo.setVersion(table, id, version);
        case 'merged':
          final canonical = result['canonicalId'] as String?;
          if (canonical == null) break;
          if (table.actualTableName == repo.db.transactions.actualTableName) {
            await repo.rekeyTransaction(from: id, to: canonical);
          } else if (table.actualTableName == repo.db.wallets.actualTableName) {
            await repo.mergeWalletInto(from: id, to: canonical);
          } else if (table.actualTableName == repo.db.commissionRules.actualTableName) {
            await repo.dropRule(id);
          }
        case 'conflict':
          if (version is int) await repo.setVersion(table, id, version);
          await repo.resolveConflict(table, id);
        case 'rejected':
          rejected['${table.actualTableName}:$id'] = result['reason'] as String? ?? 'rejected';
      }
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
    // A server too old to know a field leaves the phone's own value alone,
    // rather than blanking a bill's meter number on every pull.
    Value<String?> textIf(String key) => r.containsKey(key) ? Value(r[key] as String?) : const Value.absent();
    Value<bool> flagIf(String key) => r.containsKey(key) ? Value(r[key] == true) : const Value.absent();

    switch (table) {
      case 'wallets':
        await repo.applyRemote(
          db.wallets,
          _walletRow(r),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
      case 'entries':
        await repo.applyRemoteTransaction(
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
            commissionInCash: flagIf('commissionInCash'),
            billerName: textIf('billerName'),
            billerAccount: textIf('billerAccount'),
            billerToken: textIf('billerToken'),
            status: Value(TxStatusIndex.ofName(r['status'])),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          walletId: r['walletId'] as String,
          trxId: r['trxId'] as String?,
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
            takenInCash: flagIf('takenInCash'),
            billerMatch: textIf('billerMatch'),
            effectiveFrom: Value(dtN(r['effectiveFrom'])),
            version: Value((r['version'] as num?)?.toInt() ?? 1),
            updatedAt: Value(dt(r['updatedAt'])),
            deletedAt: Value(dtN(r['deletedAt'])),
            dirty: const Value(false),
          ),
          id: r['id'] as String,
          remoteVersion: (r['version'] as num?)?.toInt() ?? 1,
        );
      case 'parties':
        // Archived customers stay archived on the phone by leaving the book.
        final tags = (r['tags'] as List?)?.cast<String>() ?? const [];
        await repo.applyRemoteCustomer(CustomersCompanion(
          id: Value(r['id'] as String),
          name: Value(r['name'] as String? ?? ''),
          phone: Value(r['phone'] as String?),
          note: Value(r['note'] as String?),
          updatedAt: Value(dt(r['updatedAt'])),
          deletedAt: Value(tags.contains('archived') ? DateTime.now() : null),
        ));
    }
  }
}

/// A wallet row as the server describes it, ready to store.
WalletsCompanion _walletRow(Map<String, dynamic> r) {
  DateTime dt(dynamic v) => DateTime.parse(v as String).toLocal();
  return WalletsCompanion(
    id: Value(r['id'] as String),
    kind: Value(WalletKindIndex.ofName(r['kind'])),
    label: Value(r['label'] as String),
    accountNumber: Value(r['accountNumber'] as String?),
    isActive: Value(r['isActive'] as bool? ?? true),
    openingBalance: Value(int.parse((r['openingPoisha'] ?? '0').toString())),
    openingAt: Value(dt(r['openingAt'])),
    sortOrder: Value((r['sortOrder'] as num?)?.toInt() ?? 0),
    version: Value((r['version'] as num?)?.toInt() ?? 1),
    updatedAt: Value(dt(r['updatedAt'])),
    deletedAt: Value(r['deletedAt'] == null ? null : dt(r['deletedAt'])),
    dirty: const Value(false),
  );
}

/// "Which of the shop's bKash accounts is on this phone?"
class PendingChoice {
  const PendingChoice({required this.localId, required this.kind, required this.candidates});
  final String localId;
  final core.WalletKind kind;
  final List<({String id, String label, String? accountNumber})> candidates;
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
