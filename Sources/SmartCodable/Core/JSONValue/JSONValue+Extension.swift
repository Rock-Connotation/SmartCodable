//
//  JSONValue+Extension.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/23.
//

import Foundation

// MARK: - JSONValue 扩展：类型提取和解包

extension JSONValue {

    /// 提取对象类型值（如果是字典）
    var object: [String: JSONValue]? {
        switch self {
        case .object(let v):
            return v
        default:
            return nil
        }
    }

    /// 提取数组类型值（如果是数组）
    var array: [JSONValue]? {
        switch self {
        case .array(let v):
            return v
        default:
            return nil
        }
    }

    /// 提取原始值（String/Bool/NSNumber）
    /// - 递归处理容器类型（Array/Dictionary）
    /// - Number 值通过 fromJSONNumber 转换为最合适的 NSNumber 类型
    /// - 参见 Decoding-Pipeline.md §4.4
    var peel: Any {
        switch self {
        case .array(let v):
            return v.peel
        case .bool(let v):
            return v
        case .number(let v):
            if let number = NSNumber.fromJSONNumber(v) {
                return number
            } else {
                return v // fallback to string
            }
        case .string(let v):
            return v
        case .object(let v):
            return v.peel
        case .null:
            return NSNull()
        }
    }
}

// MARK: - 容器类型 peel 扩展

extension Dictionary where Key == String, Value == JSONValue {
    /// 解包 JSONValue 字典为 Foundation 字典
    /// 解析后的值会被 SmartAny 包装，使用此属性解包
    var peel: [String: Any] {
        mapValues { $0.peel }
    }
}

extension Array where Element == JSONValue {
    /// 解包 JSONValue 数组为 Foundation 数组
    /// 解析后的值会被 SmartAny 包装，使用此属性解包
    var peel: [Any] {
        map { $0.peel }
    }
}

extension Array where Element == [String: JSONValue] {
    /// 解包 JSONValue 字典数组为 Foundation 字典数组
    /// 解析后的值会被 SmartAny 包装，使用此属性解包
    var peel: [Any] {
        map { $0.peel }
    }
}
