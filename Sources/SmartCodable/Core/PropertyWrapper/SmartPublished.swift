//
//  SmartPublished.swift
//  SmartCodable
//
//  Created by Mccc on 2024/9/26.
//

import Foundation
#if canImport(Combine)
import SwiftUI
import Combine

// MARK: - @SmartPublished 属性包装器

/// 将 Combine 发布能力与 Codable 序列化结合在一起的属性包装器。
///
/// **WHAT**: 让 Codable 模型的属性同时具备 Combine 发布能力和编解码能力。
/// 通过 `$title` 投影值访问 Publisher，通过 `deserialize/encode` 处理 JSON。
///
/// **HOW (三个关键组件)**:
/// 1. wrappedValue 的 willSet → 值变更前通知 publisher.subject（CurrentValueSubject）
/// 2. Custom Publisher → 使用 CurrentValueSubject（非 PassthroughSubject），新订阅者立即收到当前值
/// 3. ObservableObject subscript → 实现 `subscript(_enclosingInstance:wrapped:storage:)`，
///    属性变更时触发 `objectWillChange`，驱动 SwiftUI 视图刷新
///
/// - Note: 需要 iOS 13.0+ / macOS 10.15+（依赖 Combine 框架）
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Property-Wrappers.md`
@propertyWrapper
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public struct SmartPublished<Value: Codable>: PropertyWrapperable {
    
    
    public var wrappedValue: Value {
        // Notify subscribers before value changes
        willSet {
            publisher.subject.send(newValue)
        }
    }
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
        publisher = Publisher(wrappedValue)
    }
    
    public static func createInstance(with value: Any) -> SmartPublished? {
        if let value = value as? Value {
            return SmartPublished(wrappedValue: value)
        }
        return nil
    }
    
    public func wrappedValueDidFinishMapping() -> SmartPublished<Value>? {
        if var temp = wrappedValue as? SmartDecodable {
            temp.didFinishMapping()
            return SmartPublished(wrappedValue: temp as! Value)
        }
        return nil
    }
    
    
    /// The publisher that exposes the wrapped value's changes
    public var projectedValue: Publisher {
        publisher
    }
    
    private var publisher: Publisher
    
    // MARK: - Publisher Implementation
    
    /// 自定义 Publisher，使用 CurrentValueSubject 保留当前值。
    /// 与 PassthroughSubject 不同，新订阅者会立即收到当前值，更适合属性包装器场景。
    public struct Publisher: Combine.Publisher {
        public typealias Output = Value
        public typealias Failure = Never
        
        // CurrentValueSubject 保存当前值，新订阅者立即收到当前值。
        var subject: CurrentValueSubject<Value, Never>

        public func receive<S>(subscriber: S) where S: Subscriber, Self.Failure == S.Failure, Self.Output == S.Input {
            subject.subscribe(subscriber)
        }

        init(_ output: Output) {
            subject = .init(output)
        }
    }
    

    /// ObservableObject subscript：属性变更时触发 objectWillChange.send()，驱动 SwiftUI 刷新。
    public static subscript<OuterSelf: ObservableObject>(
        _enclosingInstance observed: OuterSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<OuterSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<OuterSelf, Self>
    ) -> Value {
        get {
            observed[keyPath: storageKeyPath].wrappedValue
        }
        set {
            // Notify observers before changing value
            if let subject = observed.objectWillChange as? ObservableObjectPublisher {
                subject.send()
                observed[keyPath: storageKeyPath].wrappedValue = newValue
            }
        }
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
extension SmartPublished: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Value.self)
        self.wrappedValue = value
        publisher = Publisher(wrappedValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.wrappedValue)
    }
}
#endif
