//
//  JSONDecoderImpl+unwrap.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/21.
//

import Foundation

/// 字符串字典解码标记协议：标记 [String: Decodable] 类型，启用特殊解码路径
/// 设计目的：区分普通字典和需要递归解码的字典
fileprivate protocol _JSONStringDictionaryDecodableMarker {
    static var elementType: Decodable.Type { get }
}

extension Dictionary: _JSONStringDictionaryDecodableMarker where Key == String, Value: Decodable {
    static var elementType: Decodable.Type { return Value.self }
}

extension JSONDecoderImpl {
    // MARK: 类型调度中枢

    /// 类型调度中枢：根据目标类型分发到专门的解码方法
    /// 参见 Decoding-Pipeline.md §6 - 类型调度机制
    ///
    /// 执行策略：
    /// 1. 特殊类型拦截：Date/Data/URL/Decimal/CGFloat/Dictionary 走专用路径
    /// 2. 普通模型路径：使用快照栈管理，支持循环引用检测
    ///
    /// - parameter type: 要解码的目标类型
    /// - returns: 解码后的实例
    func unwrap<T: Decodable>(as type: T.Type) throws -> T {
        // 第一层：特殊类型拦截 - 这些类型有特定的解码逻辑
        if type == Date.self {
            return try self.unwrapDate() as! T
        }
        if type == Data.self {
            return try self.unwrapData() as! T
        }
        if type == URL.self {
            return try self.unwrapURL() as! T
        }
        if type == Decimal.self {
            return try self.unwrapDecimal() as! T
        }
        if type == CGFloat.self {
            return try unwrapCGFloat() as! T
        }
        if type is _JSONStringDictionaryDecodableMarker.Type {
            return try self.unwrapDictionary(as: type)
        }

        // 第二层：普通模型路径 - 使用快照栈管理循环引用
        cache.cacheSnapshot(for: type, codingPath: codingPath)
        let decoded = try type.init(from: self)
        cache.removeSnapshot(for: type)
        return decoded
    }

    /// 浮点数解码：支持快速路径和慢速路径，处理非规浮点值
    ///
    /// 执行策略：
    /// 1. 自定义转换器拦截：优先使用用户注册的 Transformer
    /// 2. 快速路径：直接从 JSON 数字转换为浮点类型
    /// 3. 非规浮点处理：根据 nonConformingFloatDecodingStrategy 解析字符串形式的特殊值
    ///
    /// - parameter value: JSON 值
    /// - parameter additionalKey: 可选的附加键（用于缓存查找）
    /// - parameter type: 目标浮点类型
    /// - returns: 解码后的浮点值，失败返回 nil
    func unwrapFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>(
        from value: JSONValue, for additionalKey: CodingKey? = nil, as type: T.Type) -> T? {

            // 路径0：自定义转换器拦截
            if let tranformer = cache.valueTransformer(for: additionalKey, in: codingPath) {
                guard let decoded = tranformer.transformFromJSON(value) as? T else { return nil }
                return decoded
            }

            // 路径1：快速路径 - 直接从 JSON 数字转换
            if case .number(let number) = value {
                guard let floatingPoint = T(number), floatingPoint.isFinite else { return nil }
                return floatingPoint
            }

            // 路径2：非规浮点处理 - 解析字符串形式的 +∞/-∞/NaN
            if case .string(let string) = value,
               case .convertFromString(let posInfString, let negInfString, let nanString) = self.options.nonConformingFloatDecodingStrategy {
                if string == posInfString {
                    return T.infinity
                } else if string == negInfString {
                    return -T.infinity
                } else if string == nanString {
                    return T.nan
                }
            }

            return nil
        }

