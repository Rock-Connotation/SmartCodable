//
//  PropertyWrapperProtocol.swift
//  SmartCodable
//
//  Created by Mccc on 2025/4/9.
//

import Foundation

// MARK: - 属性包装器统一协议

/// 所有 SmartCodable 属性包装器必须遵循的统一接口。
///
/// **WHAT**: 定义包装器的 5 个核心能力——取值、构造、类型判断、实例创建、解码回调。
///
/// **WHY**: 如果没有统一协议，KeyedContainer 需要为每个包装器类型写独立的 case 分支（如
/// `if let any = value as? SmartAny<...>`），每增加一个包装器就多一个分支。有了
/// PropertyWrapperable，容器只关心协议方法，不关心具体类型——符合"消除特殊情况"的设计原则。
///
/// **HOW**: Swift 属性包装器编译后生成 `_propertyName` 底层存储，协议通过
/// `wrappedSmartDecodableType` 让 DecodingCache 能穿透 `_` 前缀找到内部模型类型，
/// 从而正确缓存快照和回退默认值。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
public protocol PropertyWrapperable {
    associatedtype WrappedValue
    
    var wrappedValue: WrappedValue { get }
    
    init(wrappedValue: WrappedValue)
    
    static var wrappedSmartDecodableType: SmartDecodable.Type? { get }

    static func createInstance(with value: Any) -> Self?
    
    /// 解码完成后触发 wrappedValue 内部模型的 didFinishMapping()。
    ///
    /// **WHY**: Swift 不会自动将 didFinishMapping 从 wrappedValue 穿透到外层包装器。
    /// 如果 wrappedValue 是 SmartDecodable 模型（如 `@SmartAny var user: User`），
    /// 解码完成后必须手动调用 `user.didFinishMapping()`，否则用户重写的回调不会执行。
    ///
    /// **HOW**: 返回 `Self?`——不是 SmartDecodable 则返回 nil，是则返回包含已触发回调的新实例。
    func wrappedValueDidFinishMapping() -> Self?
}

public extension PropertyWrapperable {
    /// 静态判断 WrappedValue 是否为 SmartDecodable 或 Optional<SmartDecodable>。
    ///
    /// **WHY**: DecodingCache 需要知道包装器内部是否包含 SmartDecodable 模型，
    /// 以决定是否缓存快照（用于解码失败时的默认值回退）。
    ///
    /// **HOW**: 两层尝试——① WrappedValue 本身是 SmartDecodable.Type；
    /// ② WrappedValue 是 Optional，其 Wrapped 类型是 SmartDecodable.Type。
    /// 第二层通过内部协议 `_OptionalType` 解决 Swift 泛型无法直接判断
    /// `Optional<SmartDecodable>` 的问题。
    static var wrappedSmartDecodableType: SmartDecodable.Type? {

        let valueType = WrappedValue.self

        // WrappedValue 本身是 SmartDecodable
        if let smart = valueType as? SmartDecodable.Type {
            return smart
        }

        // WrappedValue 是 Optional<SmartDecodable>
        if let optionalType = valueType as? _OptionalType.Type,
           let smart = optionalType.wrappedType as? SmartDecodable.Type {
            return smart
        }

        return nil
    }
}

/// 内部协议，让 Optional 暴露其 Wrapped 元类型。
/// Swift 的 Optional 是枚举泛型，无法直接通过 `WrappedValue.self` 获取内部类型，
/// 需要此协议桥接。
protocol _OptionalType {
    static var wrappedType: Any.Type { get }
}

extension Optional: _OptionalType {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}

// ============================================================
// MARK: - Equatable / Hashable 统一支持
//
// **WHY**: 协议扩展为泛型和非泛型包装器分别提供默认实现。
// 泛型包装器（SmartAny、SmartFlat、SmartIgnored）由于 Swift 泛型限制，
// 编译器无法自动推导 Equatable/Hashable，必须显式声明 + 条件约束。
// 非泛型包装器（SmartDate、SmartHexColor）可以直接声明。
// SmartHexColor 的 Equatable 比较 rgbaComponents 而非指针——相同颜色
// 可能有不同的内部表示（如不同色彩空间），按分量比较才能正确判等。
// ============================================================

/// 为泛型 wrapper 提供默认 Equatable（委托给 wrappedValue）
extension PropertyWrapperable where WrappedValue: Equatable, Self: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

/// 为泛型 wrapper 提供默认 Hashable（委托给 wrappedValue）
extension PropertyWrapperable where WrappedValue: Hashable, Self: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}

// ============================================================
// MARK: - 泛型包装器的 Equatable / Hashable 显式声明
//
// Swift 泛型限制：编译器无法自动将泛型 wrapper 标记为 Equatable/Hashable，
// 必须在此逐一显式声明，同时用 where 子句约束 WrappedValue。
// ============================================================

extension SmartFlat: Equatable where T: Equatable {}
extension SmartFlat: Hashable where T: Hashable {}

extension SmartIgnored: Equatable where T: Equatable {}
extension SmartIgnored: Hashable where T: Hashable {}

extension SmartAny: Equatable where T: Equatable {}
extension SmartAny: Hashable where T: Hashable {}



// MARK: - 非泛型包装器的 Equatable / Hashable 声明
// 非泛型 wrapper 类型固定，可直接声明协议遵循。
extension SmartDate: Equatable {}
extension SmartDate: Hashable {}

extension SmartHexColor: Equatable {
    public static func == (lhs: SmartHexColor, rhs: SmartHexColor) -> Bool {
        switch (lhs.wrappedValue?.rgbaComponents, rhs.wrappedValue?.rgbaComponents) {
        case let (l?, r?):
            return l.r == r.r && l.g == r.g && l.b == r.b && l.a == r.a
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}
extension SmartHexColor: Hashable {
    public func hash(into hasher: inout Hasher) {
        if let components = wrappedValue?.rgbaComponents {
            hasher.combine(components.r)
            hasher.combine(components.g)
            hasher.combine(components.b)
            hasher.combine(components.a)
        }
    }
}
