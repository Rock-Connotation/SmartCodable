//
//  SmartEncodable.swift
//  SmartCodable
//
//  Created by Mccc on 2023/9/4.
//

import Foundation


/// SmartEncodable 协议：增强型编码接口，提供自定义编码能力
///
/// 核心职责：
/// - 继承 Encodable，提供编译器合成的 encode(to:) 作为编码入口
/// - 通过 didFinishMapping() 在编码前执行业务逻辑（如数据预处理）
/// - 通过 mappingForKey() 支持自定义字段名映射（如 camelCase 转为 snake_case）
/// - 通过 mappingForValue() 支持自定义值转换（如枚举转字符串）
///
/// 对称性设计：
/// - SmartEncodable 与 SmartDecodable 是对称的，同一个 CodingKeys，同一套字段顺序
/// - 解码时的映射规则（mappingForKey）可以反向用于编码
///
/// 调用链：
/// model.toDictionary() → _transformToJson() → SmartJSONEncoder.encode()
/// → 编译器合成的 encode(to:) → KeyedEncodingContainer
///
/// 为什么需要 init()：
/// - 保持与 SmartDecodable 的接口一致性
/// - 某些场景下可能需要先创建实例再编码（虽然不常见）
public protocol SmartEncodable: Encodable {
    /// 编码前的回调，用于执行数据预处理或业务逻辑修正
    ///
    /// 调用时机：编码开始前、调用 encode(to:) 前
    /// 使用场景：数据格式转换、默认值补全、字段关联校验
    mutating func didFinishMapping()

    /// 定义编码时的字段名映射规则，与解码时的 mappingForKey() 对称
    ///
    /// 返回值：[SmartKeyTransformer] 数组，定义属性到 JSON 字段名的映射
    ///
    /// 编码时的 useMappedKeys 参数决定是否使用此映射：
    /// - useMappedKeys = false（默认）：使用属性名作为 JSON 字段名
    /// - useMappedKeys = true：使用 mappingForKey() 中定义的源字段名
    ///
    /// 示例：
    /// ```
    /// static func mappingForKey() -> [SmartKeyTransformer]? {
    ///     [CodingKeys.userName <--- ["user_name", "username"]]
    /// }
    ///
    /// let user = User(userName: "John")
    /// user.toDictionary()  // ["userName": "John"]
    /// user.toDictionary(useMappedKeys: true)  // ["user_name": "John"]
    /// ```
    static func mappingForKey() -> [SmartKeyTransformer]?

    /// 定义编码时的值转换规则，支持自定义类型转换逻辑
    ///
    /// 返回值：[SmartValueTransformer] 数组，定义属性的值转换器
    ///
    /// 使用场景：
    /// - 枚举转字符串：Status.active → "active"
    /// - Date 转字符串：Date() → "2023-01-01T00:00:00Z"
    /// - 单位转换：1500.0 → {"value":1.5,"unit":"km"}
    static func mappingForValue() -> [SmartValueTransformer]?

    /// 无参初始化器：保持与 SmartDecodable 的接口一致性
    init()
}


/// 编码选项枚举：配置编码过程中的特殊行为
///
/// 用途：通过 Set<SmartEncodingOption> 传递给 toDictionary()/toJSONString() 方法，控制编码策略
///
/// 示例：
/// let options: Set<SmartEncodingOption> = [
///     .date(.iso8601),
///     .key(.convertToSnakeCase),
///     .data(.base64)
/// ]
/// let json = model.toJSONString(options: options)
public enum SmartEncodingOption: Hashable {

    /// 日期编码策略：定义如何将 Date 类型转换为 JSON 中的表示
    ///
    /// 常用策略：
    /// - .iso8601：转换为 ISO8601 格式字符串（如 "2023-01-01T00:00:00Z"）
    /// - .secondsSince1970：转换为 Unix 时间戳（如 1672531200）
    /// - .formatted(DateFormatter...)：使用自定义 DateFormatter
    ///
    /// 默认策略：.deferredToDate（使用 Date 的默认编码逻辑）
    case date(JSONEncoder.DateEncodingStrategy)

    /// Data 编码策略：定义如何将 Data 字段编码到 JSON
    ///
    /// 常用策略：
    /// - .raw：直接编码为字节数组（JSON 中无效，通常不用）
    /// - .base64：编码为 Base64 字符串（推荐）
    /// - .custom：自定义编码逻辑
    case data(JSONEncoder.SmartDataEncodingStrategy)

