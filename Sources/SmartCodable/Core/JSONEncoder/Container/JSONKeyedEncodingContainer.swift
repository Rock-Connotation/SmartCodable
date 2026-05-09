//
//  JSONKeyedEncodingContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/3.
//

import Foundation

/// 键值编码容器：实现 KeyedEncodingContainerProtocol，处理对象字段到 JSON 的编码
/// 核心职责：将 Swift 对象的各个属性按 key 映射为 JSON 对象的键值对
/// 关键特性：支持键映射策略、全局命名策略、值转换器
struct JSONKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol, _SpecialTreatmentEncoder {
    typealias Key = K

    /// 编码器实现，持有全局配置（keyEncodingStrategy、编码缓存等）
    let impl: JSONEncoderImpl
    /// JSON 对象引用，通过 JSONFuture 延迟写入
    let object: JSONFuture.RefObject
    /// 编码路径，用于错误定位和值转换器的键查找
    let codingPath: [CodingKey]

    private var firstValueWritten: Bool = false
    /// 暴露编码选项（键命名策略、值转换器等）
    var options: SmartJSONEncoder._Options {
        return self.impl.options
    }

    /// 根容器初始化：直接使用编码器的根对象
    /// - Parameters:
    ///   - impl: 编码器实现，持有全局配置
    ///   - codingPath: 当前编码路径，用于错误追踪和转换器查找
    init(impl: JSONEncoderImpl, codingPath: [CodingKey]) {
        self.impl = impl
        self.object = impl.object!
        self.codingPath = codingPath
    }

    /// 嵌套容器初始化：使用指定的 JSON 对象引用
    /// - Parameters:
    ///   - impl: 编码器实现，持有全局配置
    ///   - object: 嵌套层的 JSON 对象引用
    ///   - codingPath: 当前编码路径（包含父路径）
    init(impl: JSONEncoderImpl, object: JSONFuture.RefObject, codingPath: [CodingKey]) {
        self.impl = impl
        self.object = object
        self.codingPath = codingPath
    }
    
    /// 创建嵌套的键值编码容器（用于嵌套对象）
    /// 流程：转换键名 → 更新路径 → 创建新的 JSON 对象引用 → 返回容器
    /// - Parameters:
    ///   - _: 嵌套键的类型
    ///   - key: 当前层级的键
    /// - Returns: 嵌套对象的编码容器
    mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Self.Key) ->
        KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey
    {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let object = self.object.setObject(for: convertedKey.stringValue)
        let nestedContainer = JSONKeyedEncodingContainer<NestedKey>(impl: impl, object: object, codingPath: newPath)
        return KeyedEncodingContainer(nestedContainer)
    }

    /// 创建嵌套的无键编码容器（用于嵌套数组）
    /// - Parameter key: 当前层级的键
    /// - Returns: 嵌套数组的编码容器
    mutating func nestedUnkeyedContainer(forKey key: Self.Key) -> UnkeyedEncodingContainer {
        let convertedKey = self._converted(key)
        let newPath = self.codingPath + [convertedKey]
        let array = self.object.setArray(for: convertedKey.stringValue)
        let nestedContainer = JSONUnkeyedEncodingContainer(impl: impl, array: array, codingPath: newPath)
        return nestedContainer
    }

    /// 获取父类编码器（用于 super 键，常见于继承场景）
    /// - Returns: 编码器实例，会写入到 "super" 字段
    mutating func superEncoder() -> Encoder {
        let newEncoder = self.getEncoder(for: _JSONKey.super)
        self.object.set(newEncoder, for: _JSONKey.super.stringValue)
        return newEncoder
    }

    /// 获取指定键的父类编码器
    /// - Parameter key: 存储父类数据的键
    /// - Returns: 编码器实例
    mutating func superEncoder(forKey key: Self.Key) -> Encoder {
        let convertedKey = self._converted(key)
        let newEncoder = self.getEncoder(for: convertedKey)
        self.object.set(newEncoder, for: convertedKey.stringValue)
        return newEncoder
    }
}

/// KeyedEncodingContainerProtocol 协议方法实现
/// 每个方法都先通过 _converted(key) 应用键映射策略，然后委托给私有方法处理
extension JSONKeyedEncodingContainer {
    /// 编码 nil 值
    mutating func encodeNil(forKey key: Self.Key) throws {
        self.object.set(.null, for: self._converted(key).stringValue)
    }

    /// 编码布尔值
    mutating func encode(_ value: Bool, forKey key: Self.Key) throws {
       try encodeBoolPoint(value, key: _converted(key))
    }

