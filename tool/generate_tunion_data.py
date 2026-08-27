#!/usr/bin/env python3
"""
generate_tunion_data.py

Parses tripreader-data CSVs and generates hinata_go/lib/utils/tunion_data.dart.
"""

import os
import glob
import csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
# If running in hinata_go/tool:
if os.path.basename(SCRIPT_DIR) == "tool" and os.path.basename(os.path.dirname(SCRIPT_DIR)) == "hinata_go":
    HINATA_GO_DIR = os.path.dirname(SCRIPT_DIR)
else:
    HINATA_GO_DIR = os.path.expanduser("~/Projects/hinata_go")

TRIPREADER_DIR = os.path.expanduser("~/Projects/tripreader-data")
OUTPUT_FILE = os.path.join(HINATA_GO_DIR, "lib", "utils", "tunion_data.dart")

# Known City Code to Chinese City Name mapping
CITY_NAMES = {
    "0100": "广州",
    "1000": "北京",
    "1121": "天津",
    "1610": "太原",
    "2000": "上海",
    "2210": "沈阳",
    "2220": "大连",
    "2610": "哈尔滨",
    "2900": "上海",
    "3010": "南京",
    "3020": "无锡",
    "3030": "徐州",
    "3040": "常州",
    "3050": "苏州",
    "3100": "杭州",
    "3104": "上海",
    "3120": "绍兴",
    "3140": "嘉兴",
    "3310": "杭州",
    "3320": "宁波",
    "3350": "嘉兴",
    "3370": "绍兴",
    "3610": "合肥",
    "3620": "芜湖",
    "3910": "福州",
    "3930": "厦门",
    "4131": "洛阳",
    "4210": "南昌",
    "4510": "济南",
    "4520": "青岛",
    "4930": "洛阳",
    "5180": "深圳",
    "5510": "长沙",
    "5810": "广州",
    "5880": "佛山",
    "6020": "东莞",
    "6900": "重庆",
    "7010": "贵阳",
    "7310": "昆明",
    "7910": "西安",
    "8210": "兰州",
    "8810": "乌鲁木齐",
}

