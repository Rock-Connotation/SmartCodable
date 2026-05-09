//
//  ValuePatcher.swift
//  SmartCodable
//
//  Created by Mccc on 2023/8/22.
//

import Foundation



extension Patcher {
    /// 零值提供者：为类型提供默认值
    ///
    /// 位置：四层韧性架构的最后一道防线
    /// WHAT: 当所有解码策略都失败时，返回类型的零值
    /// HOW: 支持 Defaultable/SmartDecodable/SmartCaseDefaultable/SmartAssociatedEnumerable 四种协议的多态处理
    /// WHY: 确保解码永远失败，至少返回一个有意义的默认值
    struct Provider {
        /// 获取类型 T 的默认值（支持多种协议）
        ///
        /// WHAT: 返回类型的零值，优先级：Defaultable > SmartDecodable > SmartCaseDefaultable > SmartAssociatedEnumerable
        /// HOW: 协议类型检查和强制类型转换
        /// WHY: 支持自定义默认值逻辑，同时为常见类型提供内置默认值
        static func defaultValue() throws -> T {
            
            
            if let defaultable = T.self as? Defaultable.Type {
                return defaultable.defaultValue as! T
            }
            
            // 处理 SmartDecodable 类型的对象
            if let decodable = T.self as? SmartDecodable.Type {
                return decodable.init() as! T
            }
            
            // 处理 SmartCaseDefaultable 类型的对象
            if let caseDefaultable = T.self as? any SmartCaseDefaultable.Type {
                if let first = caseDefaultable.allCases.first, let firstCase = first as? T {
                    return firstCase
                }
            }
            
            // 处理 SmartAssociatedEnumerable 类型的对象
            if let associatedEnumerable = T.self as? any SmartAssociatedEnumerable.Type {
                return associatedEnumerable.defaultCase as! T
            }
            
            // 如果都没有匹配的类型，抛出错误
            throw DecodingError.valueNotFound(T.self, DecodingError.Context(codingPath: [], debugDescription: "Expected \(T.self) value，but an exception occurred！Please report this issue（请上报该问题）"))
        }
    }
}



/// 零值协议：类型提供默认值的协议
///
/// WHAT: 定义类型默认值的协议
/// HOW: 静态属性 defaultValue 返回 Self 类型
/// WHY: 允许类型自定义默认值逻辑（如 Date() 返回当前时间，而不是零值）
protocol Defaultable {
    static var defaultValue: Self { get }
}

extension Date: Defaultable {
    static var defaultValue: Date {
        return Date()
    }
}

extension Data: Defaultable {
    static var defaultValue: Data { Data() }
}

extension Decimal: Defaultable {
    static var defaultValue: Decimal { Decimal(0) }
}

extension Array: Defaultable {
    static var defaultValue: Array<Element> { [] }
}

extension Dictionary: Defaultable {
    static var defaultValue: Dictionary<Key, Value> { return [:] }
}

extension String: Defaultable {
    static var defaultValue: String { "" }
}

extension Bool: Defaultable {
    static var defaultValue: Bool { false }
}


extension Double: Defaultable {
    static var defaultValue: Double { 0.0 }
}

extension Float: Defaultable {
    static var defaultValue: Float { 0.0 }
}

extension CGFloat: Defaultable {
    static var defaultValue: CGFloat { 0.0 }
}

extension Int: Defaultable {
    static var defaultValue: Int { 0 }
}

extension Int8: Defaultable {
    static var defaultValue: Int8 { 0 }
}

extension Int16: Defaultable {
    static var defaultValue: Int16 { 0 }
}

extension Int32: Defaultable {
    static var defaultValue: Int32 { 0 }
}

extension Int64: Defaultable {
    static var defaultValue: Int64 { 0 }
}


extension UInt: Defaultable {
    static var defaultValue: UInt { 0 }
}

extension UInt8: Defaultable {
    static var defaultValue: UInt8 { 0 }
}

extension UInt16: Defaultable {
    static var defaultValue: UInt16 { 0 }
}

extension UInt32: Defaultable {
    static var defaultValue: UInt32 { 0 }
}

extension UInt64: Defaultable {
    static var defaultValue: UInt64 { 0 }
}