    /// 浮点数编码策略：定义如何处理非标准浮点数（NaN、Infinity）
    ///
    /// 常用策略：
    /// - .convertToString(positiveInfinity: "+∞", negativeInfinity: "-∞", nan: "NaN")
    /// - .throw：遇到非标准浮点数时抛出错误
    ///
    /// 使用场景：生成其他语言可解析的 JSON（某些 JSON 解析器不支持特殊浮点数）
    case float(JSONEncoder.NonConformingFloatEncodingStrategy)

    /// 字段名编码策略：定义如何将模型属性名映射到 JSON 字段名
    ///
    /// 常用策略：
    /// - .useDefaultKeys：直接使用 CodingKeys 定义的名称
    /// - .convertToSnakeCase：将 camelCase 转换为 snake_case（如 userName → user_name）
    /// - .custom：自定义映射逻辑
    ///
    /// 注意：此策略与 useMappedKeys 参数独立
    ///       - useMappedKeys = true：使用 mappingForKey() 定义的源字段名
    ///       - useMappedKeys = false：使用此策略或 CodingKeys
    case key(JSONEncoder.SmartKeyEncodingStrategy)
    
    /// Handles the hash value, ignoring the impact of associated values.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .date:
            hasher.combine(0)
        case .data:
            hasher.combine(1)
        case .float:
            hasher.combine(2)
        case .key:
            hasher.combine(3)
        }
    }
    
    public static func == (lhs: SmartEncodingOption, rhs: SmartEncodingOption) -> Bool {
        switch (lhs, rhs) {
        case (.date, .date):
            return true
        case (.data, .data):
            return true
        case (.float, .float):
            return true
        case (.key, .key):
            return true
        default:
            return false
        }
    }
}


extension SmartEncodable {

    /// 将对象序列化为字典
    ///
    /// 功能：将 SmartEncodable 实例转换为 [String: Any] 字典表示
    ///
    /// 调用流程：
    /// 1. 调用 _transformToJson() 执行编码
    /// 2. 内部使用 SmartJSONEncoder.encode() 生成 JSON Data
    /// 3. JSONSerialization.jsonObject() 将 Data 转换为字典
    ///
    /// 参数说明：
    /// - useMappedKeys：是否使用映射后的字段名（来自 mappingForKey()）
    ///   - false（默认）：使用属性名作为 JSON 字段名（如 userName → "userName"）
    ///   - true：使用 mappingForKey() 中定义的源字段名（如 ["user_name", "username"] → "user_name"）
    ///
    /// - options：编码选项集合，控制日期/Data/字段名等策略
    ///
    /// 返回值：编码成功的字典，失败返回 nil
    ///
    /// 示例：
    /// ```swift
    /// struct Model: SmartCodableX {
    ///     var data: String
    ///     static func mappingForKey() -> [SmartKeyTransformer]? {
    ///         [CodingKeys.data <--- ["json_data", "alt_data"]]
    ///     }
    /// }
    ///
    /// let model = Model(data: "value")
    /// model.toDictionary()  // ["data": "value"]
    /// model.toDictionary(useMappedKeys: true)  // ["json_data": "value"]
    /// ```
    ///
    /// 参见学习文档 03-编码管线：SmartJSONEncoder 的实现细节
    public func toDictionary(useMappedKeys: Bool = false, options: Set<SmartEncodingOption>? = nil) -> [String: Any]? {
        return _transformToJson(self, type: Self.self, useMappedKeys: useMappedKeys, options: options)
    }
    
    /// 将对象序列化为 JSON 字符串
    ///
    /// 功能：将 SmartEncodable 实例转换为 JSON 格式的字符串
    ///
    /// 调用流程：
    /// 1. 调用 toDictionary() 获取字典表示
    /// 2. 调用 _transformToJsonString() 将字典转换为 JSON 字符串
    ///
    /// 参数说明：
    /// - useMappedKeys：是否使用映射后的字段名（见 toDictionary() 说明）
    /// - options：编码选项集合
    /// - prettyPrint：是否格式化输出（添加换行和缩进，便于阅读）
    ///
    /// 返回值：编码成功的 JSON 字符串，失败返回 nil
    ///
    /// 示例：
    /// ```swift
    /// let user = User(name: "John", age: 30)
    /// user.toJSONString()  // {"name":"John","age":30}
    /// user.toJSONString(prettyPrint: true)  // {\n  "name": "John",\n  "age": 30\n}
    /// ```
    public func toJSONString(useMappedKeys: Bool = false, options: Set<SmartEncodingOption>? = nil, prettyPrint: Bool = false) -> String? {
        if let anyObject = toDictionary(useMappedKeys: useMappedKeys, options: options) {
            return _transformToJsonString(object: anyObject, prettyPrint: prettyPrint, type: Self.self)
        }
        return nil
    }
}


