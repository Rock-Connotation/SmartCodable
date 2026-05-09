//
//  JSONDecoderImpl+KeyedContainer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/17.
//

import Foundation
/// 键值容器：处理 JSON 对象字段的解码（最复杂的容器类型）
///
/// WHAT：提供对 JSON 字典的视图并从中解码值
/// HOW：通过四层韧性解码架构实现：直接解码 → Patcher 兼容转换 → DecodingCache 初始值 → 类型零值
/// WHY：需要处理键名转换、类型兼容、缺失字段回退等复杂场景
/// 键值容器：处理 JSON 对象字段的解码（最复杂的容器类型）
///
/// WHAT：提供对 JSON 字典的视图并从中解码值
/// HOW：通过四层韧性解码架构实现：直接解码 → Patcher 兼容转换 → DecodingCache 初始值 → 类型零值
/// WHY：需要处理键名转换、类型兼容、缺失字段回退等复杂场景
extension JSONDecoderImpl {
    struct KeyedContainer<K: CodingKey>: KeyedDecodingContainerProtocol {
        typealias Key = K

        let impl: JSONDecoderImpl
        let codingPath: [CodingKey]
        let dictionary: [String: JSONValue]

        /// 初始化键值容器，执行两层键名转换
        /// 第一层：应用全局 keyDecodingStrategy（snake_case → camelCase 等）
        /// 第二层：应用 KeysMapper 自定义映射规则
        /// 初始化键值容器，执行两层键名转换
        /// 第一层：应用全局 keyDecodingStrategy（snake_case → camelCase 等）
        /// 第二层：应用 KeysMapper 自定义映射规则
        init(impl: JSONDecoderImpl, codingPath: [CodingKey], dictionary: [String: JSONValue]) {

            self.codingPath = codingPath

            self.dictionary = _convertDictionary(dictionary, impl: impl)
            // 字典的转换不影响结构，只是给当前容器对应的数据添加新字段
            // 不需要修改 impl
            self.impl = impl
        }

        /// 返回容器中所有存在的键（基于转换后的字典）
        var allKeys: [K] {
            self.dictionary.keys.compactMap { K(stringValue: $0) }
        }

        /// 检查指定键是否存在于字典中（使用转换后的键名）
        /// 注意：使用的是 _convertDictionary 转换后的键名，而不是原始 JSON 键名
        func contains(_ key: K) -> Bool {
            if let _ = dictionary[key.stringValue] {
                return true
            }
            return false
        }
        
        /// 检查指定键的值是否为 null
        func decodeNil(forKey key: K) throws -> Bool {
            guard let value = getValue(forKey: key) else {
                throw DecodingError._keyNotFound(key: key, codingPath: self.codingPath)
            }
            return value == .null
        }

        /// 创建嵌套的键值容器（用于处理嵌套对象）
        func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws
        -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey
        {
            try decoderForKey(key).container(keyedBy: type)
        }

        /// 创建嵌套的无键容器（用于处理嵌套数组）
        func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
            try decoderForKey(key).unkeyedContainer()
        }

        /// 获取父类的解码器（用于继承场景）
        func superDecoder() throws -> Decoder {
            return decoderForKeyNoThrow(_JSONKey.super)
        }

        /// 为指定键获取父类解码器
        func superDecoder(forKey key: K) throws -> Decoder {
            return decoderForKeyNoThrow(key)
        }

        /// 为嵌套模型创建新的解码器（不继承父级 cache）
        ///
        /// 使用场景：解码 SmartCodable 模型时，需要独立的 cache 以避免属性初始值污染
        /// 关键决策：每个嵌套模型都有独立的解码状态，不与父级共享 cache
        private func decoderForKey<LocalKey: CodingKey>(_ key: LocalKey) throws -> JSONDecoderImpl {

            guard let value = getValue(forKey: key) else {
                throw DecodingError._keyNotFound(key: key, codingPath: self.codingPath)
            }

            var newPath = self.codingPath
            newPath.append(key)

            return JSONDecoderImpl(userInfo: self.impl.userInfo, from: value, codingPath: newPath, options: self.impl.options)
        }

