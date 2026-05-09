//
//  JSONFuture.swift
//  BTBubble
//
//  Created by Mccc on 2024/6/3.
//

import Foundation
enum JSONFuture {
    /// 已编码的 JSON 值
    case value(JSONValue)
    /// 子编码器实例（用于嵌套编码）
    case encoder(JSONEncoderImpl)
    /// 嵌套数组引用
    case nestedArray(RefArray)
    /// 嵌套对象引用
    case nestedObject(RefObject)

    /// 数组引用类：管理数组元素的延迟编码
    /// WHAT：持有待编码元素的 future 列表
    /// HOW：通过 append 方法添加元素，通过 values 计算属性 resolve
    /// WHY：支持数组元素逐个编码，避免一次性递归深度过大
    class RefArray {
        /// future 元素列表
        private(set) var array: [JSONFuture] = []

        init() {
            self.array.reserveCapacity(10)
        }

        /// 追加已编码值
        @inline(__always) func append(_ element: JSONValue) {
            self.array.append(.value(element))
        }

        /// 追加子编码器（用于嵌套值编码）
        @inline(__always) func append(_ encoder: JSONEncoderImpl) {
            self.array.append(.encoder(encoder))
        }

        /// 追加嵌套数组（创建并返回新的 RefArray）
        @inline(__always) func appendArray() -> RefArray {
            let array = RefArray()
            self.array.append(.nestedArray(array))
            return array
        }

        /// 追加嵌套对象（创建并返回新的 RefObject）
        @inline(__always) func appendObject() -> RefObject {
            let object = RefObject()
            self.array.append(.nestedObject(object))
            return object
        }

        /// Resolve 所有 future 为 JSONValue 数组
        /// WHAT：将 future 列表转换为最终的 JSONValue 列表
        /// HOW：逐个处理 future，递归 resolve 嵌套数组和对象
        /// WHY：在编码完成后获取最终结果，用于 JSON 序列化
        var values: [JSONValue] {
            self.array.map { (future) -> JSONValue in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return .array(array.values)
                case .nestedObject(let object):
                    return .object(object.values)
                case .encoder(let encoder):
                    return encoder.value ?? .object([:])
                }
            }
        }
    }

    /// 对象引用类：管理对象属性的延迟编码
    /// WHAT：持有键到 future 的映射
    /// HOW：通过 set 方法设置值，通过 values 计算属性 resolve
    /// WHY：支持对象属性逐个编码，保证键名正确性
    class RefObject {
        /// 键到 future 的映射字典
        private(set) var dict: [String: JSONFuture] = [:]

        init() {
            self.dict.reserveCapacity(20)
        }

        /// 设置键值为已编码值
        @inline(__always) func set(_ value: JSONValue, for key: String) {
            self.dict[key] = .value(value)
        }

        /// 设置键值为嵌套数组（复用或创建新的 RefArray）
        /// WHAT：获取或创建键对应的数组引用
        /// HOW：检查现有值类型，如果是 nestedArray 则复用，否则创建新的
        /// WHY：支持同一键多次追加元素，避免覆盖已有数组
        @inline(__always) func setArray(for key: String) -> RefArray {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray(let array):
                return array
            case .none, .value:
                let array = RefArray()
                dict[key] = .nestedArray(array)
                return array
            }
        }

        /// 设置键值为嵌套对象（复用或创建新的 RefObject）
        /// WHAT：获取或创建键对应的对象引用
        /// HOW：检查现有值类型，如果是 nestedObject 则复用，否则创建新的
        /// WHY：支持同一键多次设置属性，避免覆盖已有对象
        @inline(__always) func setObject(for key: String) -> RefObject {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject(let object):
                return object
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                let object = RefObject()
                dict[key] = .nestedObject(object)
                return object
            }
        }

        /// 设置键值为子编码器（用于嵌套值编码）
        @inline(__always) func set(_ encoder: JSONEncoderImpl, for key: String) {
            switch self.dict[key] {
            case .encoder:
                preconditionFailure("For key \"\(key)\" an encoder has already been created.")
            case .nestedObject:
                preconditionFailure("For key \"\(key)\" a keyed container has already been created.")
            case .nestedArray:
                preconditionFailure("For key \"\(key)\" a unkeyed container has already been created.")
            case .none, .value:
                dict[key] = .encoder(encoder)
            }
        }

        /// Resolve 所有 future 为 JSONValue 字典
        /// WHAT：将 future 字典转换为最终的 JSONValue 字典
        /// HOW：逐个处理每个键的 future，递归 resolve 嵌套数组和对象
        /// WHY：在编码完成后获取最终结果，用于 JSON 序列化
        var values: [String: JSONValue] {
            self.dict.mapValues { (future) -> JSONValue in
                switch future {
                case .value(let value):
                    return value
                case .nestedArray(let array):
                    return .array(array.values)
                case .nestedObject(let object):
                    return .object(object.values)
                case .encoder(let encoder):
                    return encoder.value ?? .object([:])
                }
            }
        }
    }
}