extension Array where Element: SmartEncodable {
    /// 将模型数组序列化为 [Any] 数组
    ///
    /// 功能：将 [SmartEncodable] 数组转换为 [Any] 数组表示
    ///
    /// 调用流程：
    /// 1. 调用 _transformToJson() 批量编码
    /// 2. 内部对每个元素执行 SmartJSONEncoder.encode()
    ///
    /// 参数说明：
    /// - useMappedKeys：是否使用映射后的字段名（应用于每个元素）
    /// - options：编码选项集合（应用于每个元素）
    ///
    /// 返回值：编码成功的数组，失败返回 nil
    public func toArray(useMappedKeys: Bool = false, options: Set<SmartEncodingOption>? = nil) -> [Any]? {
        return _transformToJson(self,type: Element.self, useMappedKeys: useMappedKeys, options: options)
    }

    /// 将模型数组序列化为 JSON 字符串
    ///
    /// 功能：将 [SmartEncodable] 数组转换为 JSON 格式的字符串
    ///
    /// 调用流程：
    /// 1. 调用 toArray() 获取数组表示
    /// 2. 调用 _transformToJsonString() 转换为 JSON 字符串
    ///
    /// 参数说明：
    /// - useMappedKeys：是否使用映射后的字段名
    /// - options：编码选项集合
    /// - prettyPrint：是否格式化输出
    ///
    /// 返回值：编码成功的 JSON 字符串，失败返回 nil
    ///
    /// 示例：
    /// ```swift
    /// let users = [User(name: "John"), User(name: "Jane")]
    /// users.toJSONString()  // [{"name":"John"},{"name":"Jane"}]
    /// users.toJSONString(prettyPrint: true)  // [\n  {"name": "John"},\n  {"name": "Jane"}\n]
    /// ```
    public func toJSONString(useMappedKeys: Bool = false, options: Set<SmartEncodingOption>? = nil, prettyPrint: Bool = false) -> String? {
        if let anyObject = toArray(useMappedKeys: useMappedKeys, options: options) {
            return _transformToJsonString(object: anyObject, prettyPrint: prettyPrint, type: Element.self)
        }
        return nil
    }
}



