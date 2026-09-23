import '../core/core.dart' as core;
import 'database.dart';

extension WalletRowX on WalletRow {
  core.Wallet toDomain() => core.Wallet(
        id: id,
        kind: kind,
        label: label,
        accountNumber: accountNumber,
        isActive: isActive,
        openingBalance: core.Paisa(openingBalance),
        openingAt: openingAt,
      );
}

extension TransactionRowX on TransactionRow {
  core.Transaction toDomain() => core.Transaction(
        id: id,
        walletId: walletId,
        type: type,
        amount: core.Paisa(amount),
        fee: core.Paisa(fee),
        commission: core.Paisa(commission),
        counterparty: counterparty,
        trxId: trxId,
        balanceAfter: balanceAfter == null ? null : core.Paisa(balanceAfter!),
        occurredAt: occurredAt,
        source: source,
        rawMessageId: rawMessageId,
        note: note,
        customerId: customerId,
        counterWalletId: counterWalletId,
        billerName: billerName,
        billerAccount: billerAccount,
        billerToken: billerToken,
        commissionInCash: commissionInCash,
        status: status,
      );
}

extension CustomerRowX on CustomerRow {
  core.Customer toDomain() => core.Customer(id: id, name: name, phone: phone, note: note);
}

extension DayCloseRowX on DayCloseRow {
  core.DayClose toDomain() => core.DayClose(
        id: id,
        date: date,
        walletId: walletId,
        expected: core.Paisa(expected),
        actual: core.Paisa(actual),
        note: note,
        closedAt: closedAt,
      );
}

extension CommissionRuleRowX on CommissionRuleRow {
  core.CommissionRule toDomain() => core.CommissionRule(
        walletKind: walletKind,
        txType: txType,
        mode: mode,
        ratePpm: ratePpm,
        flatPoisha: flatPoisha,
        effectiveFrom: effectiveFrom,
        takenInCash: takenInCash,
        billerMatch: billerMatch,
      );
}