        /// 为普通属性创建解码器（继承父级 cache）
        ///
        /// 使用场景：解码普通属性（非 SmartCodable 模型）时，继承父级 cache 以支持初始值回退
        /// 关键决策：只有非 SmartDecodable 类型才继承 cache，避免嵌套模型的属性值冲突
        private func decoderForKeyCompatibleForJson<LocalKey: CodingKey, T>(_ key: LocalKey, type: T.Type) throws -> JSONDecoderImpl {
            guard let value = getValue(forKey: key) else {
                throw DecodingError._keyNotFound(key: key, codingPath: self.codingPath)
            }
            var newPath = self.codingPath
            newPath.append(key)

            var newImpl = JSONDecoderImpl(userInfo: self.impl.userInfo, from: value, codingPath: newPath, options: self.impl.options)

            // 如果新解码器不是解析 Model，则继承上一个的 cache
            if !(type is SmartDecodable.Type) {
                newImpl.cache = impl.cache
            }

            return newImpl
        }

        /// 创建不抛出异常的解码器（用于 superDecoder 等容错场景）
        private func decoderForKeyNoThrow<LocalKey: CodingKey>(_ key: LocalKey) -> JSONDecoderImpl {
            let value: JSONValue = getValue(forKey: key) ?? .null
            var newPath = self.codingPath
            newPath.append(key)

            return JSONDecoderImpl(
                userInfo: self.impl.userInfo,
                from: value,
                codingPath: newPath,
                options: self.impl.options
            )
        }

        /// 从字典中获取指定键的值（使用转换后的键名）
        @inline(__always) private func getValue<LocalKey: CodingKey>(forKey key: LocalKey) -> JSONValue? {
            guard let value = dictionary[key.stringValue] else { return nil }
            return value
        }
    }
}


extension JSONDecoderImpl.KeyedContainer {
    func decode(_ type: Bool.Type, forKey key: K) throws -> Bool {
        try _decodeBoolValue(key: key)
    }
    
    func decode(_ type: String.Type, forKey key: K) throws -> String {
        try _decodeStringValue(key: key)
    }
    
    func decode(_: Double.Type, forKey key: K) throws -> Double {
        try _decodeFloatingPoint(key: key)
    }
    
    func decode(_: Float.Type, forKey key: K) throws -> Float {
        try _decodeFloatingPoint(key: key)
    }
    
    func decode(_: Int.Type, forKey key: K) throws -> Int {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: Int8.Type, forKey key: K) throws -> Int8 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: Int16.Type, forKey key: K) throws -> Int16 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: Int32.Type, forKey key: K) throws -> Int32 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: Int64.Type, forKey key: K) throws -> Int64 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: UInt.Type, forKey key: K) throws -> UInt {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: UInt8.Type, forKey key: K) throws -> UInt8 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: UInt16.Type, forKey key: K) throws -> UInt16 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: UInt32.Type, forKey key: K) throws -> UInt32 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode(_: UInt64.Type, forKey key: K) throws -> UInt64 {
        try _decodeFixedWidthInteger(key: key)
    }
    
    func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T: Decodable {
        try _decodeDecodable(type, forKey: key)
    }
}


extension JSONDecoderImpl.KeyedContainer {
    
