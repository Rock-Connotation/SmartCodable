//
//  SmartAny.swift
//  SmartCodable
//
//  Created by Mccc on 2023/12/1.
//

import Foundation

// MARK: - SmartAnyImpl 内部枚举

/// SmartCodable 内部动态类型系统，用 5 个 case 覆盖 JSON 所有可能的值类型。
///
/// **WHAT**: 将 JSON 值归一化为 5 种情况，提供 `peel` 展开和 Codable 编解码。
///
/// **WHY (为什么是 NSNumber？)**: 早期实现将每种数字类型拆成独立 case（bool/double/float/int/int8/...），
/// 但 JSON 中的数字 `5` 无法确定它是 Int、Int8 还是 UInt——强类型指定会导致 `as? Double` 失败。
/// NSNumber 在内部保留原始数值的同时允许运行时查询具体类型，牺牲部分类型安全换取动态类型灵活性。
/// 在 @SmartAny 需要处理 `[String: Any]` 的场景下，这个取舍是合理的。
///
/// **WHY (5 个 case？)**: JSON 规范只有 6 种值类型，其中 boolean 在 Foundation 中通过 NSNumber 桥接
/// （kCFBooleanTrue/kCFBooleanFalse），所以 number 一个 case 覆盖了数字和布尔。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
enum SmartAnyImpl {
    
    /// 所有数字类型（含 Bool）。NSNumber 的动态特性允许运行时查询具体类型，
    /// 避免了早期实现中拆分为 bool/double/float/int/int8... 等独立 case 时
    /// 因类型信息丢失导致的 `as? Double` 失败问题。
    case number(NSNumber)
    case string(String)
    case dict([String: SmartAnyImpl])
    case array([SmartAnyImpl])
    case null(NSNull)
    
    
    public init(from value: Any) {
        self = .convertToSmartAny(value)
    }
}

// MARK: - cover / peel 转换桥梁
// cover: Swift 原生类型 → SmartAnyImpl（编码方向）
// peel:  SmartAnyImpl → Swift 原生类型（解码方向）

extension Dictionary where Key == String {
    /// [String: Any] → [String: SmartAnyImpl]，用于编码时将字典值逐项包装
    internal var cover: [String: SmartAnyImpl] {
        mapValues { SmartAnyImpl(from: $0) }
    }

    /// 如果是 SmartAnyImpl 字典则 peel，否则直接返回自身（已是原生类型）
    internal var peelIfPresent: [String: Any] {
        if let dict = self as? [String: SmartAnyImpl] {
            return dict.peel
        } else {
            return self
        }
    }
}

extension Array {
    /// [Any] → [SmartAnyImpl]，用于编码时将数组元素逐项包装
    internal var cover: [ SmartAnyImpl] {
        map { SmartAnyImpl(from: $0) }
    }

    /// 尝试 peel 三种可能的数组包装形式
    internal var peelIfPresent: [Any] {
        if let arr = self as? [[String: SmartAnyImpl]] {
            return arr.peel
        } else if let arr = self as? [SmartAnyImpl] {
            return arr.peel
        } else {
            return self
        }
    }
}


extension Dictionary where Key == String, Value == SmartAnyImpl {
    /// SmartAnyImpl 字典 → [String: Any]，递归 peel 每个值
    internal var peel: [String: Any] {
        mapValues { $0.peel }
    }
}
extension Array where Element == SmartAnyImpl {
    /// SmartAnyImpl 数组 → [Any]，递归 peel 每个元素
    internal var peel: [Any] {
        map { $0.peel }
    }
}

extension Array where Element == [String: SmartAnyImpl] {
    /// [[String: SmartAnyImpl]] → [Any]（嵌套字典数组场景）
    public var peel: [Any] {
        map { $0.peel }
    }
}


extension SmartAnyImpl {
    /// SmartAnyImpl → 原生 Swift 类型。dict/array 递归 peel，number/string/null 直接返回。
    public var peel: Any {
        switch self {
        case .number(let v):  return v
        case .string(let v):  return v
        case .dict(let v):    return v.peel
        case .array(let v):   return v.peel
        case .null:           return NSNull()
        }
    }
}



