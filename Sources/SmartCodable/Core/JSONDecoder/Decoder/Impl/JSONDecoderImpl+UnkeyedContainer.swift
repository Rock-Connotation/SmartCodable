//
//  JSONDecoderImpl+UnkeyedContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/17.
//

import Foundation

/// 无键容器：处理数组解码
///
/// WHAT：遍历 JSON 数组并为每个元素创建新的解码器
/// HOW：通过 currentIndex 追踪当前位置，解码时创建新的 JSONDecoderImpl 递归处理
/// WHY：数组元素类型可能各不相同，需要为每个元素独立解码
extension JSONDecoderImpl {
    struct UnkeyedContainer: UnkeyedDecodingContainer {
        let impl: JSONDecoderImpl
        let codingPath: [CodingKey]
        let array: [JSONValue]

        var count: Int? { self.array.count }
        var isAtEnd: Bool { self.currentIndex >= (self.count ?? 0) }
        var currentIndex = 0

        init(impl: JSONDecoderImpl, codingPath: [CodingKey], array: [JSONValue]) {
            self.impl = impl
            self.codingPath = codingPath
            self.array = array
        }

        /// 解码 null 值：当前元素为 null 时返回 true 并前进索引
        mutating func decodeNil() throws -> Bool {
            if try self.getNextValue(ofType: Never.self) == .null {
                self.currentIndex += 1
                return true
            }

            // The protocol states:
            //   If the value is not null, does not increment currentIndex.
            return false
        }

        /// 创建嵌套的键值容器（用于处理数组中的对象元素）
        mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws
            -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            let decoder = decoderForNextElement(ofType: KeyedDecodingContainer<NestedKey>.self)
            let container = try decoder.container(keyedBy: type)

            self.currentIndex += 1
            return container
        }

        /// 创建嵌套的无键容器（用于处理数组中的数组元素）
        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let decoder = decoderForNextElement(ofType: UnkeyedDecodingContainer.self)
            let container = try decoder.unkeyedContainer()

            self.currentIndex += 1
            return container
        }

        /// 获取父类解码器（用于继承场景）
        mutating func superDecoder() throws -> Decoder {
            let decoder = decoderForNextElement(ofType: Decoder.self)
            self.currentIndex += 1
            return decoder
        }

        /// 为下一个数组元素创建新的解码器
        /// 每个数组元素都需要独立的解码器，因为它们的类型和路径不同
        private mutating func decoderForNextElement<T>(ofType: T.Type) -> JSONDecoderImpl {
            var value: JSONValue
            do {
                value = try getNextValue(ofType: T.self)
            } catch {
                value = JSONValue.array([])
            }

            let newPath = self.codingPath + [_JSONKey(index: self.currentIndex)]

            return JSONDecoderImpl(
                userInfo: self.impl.userInfo,
                from: value,
                codingPath: newPath,
                options: self.impl.options
            )
        }
    }
}


// Because UnkeyedDecodingContainer itself is not directly associated with a particular model property,
// but is used to parse unlabeled sequences,
// it does not automatically select a decoding method for a particular type.
// Instead, it tries to use generic decoding methods so that it can handle values of various types.
// Specific types of decode methods, the use of scenarios are relatively few,
// `let first = try unkeyedContainer.decode(Int.self) '.

/// 无键容器的类型特定解码方法
///
/// 使用场景：当数组元素类型明确时使用，如 `let first = try unkeyedContainer.decode(Int.self)`
/// 大多数场景使用通用的 decode<T>() 方法
extension JSONDecoderImpl.UnkeyedContainer {
    /// 解码布尔值：直接匹配或强制解码（兼容回退）
    mutating func decode(_ type: Bool.Type) throws -> Bool {
        guard let value = try? self.getNextValue(ofType: Bool.self) else {
            return try forceDecode()
        }
        guard case .bool(let bool) = value else {
            return try forceDecode()
        }
        self.currentIndex += 1
        return bool
    }

    /// 解码字符串：直接匹配或强制解码（兼容回退）
    mutating func decode(_ type: String.Type) throws -> String {
        guard let value = try? self.getNextValue(ofType: Bool.self) else {
            return try forceDecode()
        }
        guard case .string(let string) = value else {
            return try forceDecode()
        }
        self.currentIndex += 1
        return string
    }

    mutating func decode(_: Double.Type) throws -> Double {
        try decodeFloatingPoint()
    }

    mutating func decode(_: Float.Type) throws -> Float {
        try decodeFloatingPoint()
    }