    func decodeIfPresent(_ type: Bool.Type, forKey key: K) throws -> Bool? {
        _decodeBoolValueIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: String.Type, forKey key: K) throws -> String? {
        _decodeStringValueIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Float.Type, forKey key: K) throws -> Float? {
        _decodeFloatingPointIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Double.Type, forKey key: K) throws -> Double? {
        _decodeFloatingPointIfPresent(key: key)
    }
    
    
    func decodeIfPresent(_ type: Int.Type, forKey key: K) throws -> Int? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Int8.Type, forKey key: K) throws -> Int8? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Int16.Type, forKey key: K) throws -> Int16? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Int32.Type, forKey key: K) throws -> Int32? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: Int64.Type, forKey key: K) throws -> Int64? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: UInt.Type, forKey key: K) throws -> UInt? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: UInt8.Type, forKey key: K) throws -> UInt8? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: UInt16.Type, forKey key: K) throws -> UInt16? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: UInt32.Type, forKey key: K) throws -> UInt32? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent(_ type: UInt64.Type, forKey key: K) throws -> UInt64? {
        _decodeFixedWidthIntegerIfPresent(key: key)
    }
    
    func decodeIfPresent<T>(_ type: T.Type, forKey key: K) throws -> T? where T: Decodable {
        _decodeDecodableIfPresent(type, forKey: key)
    }
}


/// 四层韧性解码架构的核心实现
///
/// WHAT：提供兼容性解码回退机制
/// HOW：直接解码失败 → Patcher 兼容转换 → DecodingCache 初始值 → 返回 nil
/// WHY：确保在字段缺失或类型不匹配时能够优雅降级，避免解析崩溃
extension JSONDecoderImpl.KeyedContainer {

    /// 兼容性解码的核心方法：衔接正常解码和回退的枢纽
    ///
    /// 处理流程：
    /// 1. 字段不存在 → 记录日志 → 返回初始值（来自 DecodingCache）
    /// 2. 字段存在 → 记录日志 → 尝试 Patcher 类型转换
    /// 3. 转换失败 → 返回初始值（来自 DecodingCache）
    ///
    /// 关键决策：needConvert 控制是否应用 Patcher，某些场景（如 @SmartFlat）需要跳过转换
    fileprivate func _compatibleDecode<T>(forKey key: Key, logIfKeyMissing: Bool = true, needConvert: Bool = true) -> T? {

        guard let value = getValue(forKey: key) else {
            if logIfKeyMissing {
                SmartSentinel.monitorLog(impl: impl, forKey: key, value: nil, type: T.self)
            }
            return impl.cache.initialValueIfPresent(forKey: key, codingPath: codingPath)
        }

        SmartSentinel.monitorLog(impl: impl, forKey: key, value: value, type: T.self)

        if needConvert {
            if let decoded = Patcher<T>.convertToType(from: value, impl: impl) {
                return decoded
            }
        }
        return impl.cache.initialValueIfPresent(forKey: key, codingPath: codingPath)
    }

    /// 完成映射后的回调处理
    ///
    /// WHAT：在解码完成后调用模型的 didFinishMapping() 方法
    /// HOW：检查解码值是否符合 SmartDecodable 协议，符合则调用回调
    /// WHY：允许模型在解码完成后执行自定义逻辑（如数据验证、默认值补全）
    ///
    /// 关键决策：属性包装器不直接符合 SmartDecodable，需要通过 PropertyWrapperable 协议桥接
    fileprivate func didFinishMapping<T>(_ decodeValue: T) -> T {
        // 被属性包装器包裹的属性不符合 SmartDecodable 协议
        // 这里使用 PropertyWrapperable 作为中间层进行处理
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

    /// 使用自定义值转换器进行解码
    ///
    /// WHAT：支持通过 SmartValueTransformer 进行 JSON → 类型的自定义转换
    /// HOW：优先处理属性包装器类型（如 @SmartDate），再处理普通类型
    /// WHY：允许用户为特定类型注册自定义转换逻辑（如日期格式、十六进制颜色等）
    ///
    /// 关键决策：FlatType 类型使用 impl.json 而非 getValue(forKey:)，因为 @SmartFlat 是"扁平化"的
    private func decodeWithTransformer<T>(_ transformer: SmartValueTransformer,
                                          type: T.Type,
                                          key: K) -> T? where T: Decodable {
        // 处理属性包装类型
        if let propertyWrapperType = T.self as? any PropertyWrapperable.Type {
            let value: JSONValue? = (type is FlatType.Type) ? impl.json : getValue(forKey: key)

            if let value = value,
               let decoded = transformer.transformFromJSON(value),
               let wrapperValue = propertyWrapperType.createInstance(with: decoded) as? T {
                return didFinishMapping(wrapperValue)
            }
        }

        // 处理普通类型转换
        if let value = getValue(forKey: key),
           let decoded = transformer.transformFromJSON(value) as? T {
            return didFinishMapping(decoded)
        }
        return nil
    }
}


/// 定宽整数解码（Int、Int8、Int16、Int32、Int64、UInt、UInt8、UInt16、UInt32、UInt64）
///
/// 遵循四层韧性解码架构：
/// 1. 直接解码：impl.unwrapFixedWidthInteger
/// 2. Patcher 兼容转换：_compatibleDecode 中的 Patcher.convertToType
/// 3. DecodingCache 初始值：_compatibleDecode 中的 cache.initialValueIfPresent
/// 4. 类型零值：Patcher.defaultForType
extension JSONDecoderImpl.KeyedContainer {
    /// 可选整数解码（字段可能不存在或为 null）
    @inline(__always) private func _decodeFixedWidthIntegerIfPresent<T: FixedWidthInteger>(key: Self.Key) -> T? {

        guard let decoded: T = _decodeFixedWidthIntegerIfPresentCore(key: key) else {
            return _compatibleDecode(forKey: key, logIfKeyMissing: false)
        }
        return decoded
    }

