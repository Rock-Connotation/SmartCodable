//
//  JSONSingleValueEncodingContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation

/// 单值编码容器：实现 SingleValueEncodingContainer，处理标量值到 JSON 的编码
/// 使用场景：编码包装类型（如 Optional、@SmartFlat）、枚举关联值、根值
/// 约束：只能编码一个值，多次编码会触发 precondition 失败
struct JSONSingleValueEncodingContainer: SingleValueEncodingContainer, _SpecialTreatmentEncoder {
    /// 编码器实现，持有全局配置
    let impl: JSONEncoderImpl
    /// 编码路径，用于错误定位
    let codingPath: [CodingKey]

    private var firstValueWritten: Bool = false
    /// 暴露编码选项
    internal var options: SmartJSONEncoder._Options {
        return self.impl.options
    }

    init(impl: JSONEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.codingPath = codingPath
    }

    /// 编码 nil 值
    mutating func encodeNil() throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .null
    }

    /// 编码布尔值
    mutating func encode(_ value: Bool) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .bool(value)
    }

    /// 编码各种有符号整数类型（Int/Int8/Int16/Int32/Int64）
    mutating func encode(_ value: Int) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: Int64) throws {
        try encodeFixedWidthInteger(value)
    }

    /// 编码各种无符号整数类型（UInt/UInt8/UInt16/UInt32/UInt64）
    mutating func encode(_ value: UInt) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt8) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt16) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt32) throws {
        try encodeFixedWidthInteger(value)
    }

    mutating func encode(_ value: UInt64) throws {
        try encodeFixedWidthInteger(value)
    }

    /// 编码浮点数类型（Float/Double）
    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
    }

    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    /// 编码字符串
    mutating func encode(_ value: String) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .string(value)
    }

    /// 编码任意 Encodable 类型（包括 Date/Data/URL 等特殊类型）
    mutating func encode<T: Encodable>(_ value: T) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = try self.wrapEncodable(value, for: nil)
    }

    /// 验证是否可以编码新值：单值容器只能编码一次
    func preconditionCanEncodeNewValue() {
        precondition(self.impl.singleValue == nil, "Attempt to encode value through single value container when previously value already encoded.")
    }
}

/// 私有编码方法：处理定宽整数和浮点数的编码
extension JSONSingleValueEncodingContainer {
    /// 编码定宽整数：转换为字符串形式的 JSON number
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N) throws {
        self.preconditionCanEncodeNewValue()
        self.impl.singleValue = .number(value.description)
    }

    /// 编码浮点数：通过 wrapFloat 处理特殊值（NaN/Infinity）
    @inline(__always) private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(_ float: F) throws {
        self.preconditionCanEncodeNewValue()
        let value = try self.wrapFloat(float, for: nil)
        self.impl.singleValue = value
    }
}