extension SmartAnyImpl: Codable {
    public init(from decoder: Decoder) throws {
        
        
        guard let decoder = decoder as? JSONDecoderImpl else {
            throw DecodingError.typeMismatch(
                SmartAnyImpl.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected \(Self.self) value, but decoder type mismatch"
                )
            )
        }
        
        guard let containerAny = try? decoder.singleValueContainer(),
              let container = containerAny as? JSONDecoderImpl.SingleValueContainer else {
            throw DecodingError.typeMismatch(
                SmartAnyImpl.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected \(Self.self) value, but container type mismatch"
                )
            )
        }
        
        
       
        if container.decodeNil() {
            self = .null(NSNull())
        } else if let value = try? decoder.unwrapSmartAny() {
            self = value
        } else {
            throw DecodingError.typeMismatch(SmartAnyImpl.self, DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "Expected \(Self.self) value，but an exception occurred！Please report this issue（请上报该问题）")
            )
        }
    }
        
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .dict(let dictValue):
            try container.encode(dictValue)
        case .array(let arrayValue):
            try container.encode(arrayValue)
        case .number(let value):
            // NSNumber 编码：必须先判断 Bool（kCFBoolean 的内存标识不同于纯数字），
            // 然后按精度从高到低尝试类型转换（Double → Float → CGFloat → Int... → UInt64）。
            // 顺序不能调整，否则布尔会被误判为数字，或 Float 被提升为 Double。
            if value === kCFBooleanTrue as NSNumber || value === kCFBooleanFalse as NSNumber {
                if let bool = value as? Bool {
                    try container.encode(bool)
                }  
            } else if let double = value as? Double {
                try container.encode(double)
            } else if let float = value as? Float {
                try container.encode(float)
            } else if let cgfloat = value as? CGFloat {
                try container.encode(cgfloat)
            } else if let int = value as? Int {
                try container.encode(int)
            } else if let int8 = value as? Int8 {
                try container.encode(int8)
            } else if let int16 = value as? Int16 {
                try container.encode(int16)
            } else if let int32 = value as? Int32 {
                try container.encode(int32)
            } else if let int64 = value as? Int64 {
                try container.encode(int64)
            } else if let uInt = value as? UInt {
                try container.encode(uInt)
            } else if let uInt8 = value as? UInt8 {
                try container.encode(uInt8)
            } else if let uInt16 = value as? UInt16 {
                try container.encode(uInt16)
            } else if let uInt32 = value as? UInt32 {
                try container.encode(uInt32)
            } else if let uInt64 = value as? UInt64 {
                try container.encode(uInt64)
            } else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "NSNumber contains unsupported type"))
            }
        }
    }
}


extension SmartAnyImpl {
    private static func convertToSmartAny(_ value: Any) -> SmartAnyImpl {
        switch value {
        case let v as NSNumber:      return .number(v)
        case let v as String:        return .string(v)
        case let v as [String: Any]: return .dict(v.mapValues { convertToSmartAny($0) })
        case let v as SmartCodableX:
            if let dict = v.toDictionary() {
                return .dict(dict.mapValues { convertToSmartAny($0) })
            }
        case let v as [Any]:         return .array(v.map { convertToSmartAny($0) })
        case is NSNull:              return .null(NSNull())
        default:                     break
        }
        
        return .null(NSNull())
    }
}


extension JSONDecoderImpl {
    // MARK: - unwrapSmartAny（SmartAnyImpl 解码核心）

