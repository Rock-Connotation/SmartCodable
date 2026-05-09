//
//  SmartDecodable.swift
//  SmartCodable
//
//  Created by Mccc on 2023/9/4.
//

import Foundation

/**
 A protocol that enhances Swift's Decodable with additional customization options for decoding.
 
 Conforming types gain:
 - Post-decoding mapping callbacks
 - Custom key and value transformation strategies
 - Convenient deserialization methods
 
 Requirements:
 - Implement `didFinishMapping()` for post-processing
 - Optionally provide key/value mapping strategies
 */
/// SmartDecodable 协议：增强型解码接口，提供韧性解码能力
///
/// 核心职责：
/// - 继承 Decodable，提供编译器合成的 init(from:) 作为解码入口
/// - 通过 didFinishMapping() 在解码完成后执行业务逻辑修正（如字段间关联校验）
/// - 通过 mappingForKey() 支持多候选字段名映射（如 jsonField/altField 都映射到同一个属性）
/// - 通过 mappingForValue() 支持自定义值转换逻辑（如字符串转枚举）
///
/// 为什么需要 init()：
/// - 当解码失败（如字段缺失、类型不匹配）时，需要从 DecodingCache 获取属性的初始值
/// - DecodingCache 在 init() 时捕获，因此要求类型必须有无参初始化器
///
/// 调用链：
/// User.deserialize(from:) → JSONExtractor（归一化输入）→ SmartJSONDecoder.smartDecode
/// → JSONDecoderImpl → 编译器合成的 init(from:) → KeyedDecodingContainer
public protocol SmartDecodable: Decodable {
    /// 解码完成后的回调，用于执行字段间的业务规则修正（如数据校验、默认值补全）
    ///
    /// 调用时机：所有字段解析完成后、返回结果前
    /// 使用场景：校验字段间依赖关系（如 startDate < endDate）、设置计算属性
    mutating func didFinishMapping()

    /// 定义解码时的字段名映射规则，支持多候选字段名
    ///
    /// 返回值：[SmartKeyTransformer] 数组，每个元素定义一个属性的多候选映射关系
    ///
    /// 示例：CodingKeys.name <--- ["user_name", "username"]
    ///   表示 JSON 中的 "user_name" 或 "username" 都会映射到模型的 name 属性
    ///
    /// 优先级：按数组顺序尝试，第一个匹配成功的映射生效
    static func mappingForKey() -> [SmartKeyTransformer]?

    /// 定义解码时的值转换规则，支持自定义类型转换逻辑
    ///
    /// 返回值：[SmartValueTransformer] 数组，每个元素定义一个属性的值转换器
    ///
    /// 使用场景：
    /// - 字符串转枚举："active" → Status.active
    /// - 时间格式转换："2023-01-01" → Date
    /// - 单位转换："1.5km" → 1500.0（ meters）
    static func mappingForValue() -> [SmartValueTransformer]?

    /// 无参初始化器：为解码失败时提供属性初始值来源
    ///
    /// 为什么需要：解码失败时，DecodingCache 需要捕获属性的初始值作为兜底
    ///
    /// 注意：如果属性有默认值（如 var name: String = ""），编译器会自动生成 init()
    ///       如果属性没有默认值，需要手动实现 init() 并初始化所有属性
    init()
}


/// 为 SmartDecodable 提供默认实现，避免强制要求用户实现所有方法
extension SmartDecodable {
    /// 空实现：如果用户不需要解码后处理，可以不实现此方法
    public mutating func didFinishMapping() { }

    /// 返回 nil：表示不使用自定义字段名映射，直接使用 CodingKeys 定义的名称
    public static func mappingForKey() -> [SmartKeyTransformer]? { return nil }

    /// 返回 nil：表示不使用自定义值转换，使用默认的类型转换逻辑
    public static func mappingForValue() -> [SmartValueTransformer]? { return nil }
}


/// 解码选项枚举：配置解码过程中的特殊行为
///
/// 用途：通过 Set<SmartDecodingOption> 传递给 deserialize(from:) 方法，控制解码策略
///
/// 示例：
/// let options: Set<SmartDecodingOption> = [
///     .date(.iso8601),
///     .key(.convertFromSnakeCase),
///     .logContext(header: "API Response", footer: "User List")
/// ]
/// let user = User.deserialize(from: json, options: options)
public enum SmartDecodingOption: Hashable {

