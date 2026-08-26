import 'package:flutter_test/flutter_test.dart';
import 'package:hinata_go/utils/tunion_data.dart';

void main() {
  group('TUnion Data & Lookup Tests', () {
    test('lookupTUnionIssuer matches known IINs and Issuers', () {
      // Shanghai Public Transportation Card
      expect(lookupTUnionIssuer('3104770000000000'), '上海公共交通卡');
      expect(lookupTUnionIssuer('02002900'), '上海公共交通卡');

      // Beijing Mutong Card
      expect(lookupTUnionIssuer('3105170000000000'), '北京互通卡');
      expect(lookupTUnionIssuer('01011000'), '北京互通卡');

      // Tianfutong (Chengdu)
      expect(lookupTUnionIssuer('3104780000000000'), '天府通');

      // Yangchengtong (Guangzhou)
      expect(lookupTUnionIssuer('3104870300000000'), '羊城通');

      // Shenzhen Tong
      expect(lookupTUnionIssuer('3104870400000000'), '深圳通');
      expect(lookupTUnionIssuer('02215840'), '深圳通');

      // Unknown
      expect(lookupTUnionIssuer('9999999900000000'), isNull);
      expect(lookupTUnionIssuer(null), isNull);
      expect(lookupTUnionIssuer(''), isNull);
    });

    test('lookupTUnionCity matches city codes', () {
      expect(lookupTUnionCity('2900'), '上海');
      expect(lookupTUnionCity('1000'), '北京');
      expect(lookupTUnionCity('5810'), '广州');
      expect(lookupTUnionCity('3310'), '杭州');
      expect(lookupTUnionCity('3010'), '南京');
      expect(lookupTUnionCity('9999'), isNull);
    });

    test('lookupTUnionStation matches Shanghai Metro stations', () {
      // Line 1, Xinzhuang (00010011)
      final info = lookupTUnionStation(cityCode: '2900', stationCode: '00010011');
      expect(info, isNotNull);
      expect(info!.cityName, '上海');
      expect(info.type, '地铁');
      expect(info.line, '1号线');
      expect(info.station, '莘庄');
      expect(info.formatted, '[上海地铁] 1号线 莘庄');

      // Line 2, People's Square (00020045)
      final info2 = lookupTUnionStation(cityCode: '2900', stationCode: '00020045');
      expect(info2, isNotNull);
      expect(info2!.station, '人民广场');
      expect(info2.line, '2号线');
    });

    test('lookupTUnionStation matches Beijing Metro stations', () {
      // Line 1, Gongzhufen (01000A)
      final info = lookupTUnionStation(cityCode: '1000', stationCode: '01000A');
      expect(info, isNotNull);
      expect(info!.cityName, '北京');
      expect(info.type, '地铁');
      expect(info.line, '1号线');
      expect(info.station, '公主坟');
      expect(info.formatted, '[北京地铁] 1号线 公主坟');
    });

    test('lookupTUnionStation matches Hangzhou Metro POS terminal IDs', () {
      // 413101784816 -> Line 4, Citizen Center
      final info = lookupTUnionStation(cityCode: '3310', terminalId: '413101784816');
      expect(info, isNotNull);
      expect(info!.cityName, '杭州');
      expect(info.type, '地铁');
      expect(info.line, '4');
      expect(info.station, '市民中心');
      expect(info.formatted, '[杭州地铁] 4 市民中心');
    });

    test('lookupTUnionStation matches Shanghai CU terminal IDs by prefix', () {
      // 310111744302 -> Line 1, Xinzhuang
      final info1 = lookupTUnionStation(cityCode: '3104', terminalId: '310111744302');
      expect(info1, isNotNull);
      expect(info1!.station, '莘庄');
      expect(info1.line, '1号线');

      // 310125984402 -> Line 1, Hanzhonglu
      final info2 = lookupTUnionStation(cityCode: '3104', terminalId: '310125984402');
      expect(info2, isNotNull);
      expect(info2!.station, '汉中路');
      expect(info2.line, '1号线');

      // 310623109401 -> Line 6, Shangnanlu
      final info3 = lookupTUnionStation(cityCode: '3104', terminalId: '310623109401');
      expect(info3, isNotNull);
      expect(info3!.station, '上南路');
      expect(info3.line, '6号线');
    });

    test('formatTUnionDetails formats route when entry and exit stations are provided', () {
      final formatted = formatTUnionDetails(
        cityCode: '2900',
        stationCode: '00010011', // Xinzhuang
        entryCityCode: '2900',
        entryStationCode: '00010023', // People's Square
      );
      expect(formatted, contains('[上海地铁]'));
      expect(formatted, contains('人民广场 ──► 莘庄'));
    });
  });
}