    /// 编码字符串
    mutating func encode(_ value: String, forKey key: Self.Key) throws {
        try encodeStringPoint(value, key: _converted(key))
    }

    /// 编码双精度浮点数
    mutating func encode(_ value: Double, forKey key: Self.Key) throws {
        try encodeFloatingPoint(value, key: _converted(key))
    }

    /// 编码单精度浮点数
    mutating func encode(_ value: Float, forKey key: Self.Key) throws {
        try encodeFloatingPoint(value, key: _converted(key))
    }

    /// 编码各种整数类型（Int/Int8/Int16/Int32/Int64）
    mutating func encode(_ value: Int, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: Int8, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: Int16, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: Int32, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: Int64, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    /// 编码各种无符号整数类型（UInt/UInt8/UInt16/UInt32/UInt64）
    mutating func encode(_ value: UInt, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: UInt8, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: UInt16, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: UInt32, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    mutating func encode(_ value: UInt64, forKey key: Self.Key) throws {
        try encodeFixedWidthInteger(value, key: _converted(key))
    }

    /// 编码任意 Encodable 类型（包括嵌套对象、数组、字典等）
    mutating func encode<T>(_ value: T, forKey key: Self.Key) throws where T: Encodable {
        try encodeEncodableCore(value, key: _converted(key))
    }

}


/// 私有编码方法：统一应用值转换器，然后写入 JSON
/// 设计模式：转换器优先策略（如果有转换器，直接使用转换结果；否则走默认编码）
extension JSONKeyedEncodingContainer {

    /// 编码布尔值：先尝试应用转换器，否则直接编码为 JSON bool
    @inline(__always) private mutating func encodeBoolPoint(_ value: Bool, key: CodingKey) throws {
        if let jsonValue = tranform(from: value, with: key, containerPath: codingPath) {
            self.object.set(jsonValue, for: key.stringValue)
        } else {
            self.object.set(.bool(value), for: key.stringValue)
        }
    }

    /// 编码字符串：先尝试应用转换器，否则直接编码为 JSON string
    @inline(__always) private mutating func encodeStringPoint(_ value: String, key: CodingKey) throws {
        if let jsonValue = tranform(from: value, with: key, containerPath: codingPath) {
            self.object.set(jsonValue, for: key.stringValue)
        } else {
            self.object.set(.string(value), for: key.stringValue)
        }
    }

    /// 编码浮点数：先尝试应用转换器，否则通过 wrapFloat 处理特殊值（NaN/Infinity）
    @inline(__always) private mutating func encodeFloatingPoint<F: FloatingPoint & CustomStringConvertible>(_ value: F, key: CodingKey) throws {

        if let jsonValue = tranform(from: value, with: key, containerPath: codingPath) {
            self.object.set(jsonValue, for: key.stringValue)
        } else {
            let value = try self.wrapFloat(value, for: key)
            self.object.set(value, for: key.stringValue)
        }
    }

    /// 编码定宽整数：先尝试应用转换器，否则转换为字符串形式的 JSON number
    @inline(__always) private mutating func encodeFixedWidthInteger<N: FixedWidthInteger>(_ value: N, key: CodingKey) throws {

        if let jsonValue = tranform(from: value, with: key, containerPath: codingPath) {
            self.object.set(jsonValue, for: key.stringValue)
        } else {
            self.object.set(.number(value.description), for: key.stringValue)
        }
    }

    /// 编码 Encodable 类型：先尝试应用转换器，否则递归编码为 JSON 值
    @inline(__always) private mutating func encodeEncodableCore<T: Encodable>(_ value: T, key: CodingKey) throws {
        if let jsonValue = tranform(from: value, with: key, containerPath: codingPath) {
            self.object.set(jsonValue, for: key.stringValue)
        } else {
            if let encoded = try self.wrapEncodable(value, for: key) {
                self.object.set(encoded, for: key.stringValue)
            }
        }
    }

    /// 应用值转换器：根据键和路径查找转换器，执行转换并返回 JSON 值
    /// - Parameters:
    ///   - value: 原始值
    ///   - key: 当前编码键
    ///   - path: 编码路径（用于转换器缓存查找）
    /// - Returns: 转换后的 JSON 值，如果无转换器则返回 nil
    private func tranform(from value: Any, with key: CodingKey, containerPath path: [CodingKey]) -> JSONValue? {
        guard let tranformer = impl.cache.valueTransformer(for: key, in: path) else { return nil }
        let decoded = encodeWithTransformer(tranformer.performer, decodedValue: value)
        return JSONValue.make(decoded)
    }
}