    mutating func decode(_: Int.Type) throws -> Int {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: Int8.Type) throws -> Int8 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: Int16.Type) throws -> Int16 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: Int32.Type) throws -> Int32 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: Int64.Type) throws -> Int64 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: UInt.Type) throws -> UInt {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: UInt8.Type) throws -> UInt8 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: UInt16.Type) throws -> UInt16 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: UInt32.Type) throws -> UInt32 {
        try decodeFixedWidthInteger()
    }

    mutating func decode(_: UInt64.Type) throws -> UInt64 {
        try decodeFixedWidthInteger()
    }

    /// 通用 Decodable 类型解码：创建新解码器并递归处理
    ///
    /// 关键决策：顶层数组（codingPath 为空）允许兼容回退，嵌套数组直接抛出错误
    /// WHY：顶层数组可能是模型的根，需要支持缺失字段的回退；嵌套数组类型必须严格匹配
    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {

        // If it is a basic data type,
        // a new decoder is still created for parsing.
        // If type is of type Int, then SingleContainer is created.
        let newDecoder = decoderForNextElement(ofType: type)

        // Because of the requirement that the index not be incremented unless
        // decoding the desired result type succeeds, it can not be a tail call.
        // Hopefully the compiler still optimizes well enough that the result
        // doesn't get copied around.
        if codingPath.isEmpty {
            // 顶层数组：解码失败时尝试兼容回退
            guard let result = try? newDecoder.unwrap(as: type) else {
                let decoded: T = try forceDecode()
                return didFinishMapping(decoded)
            }
            self.currentIndex += 1
            return didFinishMapping(result)
        } else {
            // 嵌套数组：不允许兼容回退，直接抛出错误让 KeyedContainer 处理
            let result = try newDecoder.unwrap(as: type)
            self.currentIndex += 1
            return didFinishMapping(result)
        }
    }

    /// 定宽整数解码：直接提取 → 失败则强制解码
    @inline(__always) private mutating func decodeFixedWidthInteger<T: FixedWidthInteger>() throws -> T {
        guard let value = try? self.getNextValue(ofType: T.self) else {
            return try forceDecode()
        }

        let key = _JSONKey(index: self.currentIndex)
        guard let result = self.impl.unwrapFixedWidthInteger(from: value, for: key, as: T.self) else {
            return try forceDecode()
        }
        self.currentIndex += 1
        return result
    }

    /// 浮点数解码：直接提取 → 失败则强制解码
    @inline(__always) private mutating func decodeFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>() throws -> T {
        guard let value = try? self.getNextValue(ofType: T.self) else {
            return try forceDecode()
        }

        let key = _JSONKey(index: self.currentIndex)
        guard let result = self.impl.unwrapFloatingPoint(from: value, for: key, as: T.self) else {
            return try forceDecode()
        }
        self.currentIndex += 1
        return result
    }

    /// 强制解码：当直接解码失败时的兼容回退机制
    ///
    /// 处理流程：
    /// 1. 元素不存在 → 从 DecodingCache 获取初始值
    /// 2. 元素存在 → 记录日志 → 尝试 Patcher 类型转换
    /// 3. 转换失败 → 从 DecodingCache 获取初始值
    fileprivate mutating func forceDecode<T>() throws -> T {

        let key = _JSONKey(index: currentIndex)

        guard let value = try? self.getNextValue(ofType: T.self) else {
            let decoded: T = try impl.cache.initialValue(forKey: key, codingPath: codingPath)
            SmartSentinel.monitorLog(impl: impl, forKey: key, value: nil, type: T.self)
            self.currentIndex += 1
            return decoded
        }

        SmartSentinel.monitorLog(impl: impl, forKey: key, value: value, type: T.self)


        if let decoded = Patcher<T>.convertToType(from: value, impl: impl) {
            self.currentIndex += 1
            return decoded
        } else {
            let decoded: T = try impl.cache.initialValue(forKey: key, codingPath: codingPath)
            self.currentIndex += 1
            return decoded
        }
    }
}

extension JSONDecoderImpl.UnkeyedContainer {

    /// 可选布尔值解码：直接匹配或可选解码
    mutating func decodeIfPresent(_ type: Bool.Type) throws -> Bool? {
        guard let value = try? self.getNextValue(ofType: Bool.self) else {
            return optionalDecode()
        }
        guard case .bool(let bool) = value else {
            return optionalDecode()
        }
        self.currentIndex += 1
        return bool
    }


    /// 可选字符串解码：直接匹配或可选解码
    mutating func decodeIfPresent(_ type: String.Type) throws -> String? {
        self.currentIndex += 1
        guard let value = try? self.getNextValue(ofType: String.self) else {
            return optionalDecode()
        }
        guard case .string(let string) = value else {
            return optionalDecode()
        }
        self.currentIndex += 1
        return string
    }

    /// 可选浮点数解码：委托给 decodeIfPresentFloatingPoint
    mutating func decodeIfPresent(_ type: Double.Type) throws -> Double? {
        return decodeIfPresentFloatingPoint()
    }