    /// 必选整数解码（字段必须存在且能解码）
    @inline(__always) private func _decodeFixedWidthInteger<T: FixedWidthInteger>(key: Self.Key) throws -> T {
        if let decoded: T = _decodeFixedWidthIntegerIfPresentCore(key: key) { return decoded }
        if let value: T = _compatibleDecode(forKey: key, logIfKeyMissing: true) {
            return value
        }
        return try Patcher<T>.defaultForType()
    }

    /// 定宽整数解码的核心实现：直接从 JSONValue 提取整数值
    @inline(__always) private func _decodeFixedWidthIntegerIfPresentCore<T: FixedWidthInteger>(key: Self.Key) -> T? {
        guard let value = getValue(forKey: key) else { return nil }
        return impl.unwrapFixedWidthInteger(from: value, for: key, as: T.self)
    }
}


/// 浮点数解码（Float、Double）
///
/// 遵循四层韧性解码架构（同整数）
extension JSONDecoderImpl.KeyedContainer {

    /// 可选浮点数解码
    @inline(__always) private func _decodeFloatingPointIfPresent<T: LosslessStringConvertible & BinaryFloatingPoint>(key: K) -> T? {
        guard let decoded: T = _decodeFloatingPointIfPresentCore(key: key) else {
            return _compatibleDecode(forKey: key, logIfKeyMissing: false)
        }
        return decoded
    }

    /// 必选浮点数解码
    @inline(__always) private func _decodeFloatingPoint<T: LosslessStringConvertible & BinaryFloatingPoint>(key: K) throws -> T {
        if let decoded: T = _decodeFloatingPointIfPresentCore(key: key) { return decoded }
        if let value: T = _compatibleDecode(forKey: key, logIfKeyMissing: true) {
            return value
        }
        return try Patcher<T>.defaultForType()
    }

    /// 浮点数解码的核心实现：直接从 JSONValue 提取浮点数值
    @inline(__always) private func _decodeFloatingPointIfPresentCore<T: LosslessStringConvertible & BinaryFloatingPoint>(key: K) -> T? {
        guard let value = getValue(forKey: key) else { return nil }
        return impl.unwrapFloatingPoint(from: value, for: key, as: T.self)
    }
}


/// 布尔值解码
///
/// 遵循四层韧性解码架构（同整数）
extension JSONDecoderImpl.KeyedContainer {
    /// 可选布尔值解码
    @inline(__always) private func _decodeBoolValueIfPresent(key: K) -> Bool? {
        guard let decoded = _decodeBoolValueIfPresentCore(key: key) else {
            return _compatibleDecode(forKey: key, logIfKeyMissing: false)
        }
        return decoded
    }

