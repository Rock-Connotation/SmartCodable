//
//  JSONUnkeyedEncodingContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation
/// 无键编码容器：实现 UnkeyedEncodingContainer，处理数组到 JSON 的编码
/// 核心职责：将 Swift 数组的各个元素顺序编码为 JSON 数组
/// 关键特性：支持嵌套容器、计数追踪、通过 JSONFuture 延迟写入
struct JSONUnkeyedEncodingContainer: UnkeyedEncodingContainer, _SpecialTreatmentEncoder {
    /// 编码器实现，持有全局配置
    let impl: JSONEncoderImpl
    /// JSON 数组引用，通过 JSONFuture 延迟写入
    let array: JSONFuture.RefArray
    /// 编码路径，用于错误定位和值转换器的键查找
    let codingPath: [CodingKey]

    /// 当前已编码的元素数量，用于追踪编码位置
    var count: Int {
        self.array.array.count
    }
    private var firstValueWritten: Bool = false
    /// 暴露编码选项
    internal var options: SmartJSONEncoder._Options {
        return self.impl.options
    }

    /// 根容器初始化：直接使用编码器的根数组
    init(impl: JSONEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = impl.array!
        self.codingPath = codingPath
    }

    /// 嵌套容器初始化：使用指定的 JSON 数组引用
    init(impl: JSONEncoderImpl, array: JSONFuture.RefArray, codingPath: [CodingKey]) {
        self.impl = impl
        self.array = array
        self.codingPath = codingPath
    }

    /// 编码 nil 值
    mutating func encodeNil() throws {
        self.array.append(.null)
    }

    /// 编码布尔值
    mutating func encode(_ value: Bool) throws {
        self.array.append(.bool(value))
    }

    /// 编码字符串
    mutating func encode(_ value: String) throws {
        self.array.append(.string(value))
    }

    /// 编码双精度浮点数
    mutating func encode(_ value: Double) throws {
        try encodeFloatingPoint(value)
    }

    /// 编码单精度浮点数
    mutating func encode(_ value: Float) throws {
        try encodeFloatingPoint(value)
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

    /// 编码任意 Encodable 类型（包括嵌套对象、数组、字典等）
    /// - Note: 使用当前 count 作为虚拟键，用于错误追踪和转换器查找
    mutating func encode<T>(_ value: T) throws where T: Encodable {
        let key = _JSONKey(stringValue: "Index \(self.count)", intValue: self.count)
        let encoded = try self.wrapEncodable(value, for: key)
        self.array.append(encoded ?? .object([:]))
    }

    /// 创建嵌套的键值编码容器（用于数组中的嵌套对象）
    /// 流程：更新路径 → 创建新的 JSON 对象引用 → 返回容器
    /// - Parameter _: 嵌套键的类型
    /// - Returns: 嵌套对象的编码容器
    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) ->
        KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let newPath = self.codingPath + [_JSONKey(index: self.count)]
        let object = self.array.appendObject()
        let nestedContainer = JSONKeyedEncodingContainer<NestedKey>(impl: impl, object: object, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    /// 创建嵌套的无键编码容器（用于数组中的嵌套数组）
    /// - Returns: 嵌套数组的编码容器
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let newPath = self.codingPath + [_JSONKey(index: self.count)]
        let array = self.array.appendArray()
        let nestedContainer = JSONUnkeyedEncodingContainer(impl: impl, array: array, codingPath: newPath)
        return nestedContainer
    }

    /// 获取父类编码器（用于 super 键，常见于继承场景）
    /// - Returns: 编码器实例，会追加到数组末尾
    mutating func superEncoder() -> Encoder {
        let encoder = self.getEncoder(for: _JSONKey(index: self.count))
        self.array.append(encoder)
        return encoder
    }
}

/// 私有编码方法：处理定宽整数和浮点数的编码
extension JSONUnkeyedEncodingContainer {
    /// 编码定宽整数：转换为字符串形式的 JSON number
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N) throws {
        self.array.append(.number(value.description))
    }

    /// 编码浮点数：通过 wrapFloat 处理特殊值（NaN/Infinity）
    @inline(__always) private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(_ float: F) throws {
        let value = try self.wrapFloat(float, for: _JSONKey(index: self.count))
        self.array.append(value)
    }
}
