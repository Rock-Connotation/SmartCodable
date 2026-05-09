//
//  JSONValue.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/17.
//

import Foundation

/// SmartCodable 内部 JSON 树表示，替代 Foundation 的 NSNumber/NSString 等类型
/// 设计目标：延迟类型决策，避免精度丢失
/// 参见 Decoding-Pipeline.md §4
enum JSONValue: Equatable {
    case string(String)
    case number(String)  // 用字符串保存数字——延迟类型决策，避免精度丢失
    case bool(Bool)
    case null

    case array([JSONValue])
    case object([String: JSONValue])


    /// 从 Foundation 对象递归构建 JSONValue 树
    /// - 关键决策：NSNumber → Bool 区分（ObjC 中 @YES/@NO 是 char 型 NSNumber）
    static func make(_ value: Any?) -> Self? {

        guard let value = value else { return nil }

        if let jsonValue = value as? JSONValue {
            return jsonValue
        }

        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:

            // 判断是否为 Bool 类型（ObjC 中 @YES/@NO 是 char 型 NSNumber）
            let cfType = CFNumberGetType(number)
            if cfType == .charType {
                return .bool(number.boolValue)
            } else {
                return .number(number.stringValue)
            }

        case let array as [Any]:
            let jsonArray = array.compactMap { make($0) }
            return .array(jsonArray)
        case let dictionary as [String: Any]:
            let jsonObject = dictionary.compactMapValues { make($0) }
            return .object(jsonObject)
        default:
            return nil
        }
    }
    
    func toFoundation() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .number(let n):
            /// 直接返回number即可。
            if let number = NSNumber.fromJSONNumber(n) {
                return number
            } else {
                return n
            }
            
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { $0.toFoundation() }
        case .object(let dict):
            return dict.mapValues { $0.toFoundation() }
        }
    }
}

// MARK: - Helper 属性

extension JSONValue {
    /// 是否为叶子节点（非容器类型）
    var isValue: Bool {
        switch self {
        case .array, .object:
            return false
        case .null, .number, .string, .bool:
            return true
        }
    }

    /// 是否为 null 值
    var isNull: Bool {
        switch self {
        case .null:
            return true
        case .array, .object, .number, .string, .bool:
            return false
        }
    }

    /// 是否为容器类型（数组或对象）
    var isContainer: Bool {
        switch self {
        case .array, .object:
            return true
        case .null, .number, .string, .bool:
            return false
        }
    }
}

// MARK: - 调试支持

extension JSONValue {
    /// 获取数据类型的调试描述
    var debugDataTypeDescription: String {
        switch self {
        case .array:
            return "’Array’"
        case .bool:
            return "’Bool’"
        case .number:
            return "’Number’"
        case .string:
            return "’String’"
        case .object:
            return "’Dictionary’"
        case .null:
            return "’null’"
        }
    }
}

// MARK: - NSNumber 转换扩展

extension NSNumber {
    /// 从 JSON 数字字符串转换为 NSNumber，采用分级保精度策略
    /// - 整数优先：Int64(≤19位) → UInt64(≤20位)
    /// - 超高精度：Decimal（17位以上的小数）
    /// - 兜底：Double
    /// 参见 Decoding-Pipeline.md §4.4
    static func fromJSONNumber(_ string: String) -> NSNumber? {
        let decIndex = string.firstIndex(of: ".")
        // JSON 规范允许大写 E 作为科学计数法标记
        let expIndex = string.firstIndex(where: { $0 == "e" || $0 == "E" })
        let isInteger = decIndex == nil && expIndex == nil
        let isNegative = string.utf8[string.utf8.startIndex] == UInt8(ascii: "-")
        let digitCount = string[string.startIndex..<(expIndex ?? string.endIndex)].count

        // 整数优先：尝试 Int64() 或 UInt64()
        if isInteger {
            if isNegative {
                if digitCount <= 19, let intValue = Int64(string) {
                    return NSNumber(value: intValue)
                }
            } else {
                if digitCount <= 20, let uintValue = UInt64(string) {
                    return NSNumber(value: uintValue)
                }
            }
        }

        var exp = 0

        if let expIndex = expIndex {
            let expStartIndex = string.index(after: expIndex)
            if let parsed = Int(string[expStartIndex...]) {
                exp = parsed
            }
        }

        // Decimal 精度更高但指数范围更小，适用于高精度小数
        if digitCount > 17, exp >= -128, exp <= 127, let decimal = Decimal(string: string), decimal.isFinite {
            return NSDecimalNumber(decimal: decimal)
        }

        // 兜底方案：使用 Double()
        if let doubleValue = Double(string), doubleValue.isFinite {
            return NSNumber(value: doubleValue)
        }

        return nil
    }
    
    /// 尝试将 NSNumber 转换为最合适的 Swift 基础类型（Int64、Double、Bool、Decimal 等）
    var toBestSwiftType: Any {
        if let decimal = self as? NSDecimalNumber {
            return decimal.decimalValue // 返回 Swift 的 Decimal 类型更自然
        }

        switch CFNumberGetType(self) {
        case .charType:
            return self.boolValue

        case .sInt8Type, .sInt16Type, .sInt32Type, .sInt64Type:
            let int64 = self.int64Value
            if int64 >= Int.min && int64 <= Int.max {
                return Int(int64)
            } else {
                return int64 // fallback
            }

        case .floatType, .float32Type, .float64Type, .doubleType:
            return self.doubleValue

        default:
            return self // fallback 为原始 NSNumber
        }
    }
}
