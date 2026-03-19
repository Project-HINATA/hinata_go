// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'SEGA NFC';

  @override
  String get settings => '设置';

  @override
  String get secondaryConfirmation => '二次确认';

  @override
  String get secondaryConfirmationDescription => '发送卡片数据前要求确认';

  @override
  String get about => '关于';

  @override
  String updateToVersion(Object version) {
    return '更新到 $version';
  }

  @override
  String get language => '语言';

  @override
  String get languageDescription => '选择应用显示语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglishNative => 'English';

  @override
  String get languageChineseNative => '简体中文';

  @override
  String get reader => '读取';

  @override
  String get cards => '卡片';

  @override
  String get scanQrCode => '扫描二维码';

  @override
  String get scanning => '扫描中...';

  @override
  String get tapToScan => '点击开始扫描';

  @override
  String get readyToScan => '准备扫描';

  @override
  String get nfcInactive => 'NFC 未激活';

  @override
  String get holdCardNearTop => '请将卡片靠近 iPhone 顶部。';

  @override
  String get tapToActivateNfc => '点击此区域以启用 NFC 读取器。';

  @override
  String get holdCardNearReader => '请将卡片靠近设备的 NFC 感应区域。';

  @override
  String get nfcUnavailable => 'NFC 服务当前不可用或未启用。';

  @override
  String get noActiveInstanceSelectedTap => '未选择活动实例。\n点击以选择。';

  @override
  String get noRecentScans => '暂无最近扫描记录。';

  @override
  String get recentScans => '最近扫描';

  @override
  String get viewAllLogs => '查看全部日志';

  @override
  String get resendToActiveInstance => '重新发送到当前活动实例';

  @override
  String get scanHistoryLogs => '扫描历史日志';

  @override
  String get clearHistory => '清空历史';

  @override
  String get noScanHistoryYet => '暂无扫描历史。';

  @override
  String get savedCardsSource => '已保存卡片';

  @override
  String sourceLine(Object source) {
    return '来源：$source';
  }

  @override
  String timeLine(Object time) {
    return '时间：$time';
  }

  @override
  String get saveToSavedCards => '保存到已保存卡片';

  @override
  String get savedCards => '已保存卡片';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get noCardsInFolder => '此文件夹中没有卡片。';

  @override
  String get addCard => '添加卡片';

  @override
  String get cannotDeleteDefaultFolders => '无法删除默认文件夹。';

  @override
  String get deleteFolder => '删除文件夹？';

  @override
  String deleteFolderMessage(Object folderName) {
    return '确定要删除“$folderName”及其中所有卡片吗？';
  }

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get quickSend => '快速发送';

  @override
  String get addCardManually => '手动添加卡片';

  @override
  String get nameDescription => '名称 / 描述';

  @override
  String get folder => '文件夹';

  @override
  String get newFolderOption => '+ 新建文件夹';

  @override
  String get accessCode => 'Access Code';

  @override
  String get save => '保存';

  @override
  String get folderName => '文件夹名称';

  @override
  String get create => '创建';

  @override
  String get confirmSend => '确认发送';

  @override
  String confirmSendWithValue(Object value) {
    return '确定要发送这张卡片吗？\nValue: $value';
  }

  @override
  String get remoteInstances => '远程实例';

  @override
  String get noInstancesConfigured => '尚未配置实例。';

  @override
  String get addInstance => '添加实例';

  @override
  String instanceNowActive(Object name) {
    return '$name 现已激活';
  }

  @override
  String get invalidUrl => '请输入有效的 URL（http/https）';

  @override
  String get invalidEndpoint => '请输入有效的地址';

  @override
  String get editInstance => '编辑实例';

  @override
  String get nameExample => '名称（例如 maimaiDX）';

  @override
  String get webhookUrl => 'Webhook URL (http://...)';

  @override
  String get endpointLabel => '地址';

  @override
  String get instanceType => '实例类型';

  @override
  String get instanceTypeHinataIo => 'HINATA IO';

  @override
  String get instanceTypeSpiceApi => 'SpiceAPI (TcpSocket)';

  @override
  String get instanceTypeSpiceApiWebSocket => 'SpiceAPI (WebSocket)';

  @override
  String get spiceApiUnit => 'SpiceAPI Unit';

  @override
  String get spiceApiPassword => '密码（可选）';

  @override
  String get selectIcon => '选择图标:';

  @override
  String confirmSendToActiveInstance(Object cardName) {
    return '将这张 $cardName 卡片发送到活动实例吗？';
  }

  @override
  String cardDetails(Object cardName) {
    return '$cardName 详情';
  }

  @override
  String get valueCopiedToClipboard => '已复制 Value 到剪贴板';

  @override
  String get copyValue => '复制 Value';

  @override
  String get amusementIcInfo => 'Amusement IC 信息';

  @override
  String get manufacturer => 'Manufacturer';

  @override
  String get aimeInfo => 'Aime 信息';

  @override
  String get felicaDetails => 'FeliCa 技术详情';

  @override
  String get idm => 'IDm';

  @override
  String get pmm => 'PMm';

  @override
  String get systemCode => 'System Code';

  @override
  String get banapassData => 'Banapassport 数据';

  @override
  String get block1 => 'Block 1';

  @override
  String get block2 => 'Block 2';

  @override
  String get iso14443Details => 'ISO14443 技术详情';

  @override
  String get uid => 'UID';

  @override
  String get sak => 'SAK';

  @override
  String get atqa => 'ATQA';

  @override
  String get technicalDetails => '技术详情';

  @override
  String get idOrValue => 'ID / Value';

  @override
  String get savingUpper => '保存中...';

  @override
  String get saveUpper => '保存';

  @override
  String get sendingUpper => '发送中...';

  @override
  String get sendUpper => '发送';

  @override
  String get send => '发送';

  @override
  String get saveToFolder => '保存到文件夹';

  @override
  String savedToFolder(Object name, Object folder) {
    return '已将“$name”保存到 $folder。';
  }

  @override
  String get cameraScanInstruction => '扫描二维码';

  @override
  String get historyFolder => '历史';

  @override
  String get favoritesFolder => '收藏';

  @override
  String sourceNfcWithType(Object displayType) {
    return 'NFC（$displayType）';
  }

  @override
  String get nfcDeviceNotSupported => '你的设备不支持 NFC';

  @override
  String get nfcEnablePrompt => '请启用 NFC';

  @override
  String get nfcListening => '正在监听 NFC...';

  @override
  String nfcError(Object error) {
    return '错误：$error';
  }

  @override
  String get nfcIosAlert => '请将卡片靠近 iPhone 顶部';

  @override
  String get noActiveInstanceSelected => '未选择活动实例。';

  @override
  String sendingToInstance(Object name) {
    return '正在发送到 $name...';
  }

  @override
  String successSentToInstance(Object name) {
    return '发送成功：已发送到 $name';
  }

  @override
  String failedSentToInstance(Object name) {
    return '发送失败：无法发送到 $name';
  }

  @override
  String get dataManagement => '数据管理';

  @override
  String get dataManagementDescription => '导入或导出卡包和实例';

  @override
  String get exportData => '导出数据';

  @override
  String get importData => '导入数据';

  @override
  String get exportSuccess => '导出成功';

  @override
  String exportFailed(Object error) {
    return '导出失败：$error';
  }

  @override
  String get importSuccess => '导入成功';

  @override
  String importFailed(Object error) {
    return '导入失败：$error';
  }

  @override
  String get exportToClipboard => '复制到剪贴板';

  @override
  String get exportToFile => '保存为文件';

  @override
  String get importFromClipboard => '从剪贴板粘贴';

  @override
  String get importFromFile => '从文件加载';

  @override
  String get selectExportMethod => '选择导出方式';

  @override
  String get selectImportMethod => '选择导入方式';

  @override
  String get invalidDataFormat => '数据格式无效';

  @override
  String get importPreviewTitle => '导入预览';

  @override
  String get importPreviewMessage => '将要导入以下数据：';

  @override
  String itemCountCards(Object count) {
    return '卡片：$count';
  }

  @override
  String itemCountFolders(Object count) {
    return '文件夹：$count';
  }

  @override
  String itemCountInstances(Object count) {
    return '实例：$count';
  }

  @override
  String get confirmImport => '确认导入';

  @override
  String get importMerge => '合并导入';

  @override
  String get importOverwrite => '覆盖导入';

  @override
  String get confirmOverwriteTitle => '确认覆盖';

  @override
  String get confirmOverwriteMessage => '此操作将覆盖本地数据且无法恢复。是否确定？';

  @override
  String get invalidAccessCodeLength => 'Access Code 必须为 20 位数字且不能以 3 开头';
}
