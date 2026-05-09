//
//  SmartUpdater.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/30.
//

import Foundation

/// 智能更新工具：用新数据局部更新已有模型实例
///
/// WHAT: 只更新 JSON 中存在的字段，保留其他字段不变
/// HOW: 基于 Mirror 反射实现，递归合并嵌套字典
/// WHY: 支持增量更新场景（如只更新用户昵称而不影响其他字段）
public struct SmartUpdater<T: SmartCodableX> {

    /// 从 Data 格式的 JSON 数据更新目标对象
    ///
    /// WHAT: 解析 Data 为 JSON 字典，并用其更新目标对象
    /// HOW: Data → JSONSerialization → [String:Any] → 合并 → 重新解析
    /// WHY: 支持网络响应、本地存储等常见数据源的场景
    /// - Parameters:
    ///   - dest: A reference to the target object (the inout keyword indicates that this object will be modified within the method).
    ///   - src: A Data object containing the JSON data.
    public static func update(_ dest: inout T, from src: Data?) {
        
        guard let src = src else { return }
        
        guard let dict = try? JSONSerialization.jsonObject(with: src, options: .mutableContainers) as? [String: Any] else {
            return
        }
        update(&dest, from: dict)
    }


    /// 从 String 格式的 JSON 数据更新目标对象
    ///
    /// WHAT: 解析 String 为 Data → JSON 字典，并用其更新目标对象
    /// HOW: String → UTF8 Data → JSONSerialization → [String:Any] → 合并 → 重新解析
    /// WHY: 支持字符串形式的 JSON 数据（如配置文件、API 响应字符串）
    /// - Parameters:
    ///   - dest: A reference to the target object (the inout keyword indicates that this object will be modified within the method).
    ///   - src: A String object containing the JSON data.
    public static func update(_ dest: inout T, from src: String?) {
        
        guard let src = src else { return }
        
        guard let data = src.data(using: .utf8) else { return }
        
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        
        update(&dest, from: dict)
    }


    /// 从字典格式的 JSON 数据更新目标对象
    ///
    /// WHAT: 将源字典合并到目标对象的字典表示中，重新解析
    /// HOW: 目标对象 → toDictionary() → 合并字典 → deserialize() → 新实例
    /// WHY: 支持内存中字典数据的增量更新，是其他两个重载方法的核心实现
    /// - Parameters:
    ///   - dest: A reference to the target object (the inout keyword indicates that this object will be modified within the method).
    ///   - src: A Dictionary object containing the JSON data.
    public static func update(_ dest: inout T, from src: [String: Any]?) {
        guard let src = src else { return }
        var destDict = dest.toDictionary(useMappedKeys: true) ?? [:]
        updateDict(&destDict, from: src)
        if let model = T.deserialize(from: destDict) {
            dest = model
        }
    }
}

extension SmartUpdater {

    /// 递归合并字典（支持嵌套对象）
    ///
    /// WHAT: 将源字典合并到目标字典，嵌套对象递归合并
    /// HOW: 遍历源字典，遇到嵌套字典时递归合并，否则直接覆盖
    /// WHY: 支持嵌套对象的局部更新，如只更新 address.city 而不影响 address.street
    /// - Parameters:
    ///   - dest: 目标字典
    ///   - src: 源字典
//    fileprivate static func updateDict(_ dest: inout [String: Any], from src: [String: Any]) {
//        dest.merge(src) { _, new in
//            return new
//        }
//    }

    fileprivate static func updateDict(_ dest: inout [String: Any], from src: [String: Any]) {
        for (key, value) in src {
            if let subDict = value as? [String: Any],
               var existingSubDict = dest[key] as? [String: Any] {
                updateDict(&existingSubDict, from: subDict)
                dest[key] = existingSubDict
            } else {
                dest[key] = value
            }
        }
    }
}
