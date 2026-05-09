//
//  _SpecialTreatmentEncoder.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation


/// 标记协议：用于识别 [String: Encodable] 类型字典
/// 在 wrapEncodable 中特殊处理，避免递归编码
protocol _JSONStringDictionaryEncodableMarker { }

extension Dictionary: _JSONStringDictionaryEncodableMarker where Key == String, Value: Encodable { }


/// 特殊处理编码器协议：为特定类型提供定制编码路径
/// 与解码端的 _SpecialTreatmentDecoder 对称
/// 学习文档：编码器架构 - 特殊类型处理
protocol _SpecialTreatmentEncoder {
    var codingPath: [CodingKey] { get }
    var options: SmartJSONEncoder._Options { get }
    var impl: JSONEncoderImpl { get }
}

extension _SpecialTreatmentEncoder {
    /// 处理浮点数编码（包括特殊值 NaN 和 Infinity）
    /// 支持两种策略：转换为字符串或抛出错误
    /// 优化：移除 .0 后缀（如 3.0 → 3）
    /// 学习文档：特殊值处理 - 浮点数特殊值
    @inline(__always)
    func wrapFloat<F: FloatingPoint & CustomStringConvertible>(_ float: F, for additionalKey: CodingKey?) throws -> JSONValue {
        guard !float.isNaN, !float.isInfinite else {
            if case .convertToString(let posInfString, let negInfString, let nanString) = self.options.nonConformingFloatEncodingStrategy {
                switch float {
                case F.infinity:
                    return .string(posInfString)
                case -F.infinity:
                    return .string(negInfString)
                default:
                    // must be nan in this case
                    return .string(nanString)
                }
            }

            var path = self.codingPath
            if let additionalKey = additionalKey {
                path.append(additionalKey)
            }

            throw EncodingError.invalidValue(float, .init(
                codingPath: path,
                debugDescription: "Unable to encode \(F.self).\(float) directly in JSON."
            ))
        }

        var string = float.description
        if string.hasSuffix(".0") {
            string.removeLast(2)
        }
        return .number(string)
    }

    /// 处理 Encodable 类型编码（分发到具体处理方法）
    /// 特殊类型走定制路径，其他类型走默认 Codable 路径
    /// SmartCodable 模型通过 cacheSnapshot 支持值转换器
    /// FlatType 特殊处理：将嵌套属性提升到上层
    /// 学习文档：编码器架构 - 类型分发逻辑
    func wrapEncodable<E: Encodable>(_ encodable: E, for additionalKey: CodingKey?) throws -> JSONValue? {
        switch encodable {
        case let date as Date:
            return try self.wrapDate(date, for: additionalKey)
        case let data as Data:
            return try self.wrapData(data, for: additionalKey)
        case let url as URL:
            return .string(url.absoluteString)
        case let decimal as Decimal:
            return .number(decimal.description)
        case let object as _JSONStringDictionaryEncodableMarker:
            return try self.wrapObject(object as! [String: Encodable], for: additionalKey)
        default:

            // 为 SmartCodable 模型创建快照（支持值转换器）
            let encoder = self.getEncoder(for: additionalKey)
            encoder.cache.cacheSnapshot(for: E.self, codingPath: encoder.codingPath)
            try encodable.encode(to: encoder)
            encoder.cache.removeSnapshot(for: E.self)

            // SmartFlat 特殊处理：将嵌套属性提升到上层对象
            // SmartFlat 展平了嵌套结构，编码时需要将子属性直接合并到父对象
            if encodable is FlatType {
                if let object = encoder.value?.object {
                    for (key, value) in object {
                        self.impl.object?.set(value, for: key)
                    }
                    return nil
                }
            }
        
            return encoder.value
        }
    }