def escape_dart_str(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")

def main():
    if not os.path.exists(TRIPREADER_DIR):
        print(f"Error: {TRIPREADER_DIR} does not exist.")
        return

    # 1. Parse cardname-tu.csv
    cardname_csv = os.path.join(TRIPREADER_DIR, "cardname-tu.csv")
    iin_map = {}
    issuer_map = {}

    if os.path.exists(cardname_csv):
        with open(cardname_csv, "r", encoding="utf-8", errors="ignore") as f:
            reader = csv.DictReader(f)
            for r in reader:
                iin = (r.get("IIN") or "").strip()
                issuer = (r.get("Issuer") or "").strip()
                name = (r.get("Name") or "").strip()
                if iin and name:
                    iin_map[iin] = name
                if issuer and name:
                    issuer_map[issuer] = name

    print(f"Loaded {len(iin_map)} IINs, {len(issuer_map)} Issuers.")

    # 2. Parse all transit CSVs
    # Key: (city_code, code) -> (type, line, station)
    station_map = {}

    for csv_file in sorted(glob.glob(os.path.join(TRIPREADER_DIR, "**", "*.csv"), recursive=True)):
        if "cardname-tu.csv" in csv_file:
            continue
        with open(csv_file, "r", encoding="utf-8", errors="ignore") as f:
            reader = csv.DictReader(f)
            for r in reader:
                city = (r.get("City") or r.get("Prefix") or "").strip().upper()
                code = (r.get("Code") or "").strip().upper()
                t = (r.get("Type") or "").strip()
                line = (r.get("Line") or "").strip()
                station = (r.get("Station") or "").strip()
                if not city or not code:
                    continue
                if not t and not line and not station:
                    continue

                def add_entry(c, cd, typ, l, st):
                    k = f"{c},{cd}"
                    if k in station_map:
                        prev_t, prev_line, prev_station = station_map[k].split("|")
                        if not prev_station and st:
                            station_map[k] = f"{typ or prev_t}|{l or prev_line}|{st}"
                    else:
                        station_map[k] = f"{typ}|{l}|{st}"

                add_entry(city, code, t, line, station)

                # Special aliases for Shanghai CU metro codes: 11LLSS <-> 31LLSS
                if city in ("2000", "2900") and code.startswith("11") and len(code) >= 4:
                    sh_31 = "31" + code[2:]
                    add_entry("2000", sh_31, t, line, station)
                    add_entry("2900", sh_31, t, line, station)
                    add_entry("3104", sh_31, t, line, station)

                # Special aliases for Luoyang terminal city prefix: 4131 <-> 4930
                if city == "4930":
                    add_entry("4131", code, t, line, station)

    print(f"Loaded {len(station_map)} station/line entries.")

    # 3. Generate Dart file
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write("// Generated file from tripreader-data. Do not edit manually.\n\n")

        # TUnionStationInfo class
        f.write("""class TUnionStationInfo {
  final String cityCode;
  final String? cityName;
  final String type;
  final String line;
  final String station;

  const TUnionStationInfo({
    required this.cityCode,
    this.cityName,
    required this.type,
    required this.line,
    required this.station,
  });

  String get formatted {
    final cityPrefix = cityName ?? (cityCode.isNotEmpty ? '城市 $cityCode' : '');
    final typeStr = type.isNotEmpty ? type : '交通';
    final tag = cityPrefix.isNotEmpty ? '[$cityPrefix$typeStr]' : '[$typeStr]';

    if (line.isNotEmpty && station.isNotEmpty) {
      return '$tag $line $station';
    } else if (station.isNotEmpty) {
      return '$tag $station';
    } else if (line.isNotEmpty) {
      return '$tag $line';
    } else {
      return tag;
    }
  }

  @override
  String toString() => formatted;
}

""")

        # tunionCityMap
        f.write("/// City Code (4 hex digits) to Chinese City Name\n")
        f.write("const Map<String, String> tunionCityMap = {\n")
        for k, v in sorted(CITY_NAMES.items()):
            f.write(f"  '{escape_dart_str(k)}': '{escape_dart_str(v)}',\n")
        f.write("};\n\n")

        # tunionIinMap
        f.write("/// IIN (e.g. first 8-10 digits of card number) to Card Issuer Name\n")
        f.write("const Map<String, String> tunionIinMap = {\n")
        for k, v in sorted(iin_map.items()):
            f.write(f"  '{escape_dart_str(k)}': '{escape_dart_str(v)}',\n")
        f.write("};\n\n")

        # tunionIssuerMap
        f.write("/// Issuer Code to Card Issuer Name\n")
        f.write("const Map<String, String> tunionIssuerMap = {\n")
        for k, v in sorted(issuer_map.items()):
            f.write(f"  '{escape_dart_str(k)}': '{escape_dart_str(v)}',\n")
        f.write("};\n\n")

        # tunionStationMap
        f.write("/// CityCode,Code -> Type|Line|Station\n")
        f.write("const Map<String, String> tunionStationMap = {\n")
        for k, v in sorted(station_map.items()):
            f.write(f"  '{escape_dart_str(k)}': '{escape_dart_str(v)}',\n")
        f.write("};\n\n")

        # Lookup functions
        f.write("""/// Look up T-Union Card Name by Card Number (ASN) or Issuer Code
String? lookupTUnionIssuer(String? cardNumber) {
  if (cardNumber == null || cardNumber.isEmpty) return null;
  final cleanNum = cardNumber.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  
  // 1. Try variable length IIN prefixes (e.g. 10-digit, 8-digit)
  if (cleanNum.length >= 10) {
    final iin10 = cleanNum.substring(0, 10);
    final name10 = tunionIinMap[iin10];
    if (name10 != null && name10.isNotEmpty) return name10;
  }
  if (cleanNum.length >= 8) {
    final iin8 = cleanNum.substring(0, 8);
    final name8 = tunionIinMap[iin8];
    if (name8 != null && name8.isNotEmpty) return name8;
  }

  // 2. Try Issuer code direct lookup
  final issuerName = tunionIssuerMap[cleanNum];
  if (issuerName != null && issuerName.isNotEmpty) return issuerName;

  if (cleanNum.length >= 8) {
    final issuer8 = cleanNum.substring(0, 8);
    final name8 = tunionIssuerMap[issuer8];
    if (name8 != null && name8.isNotEmpty) return name8;
  }

  return null;
}

/// Look up City Name by 4-digit City Code
String? lookupTUnionCity(String? cityCode) {
  if (cityCode == null || cityCode.isEmpty) return null;
  return tunionCityMap[cityCode.toUpperCase()];
}

/// Look up Station/Line info for a T-Union transaction
TUnionStationInfo? lookupTUnionStation({
  required String cityCode,
  String? stationCode,
  String? terminalId,
  String? industryCode,
}) {
  var cleanCity = cityCode.trim().toUpperCase();
  final cleanStation = stationCode?.trim().toUpperCase() ?? '';
  final cleanTerm = terminalId?.trim().toUpperCase() ?? '';
  final isBus = industryCode == '0001' || industryCode == '01';
  final isMetro = industryCode == '0002' || industryCode == '02';

  // If cityCode is not specified but terminalId starts with known 4-digit city prefix (e.g. 4131 for Luoyang)
  if (cleanCity.isEmpty && cleanTerm.length >= 4) {
    final pfx4 = cleanTerm.substring(0, 4);
    if (tunionCityMap.containsKey(pfx4)) {
      cleanCity = pfx4;
    }
  }

  final cityName = tunionCityMap[cleanCity];

  // Helper to parse Type|Line|Station
  TUnionStationInfo parseEntry(String city, String rawVal) {
    final parts = rawVal.split('|');
    return TUnionStationInfo(
      cityCode: city,
      cityName: tunionCityMap[city],
      type: parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : '交通',
      line: parts.length > 1 ? parts[1] : '',
      station: parts.length > 2 ? parts[2] : '',
    );
  }

  // 1. Station code matching within city
  if (cleanCity.isNotEmpty && cleanStation.isNotEmpty) {
    final strippedTrailingZeros = cleanStation.replaceAll(RegExp(r'(00)+$'), '');
    final cleanCode = strippedTrailingZeros.isNotEmpty ? strippedTrailingZeros : cleanStation;

    // 1.1 First priority: Match exact station entries (with non-empty station name)
    final candidates = <String>[];
    if (strippedTrailingZeros.isNotEmpty) candidates.add(strippedTrailingZeros);
    candidates.add(cleanStation);
    if (cleanStation.length >= 8) candidates.add(cleanStation.substring(0, 8));
    if (cleanStation.length >= 6) candidates.add(cleanStation.substring(0, 6));
    if (cleanStation.length >= 4) candidates.add(cleanStation.substring(0, 4));

    if (cleanStation.length == 8) {
      // 00LL00SS -> 010014 (6 chars)
      candidates.add(cleanStation.substring(2));
      // 00LL00SS -> 020E (2-digit line + 2-digit station)
      candidates.add(cleanStation.substring(2, 4) + cleanStation.substring(6, 8));
    }

    // Try finding an exact station match in CSV (e.g. 七里河, 青年宫, 马栏广场, 机场, 莘庄)
    for (final cand in candidates) {
      final match = tunionStationMap['$cleanCity,$cand'];
      if (match != null) {
        final parsed = parseEntry(cleanCity, match);
        // If it has a specific station name, it is a confirmed station match!
        if (parsed.station.isNotEmpty) {
          return parsed;
        }
      }
    }

    // 1.2 Second priority: Bus / BRT CSV entries
    for (final cand in candidates) {
      final match = tunionStationMap['$cleanCity,$cand'];
      if (match != null) {
        final parsed = parseEntry(cleanCity, match);
        if (parsed.type == '公交' || parsed.type == 'BRT') {
          return parsed;
        }
      }
    }

    // 1.3 Third priority: Decode Bus Line Number from stationCode for verified cities (e.g. Dalian 2220, Shanghai 2900/3104)
    final isDalian = cleanCity == '2220';
    final isShanghai = cleanCity == '2900' || cleanCity == '3104' || cleanCity == '3100';

    if (isDalian) {
      final pfx4 = cleanCode.length >= 4 ? cleanCode.substring(0, 4) : cleanCode;
      // Hex integer (e.g. 01FD == 509 -> 509路)
      if (pfx4.length >= 4 && RegExp(r'^[0-9A-Fa-f]+$').hasMatch(pfx4) && RegExp(r'[A-Fa-f]').hasMatch(pfx4)) {
        final hexVal = int.tryParse(pfx4, radix: 16);
        if (hexVal != null && hexVal > 0 && hexVal <= 2000) {
          return TUnionStationInfo(
            cityCode: cleanCity,
            cityName: cityName,
            type: '公交',
            line: '${hexVal}路',
            station: '',
          );
        }
      }

      // BCD / Decimal integer (e.g. 0509 -> 509路, 1106 -> 1106路, 0001 -> 1路)
      if (RegExp(r'^\d+$').hasMatch(pfx4)) {
        final decNum = int.tryParse(pfx4);
        if (decNum != null && decNum > 0 && decNum <= 2000) {
          return TUnionStationInfo(
            cityCode: cleanCity,
            cityName: cityName,
            type: '公交',
            line: '${decNum}路',
            station: '',
          );
        }
      }
    } else if (isShanghai) {
      final pfx4 = cleanCode.length >= 4 ? cleanCode.substring(0, 4) : cleanCode;
      if (RegExp(r'^\d+$').hasMatch(pfx4)) {
        final decNum = int.tryParse(pfx4);
        if (decNum != null && decNum > 0 && decNum <= 2000) {
          return TUnionStationInfo(
            cityCode: cleanCity,
            cityName: cityName,
            type: '公交',
            line: '${decNum}路',
            station: '',
          );
        }
      }
    }

    // Default fallback for bus transactions without verified line format: cleanly return [城市公交]
    return TUnionStationInfo(
      cityCode: cleanCity,
      cityName: cityName,
      type: '公交',
      line: '',
      station: '',
    );
  }

  // 2. Terminal ID matching within city
  if (cleanCity.isNotEmpty && cleanTerm.isNotEmpty) {
    final termMatch = tunionStationMap['$cleanCity,$cleanTerm'];
    if (termMatch != null) {
      return parseEntry(cleanCity, termMatch);
    }

    final termPrefixes = <String>[];
    if (cleanTerm.length >= 8) termPrefixes.add(cleanTerm.substring(0, 8));
    if (cleanTerm.length >= 6) termPrefixes.add(cleanTerm.substring(0, 6));
    if (cleanTerm.length >= 4) termPrefixes.add(cleanTerm.substring(0, 4));

    for (final pfx in termPrefixes) {
      final pfxMatch = tunionStationMap['$cleanCity,$pfx'];
      if (pfxMatch != null) {
        return parseEntry(cleanCity, pfxMatch);
      }
    }
  }

  // 3. Global Full Terminal ID (only for 8+ digits unique terminals like Hangzhou 413101784816 or Shanghai 310111744302)
  if (cleanTerm.length >= 8) {
    for (final cityKey in tunionCityMap.keys) {
      final crossMatch = tunionStationMap['$cityKey,$cleanTerm'];
      if (crossMatch != null) {
        return parseEntry(cityKey, crossMatch);
      }
    }
    // Shanghai CU terminal prefix 31LLSS
    if (cleanTerm.startsWith('31') && cleanTerm.length >= 6) {
      final pfx6 = cleanTerm.substring(0, 6);
      final shMatch = tunionStationMap['2900,$pfx6'] ?? tunionStationMap['2000,$pfx6'] ?? tunionStationMap['3104,$pfx6'];
      if (shMatch != null) {
        return parseEntry('2900', shMatch);
      }
    }
  }

  // 4. If only City is known
  if (cityName != null) {
    final typeStr = isMetro ? '地铁' : (isBus ? '公交' : '交通');
    return TUnionStationInfo(
      cityCode: cleanCity,
      cityName: cityName,
      type: typeStr,
      line: '',
      station: '',
    );
  }

  return null;
}

/// Format station or route details for a transaction
String formatTUnionDetails({
  required String cityCode,
  String? stationCode,
  String? terminalId,
  String? industryCode,
  int typeCode = 0,
  String? entryCityCode,
  String? entryStationCode,
  String? entryIndustryCode,
  double amount = 0.0,
}) {
  final exitInfo = lookupTUnionStation(
    cityCode: cityCode,
    stationCode: stationCode,
    terminalId: terminalId,
    industryCode: industryCode,
  );

  // If entry station is provided
  if (entryCityCode != null && entryCityCode.isNotEmpty && entryStationCode != null && entryStationCode.isNotEmpty) {
    final entryInfo = lookupTUnionStation(
      cityCode: entryCityCode,
      stationCode: entryStationCode,
      industryCode: entryIndustryCode,
    );

    if (amount == 0.0 || typeCode == 0x03) {
      // Entry-only transaction (tap in)
      if (entryInfo != null) {
        return '${entryInfo.formatted} (乘入)';
      }
    } else {
      // Completed trip (entry -> exit)
      if (entryInfo != null && exitInfo != null) {
        final entryName = entryInfo.station.isNotEmpty ? entryInfo.station : (entryInfo.line.isNotEmpty ? entryInfo.line : entryStationCode);
        final exitName = exitInfo.station.isNotEmpty ? exitInfo.station : (exitInfo.line.isNotEmpty ? exitInfo.line : (stationCode ?? ''));
        final linePrefix = exitInfo.line.isNotEmpty ? '${exitInfo.line} ' : (entryInfo.line.isNotEmpty ? '${entryInfo.line} ' : '');
        final city = exitInfo.cityName ?? entryInfo.cityName ?? '';
        final cityTag = city.isNotEmpty ? '[$city${exitInfo.type}] ' : '';
        if (entryName == exitName) {
          return '$cityTag$linePrefix$exitName';
        }
        return '$cityTag$linePrefix$entryName ──► $exitName';
      }
    }
  }

  if (exitInfo != null) {
    if (typeCode == 0x03 || (amount == 0.0 && stationCode != null && stationCode.isNotEmpty)) {
      return '${exitInfo.formatted} (乘入)';
    }
    if (typeCode == 0x04 && exitInfo.type != '公交') {
      return '${exitInfo.formatted} (乘出)';
    }
    return exitInfo.formatted;
  }

  if (terminalId != null && terminalId.isNotEmpty) {
    return 'Terminal: $terminalId';
  }

  return '';
}
""")

    print(f"Successfully generated {OUTPUT_FILE}")

if __name__ == "__main__":
    main()
