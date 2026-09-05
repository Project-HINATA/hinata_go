// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'HINATA Go';

  @override
  String get settings => '设置';

  @override
  String get cardExpiration => '卡片显示时长';

  @override
  String get cardExpirationDescription => '扫描卡片后自动清除前的显示秒数';

  @override
  String cardExpirationValue(String seconds) {
    return '$seconds 秒';
  }

  @override
  String get secondaryConfirmation => '二次确认';

  @override
  String get secondaryConfirmationDescription => '发送卡片数据前要求确认';

  @override
  String get about => '关于';

  @override
  String updateToVersion(String version) {
    return '更新到 $version';
  }

  @override
  String get updateViaGithub => 'GitHub 发布页';

  @override
  String get updateViaGooglePlay => 'Google Play';

  @override
  String get updateViaAppStore => 'App Store';

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
  String get scan => '扫描';

  @override
  String get cards => '卡片';

  @override
  String get scanQrCode => '扫描二维码';

  @override
  String get scanning => '扫描中...';

  @override
  String get tapToScan => '触摸后开始扫描';

  @override
  String get readyToScan => '准备扫描';

  @override
  String get nfcInactive => '没有可用扫描设备';

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
  String sourceLine(String source) {
    return '来源：$source';
  }

  @override
  String timeLine(String time) {
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
  String deleteFolderMessage(String folderName) {
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
  String confirmSendWithValue(String value) {
    return '确定要发送这张卡片吗？\nValue: $value';
  }

  @override
  String get remoteInstances => '远程实例';

  @override
  String get noInstancesConfigured => '尚未配置实例。';

  @override
  String get addInstance => '添加实例';

  @override
  String instanceNowActive(String name) {
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
  String get remotePassword => '密码（可选）';

  @override
  String remotePasswordIoVersionRequirement(String version) {
    return '启用密码后，只有 IO $version 及以上版本才能接收卡片。';
  }

  @override
  String get selectIcon => '选择图标:';

  @override
  String confirmSendToActiveInstance(String cardName) {
    return '将这张 $cardName 卡片发送到活动实例吗？';
  }

  @override
  String cardDetails(String cardName) {
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
  String get selectInstance => '选择实例';

  @override
  String get noInstances => '尚未配置任何实例。';

  @override
  String savedToFolder(String name, String folder) {
    return '已将“$name”保存到 $folder。';
  }

  @override
  String get cameraScanInstruction => '扫描二维码';

  @override
  String get historyFolder => '历史';

  @override
  String get favoritesFolder => '收藏';

  @override
  String sourceNfcWithType(String displayType) {
    return 'NFC（$displayType）';
  }

  @override
  String get nfcDeviceNotSupported => '你的设备不支持 NFC';

  @override
  String get nfcEnablePrompt => '请启用 NFC';

  @override
  String get nfcListening => '正在监听 NFC...';

  @override
  String nfcError(String error) {
    return '错误：$error';
  }

  @override
  String get nfcIosAlert => '请将卡片靠近 iPhone 顶部';

  @override
  String get nfcFelicaOnlyLongPressHint => '长按扫描区域，可读取另一台 iPhone 上的日本交通卡或香港八达通';

  @override
  String get nfcIosFelicaOnlyPrompt => '仅扫描 FeliCa：请将两台 iPhone 的顶部靠近';

  @override
  String get nfcIosFelicaOnlyAlert =>
      '仅扫描 FeliCa：请将本机靠近另一台 iPhone，以读取日本交通卡或香港八达通';

  @override
  String get noActiveInstanceSelected => '未选择活动实例。';

  @override
  String sendingToInstance(String name) {
    return '正在发送到 $name...';
  }

  @override
  String successSentToInstance(String name) {
    return '发送成功：已发送到 $name';
  }

  @override
  String failedSentToInstance(String name) {
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
  String exportFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String get importSuccess => '导入成功';

  @override
  String importFailed(String error) {
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
  String itemCountCards(int count) {
    return '卡片：$count';
  }

  @override
  String itemCountFolders(int count) {
    return '文件夹：$count';
  }

  @override
  String itemCountInstances(int count) {
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
  String get confirmOverwriteMessage => '这将不可恢复地覆盖您的本地数据。您确定吗？';

  @override
  String get invalidAccessCodeLength => '访问代码必须为 20 位数字且不能以 3 开头';

  @override
  String get hardwareDevice => '设备';

  @override
  String get firmwareUpdate => '固件更新';

  @override
  String get ledSettings => 'LED 设置';

  @override
  String get deviceHub => '设备中心';

  @override
  String get noDeviceConnected => '未连接设备';

  @override
  String get scanForDevices => '扫描 HINATA USB 读卡器';

  @override
  String get scanUsbDevice => '扫描 USB 设备';

  @override
  String get saveToFlash => '保存到闪存';

  @override
  String get configSavedSuccess => '配置已成功保存到闪存！';

  @override
  String errorSavingFlash(String error) {
    return '保存到闪存时出错: $error';
  }

  @override
  String get upToDate => '您的设备固件已是最新！';

  @override
  String get updateAvailable => '发现新版本';

  @override
  String latestVersion(String version) {
    return '最新版本: $version';
  }

  @override
  String get startUpdate => '开始更新';

  @override
  String get retryUpdate => '重试更新';

  @override
  String get failedToCheckFirmware => '获取固件信息失败。';

  @override
  String get settingsAndControls => '设置与控制';

  @override
  String get advancedConfig => '高级配置';

  @override
  String get checkLatestSoftware => '检查并下载最新固件';

  @override
  String get configureLighting => '配置灯效与颜色';

  @override
  String firmwareVersion(String version) {
    return '固件版本: $version';
  }

  @override
  String get tapToConnect => '点击连接';

  @override
  String get globalSettings => '全局设置';

  @override
  String get segaSerialSettings => 'SEGA 串口协议设置';

  @override
  String get cardioSettings => 'CardIO 设置';

  @override
  String get restoreDefaults => '恢复默认值';

  @override
  String get processing => '处理中';

  @override
  String get applySettings => '保存设置';

  @override
  String get tipsTitle => 'Tips:';

  @override
  String get flashWarning =>
      '如果你不点击保存，那么读卡器重新上电后会恢复原来的设置，但由于flash芯片寿命有限，只能擦写几百次，也就是只能保存几百次，所以建议你考虑好后再保存';

  @override
  String get usbDescriptorNote =>
      'USB描述符唯一性需要保存后给读卡器重新上电才可以生效，并且修改后会被操作系统认为是一个全新的设备，SEGA游戏需要重新设置端口，上位机会需要重新配对设备';

  @override
  String get cardioDisableIso14443a => '不上报 ISO14443-A 卡片';

  @override
  String get cardioIso14443aE004 => '为 ISO14443-A 卡号头部填充 E004';

  @override
  String get uniqueDescriptor => 'USB描述符唯一性';

  @override
  String get ledRainbow => '彩虹灯效';

  @override
  String get segaFwHw => 'HW/FW';

  @override
  String get segaFastRead => '高速读卡';

  @override
  String get segaBrightness => 'LED亮度';

  @override
  String get idleRGB => '待机灯光颜色';

  @override
  String get busyRGB => '待机刷卡灯光颜色';

  @override
  String get pickFavoriteColor => '选一个喜欢的颜色吧~';

  @override
  String get confirmColorChoice => '就这个了！';

  @override
  String get scanPaused => '扫描暂停';

  @override
  String get scanPausedDescription => '应用失去焦点，扫描已暂停';

  @override
  String get unknownCardType => '不可在游戏中使用的卡片';

  @override
  String get unusableMifareCardWarning => '这张卡无法在游戏中使用。';

  @override
  String get transitBalance => '余额';

  @override
  String get cardNumber => '卡号';

  @override
  String get transactionHistory => '交易记录';

  @override
  String get snapshotTime => '快照时间';

  @override
  String get noTransactions => '暂无交易记录';

  @override
  String get transitTypeRide => '乘车';

  @override
  String get transitTypeTopup => '充值';

  @override
  String get transitTypeShopping => '消费';

  @override
  String get transitTypeAdjustment => '调整/精算';

  @override
  String get transitTypeRefund => '退款';

  @override
  String get transitTypeIssue => '发行';

  @override
  String get transitTypeDeduction => '扣费';

  @override
  String get transitTypeReissue => '补卡发行';

  @override
  String get transitTypeOther => '其他';

  @override
  String get duplicateCardTitle => '卡片已存在';

  @override
  String get duplicateCardPrompt => '已经存在相同卡片，要覆盖吗';

  @override
  String get overwrite => '确认';

  @override
  String get renameCard => '重命名卡片';

  @override
  String get cardNameLabel => '新卡片名称';

  @override
  String get deleteCard => '删除卡片';

  @override
  String get confirmDeleteCard => '确定要删除这张卡片吗？删除后数据将无法恢复。';

  @override
  String get renameSuccess => '重命名成功';

  @override
  String get deleteSuccess => '删除成功';

  @override
  String get nfcReadIncomplete => '卡片读取未完成，请重新贴卡。';

  @override
  String get tagTUnion => '交通联合';

  @override
  String get tagJapanTransit => '交通系 IC';

  @override
  String get transitCardType => '卡片类型';

  @override
  String get transitExpiryDate => '有效期至';

  @override
  String get transitIssueDate => '发卡日期';

  @override
  String get transitCardTypeStandard => '普通卡';

  @override
  String get transitCardTypeStudent => '学生卡';

  @override
  String get transitCardTypeSenior => '老人卡';

  @override
  String get transitCardTypeMilitary => '军人卡';

  @override
  String transitCardTypeOther(String code) {
    return '其他 ($code)';
  }

  @override
  String get cardWrite => '写入';

  @override
  String get cardWriteTitle => '写入 MIFARE 卡片';

  @override
  String get cardWriteWarningWritable => '并非所有卡片都可以写入，请以实际写入结果为准。';

  @override
  String get cardWriteWarningUid => '写入不会覆盖卡片原有 UID。';

  @override
  String get cardWriteWarningCompatibility => '写入后不保证能在所有机器或服务器上使用。';

  @override
  String get cardWriteMode => '写入后的访问方式';

  @override
  String get cardWriteRewritable => '可再次写入';

  @override
  String get cardWriteRewritableDescription => '之后仍可使用支持的密钥更新卡片。';

  @override
  String get cardWritePermanent => '永久只读';

  @override
  String get cardWritePermanentDescription => '访问控制将被锁死，无法恢复。';

  @override
  String get cardWritePermanentConfirmTitle => '永久锁定这张卡片？';

  @override
  String get cardWritePermanentConfirmBody =>
      '此操作会不可逆地修改扇区访问控制，之后无法再改写相关数据块或密钥。';

  @override
  String get cardWriteStart => '开始写入';

  @override
  String get cardWriteConfirmPermanent => '锁定并写入';

  @override
  String get cardWriteWaitingForCard => '请将 MIFARE Classic 1K 卡片贴近手机或读卡器';

  @override
  String get cardWriteCheckingCard => '正在检查卡片类型';

  @override
  String get cardWriteCheckingPermissions => '正在检查密钥和访问控制';

  @override
  String get cardWriteWritingData => '正在写入卡片数据';

  @override
  String get cardWriteLockingCard => '正在写入访问控制';

  @override
  String get cardWriteVerifying => '正在验证写入结果';

  @override
  String get cardWriteSuccess => '卡片写入并验证成功';

  @override
  String get cardWriteFailed => '卡片写入失败';

  @override
  String get cardWriteUnsupportedSavedCard => '仅支持写入已保存的 Aime 和 Banapass 卡片';

  @override
  String get cardWriteNoBackend => '卡片写入需要安卓 NFC 或已连接的 HINATA 读卡器';

  @override
  String get cardWriteUnsupportedTarget =>
      '请使用 4 字节 UID 的 MIFARE Classic 1K 卡片';

  @override
  String get cardWriteUnknownKey => '无法使用支持的密钥认证该卡片';

  @override
  String get cardWriteInvalidAccessBits => '卡片的 MIFARE 访问位无效';

  @override
  String get cardWritePermissionDenied => '卡片当前访问控制不允许本次写入';

  @override
  String get cardWriteCardRemoved => '卡片已移开，或等待卡片超时';

  @override
  String get cardWriteVerificationFailed => '无法验证写入后的数据';

  @override
  String get cardWriteDone => '完成';

  @override
  String get cardWriteCancelled => '已在修改数据前取消卡片写入';
}
