//
//  SmartKeyTransformer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/9.
//

import Foundation


/// 键映射转换器：将 JSON 字段名映射到模型属性名
/// - WHAT：支持单个或多个 JSON 字段映射到同一个模型属性
/// - HOW：存储源字段数组（from）和目标 CodingKey（to）
/// - WHY：处理 API 字段命名不一致的情况，如 snake_case 转换为 camelCase
public struct SmartKeyTransformer {
    var from: [String]
    var to: CodingKey
}

infix operator <---
/// 将单个 JSON 字段名映射到模型属性（便捷语法）
/// - WHAT：通过运算符重载提供字段映射的简洁语法
/// - HOW：将单个字符串转换为数组，调用多字段版本
/// - WHY：提供 `CodingKeys.name <--- “user_name”` 这样的直观语法
public func <---(to: CodingKey, from: String) -> SmartKeyTransformer {
    to <--- [from]
}

/// 将多个 JSON 字段名映射到同一个模型属性（优先级顺序）
/// - WHAT：支持多个备选字段映射，按数组顺序依次尝试
/// - HOW：按 from 数组顺序查找第一个存在的字段
/// - WHY：处理 API 版本兼容性，如旧字段和新字段同时存在时优先使用新字段
public func <---(to: CodingKey, from: [String]) -> SmartKeyTransformer {
    SmartKeyTransformer(from: from, to: to)
}




/// 值转换器：将特定字段的 JSON 值转换为目标类型
/// - WHAT：包装位置信息（CodingKey）和转换逻辑（ValueTransformable）
/// - HOW：在解码时定位字段，调用执行者的转换方法
/// - WHY：支持为单个字段定制转换逻辑，与 mappingForValue() 配合使用
/// - 参见：Mapping-And-Conversion.md "mappingForValue" 章节
public struct SmartValueTransformer {
    var location: CodingKey
    var performer: any ValueTransformable
    public init(location: CodingKey, performer: any ValueTransformable) {
        self.location = location
        self.performer = performer
    }

    /// 使用对应的转换器转换 JSON 值
    /// - WHAT：执行值转换的核心方法
    /// - HOW：剥离 JSONValue 包装层，委托给 performer 执行实际转换
    /// - WHY：统一处理 JSONValue 类型，解耦转换逻辑与数据结构
    func transformFromJSON(_ value: JSONValue) -> Any? {
        return performer.transformFromJSON(value.peel)
    }
}


/// 值转换协议：定义 JSON ↔ Object 双向转换接口
/// - WHAT：所有类型转换器必须实现的协议
/// - HOW：关联类型 Object 定义目标类型，JSON 定义源类型
/// - WHY：提供统一的转换抽象，支持自定义类型编解码
public protocol ValueTransformable {
    associatedtype Object
    associatedtype JSON

    /// 从 JSON 值转换为目标类型
    /// - WHAT：解码时的转换入口
    /// - HOW：接收 Any 类型 JSON 值，返回可选的 Object 类型
    /// - WHY：支持转换失败场景（如格式错误），返回 nil 表示转换失败
    func transformFromJSON(_ value: Any) -> Object?

    /// 从目标类型转换为 JSON 值
    /// - WHAT：编码时的转换入口
    /// - HOW：接收 Object 类型，返回可选的 JSON 类型
    /// - WHY：支持编码转换，可选返回值处理不可序列化情况
    func transformToJSON(_ value: Object) -> JSON?
}

/// 将 CodingKey 和转换器绑定（值映射运算符）
/// - WHAT：通过运算符重载创建 SmartValueTransformer 的便捷语法
/// - HOW：将位置和执行者组合成转换器实例
/// - WHY：提供 `CodingKeys.age <--- FastTransformer<Int, String>` 这样的声明式语法
public func <---(location: CodingKey, performer: any ValueTransformable) -> SmartValueTransformer {
    SmartValueTransformer.init(location: location, performer: performer)
}



/** 快速转换器示例
 static func mappingForValue() -> [SmartValueTransformer]? {
     [
         CodingKeys.name <--- FastTransformer<String, String>(fromJSON: { json in
             "abc"
         }, toJSON: { object in
             "123"
         }),
         CodingKeys.subModel <--- FastTransformer<TestEnum, String>(fromJSON: { json in
             TestEnum.man
         }, toJSON: { object in
             object?.rawValue
         }),
     ]
 }
 */
/// 快速转换器：闭包便捷封装，适合一次性简单转换
/// - WHAT：通过闭包直接定义转换逻辑，无需创建独立类型
/// - HOW：存储 fromJSON 和 toJSON 两个闭包，分别处理编解码
/// - WHY：避免为简单转换创建单独的结构体，减少样板代码
/// - 适用场景：字符串截取、枚举映射、单位转换等一次性逻辑
public struct FastTransformer<Object, JSON>: ValueTransformable {

    private let fromJSON: (JSON?) -> Object?
    private let toJSON: ((Object?) -> JSON?)?


    /// 便捷的转换器初始化
    /// - WHAT：通过闭包快速定义双向转换逻辑
    /// - HOW：存储 fromJSON 闭包（必填），toJSON 闭包（可选）
    /// - WHY：只读场景可省略 toJSON，降低代码量
    /// - Parameters:
    ///   - fromJSON: json 转 object 的转换闭包
    ///   - toJSON: object 转 json 的转换闭包，只读场景可省略
    public init(fromJSON: @escaping (JSON?) -> Object?, toJSON: ((Object?) -> JSON?)? = nil) {
        self.fromJSON = fromJSON
        self.toJSON = toJSON
    }

    public func transformFromJSON(_ value: Any) -> Object? {
        return fromJSON(value as? JSON)
    }

    public func transformToJSON(_ value: Object) -> JSON? {
        return toJSON?(value)
    }
}
