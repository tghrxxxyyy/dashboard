import Foundation

/// 可由启动台管理的本地 macOS 应用。
struct AppItem: Codable, Identifiable, Hashable {
    /// 应用记录的唯一标识。
    var id: UUID
    /// 应用展示名称。
    var name: String
    /// 应用包在本机的绝对路径。
    var path: String
    /// 应用包标识，用于路径失效后的识别与修复。
    var bundleId: String?
    /// 是否已加入常用应用。
    var isFavorite: Bool
    /// 从 Workbench 启动应用的累计次数。
    var launchCount: Int
    /// 最近一次从 Workbench 启动的时间。
    var lastLaunchedAt: Date?

    /// 应用记录的持久化字段键。
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case bundleId
        case isFavorite
        case launchCount
        case lastLaunchedAt
    }

    /// 创建应用记录。
    /// - Parameters:
    ///   - id: 应用记录的唯一标识。
    ///   - name: 应用展示名称。
    ///   - path: 应用包绝对路径。
    ///   - bundleId: 应用包标识。
    ///   - isFavorite: 是否加入常用应用。
    ///   - launchCount: 累计启动次数。
    ///   - lastLaunchedAt: 最近启动时间。
    init(
        id: UUID,
        name: String,
        path: String,
        bundleId: String?,
        isFavorite: Bool = false,
        launchCount: Int = 0,
        lastLaunchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bundleId = bundleId
        self.isFavorite = isFavorite
        self.launchCount = launchCount
        self.lastLaunchedAt = lastLaunchedAt
    }

    /// 从持久化数据解码应用，并为旧版本缺失字段提供兼容默认值。
    /// - Parameter decoder: Codable 解码器。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        launchCount = try container.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        lastLaunchedAt = try container.decodeIfPresent(Date.self, forKey: .lastLaunchedAt)
    }

    /// 将完整应用记录编码到持久化数据。
    /// - Parameter encoder: Codable 编码器。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(bundleId, forKey: .bundleId)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(launchCount, forKey: .launchCount)
        try container.encodeIfPresent(lastLaunchedAt, forKey: .lastLaunchedAt)
    }
}

/// 启动台中的应用分组。
struct LauncherTag: Codable, Identifiable {
    /// 分组的唯一标识。
    var id: UUID
    /// 分组展示名称。
    var name: String
    /// 分组内的应用列表。
    var items: [AppItem]
}

/// 密钥条目中的一个键值字段。
struct SecretField: Codable, Identifiable, Hashable {
    /// 字段的唯一标识。
    var id: UUID
    /// 字段名称。
    var key: String
    /// 字段值。
    var value: String
    /// 是否默认隐藏字段值。
    var isSensitive: Bool

    /// 密钥字段的持久化字段键。
    private enum CodingKeys: String, CodingKey {
        case id
        case key
        case value
        case isSensitive
    }

    /// 创建密钥字段。
    /// - Parameters:
    ///   - id: 字段唯一标识。
    ///   - key: 字段名称。
    ///   - value: 字段值。
    ///   - isSensitive: 是否默认隐藏字段值。
    init(id: UUID, key: String, value: String, isSensitive: Bool = true) {
        self.id = id
        self.key = key
        self.value = value
        self.isSensitive = isSensitive
    }

    /// 解码字段，并兼容未包含敏感标记的旧保险库数据。
    /// - Parameter decoder: Codable 解码器。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        value = try container.decode(String.self, forKey: .value)
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? true
    }

    /// 将密钥字段编码到保险库数据。
    /// - Parameter encoder: Codable 编码器。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(value, forKey: .value)
        try container.encode(isSensitive, forKey: .isSensitive)
    }
}

/// 保险库中的一组相关密钥字段。
struct SecretEntry: Codable, Identifiable {
    /// 条目的唯一标识。
    var id: UUID
    /// 条目展示标题。
    var title: String
    /// 条目所属分类。
    var category: String
    /// 条目包含的密钥字段。
    var fields: [SecretField]
    /// 是否已加入常用条目。
    var isFavorite: Bool
    /// 条目最近更新时间。
    var updatedAt: Date

    /// 保险库条目的持久化字段键。
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case fields
        case isFavorite
        case updatedAt
    }

    /// 创建保险库条目。
    /// - Parameters:
    ///   - id: 条目唯一标识。
    ///   - title: 条目展示标题。
    ///   - category: 条目所属分类。
    ///   - fields: 条目包含的字段。
    ///   - isFavorite: 是否加入常用条目。
    ///   - updatedAt: 最近更新时间。
    init(
        id: UUID,
        title: String,
        category: String,
        fields: [SecretField],
        isFavorite: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.fields = fields
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }

    /// 解码条目，并兼容未包含收藏与更新时间的旧保险库数据。
    /// - Parameter decoder: Codable 解码器。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        fields = try container.decode([SecretField].self, forKey: .fields)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }

    /// 将完整条目编码到保险库数据。
    /// - Parameter encoder: Codable 编码器。
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(fields, forKey: .fields)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
