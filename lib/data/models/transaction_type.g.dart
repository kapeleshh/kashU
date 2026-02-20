// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionTypeAdapter extends TypeAdapter<TransactionType> {
  @override
  final int typeId = 1;

  @override
  TransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionType.buy;
      case 1:
        return TransactionType.sell;
      case 2:
        return TransactionType.dividend;
      case 3:
        return TransactionType.interest;
      default:
        return TransactionType.buy;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionType obj) {
    switch (obj) {
      case TransactionType.buy:
        writer.writeByte(0);
        break;
      case TransactionType.sell:
        writer.writeByte(1);
        break;
      case TransactionType.dividend:
        writer.writeByte(2);
        break;
      case TransactionType.interest:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
