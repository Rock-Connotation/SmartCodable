//
//  TypePatcher.swift
//  SmartCodable
//
//  Created by Mccc on 2023/9/5.
//

import Foundation

extension Patcher {
    /// 类型转换器：集成 mappingForValue 的业务转换
    ///
    /// WHAT: 优先使用 mappingForValue 注册的业务转换器，失败后才走通用转换
    /// HOW: 委托给 TypeTransformable 协议实现
    /// WHY: 业务转换（如日期格式）优先于通用转换（如 String→Int），避免误转换
    struct Transformer {
        /// 执行类型转换（调用 TypeTransformable 协议）
        ///
        /// WHAT: 将 JSONValue 转为目标类型 T
        /// HOW: 通过协议类型检查调用对应的 transformValue 实现
        /// WHY: 多态分发，每个类型实现自己的转换逻辑
        static func typeTransform(from jsonValue: JSONValue, impl: JSONDecoderImpl) -> T? {
            return (T.self as? TypeTransformable.Type)?.transformValue(from: jsonValue, impl: impl) as? T
        }
    }
}


/// 类型转换协议：私有协议，定义类型转换接口
///
/// WHAT: 定义类型从 JSONValue 转换为 Self 的接口
/// HOW: 静态方法 transformValue 接收 JSONValue 和 JSONDecoderImpl
/// WHY: 多态支持，每个类型实现自己的转换逻辑
fileprivate protocol TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Self?
}


/// Bool 类型转换：支持多种格式的 Bool 转换
///
/// WHAT: 将 "true"/"false"/1/0/YES/NO 等格式转为 Bool
/// HOW: 字符串匹配、数字判断
/// WHY: 兼容后端常见的多种布尔值表示方式
extension Bool: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Bool? {
        
        switch value {
        case .bool(let bool):
            return bool
        case .string(let string):
            if ["1","YES","Yes","yes","TRUE","True","true"].contains(string) { return true }
            if ["0","NO","No","no","FALSE","False","false"].contains(string) { return false }
        case .number(_):
            if let int = impl.unwrapFixedWidthInteger(from: value, as: Int.self) {
                if int == 1 {
                    return true
                } else if int == 0 {
                    return false
                }
            }
        default:
            break
        }
        return nil
    }
}


/// String 类型转换：数字→字符串转换
///
/// WHAT: 将数字类型转为字符串
/// HOW: 直接转换或通过 unwrapFixedWidthInteger/unwrapFloatingPoint
/// WHY: 处理后端返回数字但前端需要字符串的场景（如 ID 字段）
extension String: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> String? {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            if let int = impl.unwrapFixedWidthInteger(from: value, as: Int.self) {
                return "\(int)"
            } else if let double = impl.unwrapFloatingPoint(from: value, as: Double.self) {
                return "\(double)"
            }
            return number
        default:
            break
        }
        return nil
    }
}


/// Int 类型转换：调用通用整数转换
///
/// WHAT: 将字符串/浮点数转为整数
/// HOW: 委托给 _fixedWidthInteger 辅助函数
/// WHY: 处理后端返回字符串格式的数字
extension Int: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Int? {
        return _fixedWidthInteger(from: value)
    }
}

extension Int8: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Int8? {
        return _fixedWidthInteger(from: value)
    }
}

extension Int16: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Int16? {
        return _fixedWidthInteger(from: value)
    }
}


extension Int32: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Int32? {
        return _fixedWidthInteger(from: value)
    }
}

extension Int64: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Int64? {
        return _fixedWidthInteger(from: value)
    }
}

extension UInt: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> UInt? {
        return _fixedWidthInteger(from: value)
    }
}

extension UInt8: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> UInt8? {
        return _fixedWidthInteger(from: value)
    }
}

extension UInt16: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> UInt16? {
        return _fixedWidthInteger(from: value)
    }
}


extension UInt32: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> UInt32? {
        return _fixedWidthInteger(from: value)
    }
}

extension UInt64: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> UInt64? {
        return _fixedWidthInteger(from: value)
    }
}


/// Float 类型转换：调用通用浮点数转换
///
/// WHAT: 将字符串/数字转为 Float
/// HOW: 委托给 _floatingPoint 辅助函数
/// WHY: 处理后端返回字符串格式的浮点数
extension Float: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Float? {
        _floatingPoint(from: value)
    }
}


/// Double 类型转换：调用通用浮点数转换
///
/// WHAT: 将字符串/数字转为 Double
/// HOW: 委托给 _floatingPoint 辅助函数
/// WHY: 处理后端返回字符串格式的浮点数
extension Double: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> Double? {
        _floatingPoint(from: value)
    }
}


/// CGFloat 类型转换：通过 Double 中转
///
/// WHAT: 将字符串/数字转为 CGFloat
/// HOW: 先转为 Double，再转为 CGFloat
/// WHY: 兼容 UIKit/CoreGraphics 的 CGFloat 类型
extension CGFloat: TypeTransformable {
    static func transformValue(from value: JSONValue, impl: JSONDecoderImpl) -> CGFloat? {
        if let temp: Double = _floatingPoint(from: value) {
            return CGFloat(temp)
        }
        return nil
    }
}


/// 通用浮点数转换：字符串/数字→浮点数
///
/// WHAT: 将字符串或数字转为浮点数类型
/// HOW: 使用 LosslessStringConvertible 的初始化器
/// WHY: 统一处理 Float/Double/CGFloat 的转换逻辑
private func _floatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>(from value: JSONValue) -> T? {
    switch value {
    case .string(let string):
        return T(string)
    case .number(let number):
        return T(number)
    default:
        break
    }
    return nil
}


/// 通用整数转换：字符串/浮点数→整数
///
/// WHAT: 将字符串或浮点数转为整数类型
/// HOW: 尝试直接转换，失败则通过浮点数中转
/// WHY: 统一处理所有 Int/UInt 家族的转换逻辑
private func _fixedWidthInteger<T: FixedWidthInteger>(from value: JSONValue) -> T? {
    switch value {
    case .string(let string):
        if let integer = T(string) {
            return integer
        } else if let float = Double(string) {
            return _convertFloatToInteger(float)
        }
    case .number(let number):
        if let integer = T(number) {
            return integer
        } else if let float = Double(number) {
            return _convertFloatToInteger(float)
        }
    default:
        break
    }
    return nil
}

/// 统一的浮点数转整数方法（包含范围检查和转换策略）
private func _convertFloatToInteger<T: FixedWidthInteger>(_ float: Double) -> T? {
    // 前置检查：确保数值在目标类型范围内
    guard float.isFinite,
          float >= Double(T.min),
          float <= Double(T.max) else {
        return nil
    }

    // 应用转换策略：strict（严格）、truncate（截断）、rounded（四舍五入）
    switch SmartCodableOptions.numberStrategy {
    case .strict:
        return T(exactly: float)
    case .truncate:
        return T(float)
    case .rounded:
        return T(float.rounded())
    }
}