    /// 处理 Date 编码（支持多种策略）
    /// 优先使用值转换器（DateTransformer），否则应用 dateEncodingStrategy
    /// 策略：deferredToDate / secondsSince1970 / millisecondsSince1970 / iso8601 / formatted / custom
    /// 学习文档：特殊值处理 - Date 编码策略
    func wrapDate(_ date: Date, for additionalKey: CodingKey?) throws -> JSONValue {

        // 优先使用值转换器（自定义日期格式）
        if let value = impl.cache.tranform(from: date, with: additionalKey, codingPath: codingPath) {
            return value
        }

        switch self.options.dateEncodingStrategy {
        case .deferredToDate:
            let encoder = self.getEncoder(for: additionalKey)
            try date.encode(to: encoder)
            return encoder.value ?? .null

        case .secondsSince1970:
            return .number(date.timeIntervalSince1970.description)

        case .millisecondsSince1970:
            return .number((date.timeIntervalSince1970 * 1000).description)

        case .iso8601:
            if #available(macOS 10.12, iOS 10.0, watchOS 3.0, tvOS 10.0, *) {
                return .string(_iso8601Formatter.string(from: date))
            } else {
                fatalError("ISO8601DateFormatter is unavailable on this platform.")
            }

        case .formatted(let formatter):
            return .string(formatter.string(from: date))

        case .custom(let closure):
            let encoder = self.getEncoder(for: additionalKey)
            try closure(date, encoder)
            // The closure didn't encode anything. Return the default keyed container.
            return encoder.value ?? .object([:])
        @unknown default:
            let encoder = self.getEncoder(for: additionalKey)
            try date.encode(to: encoder)
            return encoder.value ?? .null
        }
    }

    /// 处理 Data 编码（仅支持 base64）
    /// JSON 标准不支持二进制数据，必须编码为字符串
    /// 学习文档：特殊值处理 - Data 编码
    func wrapData(_ data: Data, for additionalKey: CodingKey?) throws -> JSONValue {
        switch self.options.dataEncodingStrategy {
        case .base64:
            let base64 = data.base64EncodedString()
            return .string(base64)
        }
    }

    /// 处理字典编码（[String: Encodable]）
    /// 为每个值创建子编码器，递归编码
    /// 优化：reserveCapacity 预分配内存
    /// 学习文档：编码器架构 - 字典编码
    func wrapObject(_ object: [String: Encodable], for additionalKey: CodingKey?) throws -> JSONValue {
        var baseCodingPath = self.codingPath
        if let additionalKey = additionalKey {
            baseCodingPath.append(additionalKey)
        }
        var result = [String: JSONValue]()
        result.reserveCapacity(object.count)

        try object.forEach { (key, value) in
            var elemCodingPath = baseCodingPath
            elemCodingPath.append(_JSONKey(stringValue: key, intValue: nil))
            let encoder = JSONEncoderImpl(options: self.options, codingPath: elemCodingPath)

            result[key] = try encoder.wrapUntyped(value)
        }

        return .object(result)
    }

    /// 获取子编码器（用于嵌套编码）
    /// 如果有 additionalKey，创建新编码器并更新编码路径
    /// 否则返回当前编码器（共享状态）
    /// 学习文档：编码器架构 - 嵌套编码管理
    func getEncoder(for additionalKey: CodingKey?) -> JSONEncoderImpl {
        if let additionalKey = additionalKey {
            var newCodingPath = self.codingPath
            newCodingPath.append(additionalKey)
            return JSONEncoderImpl(options: self.options, codingPath: newCodingPath, cache: impl.cache)
        }
        return self.impl
    }
}


extension _SpecialTreatmentEncoder {


    /// 使用转换器编码值（与 EncodingCache.transform 重复实现）
    /// 区分属性包装器和普通值的转换逻辑
    /// 调用转换器的 transformToJSON 方法
    /// 学习文档：值转换器 - 编码端转换流程
    internal func encodeWithTransformer<Performer: ValueTransformable>(_ performer: Performer, decodedValue: Any) -> Any? {
        // 首先检查是否是属性包装器（需要提取 wrappedValue）
        if let propertyWrapper = decodedValue as? any PropertyWrapperable {
            let wrappedValue = propertyWrapper.wrappedValue
            guard let value = wrappedValue as? Performer.Object else {
                return nil
            }
            return performer.transformToJSON(value)
        } else {
            guard let value = decodedValue as? Performer.Object else { return nil }
            return performer.transformToJSON(value)
        }
    }
    


    /// 应用键名转换策略（与解码端 _converted 对称）
    /// 支持两种转换：
    /// 1. 键名映射（mappingForKey）：根据 useMappedKeys 决定方向
    /// 2. 全局策略（keyEncodingStrategy）：useDefaultKeys / toSnakeCase / firstLetterLower / firstLetterUpper
    /// 学习文档：键名策略 - 编码端键名转换
    internal func _converted(_ key: CodingKey) -> CodingKey {

        var newKey = key

        // 检查是否使用映射键（从 mappingForKey 的 from 列表选择）
        var useMappedKeys = false
        if let key = CodingUserInfoKey.useMappedKeys {
            useMappedKeys = impl.userInfo[key] as? Bool ?? false
        }
            
        // 应用键名映射（从模型定义的 to 键查找对应的 from 键）
        if let objectType = impl.cache.findSnapShot(with: impl.codingPath)?.objectType {
            if let mappings = objectType.mappingForKey() {
                for mapping in mappings {
                    if mapping.to.stringValue == newKey.stringValue {
                        if useMappedKeys, let first = mapping.from.first {
                            newKey = _JSONKey.init(stringValue: first, intValue: nil)
                        } else {
                            newKey = mapping.to
                        }
                    }
                }
            }
        }

        // 应用全局键名策略
        switch self.options.keyEncodingStrategy {
        case .toSnakeCase:
            let newKeyString = SmartJSONEncoder.SmartKeyEncodingStrategy._convertToSnakeCase(newKey.stringValue)
            return _JSONKey(stringValue: newKeyString, intValue: newKey.intValue)
        case .firstLetterLower:
            let newKeyString = SmartJSONEncoder.SmartKeyEncodingStrategy._convertFirstLetterToLowercase(newKey.stringValue)
            return _JSONKey(stringValue: newKeyString, intValue: newKey.intValue)
        case .firstLetterUpper:
            let newKeyString = SmartJSONEncoder.SmartKeyEncodingStrategy._convertFirstLetterToUppercase(newKey.stringValue)
            return _JSONKey(stringValue: newKeyString, intValue: newKey.intValue)
        case .useDefaultKeys:
            return newKey
        }
    }
}