    /// 必选布尔值解码
    @inline(__always) private func _decodeBoolValue(key: K) throws -> Bool {
        if let decoded = _decodeBoolValueIfPresentCore(key: key) { return decoded }
        if let value: Bool = _compatibleDecode(forKey: key, logIfKeyMissing: true) {
            return value
        }
        return try Patcher<Bool>.defaultForType()
    }

    /// 布尔值解码的核心实现：直接从 JSONValue 提取布尔值
    @inline(__always) private func _decodeBoolValueIfPresentCore(key: K) -> Bool? {
        guard let value = getValue(forKey: key) else { return nil }
        return impl.unwrapBoolValue(from: value, for: key)
    }
}


/// 字符串解码
///
/// 遵循四层韧性解码架构（同整数）
extension JSONDecoderImpl.KeyedContainer {
    /// 可选字符串解码
    @inline(__always) private func _decodeStringValueIfPresent(key: K) -> String? {
        guard let decoded = _decodeStringValueIfPresentCore(key: key) else {
            return _compatibleDecode(forKey: key, logIfKeyMissing: false)
        }
        return decoded
    }

    /// 必选字符串解码
    @inline(__always) private func _decodeStringValue(key: K) throws -> String {
        if let decoded = _decodeStringValueIfPresentCore(key: key) { return decoded }
        if let value: String = _compatibleDecode(forKey: key, logIfKeyMissing: true) {
            return value
        }
        return try Patcher<String>.defaultForType()
    }

    /// 字符串解码的核心实现：直接从 JSONValue 提取字符串值
    @inline(__always) private func _decodeStringValueIfPresentCore(key: K) -> String? {
        guard let value = getValue(forKey: key) else { return nil }
        return impl.unwrapStringValue(from: value, for: key)
    }
}

/// 嵌套模型解码（Decodable 协议的通用实现）
///
/// WHAT：处理所有符合 Decodable 协议的类型（包括 SmartCodable 模型、特殊类型、属性包装器等）
/// HOW：根据类型特征选择不同的解码策略
/// WHY：统一处理复杂类型的解码逻辑，避免在各个类型中分散实现
///
/// JSON 解码场景分类：
/// 1. 基本数据类型：Int、Bool、Double、String 等基础类型（不进入此方法）
/// 2. 特殊类型：Date、CGFloat、URL、Decimal 等需要额外格式支持的类型
/// 3. 嵌套模型类型：直接继承 Codable 或 SmartCodable 的 Model
/// 4. 属性包装器类型：@SmartDate、@SmartIgnored、@SmartHexColor 等
///
/// 关键决策：除基本数据类型外，所有复杂类型都进入此方法，在此处统一拦截处理
extension JSONDecoderImpl.KeyedContainer {
    /// 可选 Decodable 类型解码
    @inline(__always)private func _decodeDecodableIfPresent<T: Decodable>(_ type: T.Type, forKey key: K) -> T? {
        guard let decoded = _decodeDecodableIfPresentCore(type, forKey: key) else {
            if let value: T = _compatibleDecode(forKey: key, logIfKeyMissing: false) {
                return didFinishMapping(value)
            }
            return nil
        }
        return didFinishMapping(decoded)
    }

    /// 必选 Decodable 类型解码
    @inline(__always)private func _decodeDecodable<T: Decodable>(_ type: T.Type, forKey key: K) throws -> T {

        guard let decoded = _decodeDecodableIfPresentCore(type, forKey: key) else {
            if let value: T = _compatibleDecode(forKey: key, logIfKeyMissing: true) {
                return didFinishMapping(value)
            }
            let value = try Patcher<T>.defaultForType()
            return didFinishMapping(value)
        }
        return didFinishMapping(decoded)
    }