    /// 可选浮点数解码：委托给 decodeIfPresentFloatingPoint
    mutating func decodeIfPresent(_ type: Float.Type) throws -> Float? {
        return decodeIfPresentFloatingPoint()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: Int.Type) throws -> Int? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: Int8.Type) throws -> Int8? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: Int16.Type) throws -> Int16? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: Int32.Type) throws -> Int32? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: Int64.Type) throws -> Int64? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: UInt.Type) throws -> UInt? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: UInt8.Type) throws -> UInt8? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: UInt16.Type) throws -> UInt16? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: UInt32.Type) throws -> UInt32? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选整数解码：委托给 decodeIfPresentFixedWidthInteger
    mutating func decodeIfPresent(_ type: UInt64.Type) throws -> UInt64? {
        return decodeIfPresentFixedWidthInteger()
    }

    /// 可选 Decodable 类型解码：尝试解码或返回 nil
    ///   is not convertible to the requested type.
    mutating func decodeIfPresent<T>(_ type: T.Type) throws -> T? where T : Decodable {
        let newDecoder = decoderForNextElement(ofType: type)
        if let decoded = try? newDecoder.unwrap(as: type) {
            self.currentIndex += 1
            return didFinishMapping(decoded)
        } else if let decoded: T = optionalDecode() {
            self.currentIndex += 1
            return didFinishMapping(decoded)
        } else {
            self.currentIndex += 1
            return nil
        }
    }

    /// 可选定宽整数解码：直接提取 → 失败则可选解码
    @inline(__always) private mutating func decodeIfPresentFixedWidthInteger<T: FixedWidthInteger>() -> T? {
        guard let value = try? self.getNextValue(ofType: T.self) else {
            return optionalDecode()
        }

        let key = _JSONKey(index: self.currentIndex)
        guard let result = self.impl.unwrapFixedWidthInteger(from: value, for: key, as: T.self) else {
            return optionalDecode()
        }
        self.currentIndex += 1
        return result
    }

    /// 可选浮点数解码：直接提取 → 失败则可选解码
    @inline(__always) private mutating func decodeIfPresentFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>() -> T?  {
        guard let value = try? self.getNextValue(ofType: T.self) else {
            return optionalDecode()
        }

        let key = _JSONKey(index: self.currentIndex)
        guard let result = self.impl.unwrapFloatingPoint(from: value, for: key, as: T.self) else {
            return optionalDecode()
        }
        self.currentIndex += 1
        return result
    }

    /// 可选解码：当解码失败时返回 nil（而非初始值）
    ///
    /// 与 forceDecode 的区别：
    /// - forceDecode：解码失败时返回 DecodingCache 的初始值
    /// - optionalDecode：解码失败时返回 nil
    ///
    /// WHY：可选类型语义上应该返回 nil，而不是初始值
    fileprivate mutating func optionalDecode<T>() -> T? {
        guard let value = try? self.getNextValue(ofType: T.self) else {
            self.currentIndex += 1
            return nil
        }
        let key = _JSONKey(index: self.currentIndex)
        SmartSentinel.monitorLog(impl: impl, forKey: key, value: value, type: T.self)
        if let decoded = Patcher<T>.convertToType(from: value, impl: impl) {
            self.currentIndex += 1
            return decoded
        } else {
            self.currentIndex += 1
            return nil
        }
    }
}


extension JSONDecoderImpl.UnkeyedContainer {
    /// 完成映射后的回调处理
    ///
    /// WHAT：在解码完成后调用模型的 didFinishMapping() 方法
    /// HOW：检查解码值是否符合 SmartDecodable 协议，符合则调用回调
    /// WHY：允许模型在解码完成后执行自定义逻辑（如数据验证、默认值补全）
    ///
    /// 关键决策：被属性包装器包裹的属性不会直接调用此方法，需要通过 PropertyWrapperable 协议桥接
    // 被属性包装器包裹的，不会调用该方法。Swift的类型系统在运行时无法直接识别出wrappedValue的实际类型.
    fileprivate func didFinishMapping<T>(_ decodeValue: T) -> T {

        // 减少动态派发开销，is 检查是编译时静态行为，比 as? 动态转换更高效。
        guard T.self is SmartDecodable.Type else { return decodeValue }

        if var value = decodeValue as? SmartDecodable {
            value.didFinishMapping()
            if let temp = value as? T { return temp }
        } else if let value = decodeValue as? (any PropertyWrapperable) {
            if let temp = value.wrappedValueDidFinishMapping() as? T {
                return temp
            }
        }
        return decodeValue
    }
}


extension JSONDecoderImpl.UnkeyedContainer {
    /// 获取下一个数组元素的值
    ///
    /// WHAT：从数组中取出当前索引位置的元素
    /// HOW：检查 isAtEnd，如果已到末尾则抛出错误，否则返回当前元素
    /// WHY：提供统一的错误消息格式，包含类型和路径信息
    @inline(__always)
    private func getNextValue<T>(ofType: T.Type) throws -> JSONValue {
        guard !self.isAtEnd else {
            var message = "Unkeyed container is at end."

            if T.self == JSONDecoderImpl.UnkeyedContainer.self {
                message = "Cannot get nested unkeyed container -- unkeyed container is at end."
            }
            if T.self == Decoder.self {
                message = "Cannot get superDecoder() -- unkeyed container is at end."
            }

            var path = self.codingPath
            path.append(_JSONKey(index: self.currentIndex))

            throw DecodingError.valueNotFound(
                T.self,
                .init(codingPath: path,
                      debugDescription: message,
                      underlyingError: nil))
        }
        return self.array[self.currentIndex]
    }
}