    /// 定宽整数解码：快速路径 + NSNumber 慢速路径
    ///
    /// 执行策略：
    /// 1. 自定义转换器拦截
    /// 2. 快速路径：Number 直接转换为整数（适用于整数格式的 JSON 数字）
    /// 3. 慢速路径：通过 NSNumber 桥接，处理浮点数格式的整数（如 "34.0" → 34）
    ///
    /// 慢速路径的必要性：服务端可能返回浮点数格式的整数值，需要精确转换
    ///
    /// - parameter value: JSON 值
    /// - parameter additionalKey: 可选的附加键
    /// - parameter type: 目标整数类型
    /// - returns: 解码后的整数值，失败返回 nil
    func unwrapFixedWidthInteger<T: FixedWidthInteger>(
        from value: JSONValue, for additionalKey: CodingKey? = nil, as type: T.Type) -> T? {

            // 路径0：自定义转换器拦截
            if let tranformer = cache.valueTransformer(for: additionalKey, in: codingPath) {
                return tranformer.transformFromJSON(value) as? T
            }

            guard case .number(let number) = value else { return nil }

            // 路径1：快速路径 - Number 直接可转换为整数
            if let integer = T(number) {
                return integer
            }

            // 路径2：慢速路径 - 通过 NSNumber 桥接
            // 适用场景：JSON 数字是浮点数格式（如 "34.0"），但目标类型是整数
            if let nsNumber = NSNumber.fromJSONNumber(number) {
                if type == UInt8.self, NSNumber(value: nsNumber.uint8Value) == nsNumber {
                    return nsNumber.uint8Value as? T
                }
                if type == Int8.self, NSNumber(value: nsNumber.int8Value) == nsNumber {
                    return nsNumber.int8Value as? T
                }
                if type == UInt16.self, NSNumber(value: nsNumber.uint16Value) == nsNumber {
                    return nsNumber.uint16Value as? T
                }
                if type == Int16.self, NSNumber(value: nsNumber.int16Value) == nsNumber {
                    return nsNumber.int16Value as? T
                }
                if type == UInt32.self, NSNumber(value: nsNumber.uint32Value) == nsNumber {
                    return nsNumber.uint32Value as? T
                }
                if type == Int32.self, NSNumber(value: nsNumber.int32Value) == nsNumber {
                    return nsNumber.int32Value as? T
                }
                if type == UInt64.self, NSNumber(value: nsNumber.uint64Value) == nsNumber {
                    return nsNumber.uint64Value as? T
                }
                if type == Int64.self, NSNumber(value: nsNumber.int64Value) == nsNumber {
                    return nsNumber.int64Value as? T
                }
                if type == UInt.self, NSNumber(value: nsNumber.uintValue) == nsNumber {
                    return nsNumber.uintValue as? T
                }
                if type == Int.self, NSNumber(value: nsNumber.intValue) == nsNumber {
                    return nsNumber.intValue as? T
                }
            }
            return nil
        }

    /// 布尔值解码：支持自定义转换器拦截
    func unwrapBoolValue(from value: JSONValue, for additionalKey: CodingKey? = nil) -> Bool? {

        if let tranformer = cache.valueTransformer(for: additionalKey, in: codingPath) {
            return tranformer.transformFromJSON(value) as? Bool
        }

        guard case .bool(let bool) = value else { return nil }
        return bool
    }

    /// 字符串解码：支持自定义转换器拦截
    func unwrapStringValue(from value: JSONValue, for additionalKey: CodingKey? = nil) -> String? {

        if let tranformer = cache.valueTransformer(for: additionalKey, in: codingPath) {
            return tranformer.transformFromJSON(value) as? String
        }

        guard case .string(let string) = value else { return nil }
        return string
    }
}

/// 特殊类型解码：针对 Date/Data/URL/Decimal/CGFloat/Dictionary 的专用解码逻辑
/// 这些方法在新的 SingleValueContainer 上下文中调用，key 已添加到 codingPath
extension JSONDecoderImpl {

