abstract final class HgAppMetadata {
  static const String version = '1.4.16';
  static const String buildNumber = '21';
  static const String versionLabel = 'v1.4.16 (21)';
  static const String releaseTitle = '后台节能与加载优化版';
  static const List<String> releaseNotes = [
    '全局骨架屏动画现在会跟随页面可见性自动暂停，离开当前 Tab 或切到后台后不再持续重绘。',
    '页面重新可见时骨架动画自动恢复，不影响加载状态和视觉连续性。',
    '继续统一首页、详情页、标签页与作者页的深色模式细节。',
  ];

  static const List<HgReleaseRecord> releaseHistory = [
    HgReleaseRecord(
      version: 'v1.4.16',
      buildNumber: '21',
      date: '2026-11-21',
      title: '后台节能与加载优化版',
      features: [],
      improvements: [
        '骨架屏动画接入页面可见性和应用生命周期，不可见时停止刷新。',
        '页面重新可见或恢复前台后自动继续加载动画，保持界面状态连贯。',
      ],
      fixes: [],
    ),
    HgReleaseRecord(
      version: 'v1.4.15',
      buildNumber: '20',
      date: '2026-11-21',
      title: '深色模式细节统一版',
      features: [],
      improvements: ['标签目录、标签详情和作者页的辅助元素统一使用主题色，深浅模式切换更一致。'],
      fixes: ['修复深色模式下标签分类、热度与说明文字偏灰难读的问题。', '修复作者页深色背景上返回按钮对比度不足的问题。'],
    ),
    HgReleaseRecord(
      version: 'v1.4.14',
      buildNumber: '19',
      date: '2026-11-21',
      title: '详情页与深色模式修正版',
      features: [],
      improvements: [
        '详情页评分信息增加稳定的半透明承托层，封面复杂时仍能快速读取。',
        '更多菜单操作项颜色改为跟随主题，浅色与深色模式保持一致。',
      ],
      fixes: ['修复详情更多菜单在深色模式下文字和图标不可见的问题。', '修复半屏详情菜单同时出现关闭按钮和拖动条的重复操作问题。'],
    ),
    HgReleaseRecord(
      version: 'v1.4.13',
      buildNumber: '18',
      date: '2026-11-21',
      title: '个人中心清晰度版',
      features: ['我的页面追剧、历史和喜欢内容库增加选中态、轻触反馈与自动定位。'],
      improvements: [
        '选中状态仅使用强调色、字重和短指示线，不增加灰色底块或缩放动画。',
        '关于果幕说明聚焦产品定位、数据来源与隐私边界。',
      ],
      fixes: [],
    ),
    HgReleaseRecord(
      version: 'v1.4.12',
      buildNumber: '17',
      date: '2026-11-21',
      title: '播放器手势增强版',
      features: ['播放画面支持横向拖动预览，并在松手后跳转到目标位置。', '播放中跳转后自动续播，拖动过程显示目标时间与相对变化秒数。'],
      improvements: [
        '横向拖动可与底部进度条、纵向切集和长按倍速共同使用。',
        '竖屏、横屏及清屏状态统一支持拖动预览，目标位置不会越过片头或片尾。',
      ],
      fixes: [],
    ),
    HgReleaseRecord(
      version: 'v1.4.11',
      buildNumber: '16',
      date: '2026-11-21',
      title: '首页顺滑与后台节能版',
      features: ['首页幻灯片与底部页面切换增加更自然的原生交互反馈。'],
      improvements: [
        '首页幻灯片离开当前 Tab 后停止自动推进，手动滑动结束再恢复计时。',
        '幻灯片自动切换缩短到 520 毫秒，并校正首张与指示点状态。',
        '不可见页面停用动画调度，减少后台帧更新与资源消耗。',
      ],
      fixes: ['修复部分幻灯片初始页码与底部指示点不一致的问题。'],
    ),
    HgReleaseRecord(
      version: 'v1.4.10',
      buildNumber: '15',
      date: '2026-11-21',
      title: '半屏交互与播放手感版',
      features: [
        '半屏面板顶部横条支持拖动展开、收起和关闭，并提供明确的无障碍操作提示。',
        '播放页清屏状态下单击可直接暂停或继续，同时恢复必要控件。',
      ],
      improvements: [
        '登录、评论、资料编辑和确认面板共享同一套键盘避让与安全区处理。',
        '面板展开与收起使用短时缓出动画，拖动时实时跟随手指。',
      ],
      fixes: ['修复顶部横条只能拖动外层弹窗、无法展开内部面板的问题。', '修复键盘弹出后表单被遮挡或重复增加底部留白的问题。'],
    ),
    HgReleaseRecord(
      version: 'v1.4.9',
      buildNumber: '14',
      date: '2026-11-21',
      title: '流畅播放与横屏体验版',
      features: ['进度条显示已缓冲范围，横屏播放器增加选集入口。'],
      improvements: [
        '拖动松手后保持目标位置直到跳转完成，进度条触控区域扩大至 48。',
        '缓冲提示延迟出现，短暂加载不再反复闪烁。',
        '横屏按钮避开屏幕缺口和系统安全区，退出全屏后保持沉浸播放。',
      ],
      fixes: [
        '修复接近片尾时提前跳转下一集、回拖后自动连播失效的问题。',
        '修复播放错误连续重试、重连后从头播放和初始化中离开页面的资源释放问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.8',
      buildNumber: '13',
      date: '2026-11-20',
      title: '播放手感与细节打磨版',
      features: [
        '播放页跟随设备物理方向自动切换竖屏和横屏，横屏控制按钮改为无底色图标。',
        '播放器暂停状态增加清晰的播放按钮，横屏返回按钮与竖屏保持一致。',
      ],
      improvements: [
        '横屏进度条与底部操作区上移，减少贴近系统手势区导致的误触。',
        '登录和编辑资料半屏面板移除重复关闭按钮，只保留顶部拖动条和下滑关闭手势。',
        '全局轻提示改为悬浮胶囊样式，并统一深色模式配色。',
        '缓存入口提示文案精简为“已加入下载队列”。',
      ],
      fixes: ['修复评论区下拉箭头与半屏拖动条重叠的问题。', '修复横屏视频在竖屏状态下使用封面填充画面的问题。'],
    ),
    HgReleaseRecord(
      version: 'v1.4.7',
      buildNumber: '12',
      date: '2026-11-20',
      title: '多源测速与启动稳定性版',
      features: [
        '数据源池记录延迟、成功率、连续失败、最近成功时间和冷却状态，并按健康评分选择线路。',
        '启动时后台并行测速，应用回到前台时轻量复核；设置页显示当前线路状态、延迟和最近检测时间，支持立即测速。',
        '首页、搜索、分类、标签、专题、榜单和评论等只读请求失败时自动回退到下一健康源。',
        '登录、点赞、收藏、评论和资料修改固定在当前源执行，不自动重复发送有副作用的请求。',
      ],
      improvements: [
        '缓存升级为 v2 结构并兼容 v1，缓存键按接口语义和参数复用，切换源不清空已有内容。',
        '首页、最近上新、热播、专题、标签、分类、榜单和搜索热词在启动阶段按有界并发预热。',
        '数据源发现继续使用本机网络，支持 GitHub 清单、官方发布页和已知域名白名单，手动添加地址会先验证真实接口。',
        '启动预加载首页、榜单、专题、标签和搜索热词，首屏内容显示更稳定。',
      ],
      fixes: [
        '修复切换数据源后内容缓存被清空、页面需要重新抓取的问题。',
        '修复请求失败后仍继续使用同一异常源、备用源无法及时接管的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.6',
      buildNumber: '11',
      date: '2026-11-18',
      title: '原生手感与主题一致性版',
      features: [],
      improvements: [
        '全站可点区域增加轻微按压叠色，交互更接近原生客户端。',
        'Android 使用 PredictiveBack 页面转场并启用 OnBackInvokedCallback。',
        '按平台区分滚动物理与边缘拉伸指示，iOS 列表恢复回弹。',
        '底部 Tab、帖子与播放页图标状态切换仅淡入，移除 easeOutBack 缩放。',
        '骨架屏渐变取自 ColorScheme，深色模式不再显示浅色占位块。',
        '移除全局 textScaler 上限；评论回复文本改用 Text.rich 继承缩放。',
        '半屏表单随 viewInsets 即时 padding，不再叠加 180ms AnimatedPadding。',
      ],
      fixes: [],
    ),
    HgReleaseRecord(
      version: 'v1.4.5',
      buildNumber: '10',
      date: '2026-11-16',
      title: '播放器与 iOS 后台能力版',
      features: [
        'iOS 灵动岛与锁屏实时活动补齐主 App 能力声明，并在播放开始时立即创建。',
        'iOS 接入系统 Now Playing 锁屏媒体信息和播放控制。',
        '启动时自动请求通知权限，后台音频与后台 App 刷新能力同步启用。',
        'iPhone 播放器支持左右横屏，退出播放器后自动恢复竖屏。',
      ],
      improvements: [
        '视频进度条改用 Flutter 原生 Slider，触控区域扩大并支持连续跟手拖动。',
        '进度条整体上移并放到选集栏上方，避免贴近系统手势区导致难以滑动。',
        '横屏视频竖屏显示时使用纯黑背景，不再以封面图填充画面。',
        '全屏观看按钮移动到画面上方，并扩大按钮点击区域。',
      ],
      fixes: [
        '修复评论区下箭头与半屏拖动条重合的问题。',
        '修复松手后等待视频 seek 完成才更新界面造成的卡顿感。',
        '修复 Live Activity 封面过大可能导致活动创建失败的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.4',
      buildNumber: '9',
      date: '2026-11-16',
      title: '原生面板与全局打磨版',
      features: [
        '半屏面板统一复用 Flutter 原生模态底部面板、系统拖动条和中大档吸附。',
        '新增统一确认面板，清空缓存、退出登录等操作不再使用居中系统弹窗。',
        '数据源、更新说明、消息详情和设置选择等长内容统一使用面板滚动控制器。',
      ],
      improvements: [
        '登录、编辑资料、评论、选集、分享和更新说明的面板高度改由容器统一控制。',
        '面板内文字、按钮和错误提示改为跟随浅色与深色主题。',
        '评论输入、数据源地址输入和帖子评论适配键盘与底部安全区。',
      ],
      fixes: [
        '修复半屏顶部横条无法可靠拖动、内外层滚动冲突和高度跳动的问题。',
        '修复我的页面消息角标和快捷入口角标背景透明、部分环境不可见的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.3',
      buildNumber: '8',
      date: '2026-11-16',
      title: '启动稳定性修复版',
      features: [
        'Android 增加品牌化原生启动画面，并优先渲染 Flutter 首帧。',
        '通知与后台任务改为界面显示后异步初始化，失败时自动降级。',
        'iOS Widget 补齐标准 Bundle 元数据，IPA 构建时强制检查主 App 与扩展。',
      ],
      improvements: [
        '通知图标加入 R8 资源保留清单，避免 Release 构建裁剪后导致插件初始化异常。',
        'Android 启动链路增加超时与错误降级，不再因可选插件阻塞进入首页。',
      ],
      fixes: [
        '修复 Sideloadly 安装时提示 Widget 缺少非空 CFBundleName 的问题。',
        '修复 Android Release 版本启动后停留在黑屏的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.2',
      buildNumber: '7',
      date: '2026-11-16',
      title: '离线缓存与原生体验版',
      features: [
        '新增整部短剧缓存、下载任务页面、下载进度与实时网速。',
        '未完结短剧支持记录追更，更新后可通知并可选自动缓存新集。',
        'iOS 支持灵动岛和锁屏实时活动，显示封面、剧名、观看集数与进度。',
        '设置页新增追更通知、自动缓存和后台检查开关。',
      ],
      improvements: [
        '剧场、吃瓜和榜单支持左右滑动切换 Tab，切换时保留页面状态。',
        '半屏弹窗统一为可拖拽的原生式面板，支持关闭、半屏和全屏吸附。',
        '首页轮播改为连续无限滚动，并从真实短剧详情补全横幅标题。',
        '全面修复深色模式的页面、卡片和弹窗背景；下拉刷新改为原生风格。',
        '移除 Android 预测式返回的半透明过渡，统一为整页推入。',
        'GitHub Pages 改为纯界面预览，进入播放页直接阻止视频加载。',
      ],
      fixes: [
        '修复“我的”页登录按钮文字被 padding 挤压的问题。',
        '修复轮播最后一张跳回第一张、以及空标题显示为“精选短剧”的问题。',
        '修复下载内容重启应用后无法恢复、离线找不到本地播放列表的问题。',
        '修复切换邻近剧集时默认不自动播放的问题。',
        '修复设置页更新记录与功能入口表达不清晰的问题。',
        '修复播放地址缓存过期导致的 Source error，重试时自动获取新地址。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.1',
      buildNumber: '6',
      date: '2026-11-16',
      title: '在线更新与稳定版',
      features: [
        '设置页和启动阶段通过 GitHub Releases 检查在线更新。',
        'GitHub Pages 在线预览、APK 和未签名 IPA 自动构建与发布。',
      ],
      improvements: [
        'GitHub 数据源清单增加 Contents API、jsDelivr 和 Raw 多级回退。',
        '产品 README 与关于果幕页面改为面向中文黄果短剧用户的正式产品说明。',
      ],
      fixes: [
        '修复 iOS 安装包结构错误，导致部分签名工具提示未找到 App 包的问题。',
        '修复 GitHub 源清单在部分网络环境不可达时没有备用镜像的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.4.0',
      buildNumber: '5',
      date: '2026-11-16',
      title: '原生体验与续播版',
      features: [
        '追剧、历史、喜欢、详情、榜单和专题统一读取本机播放进度，可继续上次集数与播放位置。',
        '播放器新增可拖动进度条，支持点击定位、跟手预览时间和松手跳转。',
        '长按播放器两侧可临时二倍速，上滑锁定，锁定后继续长按两侧下滑解除。',
        '详情页右上角三点菜单新增分享、刷新详情、从头播放和清除本剧记录。',
        '设置页新增独立更新记录页，按版本展示新增功能、体验优化和问题修复。',
        '设置页与启动阶段通过 GitHub Releases 检查在线更新，并按平台提供 APK、IPA 或 Release 入口。',
      ],
      improvements: [
        '剧场页改为顶部全部、短剧、漫剧切换，缩短页面并移除重复说明区。',
        '榜单页改为重点作品大卡与完整排名列表，专题页改为精选大图与双列卡片。',
        '标签页改为分类切换和紧凑标签网格，标签详情页同步精简。',
        '个人页右上角固定为设置入口，消息入口保留在设置左侧，头像抽屉移除重复设置项。',
        '首页、剧场、榜单、专题、标签等页面无缓存时统一展示微光骨架动画。',
      ],
      fixes: [
        '修复追剧入口和历史入口显示的播放集数不一致。',
        '修复续播只记录集数、不记录具体播放位置的问题。',
        '修复详情页播放按钮总是从第 1 集开始的问题。',
      ],
    ),
    HgReleaseRecord(
      version: 'v1.3.0',
      buildNumber: '4',
      date: '',
      title: '第三方客户端与内容中心版',
      features: [
        '首页按精选推荐、最近上新、热播短剧、专题推荐重新组织，并支持查看更多。',
        '支持多个自定义数据源与本机网络自动发现官方最新可用线路。',
        '观看历史改为本机保存，不再依赖官方历史接口。',
      ],
      improvements: [
        '搜索、短剧、漫剧、题材标签、榜单和专题数据在启动阶段预加载。',
        '设置页支持外观选择、缓存管理与数据源管理。',
        '吃瓜页面选中图标和首页快捷卡改为自绘图形，减少不同环境的字体差异。',
      ],
      fixes: ['修复个人页重复入口与观看历史不同步问题。', '修复部分环境中图标字体缺失导致选中状态不可见。'],
    ),
  ];
}

class HgReleaseRecord {
  const HgReleaseRecord({
    required this.version,
    required this.buildNumber,
    required this.date,
    required this.title,
    required this.features,
    required this.improvements,
    required this.fixes,
  });

  final String version;
  final String buildNumber;
  final String date;
  final String title;
  final List<String> features;
  final List<String> improvements;
  final List<String> fixes;

  String get versionLabel => '$version ($buildNumber)';
}
