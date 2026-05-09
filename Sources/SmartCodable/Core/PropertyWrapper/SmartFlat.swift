//
//  SmartFlat.swift
//  SmartCodable
//
//  Created by Mccc on 2024/6/18.
//


import Foundation

// MARK: - @SmartFlat 属性包装器

/// 将子模型的字段"扁平化"到父级 JSON 中解码。
///
/// **WHAT**: 不从当前 key 下读取子模型，而是把父级 JSON 对象直接交给子模型解析。
/// 例如 `@SmartFlat var profile: Profile` 会将 `{"name":"Lin","avatar":"..."}`
/// 中的 avatar 解析到 Profile 中，而不需要 JSON 中有 `{"profile": {...}}` 嵌套。
///
/// **HOW (解码)**: `init(from:)` 直接将当前 decoder（父级对象的解码器）交给 `T.init(from:)`，
/// 不增加 codingPath 层级。容器通过 FlatType 协议的 `isArray` 判断走数组还是非数组路径：
/// - 非数组: `impl.unwrap(as: T.self)` — 复用当前解码器
/// - 数组:   `superDecoder(forKey:)` — 在当前 key 下创建子解码器
///
/// **HOW (编码)**: `encode(to:)` 直接把 encoder 传给 wrappedValue，让字段写入父级容器。
///
/// **风险**: @SmartFlat 依赖 codingPath 不改变来保持扁平化行为。如果容器给 SmartFlat
/// 加了额外的 nestedContainer 调用，解码路径和缓存路径都会错位。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
@propertyWrapper
public struct SmartFlat<T: Codable>: PropertyWrapperable {
    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
    public func wrappedValueDidFinishMapping() -> SmartFlat<T>? {
        if var temp = wrappedValue as? SmartDecodable {
            temp.didFinishMapping()
            return SmartFlat(wrappedValue: temp as! T)
        }
        return nil
    }
    
    /// Creates an instance from any value if possible
    public static func createInstance(with value: Any) -> SmartFlat? {
        if let value = value as? T {
            return SmartFlat(wrappedValue: value)
        }
        return nil
    }
}


extension SmartFlat: Codable {
    
    public init(from decoder: Decoder) throws {
        do {
            wrappedValue = try T(from: decoder)
        } catch  {
            wrappedValue = try Patcher<T>.defaultForType()
        }
    }

    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}



// MARK: - FlatType 标记协议

/// 标记协议，让 KeyedContainer 识别 @SmartFlat 并区分数组/非数组路径。
/// 数组路径需要 superDecoder(forKey:) 创建子解码器，非数组路径直接复用当前解码器。
protocol FlatType {
    static var isArray: Bool { get }
}

extension SmartFlat: FlatType {
    static var isArray: Bool { T.self is _ArrayMark.Type }
}

/// 利用 Swift 扩展标记所有 Array（Element: Decodable）类型。
/// `Array.self is _ArrayMark.Type` 仅对 Decodable 元素数组为 true。
protocol _ArrayMark { }

extension Array: _ArrayMark where Element: Decodable { }


