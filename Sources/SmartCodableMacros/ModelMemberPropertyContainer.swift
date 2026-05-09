//
//  ModelMemberPropertyContainer.swift
//  SmartCodable
//
//  Created by qixin on 2025/5/14.
//

// MARK: - 宏属性元数据

/// 宏提取的类属性信息，供代码生成使用。
///
/// **关键设计**: `accessName` 区分属性包装器——isWrapped 为 true 时返回 `_\(name)`，
/// 因为 Swift 属性包装器编译后底层存储是 `_propertyName`。
/// `codingKeyName` 始终返回原始属性名（CodingKeys 枚举使用）。
import SwiftSyntax
import SwiftSyntaxMacros

struct ModelMemberProperty {
    let name: String       // 属性名
    let type: String       // 类型（含包装器包装后的类型，如 "SmartAny<String>"）
    let isWrapped: Bool    // 是否有属性包装器
    let isStored: Bool     // 是否为存储属性

    var codingKeyName: String {
        return name
    }

    /// 访问名：包装器属性返回 `_name`（底层存储），否则返回 `name`
    var accessName: String {
        isWrapped ? "_\(name)" : name
    }
}