    /// 日期解码策略：定义如何将 JSON 中的日期字符串/数字转换为 Date 类型
    ///
    /// 常用策略：
    /// - .iso8601：解析 ISO8601 格式（如 "2023-01-01T00:00:00Z"）
    /// - .secondsSince1970：解析 Unix 时间戳（如 1672531200）
    /// - .formatted(DateFormatter...)：使用自定义 DateFormatter
    ///
    /// 默认策略：.deferredToDate（使用 Date 的默认解码逻辑）
    case date(JSONDecoder.DateDecodingStrategy)

    /// Data 解码策略：定义如何将 JSON 中的 Data 字段解码
    ///
    /// 常用策略：
    /// - .raw：直接解码为 Data
    /// - .base64：解码 Base64 编码的字符串
    /// - .custom：自定义解码逻辑
    case data(JSONDecoder.SmartDataDecodingStrategy)

    /// 浮点数解码策略：定义如何处理非标准浮点数（NaN、Infinity）
    ///
    /// 常用策略：
    /// - .convertFromString(positiveInfinity: "+∞", negativeInfinity: "-∞", nan: "NaN")
    /// - .throw：遇到非标准浮点数时抛出错误
    ///
    /// 使用场景：处理来自其他语言的 JSON，可能包含字符串形式的特殊浮点数
    case float(JSONDecoder.NonConformingFloatDecodingStrategy)

    /// 字段名解码策略：定义如何将 JSON 中的字段名映射到模型属性名
    ///
    /// 常用策略：
    /// - .useDefaultKeys：直接使用 CodingKeys 定义的名称
    /// - .convertFromSnakeCase：将 snake_case 转换为 camelCase（如 user_name → userName）
    /// - .custom：自定义映射逻辑
    ///
    /// 注意：此策略与 mappingForKey() 独立，mappingForKey() 优先级更高
    case key(JSONDecoder.SmartKeyDecodingStrategy)

    /// 日志上下文：为解码过程添加自定义的日志头尾信息，便于追踪问题
    ///
    /// 参数：
    /// - header：日志头部，用于标识解码来源（如 "API Response"、"Cache"）
    /// - footer：日志尾部，用于标记解码结束
    ///
    /// 使用场景：在调试时区分不同来源的 JSON 数据，快速定位问题
    case logContext(header: String, footer: String)
    
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
        case .logContext:
            hasher.combine(4)
        }
    }
    
    public static func == (lhs: SmartDecodingOption, rhs: SmartDecodingOption) -> Bool {
        switch (lhs, rhs) {
        case (.date, .date):
            return true
        case (.data, .data):
            return true
        case (.float, .float):
            return true
        case (.key, .key):
            return true
        case (.logContext, .logContext):
            return true
        default:
            return false
        }
    }
}


extension SmartDecodable {

