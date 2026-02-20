// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_type.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetTypeAdapter extends TypeAdapter<AssetType> {
  @override
  final int typeId = 0;

  @override
  AssetType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssetType.stock;
      case 1:
        return AssetType.mutualFund;
      case 2:
        return AssetType.gold;
      case 3:
        return AssetType.crypto;
      case 4:
        return AssetType.bond;
      case 5:
        return AssetType.fixedDeposit;
      case 6:
        return AssetType.cash;
      case 7:
        return AssetType.realEstate;
      default:
        return AssetType.stock;
    }
  }

  @override
  void write(BinaryWriter writer, AssetType obj) {
    switch (obj) {
      case AssetType.stock:
        writer.writeByte(0);
        break;
      case AssetType.mutualFund:
        writer.writeByte(1);
        break;
      case AssetType.gold:
        writer.writeByte(2);
        break;
      case AssetType.crypto:
        writer.writeByte(3);
        break;
      case AssetType.bond:
        writer.writeByte(4);
        break;
      case AssetType.fixedDeposit:
        writer.writeByte(5);
        break;
      case AssetType.cash:
        writer.writeByte(6);
        break;
      case AssetType.realEstate:
        writer.writeByte(7);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
