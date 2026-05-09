//
//  JSONDecoderImpl+SingleValueContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/17.
//

import Foundation

/** 进入Single的场景
 单容器的解析
 struct Model: SmartCodableX {
     var models: [String] = ["one"]
 }
 */


/// 单值容器：处理标量值解码（Int/Float/Double/String/Bool/Date/Data/URL 等）
///
/// WHAT：从单个 JSONValue 提取指定类型的值
/// HOW：直接从 JSONValue 按类型提取，数值使用 unwrapFloatingPoint/unwrapFixedWidthInteger
/// WHY：与 KeyedContainer 不同，单值容器的回退在调用方处理，这里只负责直接解码
extension JSONDecoderImpl {
    struct SingleValueContainer: SingleValueDecodingContainer {
        let impl: JSONDecoderImpl
        let value: JSONValue
        let codingPath: [CodingKey]

        init(impl: JSONDecoderImpl, codingPath: [CodingKey], json: JSONValue) {
            self.impl = impl
            self.codingPath = codingPath
            self.value = json
        }

        /// 检查值是否为 JSON null
        func decodeNil() -> Bool {
            self.value == .null
        }
    }
}

extension JSONDecoderImpl.SingleValueContainer {
    /// 解码布尔值：直接提取或通过 Patcher 兼容转换
    func decode(_: Bool.Type) throws -> Bool {
        guard case .bool(let bool) = self.value else {
            if let trans = Patcher<Bool>.convertToType(from: value, impl: impl) {
                return trans
            }
            throw self.impl.createTypeMismatchError(type: Bool.self, value: self.value)
        }

        return bool
    }

    /// 解码字符串：直接提取或通过 Patcher 兼容转换
    func decode(_: String.Type) throws -> String {
        guard case .string(let string) = self.value else {
            if let trans = Patcher<String>.convertToType(from: value, impl: impl) {
                return trans
            }
            throw self.impl.createTypeMismatchError(type: String.self, value: self.value)
        }
        return string
    }

    /// 浮点数解码：委托给 decodeFloatingPoint
    func decode(_: Double.Type) throws -> Double {
        try decodeFloatingPoint()
    }

    /// 浮点数解码：委托给 decodeFloatingPoint
    func decode(_: Float.Type) throws -> Float {
        try decodeFloatingPoint()
    }

    /// 整数解码：委托给 decodeFixedWidthInteger
    func decode(_: Int.Type) throws -> Int {
        try decodeFixedWidthInteger()
    }

    func decode(_: Int8.Type) throws -> Int8 {
        try decodeFixedWidthInteger()
    }

    func decode(_: Int16.Type) throws -> Int16 {
        try decodeFixedWidthInteger()
    }

    func decode(_: Int32.Type) throws -> Int32 {
        try decodeFixedWidthInteger()
    }

    func decode(_: Int64.Type) throws -> Int64 {
        try decodeFixedWidthInteger()
    }

    func decode(_: UInt.Type) throws -> UInt {
        try decodeFixedWidthInteger()
    }

    func decode(_: UInt8.Type) throws -> UInt8 {
        try decodeFixedWidthInteger()
    }

    func decode(_: UInt16.Type) throws -> UInt16 {
        try decodeFixedWidthInteger()
    }

    func decode(_: UInt32.Type) throws -> UInt32 {
        try decodeFixedWidthInteger()
    }

    func decode(_: UInt64.Type) throws -> UInt64 {
        try decodeFixedWidthInteger()
    }

    /// 通用 Decodable 类型解码：委托给 impl.unwrap
    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        try self.impl.unwrap(as: type)
    }

    /// 定宽整数解码：直接提取 → Patcher 兼容转换 → 抛出错误
    /// 与 KeyedContainer 不同，单值容器不处理 DecodingCache 回退
    @inline(__always) private func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {

        if let decoded = impl.unwrapFixedWidthInteger(from: self.value, as: T.self) {
            return decoded
        }
        if let trnas = Patcher<T>.convertToType(from: value, impl: impl) {
            return trnas
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "Parsed JSON number does not fit in \(T.self)."))
        }
    }

    /// 浮点数解码：直接提取 → Patcher 兼容转换 → 抛出错误
    /// 与 KeyedContainer 不同，单值容器不处理 DecodingCache 回退
    @inline(__always) private func decodeFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>() throws -> T {

        if let decoded = impl.unwrapFloatingPoint(from: value, as: T.self) {
            return decoded
        }
        if let trnas = Patcher<T>.convertToType(from: value, impl: impl) {
            return trnas
        } else {
            throw DecodingError.typeMismatch(T.self, .init(
                codingPath: codingPath,
                debugDescription: "Expected to decode \(T.self) but found \(value.debugDataTypeDescription) instead."
            ))
        }
    }
}


