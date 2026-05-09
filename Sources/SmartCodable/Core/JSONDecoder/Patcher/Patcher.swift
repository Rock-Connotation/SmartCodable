//
//  ValueCumulator.swift
//  SmartCodable
//
//  Created by Mccc on 2023/8/21.
//

import Foundation

/// 通用类型转换枢纽：当标准 Codable 解码失败时，尝试跨类型转换
///
/// 位置：四层韧性架构的第三层（在 DecodingCache 初始值之前）
/// 参见：Mapping-And-Conversion.md "Patcher 通用转换" 章节
struct Patcher<T> {

    /// 获取类型 T 的零值（default value）
    ///
    /// WHAT: 返回目标类型的默认零值
    /// HOW: 委托给 Provider.defaultValue() 支持 Defaultable/SmartDecodable/SmartCaseDefaultable/SmartAssociatedEnumerable 四种协议
    /// WHY: 作为解码失败的兜底方案，提供类型安全的默认值
    static func defaultForType() throws -> T {
        return try Provider.defaultValue()
    }

    /// 将 JSON 值转换为目标类型 T（支持跨类型转换）
    ///
    /// WHAT: 将 JSONValue 转为目标类型，支持 String→Int、String→Bool、Float→Int 等跨类型转换
    /// HOW: 委托给 Transformer.typeTransform() 调用各类型的 TypeTransformable 实现
    /// WHY: 提供比标准 Codable 更宽松的类型匹配能力，增强解析韧性
    static func convertToType(from value: JSONValue?, impl: JSONDecoderImpl) -> T? {
        guard let value = value else { return nil }
        return Transformer.typeTransform(from: value, impl: impl)
    }
}