    /// Decodable 解码的核心实现：根据类型特征选择解码策略
    @inline(__always)private func _decodeDecodableIfPresentCore<T: Decodable>(_ type: T.Type, forKey key: K) -> T? {

        /// JSON 解码场景可分为三大类，每类对应不同的处理策略：
        ///
        /// 1. 基本数据类型（Primitive Types）
        ///    - 包括 Int、Bool、Double、String 等基础类型，直接映射 JSON 的原始值（number/string/bool）。
        ///
        /// 2. 特殊类型（Non-Primitive Types）
        ///    - 包括 Date、CGFloat、URL、Decimal 等，需要额外格式或上下文支持的类型。
        ///
        /// 3. 嵌套模型类型（Nested model Types）
        ///    - 包括 直接继承于Codable 或 SmartCodable的Model。
        ///
        /// 4. 属性包装器类型（Property Wrapper Types）
        ///    - 包括SmartDate，SmartIgnored，SmartHexColor等。

        /// 总结：
        /// 除基本数据类型之外，都会进入该方法`_decodeDecodableIfPresentCore`.因此在此处进行统一的value解析的拦截实现即可。
        /// 不需要分散在各个类型中逐一处理。
        if let transformer = impl.cache.valueTransformer(for: key, in: codingPath) {
            if let decoded = decodeWithTransformer(transformer, type: type, key: key) {
                return decoded
            }
            if let decoded: T = _compatibleDecode(forKey: key, needConvert: false) {
                return decoded
            }
            return nil
        }

        /// @SmartFlat的处理
        /// 关于SmartFlat的解析，是往前一层解析，codingPath不应该增加。
        if let type = type as? FlatType.Type {
            if type.isArray {
                return try? T(from: superDecoder(forKey: key))
            } else {
                // 这里需要走unwrap，需要cache。
                return try? impl.unwrap(as: T.self)
            }
        }

        guard let newDecoder = try? decoderForKeyCompatibleForJson(key, type: type) else {
            return nil
        }

        if let decoded = try? newDecoder.unwrap(as: type) {
            return decoded
        }

        return nil
    }
}



/// 字典键名转换：在初始化时执行两层键转换
///
/// WHAT：将 JSON 键名转换为模型属性名
/// HOW：第一层应用全局 keyDecodingStrategy，第二层应用 KeysMapper 自定义映射
/// WHY：支持 snake_case → camelCase 转换和自定义键名映射，提高 JSON 兼容性
///
/// 关键决策：转换在初始化时一次性完成，避免每次访问都重新计算
fileprivate func _convertDictionary(_ dictionary: [String: JSONValue], impl: JSONDecoderImpl) -> [String: JSONValue] {

    var dictionary = dictionary

    switch impl.options.keyDecodingStrategy {
    case .useDefaultKeys:
        break
    case .fromSnakeCase:
        // 将容器中的 snake_case 键转换为 camelCase
        // 如果转换后出现重复键，则使用第一个遇到的键。JSON 字典的未定义行为。
        dictionary = Dictionary(dictionary.map {
            dict in (JSONDecoder.SmartKeyDecodingStrategy._convertFromSnakeCase(dict.key), dict.value)
        }, uniquingKeysWith: { (first, _) in first })
    case .firstLetterLower:
        dictionary = Dictionary(dictionary.map {
            dict in (JSONDecoder.SmartKeyDecodingStrategy._convertFirstLetterToLowercase(dict.key), dict.value)
        }, uniquingKeysWith: { (first, _) in first })
    case .firstLetterUpper:
        dictionary = Dictionary(dictionary.map {
            dict in (JSONDecoder.SmartKeyDecodingStrategy._convertFirstLetterToUppercase(dict.key), dict.value)
        }, uniquingKeysWith: { (first, _) in first })
    }

    guard let type = impl.cache.findSnapShot(with: impl.codingPath)?.objectType else { return dictionary }

    if let tempValue = KeysMapper.convertFrom(JSONValue.object(dictionary), type: type), let dict = tempValue.object {
        return dict
    }
    return dictionary
}
