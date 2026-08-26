#!/usr/bin/env python3
"""
generate_tunion_data.py

Parses tripreader-data CSVs and generates hinata_go/lib/utils/tunion_data.dart.
"""

import os
import glob
import csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
TRIPREADER_DIR = os.path.expanduser("~/Projects/tripreader-data")
OUTPUT_FILE = os.path.join(PROJECT_ROOT, "hinata_go", "lib", "utils", "tunion_data.dart")

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
    terminal_map = {}

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

                key = f"{city},{code}"
                # If entry already exists, prefer the one with station name or line
                if key in station_map:
                    prev_t, prev_line, prev_station = station_map[key].split("|")
                    if not prev_station and station:
                        station_map[key] = f"{t or prev_t}|{line or prev_line}|{station}"
                else:
                    station_map[key] = f"{t}|{line}|{station}"

                # If code looks like a terminal ID (e.g. Hangzhou or POS), also index by terminal
                if len(code) >= 8 and (code.isdigit() or all(c in '0123456789ABCDEF' for c in code)):
                    terminal_map[code] = f"{city}|{t}|{line}|{station}"

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
}) {
  final cleanCity = cityCode.trim().toUpperCase();
  final cleanStation = stationCode?.trim().toUpperCase() ?? '';
  final cleanTerm = terminalId?.trim().toUpperCase() ?? '';
  final cityName = tunionCityMap[cleanCity];

  // Helper to parse Type|Line|Station
  TUnionStationInfo parseEntry(String city, String rawVal) {
    final parts = rawVal.split('|');
    return TUnionStationInfo(
      cityCode: city,
      cityName: tunionCityMap[city],
      type: parts.isNotEmpty ? parts[0] : '',
      line: parts.length > 1 ? parts[1] : '',
      station: parts.length > 2 ? parts[2] : '',
    );
  }

  // 1. Exact match for (cityCode, stationCode)
  if (cleanStation.isNotEmpty) {
    final exact = tunionStationMap['$cleanCity,$cleanStation'];
    if (exact != null) {
      return parseEntry(cleanCity, exact);
    }
  }

  // 2. Terminal ID match for (cityCode, terminalId)
  if (cleanTerm.isNotEmpty) {
    final termMatch = tunionStationMap['$cleanCity,$cleanTerm'];
    if (termMatch != null) {
      return parseEntry(cleanCity, termMatch);
    }

    // Check across any city with this terminal ID
    for (final cityKey in tunionCityMap.keys) {
      final crossMatch = tunionStationMap['$cityKey,$cleanTerm'];
      if (crossMatch != null) {
        return parseEntry(cityKey, crossMatch);
      }
    }
  }

  // 3. Prefix matching on stationCode (e.g. 8-char code with 4-char line prefix)
  if (cleanStation.length >= 4) {
    // Try 4-char line code
    final lineCode = cleanStation.substring(0, 4);
    final lineMatch = tunionStationMap['$cleanCity,$lineCode'];
    if (lineMatch != null) {
      final info = parseEntry(cleanCity, lineMatch);
      // Return line match if found
      return TUnionStationInfo(
        cityCode: cleanCity,
        cityName: cityName,
        type: info.type,
        line: info.line,
        station: cleanStation,
      );
    }
  }

  // 4. If only City is known
  if (cityName != null && (cleanStation.isNotEmpty || cleanTerm.isNotEmpty)) {
    return TUnionStationInfo(
      cityCode: cleanCity,
      cityName: cityName,
      type: '交通',
      line: '',
      station: cleanStation.isNotEmpty ? '站点 $cleanStation' : (cleanTerm.isNotEmpty ? '终端 $cleanTerm' : ''),
    );
  }

  return null;
}

/// Format station or route details for a transaction
String formatTUnionDetails({
  required String cityCode,
  String? stationCode,
  String? terminalId,
  String? entryCityCode,
  String? entryStationCode,
}) {
  final exitInfo = lookupTUnionStation(
    cityCode: cityCode,
    stationCode: stationCode,
    terminalId: terminalId,
  );

  if (entryCityCode != null && entryCityCode.isNotEmpty && entryStationCode != null && entryStationCode.isNotEmpty) {
    final entryInfo = lookupTUnionStation(
      cityCode: entryCityCode,
      stationCode: entryStationCode,
    );

    if (entryInfo != null && exitInfo != null) {
      final entryName = entryInfo.station.isNotEmpty ? entryInfo.station : (entryInfo.line.isNotEmpty ? entryInfo.line : entryStationCode);
      final exitName = exitInfo.station.isNotEmpty ? exitInfo.station : (exitInfo.line.isNotEmpty ? exitInfo.line : (stationCode ?? ''));
      final linePrefix = exitInfo.line.isNotEmpty ? '${exitInfo.line} ' : '';
      final city = exitInfo.cityName ?? entryInfo.cityName ?? '';
      final cityTag = city.isNotEmpty ? '[$city${exitInfo.type}] ' : '';
      return '$cityTag$linePrefix$entryName ──► $exitName';
    }
  }

  if (exitInfo != null) {
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