    /// CGFloat 解码：直接 String → Double → CGFloat，避免中间层不可预测性
    /// 设计目的：CGFloat 在不同平台（32位/64位）的精度可能不同，直接转换确保一致性
    private func unwrapCGFloat() throws -> CGFloat {
        guard case .number(let numberString) = self.json else {
            throw DecodingError.typeMismatch(CGFloat.self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Expected a JSON number for \(CGFloat.self), but found."))
        }

        guard let doubleValue = Double(numberString) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: self.codingPath,
                debugDescription: "Parsed JSON number <\(numberString)> is not a valid Double for conversion to \(CGFloat.self)."))
        }

        return CGFloat(doubleValue)
    }

    /// Date 解码：两层策略（用户指定 → DateParser 自动兜底）
    /// 参见 Decoding-Pipeline.md §6.2 - 日期解码策略
    ///
    /// 第一层：用户指定的 dateDecodingStrategy
    /// - .deferredToDate: 延迟到 Date.init(from:) 解码
    /// - .secondsSince1970: Unix 时间戳（秒）
    /// - .millisecondsSince1970: Unix 时间戳（毫秒）
    /// - .iso8601: ISO8601 标准格式
    /// - .formatted: 自定义 DateFormatter
    /// - .custom: 自定义解码闭包
    ///
    /// 第二层：DateParser 自动兜底
    /// - 支持 9 种常见日期格式（RFC1123/RFC850/ANSIC 等）
    /// - 参见 DateParser.swift 了解完整格式列表
    private func unwrapDate() throws -> Date {
        let container = SingleValueContainer(impl: self, codingPath: codingPath, json: json)

        // 第一层：用户指定的策略
        if let dateDecodingStrategy = self.options.dateDecodingStrategy  {
            switch dateDecodingStrategy {
            case .deferredToDate:
                return try Date(from: self)

            case .secondsSince1970:
                let double = try container.decode(Double.self)
                return Date(timeIntervalSince1970: double)

            case .millisecondsSince1970:
                let double = try container.decode(Double.self)
                return Date(timeIntervalSince1970: double / 1000.0)

            case .iso8601:
                if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                    let string = try container.decode(String.self)
                    guard let date = _iso8601Formatter.date(from: string) else {
                        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Expected date string to be ISO8601-formatted."))
                    }

                    return date
                } else {
                    fatalError("ISO8601DateFormatter is unavailable on this platform.")
                }

            case .formatted(let formatter):
                let string = try container.decode(String.self)
                guard let date = formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Date string does not match format expected by formatter."))
                }
                return date

            case .custom(let closure):
                return try closure(self)
            @unknown default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Date is not valid , unknown anomaly"))
            }
        }

        // 第二层：DateParser 自动兜底 - 支持 9 种常见日期格式
        if let (date, _) = DateParser.parse(json.peel) {
            return date
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Unsupported date format: \(json)"))
        }
    }

    /// Data 解码：支持 Base64 编码的字符串
    /// 参见 Decoding-Pipeline.md §6.3 - 二进制数据解码
    private func unwrapData() throws -> Data {

        switch self.options.dataDecodingStrategy {
        case .base64:
            let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
            let string = try container.decode(String.self)

            guard let data = Data(base64Encoded: string) else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: self.codingPath, debugDescription: "Encountered Data is not valid Base64."))
            }

            return data
        }
    }

    /// URL 解码：SingleValueContainer 解码 + Patcher 兼容路径可抢救中文 URL
    /// 设计目的：直接使用 URL(string:) 初始化，符合 RFC3986 标准
    /// 特殊处理：对于包含中文等非 ASCII 字符的 URL，可通过 Patcher 进行路径修复
    private func unwrapURL() throws -> URL {

        let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)
        let string = try container.decode(String.self)

        guard let url = URL(string: string) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: self.codingPath,
                                      debugDescription: "Invalid URL string."))
        }
        return url
    }

    /// Decimal 解码：直接从 JSON 数字字符串创建 Decimal
    /// 设计目的：避免浮点数精度损失，确保金融计算的正确性
    private func unwrapDecimal() throws -> Decimal {

        guard case .number(let numberString) = self.json else {
            throw DecodingError.typeMismatch(Decimal.self, DecodingError.Context(codingPath: self.codingPath, debugDescription: ""))
        }

        guard let decimal = Decimal(string: numberString) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: self.codingPath,
                debugDescription: "Parsed JSON number <\(numberString)> does not fit in \(Decimal.self)."))
        }

        return decimal
    }
    
    
    
    /// 字符串字典解码：支持 [String: Any] 形式的递归解码
    /// 参见 Decoding-Pipeline.md §6.4 - 字典解码
    ///
    /// 设计目的：当字典的值也是 Decodable 类型时，需要递归解码每个值
    /// 执行策略：
    /// 1. 遍历 JSON 对象的每个键值对
    /// 2. 为每个值创建新的 JSONDecoderImpl 实例（递归调用）
    /// 3. 使用 _eraseCreateByDirectUnwrap 静态方法解码值类型
    private func unwrapDictionary<T: Decodable>(as: T.Type) throws -> T {
        guard let dictType = T.self as? (_JSONStringDictionaryDecodableMarker & Decodable).Type else {
            preconditionFailure("Must only be called of T implements _JSONStringDictionaryDecodableMarker")
        }
        
        guard case .object(let object) = self.json else {
            throw DecodingError.typeMismatch([String: JSONValue].self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Expected to decode \([String: JSONValue].self) but found \(self.json.debugDataTypeDescription) instead."
            ))
        }
        
        var result = [String: Any]()
        
        for (key, value) in object {
            var newPath = self.codingPath
            newPath.append(_JSONKey(stringValue: key)!)
            let newDecoder = JSONDecoderImpl(
                userInfo: self.userInfo,
                from: value,
                codingPath: newPath,
                options: self.options)
            result[key] = try dictType.elementType._eraseCreateByDirectUnwrap(from: newDecoder)
        }
        return result as! T
    }
    
    /// 创建类型不匹配错误：统一生成类型错误的上下文信息
    /// 设计目的：提供一致的错误格式，包含编码路径和调试信息
    func createTypeMismatchError(type: Any.Type, for additionalKey: CodingKey? = nil, value: JSONValue) -> DecodingError {
        var path = self.codingPath
        if let additionalKey = additionalKey {
            path.append(additionalKey)
        }
        
        return DecodingError.typeMismatch(type, .init(
            codingPath: path,
            debugDescription: "Expected to decode \(type) but found \(value.debugDataTypeDescription) instead."
        ))
    }
}