    /// 将 JSON 值转换为 SmartAnyImpl 枚举。根据 JSON 类型分派：
    /// - null/string/bool → 直接映射
    /// - object → decodeIfPresent([String: SmartAnyImpl].self) → .dict
    /// - array  → decodeIfPresent([SmartAnyImpl].self) → .array
    /// - number → 按精度策略解析：科学计数法用 Decimal（次正规数回退 Double），
    ///   普通浮点用 Double，整数按 Int64 范围从窄到宽尝试（Int8→UInt64），
    ///   超出 Int64 范围则保留为 string 避免精度丢失
    fileprivate func unwrapSmartAny() throws -> SmartAnyImpl {

        // 优先走转换器路径
        if let tranformer = cache.valueTransformer(for: codingPath.last, in: codingPath.dropLast()) {
            if let decoded = tranformer.transformFromJSON(json) as? SmartAnyImpl {
                return decoded
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: self.codingPath,
                                          debugDescription: "Invalid SmartAny."))
            }
        }

        let container = SingleValueContainer(impl: self, codingPath: self.codingPath, json: self.json)


        switch json {
        case .null:
            return .null(NSNull())
        case .string(let string):
            return .string(string)
        case .bool(let bool):
            return .number(bool as NSNumber)
        case .object(_):
            if let temp = container.decodeIfPresent([String: SmartAnyImpl].self) {
                return .dict(temp)
            }
        case .array(_):
            if let temp = container.decodeIfPresent([SmartAnyImpl].self) {
                return .array(temp)
            }
        case .number(let number):
            if number.contains(".") { // 浮点数
                // RFC 8259 允许 e/E 两种科学计数法
                if number.contains("e") || number.contains("E") {
                    if let temp = container.decodeIfPresent(Decimal.self) as? NSNumber {
                        return .number(temp)
                    }
                    // Decimal 无法覆盖次正规数（如 ±E-324），回退 Double
                    if let temp = container.decodeIfPresent(Double.self) as? NSNumber {
                        return .number(temp)
                    }
                } else {
                    if let temp = container.decodeIfPresent(Double.self) as? NSNumber {
                        return .number(temp)
                    }
                }
            } else {
                if let _ = Int64(number) { // Int64 范围内：从窄到宽尝试匹配
                    if let temp = container.decodeIfPresent(Int8.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(UInt8.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(Int16.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(UInt16.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(Int32.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(UInt32.self) as? NSNumber {
                        return .number(temp)
                    }  else if let temp = container.decodeIfPresent(Int64.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(UInt64.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(Int.self) as? NSNumber {
                        return .number(temp)
                    } else if let temp = container.decodeIfPresent(UInt.self) as? NSNumber {
                        return .number(temp)
                    }
                } else {
                    // 超出 Int64 范围的大整数，保留字符串避免精度丢失
                    return .string(number)
                }
            }
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: self.codingPath,
                                  debugDescription: "Invalid SmartAny."))
    }
}

extension JSONDecoderImpl.SingleValueContainer {
    
    fileprivate func decodeIfPresent(_: Bool.Type) -> Bool? {
        guard case .bool(let bool) = self.value else {
            return nil
        }

        return bool
    }

    fileprivate func decodeIfPresent(_: String.Type) -> String? {
        guard case .string(let string) = self.value else {
            return nil
        }
        return string
    }

    fileprivate func decodeIfPresent(_: Double.Type) -> Double? {
        decodeIfPresentFloatingPoint()
    }

    fileprivate func decodeIfPresent(_: Float.Type) -> Float? {
        decodeIfPresentFloatingPoint()
    }

    fileprivate func decodeIfPresent(_: Int.Type) -> Int? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: Int8.Type) -> Int8? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: Int16.Type) -> Int16? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: Int32.Type) -> Int32? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: Int64.Type) -> Int64? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: UInt.Type) -> UInt? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: UInt8.Type) -> UInt8? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: UInt16.Type) -> UInt16? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: UInt32.Type) -> UInt32? {
        decodeIfPresentFixedWidthInteger()
    }

    fileprivate func decodeIfPresent(_: UInt64.Type) -> UInt64? {
        decodeIfPresentFixedWidthInteger()
    }
    
    fileprivate func decodeIfPresent<T>(_ type: T.Type) -> T? where T: Decodable {
        if let decoded: T = try? self.impl.unwrap(as: type) {
            return decoded
        } else {
            return nil
        }
    }
    
    @inline(__always) private func decodeIfPresentFixedWidthInteger<T: FixedWidthInteger>() -> T? {
        guard let decoded = self.impl.unwrapFixedWidthInteger(from: self.value, as: T.self) else {
            return nil
        }
        return decoded
    }

    @inline(__always) private func decodeIfPresentFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>() -> T? {
        
        guard let decoded = self.impl.unwrapFloatingPoint(from: self.value, as: T.self) else {
            return nil
        }
        return decoded
    }
}
