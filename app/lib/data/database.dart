import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/core.dart' as core;

part 'database.g.dart';

@DataClassName('WalletRow')
class Wallets extends Table {
  TextColumn get id => text()();
  IntColumn get kind => intEnum<core.WalletKind>()();
  TextColumn get label => text()();
  TextColumn get accountNumber => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  DateTimeColumn get openingAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  /// Server-assigned. A push carries the version it last saw; a mismatch is a
  /// conflict the server reports rather than an edit silently overwritten.
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TransactionRow')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  IntColumn get type => intEnum<core.TxType>()();
  IntColumn get amount => integer()();
  IntColumn get fee => integer().withDefault(const Constant(0))();
  IntColumn get commission => integer().withDefault(const Constant(0))();
  TextColumn get counterparty => text().nullable()();
  TextColumn get trxId => text().nullable()();
  IntColumn get balanceAfter => integer().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  IntColumn get source => intEnum<core.TxSource>()();
  TextColumn get rawMessageId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get counterWalletId => text().nullable()();

  /// Who a bill was paid to, and the customer's account with them — the meter
  /// number on a prepaid electricity bill, a postpaid account, a WASA number.
  TextColumn get billerName => text().nullable()();
  TextColumn get billerAccount => text().nullable()();

  /// The prepaid token, when the biller sends one. What a customer comes back
  /// for when the power is still off.
  TextColumn get billerToken => text().nullable()();
  IntColumn get status => intEnum<core.TxStatus>().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// Server-assigned. A push carries the version it last saw; a mismatch is a
  /// conflict the server reports rather than an edit silently overwritten.
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RawMessageRow')
class RawMessages extends Table {
  TextColumn get id => text()();
  IntColumn get source => intEnum<core.TxSource>()();
  TextColumn get sender => text()();
  TextColumn get packageName => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  IntColumn get parseStatus => intEnum<core.ParseStatus>()();
  TextColumn get parsedTransactionId => text().nullable()();
  TextColumn get reason => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CustomerRow')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// Server-assigned. A push carries the version it last saw; a mismatch is a
  /// conflict the server reports rather than an edit silently overwritten.
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DayCloseRow')
class DayCloses extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get walletId => text().references(Wallets, #id)();
  IntColumn get expected => integer()();
  IntColumn get actual => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get closedAt => dateTime()();
  /// Server-assigned. A push carries the version it last saw; a mismatch is a
  /// conflict the server reports rather than an edit silently overwritten.
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CommissionRuleRow')
class CommissionRules extends Table {
  TextColumn get id => text()();
  IntColumn get walletKind => intEnum<core.WalletKind>()();
  IntColumn get txType => intEnum<core.TxType>()();
  IntColumn get mode => intEnum<core.RateMode>()();
  /// The ratio in parts per million: 4.10 per thousand is 4100. Integer so
  /// that multiplying it by money stays integer arithmetic end to end.
  IntColumn get ratePpm => integer().withDefault(const Constant(0))();
  /// Used only when `mode` is flat.
  IntColumn get flatPoisha => integer().nullable()();
  DateTimeColumn get effectiveFrom => dateTime().nullable()();
  /// Server-assigned. A push carries the version it last saw; a mismatch is a
  /// conflict the server reports rather than an edit silently overwritten.
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Wallets, Transactions, RawMessages, Customers, DayCloses, CommissionRules, SyncMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 4;

  /// Native: SQLite file in app documents. Web: sqlite3 compiled to wasm,
  /// persisted in OPFS/IndexedDB through a shared worker.
  static QueryExecutor _open() => driftDatabase(
        name: 'agentkhata',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
        ),
      );

  @override
  MigrationStrategy get migration => MigrationStrategy(
        /*
         * Two engines can hold this file at once: the UI, and the background
         * engine that captures while the app is closed. WAL lets one read
         * while the other writes, and the busy timeout makes a writer wait its
         * turn for a few seconds instead of failing the instant the other
         * holds the lock — which, mid-capture, would be a lost transaction.
         */
        beforeOpen: (details) async {
          await customStatement('PRAGMA busy_timeout = 5000');
          await customStatement('PRAGMA journal_mode = WAL');
        },
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX idx_tx_occurred ON transactions(occurred_at)');
          await customStatement('CREATE INDEX idx_tx_wallet ON transactions(wallet_id)');
          await customStatement('CREATE UNIQUE INDEX idx_tx_trx ON transactions(wallet_id, trx_id) WHERE trx_id IS NOT NULL');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(wallets, wallets.updatedAt);
            await m.addColumn(wallets, wallets.deletedAt);
            await m.addColumn(wallets, wallets.dirty);
            await m.addColumn(transactions, transactions.updatedAt);
            await m.addColumn(transactions, transactions.deletedAt);
            await m.addColumn(transactions, transactions.dirty);
            await m.addColumn(customers, customers.updatedAt);
            await m.addColumn(customers, customers.deletedAt);
            await m.addColumn(customers, customers.dirty);
            await m.addColumn(dayCloses, dayCloses.updatedAt);
            await m.addColumn(dayCloses, dayCloses.deletedAt);
            await m.addColumn(dayCloses, dayCloses.dirty);
            await m.addColumn(commissionRules, commissionRules.updatedAt);
            await m.addColumn(commissionRules, commissionRules.deletedAt);
            await m.addColumn(commissionRules, commissionRules.dirty);
            await m.createTable(syncMeta);
          }
          if (from < 3) {
            await m.addColumn(wallets, wallets.version);
            await m.addColumn(transactions, transactions.version);
            await m.addColumn(dayCloses, dayCloses.version);
            await m.addColumn(commissionRules, commissionRules.version);
            await m.addColumn(commissionRules, commissionRules.ratePpm);
            await m.addColumn(commissionRules, commissionRules.flatPoisha);
            /*
             * The old float rate becomes parts per million. Done in SQL
             * because the column it reads is about to stop existing in the
             * Dart schema, and a migration that referenced a generated symbol
             * would stop compiling the moment that happened.
             */
            await customStatement(
              "UPDATE commission_rules SET rate_ppm = CAST(ROUND(value * 1000) AS INTEGER) WHERE mode = 0",
            );
            await customStatement(
              "UPDATE commission_rules SET rate_ppm = CAST(ROUND(value * 10000) AS INTEGER) WHERE mode = 1",
            );
          }
          if (from < 4) {
            await m.addColumn(transactions, transactions.billerName);
            await m.addColumn(transactions, transactions.billerAccount);
            await m.addColumn(transactions, transactions.billerToken);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tx_biller_account ON transactions(biller_account)',
            );
          }
        },
      );
}