/// 将 Encodable 对象转换为指定类型（通常是 [String: Any] 或 [Any]）
///
/// 功能：执行编码流程，将对象转换为 JSON 兼容的类型
///
/// 调用流程：
/// 1. 创建 SmartJSONEncoder 实例
/// 2. 如果 useMappedKeys = true，通过 userInfo 传递标记
/// 3. 应用编码选项（日期/Data/字段名等策略）
/// 4. jsonEncoder.encode() 生成 JSON Data
/// 5. JSONSerialization.jsonObject() 将 Data 转换为指定类型
///
/// 参数说明：
/// - some：待编码的对象（遵循 Encodable）
/// - type：目标类型（通常是 [String: Any].Type 或 [Any].Type）
/// - useMappedKeys：是否使用映射后的字段名（通过 userInfo 传递）
/// - options：编码选项集合
///
/// 返回值：编码成功的目标类型实例，失败返回 nil
///
/// 关键设计：
/// - useMappedKeys 通过 CodingUserInfoKey.useMappedKeys 传递，不污染编码器 API
/// - userInfo 是 [CodingUserInfoKey: Any] 类型，用于在编码/解码过程中传递自定义信息
/// - 编码器通过检查 userInfo 中的标记来决定使用哪个字段名
///
/// 错误处理：
/// - 编码失败：返回 nil，不抛出异常
/// - 类型转换失败：返回 nil，通过 SmartSentinel 记录诊断信息
///
/// 参见学习文档 03-编码管线：userInfo 的使用机制
fileprivate func _transformToJson<T>(_ some: Encodable, type: Any.Type, useMappedKeys: Bool, options: Set<SmartEncodingOption>? = nil) -> T? {

    // 创建编码器实例
    let jsonEncoder = SmartJSONEncoder()

    // 通过 userInfo 传递 useMappedKeys 标记
    // 编码器内部会检查此标记来决定使用哪个字段名
    if useMappedKeys, let key = CodingUserInfoKey.useMappedKeys {
        var userInfo = jsonEncoder.userInfo
        userInfo.updateValue(true, forKey: key)
        jsonEncoder.userInfo = userInfo
    }

    // 应用编码选项
    if let _options = options {
        for _option in _options {
            switch _option {
            case .data(let strategy):
                // 配置 Data 编码策略
                jsonEncoder.smartDataEncodingStrategy = strategy

            case .date(let strategy):
                // 配置日期编码策略
                jsonEncoder.dateEncodingStrategy = strategy

            case .float(let strategy):
                // 配置浮点数编码策略
                jsonEncoder.nonConformingFloatEncodingStrategy = strategy

            case .key(let strategy):
                // 配置字段名编码策略
                jsonEncoder.smartKeyEncodingStrategy = strategy
            }
        }
    }

    // 执行编码：调用编译器合成的 encode(to:)，生成 JSON Data
    if let jsonData = try? jsonEncoder.encode(some) {
        do {
            // 将 JSON Data 转换为目标类型（字典或数组）
            let json = try JSONSerialization.jsonObject(with: jsonData, options: .fragmentsAllowed)

            // 检查类型转换是否成功
            if let temp = json as? T {
                return temp
            } else {
                // 类型不匹配：记录诊断信息
                SmartSentinel.monitorAndPrint(debugDescription: "\(json)) is not a valid Type, wanted \(T.self) type.", error: nil, in: type)
            }
        } catch {
            // JSONSerialization 失败：记录诊断信息
            SmartSentinel.monitorAndPrint(debugDescription: "'JSONSerialization.jsonObject(:)' falied", error: nil, in: type)
        }
    }

    // 编码或转换失败
    return nil
}



/// 将对象转换为 JSON 字符串
///
/// 功能：将 [String: Any] 或 [Any] 转换为 JSON 格式的字符串
///
/// 调用流程：
/// 1. JSONSerialization.isValidJSONObject() 验证对象是否可序列化
/// 2. JSONSerialization.data() 将对象转换为 JSON Data
/// 3. String(data:encoding:) 将 Data 转换为字符串
///
/// 参数说明：
/// - object：待转换的对象（通常是字典或数组）
/// - prettyPrint：是否格式化输出（添加换行和缩进）
/// - type：对象类型，用于日志记录
///
/// 返回值：JSON 字符串，失败返回 nil
///
/// 格式化说明：
/// - prettyPrint = false：压缩格式（{"name":"John","age":30}）
/// - prettyPrint = true：美化格式（{\n  "name": "John",\n  "age": 30\n}）
///
/// 错误处理：
/// - 对象无效：记录诊断信息，返回 nil
/// - 序列化失败：记录诊断信息，返回 nil
///
/// 验证规则：
/// - 对象必须是 NSDictionary、NSArray、NSString、NSNumber、NSNull 或其 Swift 等价类型
/// - 字典的键必须是 NSString 类型
/// - 不允许循环引用
fileprivate func _transformToJsonString(object: Any, prettyPrint: Bool = false, type: Any.Type) -> String? {
    // 验证对象是否可序列化为 JSON
    // 有效对象：字典、数组、字符串、数字、布尔值、null
    // 无效对象：自定义类型、循环引用、非字符串键的字典
    if JSONSerialization.isValidJSONObject(object) {
        do {
            // 配置序列化选项：根据 prettyPrint 决定是否美化输出
            let options: JSONSerialization.WritingOptions = prettyPrint ? [.prettyPrinted] : []

            // 将对象序列化为 JSON Data
            let jsonData = try JSONSerialization.data(withJSONObject: object, options: options)

            // 将 Data 转换为 UTF-8 字符串
            return String(data: jsonData, encoding: .utf8)

        } catch {
            // 序列化失败：记录诊断信息
            SmartSentinel.monitorAndPrint(debugDescription: "'JSONSerialization.data(:)' falied", error: error, in: type)
        }
    } else {
        // 对象无效：记录诊断信息
        SmartSentinel.monitorAndPrint(debugDescription: "\(object)) is not a valid JSON Object", error: nil, in: type)
    }

    // 转换失败
    return nil
}