    /// 从字典解码模型
    ///
    /// 功能：将 [String: Any] 字典解码为 SmartDecodable 类型的实例
    ///
    /// 调用流程：
    /// 1. JSONExtractor.extract(from:dict) 归一化输入格式，提取指定路径的数据
    /// 2. _deserializeDict() 创建 SmartJSONDecoder 并执行解码
    /// 3. 解码完成后调用 didFinishMapping() 执行后处理
    ///
    /// 参数说明：
    /// - dict：输入字典，可以是 [String: Any] 或嵌套结构
    /// - designatedPath：指定解码路径，支持点号分隔（如 "data.items"），nil 表示直接解码根节点
    /// - options：解码选项集合，控制日期/字段名/浮点数等策略
    ///
    /// 返回值：解码成功的模型实例，失败返回 nil（静默失败，不抛出异常）
    ///
    /// 注意：重复的枚举项无效（如传入多个 key 策略，只有第一个生效）
    ///
    /// 参见学习文档 02-解码管线：JSONExtractor 的归一化流程
    public static func deserialize(from dict: [String: Any]?, designatedPath: String? = nil,  options: Set<SmartDecodingOption>? = nil) -> Self? {

        // 归一化输入：将字典转换为内部 JSONValue 表示，并提取指定路径的数据
        // 归一化避免了后续解码逻辑需要处理多种输入格式（Dict/Array/String/Data）
        guard let _input = JSONExtractor.extract(from: dict, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 执行实际解码：创建解码器 → 解码 → 调用后处理回调
        return _deserializeDict(input: _input, type: Self.self, options: options)
    }
    
    /// 从 JSON 字符串解码模型
    ///
    /// 功能：将 JSON 字符串解码为 SmartDecodable 类型的实例
    ///
    /// 调用流程：
    /// 1. JSONExtractor.extract(from:json) 将字符串解析为内部 JSONValue
    /// 2. _deserializeDict() 执行解码并返回模型
    ///
    /// 参数说明：
    /// - json：JSON 格式的字符串（如 '{"name":"John","age":30}'）
    /// - designatedPath：指定解码路径，支持点号分隔（如 "data.users.0"）
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型实例，失败返回 nil
    ///
    /// 参见学习文档 02-解码管线：JSONExtractor 对字符串的解析流程
    public static func deserialize(from json: String?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> Self? {

        // 解析 JSON 字符串为内部表示，并提取指定路径的数据
        guard let _input = JSONExtractor.extract(from: json, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 执行解码
        return _deserializeDict(input: _input, type: Self.self, options: options)
    }
    
    /// 从 Data 解码模型
    ///
    /// 功能：将二进制数据（通常是 JSON 的 Data 表示）解码为模型
    ///
    /// 调用流程：
    /// 1. JSONExtractor.extract(from:data) 将 Data 解析为内部 JSONValue
    /// 2. _deserializeDict() 执行解码
    ///
    /// 参数说明：
    /// - data：二进制数据，通常是 JSONSerialization.jsonObject() 的输入
    /// - designatedPath：指定解码路径
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型实例，失败返回 nil
    ///
    /// 使用场景：网络请求返回的 Data、文件读取的 Data
    public static func deserialize(from data: Data?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> Self? {

        // 解析 Data 为内部表示，并提取指定路径的数据
        guard let _input = JSONExtractor.extract(from: data, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 执行解码
        return _deserializeDict(input: _input, type: Self.self, options: options)
    }
    
    /// 从 Property List (plist) 数据解码模型
    ///
    /// 功能：将 plist 格式的二进制数据转换为 JSON 后解码
    ///
    /// 调用流程：
    /// 1. data?.tranformToJSONData() 将 plist 转换为 JSON 格式的 Data
    /// 2. JSONExtractor.extract() 解析并提取指定路径
    /// 3. _deserializeDict() 执行解码
    ///
    /// 参数说明：
    /// - data：plist 格式的二进制数据（.plist 文件内容）
    /// - designatedPath：指定解码路径
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型实例，失败返回 nil
    ///
    /// 使用场景：读取 iOS 系统的配置文件、Info.plist 等格式
    public static func deserializePlist(from data: Data?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> Self? {

        // 将 plist 格式转换为 JSON 格式
        guard let _plistObject = data?.tranformToJSONData(type: Self.self) else { return nil }

        // 解析 JSON 并提取指定路径
        guard let _input = JSONExtractor.extract(from: _plistObject, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 执行解码
        return _deserializeDict(input: _input, type: Self.self, options: options)
    }

}


extension Array where Element: SmartDecodable {

    /// 从数组解码模型数组
    ///
    /// 功能：将 [Any] 数组解码为 [SmartDecodable] 类型的数组
    ///
    /// 调用流程：
    /// 1. JSONExtractor.extract(from:array) 归一化数组输入
    /// 2. _deserializeArray() 批量解码每个元素
    ///
    /// 参数说明：
    /// - array：输入数组，元素可以是字典、字符串、数字等
    /// - designatedPath：指定解码路径（如从嵌套结构中提取数组）
    /// - options：解码选项集合，应用于每个元素
    ///
    /// 返回值：解码成功的模型数组，任一元素解码失败则整体返回 nil
    ///
    /// 注意：数组的每个元素都会独立解码，不会因为单个元素失败而中断
    public static func deserialize(from array: [Any]?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> [Element]? {

        // 归一化数组输入，并提取指定路径
        guard let _input = JSONExtractor.extract(from: array, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 批量解码数组元素
        return _deserializeArray(input: _input, type: Self.self, options: options)
    }
    
    /// 从 JSON 字符串解码模型数组
    ///
    /// 功能：将 JSON 字符串（表示数组）解码为 [SmartDecodable] 数组
    ///
    /// 参数说明：
    /// - json：JSON 数组字符串（如 '[{"name":"John"},{"name":"Jane"}]'）
    /// - designatedPath：指定解码路径
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型数组，失败返回 nil
    public static func deserialize(from json: String?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> [Element]? {

        // 解析 JSON 字符串并提取指定路径的数组
        guard let _input = JSONExtractor.extract(from: json, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 批量解码
        return _deserializeArray(input: _input, type: Self.self, options: options)
    }
    
    /// 从 Data 解码模型数组
    ///
    /// 功能：将二进制数据（JSON 数组）解码为 [SmartDecodable] 数组
    ///
    /// 参数说明：
    /// - data：包含 JSON 数组的二进制数据
    /// - designatedPath：指定解码路径
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型数组，失败返回 nil
    public static func deserialize(from data: Data?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> [Element]? {

        // 解析 Data 并提取指定路径的数组
        guard let _input = JSONExtractor.extract(from: data, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 批量解码
        return _deserializeArray(input: _input, type: Self.self, options: options)
    }
    
    /// 从 Property List (plist) 数据解码模型数组
    ///
    /// 功能：将 plist 格式的数组转换为 JSON 后解码
    ///
    /// 调用流程：
    /// 1. data?.tranformToJSONData() 将 plist 转换为 JSON
    /// 2. JSONExtractor.extract() 提取数组
    /// 3. _deserializeArray() 批量解码
    ///
    /// 参数说明：
    /// - data：plist 格式的二进制数据
    /// - designatedPath：指定解码路径
    /// - options：解码选项集合
    ///
    /// 返回值：解码成功的模型数组，失败返回 nil
    public static func deserializePlist(from data: Data?, designatedPath: String? = nil, options: Set<SmartDecodingOption>? = nil) -> [Element]? {

        // 将 plist 转换为 JSON
        guard let _plistObject = data?.tranformToJSONData(type: Self.self) else {
            return nil
        }

        // 提取指定路径的数组
        guard let _input = JSONExtractor.extract(from: _plistObject, by: designatedPath, on: Self.self) else {
            return nil
        }

        // 批量解码
        return _deserializeArray(input: _input, type: Self.self, options: options)
    }
}


// MARK: - 内部实现
/// 解码单个模型（Model 类型）
///
/// 功能：执行单个 SmartDecodable 模型的完整解码流程
///
/// 调用链：
/// 1. createDecoder() 创建配置好的 SmartJSONDecoder
/// 2. _decoder.smartDecode() 执行解码，内部调用编译器合成的 init(from:)
/// 3. obj.didFinishMapping() 调用解码后回调，执行业务逻辑修正
///
/// 参数说明：
/// - input：归一化后的输入数据（来自 JSONExtractor）
/// - type：目标类型（SmartDecodable 泛型参数）
/// - options：解码选项，传递给 createDecoder 配置解码器
///
/// 返回值：解码成功的模型实例，失败返回 nil（静默失败，不抛出异常）
///
/// 错误处理：所有解码错误被捕获并返回 nil，通过 SmartSentinel 记录诊断信息
///
/// 参见学习文档 02-解码管线：SmartJSONDecoder.smartDecode 的实现细节
fileprivate func _deserializeDict<T>(input: Any, type: T.Type, options: Set<SmartDecodingOption>? = nil) -> T? where T: SmartDecodable {

    do {
        // 创建配置好的解码器（应用日期/字段名/浮点数等策略）
        let _decoder = createDecoder(type: type, options: options)

        // 执行解码：调用编译器合成的 init(from:)，内部使用 KeyedDecodingContainer
        // SmartJSONDecoder 提供韧性解码（类型转换、默认值、空值处理）
        var obj = try _decoder.smartDecode(type, from: input)

        // 调用解码后回调：允许用户在所有字段解析完成后执行业务逻辑
        // 典型用途：字段间关联校验、计算属性设置、默认值补全
        obj.didFinishMapping()

        return obj
    } catch {
        // 静默失败：不抛出异常，返回 nil
        // 实际错误通过 SmartSentinel 记录到诊断日志
        return nil
    }
}

/// 解码模型数组（[Model] 类型）
///
/// 功能：批量解码 SmartDecodable 模型数组
///
/// 调用链：
/// 1. createDecoder() 创建配置好的 SmartJSONDecoder
/// 2. _decoder.smartDecode() 批量解码数组元素
///
/// 参数说明：
/// - input：归一化后的输入数组（来自 JSONExtractor）
/// - type：数组类型（[T].Type，T 遵循 SmartDecodable）
/// - options：解码选项，应用于每个元素
///
/// 返回值：解码成功的模型数组，失败返回 nil
///
/// 注意：与 _deserializeDict 不同，数组解码不调用 didFinishMapping()
///       因为数组元素已经独立完成了解码流程
///
/// 参见学习文档 02-解码管线：数组解码的特殊处理
fileprivate func _deserializeArray<T>(input: Any, type: [T].Type, options: Set<SmartDecodingOption>? = nil) -> [T]? where T: SmartDecodable {

    do {
        // 创建配置好的解码器
        let _decoder = createDecoder(type: type, options: options)

        // 批量解码：对数组中的每个元素执行 _decoder.smartDecode()
        // 每个元素独立解码，单个元素失败不影响其他元素
        let obj = try _decoder.smartDecode(type, from: input)
        return obj

    } catch {
        // 静默失败
        return nil
    }
}


/// 创建配置好的解码器
///
/// 功能：根据选项集合创建并配置 SmartJSONDecoder 实例
///
/// 配置流程：
/// 1. 创建 SmartJSONDecoder 实例
/// 2. 遍历选项集合，将每个选项应用到解码器
/// 3. 返回配置完成的解码器
///
/// 参数说明：
/// - type：目标类型，用于日志记录（标识当前解码的类型）
/// - options：解码选项集合，可以包含 date/data/float/key/logContext 等配置
///
/// 返回值：配置完成的 SmartJSONDecoder 实例
///
/// 配置项说明：
/// - .data：设置 smartDataDecodingStrategy，控制 Data 字段解码方式
/// - .date：设置 smartDateDecodingStrategy，控制日期字段解码方式
/// - .float：设置 nonConformingFloatDecodingStrategy，控制特殊浮点数处理
/// - .key：设置 smartKeyDecodingStrategy，控制字段名映射策略
/// - .logContext：通过 userInfo 传递日志头尾信息，用于调试追踪
///
/// 设计意图：
/// - 使用模式匹配（switch-case）而非 if-else，保证类型安全
/// - 将配置逻辑集中在函数中，避免在各个 deserialize 方法中重复代码
/// - 通过 userInfo 传递日志上下文，不污染解码器 API
fileprivate func createDecoder<T>(type: T.Type, options: Set<SmartDecodingOption>? = nil) -> SmartJSONDecoder {
    // 创建解码器实例
    let _decoder = SmartJSONDecoder()

    // 应用配置选项
    if let _options = options {
        for _option in _options {
            switch _option {
            case .data(let strategy):
                // 配置 Data 解码策略
                _decoder.smartDataDecodingStrategy = strategy

            case .date(let strategy):
                // 配置日期解码策略
                _decoder.smartDateDecodingStrategy = strategy

            case .float(let strategy):
                // 配置浮点数解码策略
                _decoder.nonConformingFloatDecodingStrategy = strategy

            case .key(let strategy):
                // 配置字段名映射策略
                _decoder.smartKeyDecodingStrategy = strategy

            case .logContext(let header, let footer):
                // 通过 userInfo 传递日志上下文
                // userInfo 是 [CodingUserInfoKey: Any] 类型，用于在编码/解码过程中传递自定义信息
                var userInfo = _decoder.userInfo

                // 设置日志头部
                if let headerKey = CodingUserInfoKey.logContextHeader {
                    userInfo.updateValue(header, forKey: headerKey)
                }

                // 设置日志尾部
                if let footerKey = CodingUserInfoKey.logContextFooter {
                    userInfo.updateValue(footer, forKey: footerKey)
                }

                _decoder.userInfo = userInfo
            }
        }
    }

    return _decoder
}