/// Decodable 扩展：提供静态解码方法，支持类型擦除调用
/// 参见 Decoding-Pipeline.md §6.5 - 类型擦除解码机制
extension Decodable {
    /// 直接解码静态方法：在已知具体类型时直接解码
    /// 参见 Decoding-Pipeline.md §6.5.1 - 静态解码路径
    ///
    /// 执行策略：
    /// 1. 特殊类型拦截：URL/Date/Data/Decimal/CGFloat/SmartAnyImpl/字典 走专用路径
    /// 2. 普通模型路径：使用快照栈管理，支持循环引用检测
    ///
    /// - parameter decoder: JSON 解码器实例
    /// - parameter type: 要解码的目标类型
    /// - returns: 解码后的实例
    fileprivate static func createByDirectlyUnwrapping<T>(from decoder: JSONDecoderImpl, type: T.Type) throws -> Self {
        if Self.self == URL.self
            || Self.self == Date.self
            || Self.self == Data.self
            || Self.self == Decimal.self
            || Self.self == CGFloat.self
            || Self.self == SmartAnyImpl.self
            || Self.self is _JSONStringDictionaryDecodableMarker.Type
        {
            return try decoder.unwrap(as: Self.self)
        }
        decoder.cache.cacheSnapshot(for: type, codingPath: decoder.codingPath)
        let decoded = try Self.init(from: decoder)
        decoder.cache.removeSnapshot(for: type)
        
        
        return decoded
    }
    
    /// createByDirectlyUnwrapping 的 Self 是静态绑定的（一个真正的类型），
    /// 不能直接通过 Decodable.Type 这样的「存在类型」调用。
    ///
    /// 例如：
    ///     let type: Decodable.Type = Int.self
    ///     type.createByDirectlyUnwrapping(...)   // ❌ 编译不会通过
    ///
    /// Swift 在协议扩展里对 static 方法的规则是：
    /// - 必须在编译期确定具体的 Self 类型
    /// - 协议存在类型（Decodable.Type）并不携带这个静态类型信息
    ///
    /// unwrapDictionary 的场景里，我们拿到的是
    ///     dictType.elementType: Decodable.Type
    /// 这里没有具体的 Self，因此无法直接调 createByDirectlyUnwrapping。
    ///
    /// _eraseCreateByDirectUnwrap 做的事很简单：
    /// - 把静态方法的调用重新包装一层，让 Self = 实际的 metatype 本身
    /// - 返回值用 Any 消除静态类型要求
    ///
    /// 最终可以通过：
    ///     dictType.elementType._eraseCreateByDirectUnwrap(...)
    /// 让 Swift 正确推导 Self 并调用真正的解码逻辑。
    ///
    /// 本质上，这是一个「存在类型调用协议扩展 static 方法」的逃逸通道。
    static func _eraseCreateByDirectUnwrap(from decoder: JSONDecoderImpl) throws -> Any {
        return try self.createByDirectlyUnwrapping(from: decoder, type: self)
    }
}

@available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *)
internal let _iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    return formatter
}()


