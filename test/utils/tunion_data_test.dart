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

    test('lookupTUnionStation matches Luoyang and Dalian Metro and Bus', () {
      // Luoyang Line 1, Qingniangong (010014)
      final luoyangExit = lookupTUnionStation(cityCode: '4930', stationCode: '010014');
      expect(luoyangExit, isNotNull);
      expect(luoyangExit!.cityName, '洛阳');
      expect(luoyangExit.station, '青年宫');
      expect(luoyangExit.line, '1号线');

      // Luoyang Line 1, Qilihe (010008)
      final luoyangEntry = lookupTUnionStation(cityCode: '4930', stationCode: '010008');
      expect(luoyangEntry, isNotNull);
      expect(luoyangEntry!.cityName, '洛阳');
      expect(luoyangEntry.station, '七里河');
      expect(luoyangEntry.line, '1号线');

      // Dalian Line 2, Malan Square (020E)
      final dalianMalan = lookupTUnionStation(cityCode: '2220', stationCode: '020E');
      expect(dalianMalan, isNotNull);
      expect(dalianMalan!.cityName, '大连');
      expect(dalianMalan.station, '马栏广场');
      expect(dalianMalan.line, '2号线');

      // Dalian Line 2, Airport (0213)
      final dalianAirport = lookupTUnionStation(cityCode: '2220', stationCode: '0213');
      expect(dalianAirport, isNotNull);
      expect(dalianAirport!.cityName, '大连');
      expect(dalianAirport.station, '机场');

      // Dalian Bus 1106 (stationCode 1106)
      final dalianBus1106 = lookupTUnionStation(cityCode: '2220', stationCode: '1106', industryCode: '0001');
      expect(dalianBus1106, isNotNull);
      expect(dalianBus1106!.cityName, '大连');
      expect(dalianBus1106.type, '公交');
      expect(dalianBus1106.line, '1106');

      // Dalian Bus 509 (stationCode 0509)
      final dalianBus509 = lookupTUnionStation(cityCode: '2220', stationCode: '0509', industryCode: '0001');
      expect(dalianBus509, isNotNull);
      expect(dalianBus509!.cityName, '大连');
      expect(dalianBus509.type, '公交');
      expect(dalianBus509.line, '509');
    });

    test('formatTUnionDetails formats route when entry and exit stations are provided', () {
      final formatted = formatTUnionDetails(
        cityCode: '2900',
        stationCode: '00010011', // Xinzhuang
        entryCityCode: '2900',
        entryStationCode: '00010023', // People's Square
        amount: 3.0,
      );
      expect(formatted, contains('[上海地铁]'));
      expect(formatted, contains('人民广场 ──► 莘庄'));

      // Luoyang entry tap (typeCode = 0x03)
      final luoyangEntryOnly = formatTUnionDetails(
        cityCode: '4930',
        stationCode: '01000800000000',
        typeCode: 0x03,
        amount: 0.0,
      );
      expect(luoyangEntryOnly, '[洛阳地铁] 1号线 七里河 (乘入)');

      // Luoyang exit tap (typeCode = 0x04)
      final luoyangExitOnly = formatTUnionDetails(
        cityCode: '4930',
        stationCode: '01001400000000',
        typeCode: 0x04,
        amount: 3.0,
      );
      expect(luoyangExitOnly, '[洛阳地铁] 1号线 青年宫 (乘出)');

      // Luoyang completed trip (amount = 3.0)
      final luoyangTrip = formatTUnionDetails(
        cityCode: '4930',
        stationCode: '010014',
        entryCityCode: '4930',
        entryStationCode: '010008',
        amount: 3.0,
      );
      expect(luoyangTrip, '[洛阳地铁] 1号线 七里河 ──► 青年宫');
    });
  });
}
