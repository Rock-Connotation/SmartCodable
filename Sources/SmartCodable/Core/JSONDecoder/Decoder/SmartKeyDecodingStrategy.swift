//
//  SmartKeyDecodingStrategy.swift
//  SmartCodable
//
//  Created by Mccc on 2024/3/27.
//

import Foundation

extension JSONDecoder {
    public enum SmartDataDecodingStrategy : Sendable {
        /// 从Base64编码的字符串解码Data（默认策略）
        case base64
    }
}



extension JSONDecoder {
    /// 全局键名转换策略（在自定义映射KeysMapper之前执行）
    /// 执行顺序：全局策略 → 自定义映射
    public enum SmartKeyDecodingStrategy : Sendable {

        /// 使用类型指定的原始键（默认策略，零开销）
        case useDefaultKeys

        /// 将"snake_case_keys"转换为"camelCaseKeys"
        /// 转换规则：
        /// 1. 每个下划线后的单词首字母大写
        /// 2. 移除所有下划线
        /// 3. 保留首尾下划线（常用于标识私有变量或元数据）
        /// 示例：`one_two_three` → `oneTwoThree`，`_one_two_three_` → `_oneTwoThree_`
        case fromSnakeCase

        /// 将键名首字母转为小写
        /// 示例：`OneTwoThree` → `oneTwoThree`
        /// 警告：谨慎使用，如果首字母大写有区分意义（如类型名），不应转换
        case firstLetterLower

        /// 将键名首字母转为大写
        /// 示例：`oneTwoThree` → `OneTwoThree`
        /// 适用场景：预期键名以小写开头，需要转换为驼峰首字母大写
        case firstLetterUpper
    }
}

extension JSONDecoder.SmartKeyDecodingStrategy {



    /// 将键名首字母转为小写（用于firstLetterLower策略）
    static func _convertFirstLetterToLowercase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        return stringKey.prefix(1).lowercased() + stringKey.dropFirst()
    }

    /// 将键名首字母转为大写（用于firstLetterUpper策略）
    static func _convertFirstLetterToUppercase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        return stringKey.prefix(1).uppercased() + stringKey.dropFirst()
    }

    /// 蛇形命名转驼峰（用于fromSnakeCase策略）
    /// 关键设计：保留首尾下划线，仅转换中间部分
    /// 算法步骤：
    /// 1. 定位首尾非下划线范围（排除首尾连续下划线）
    /// 2. 按下划线分割中间部分
    /// 3. 第一个单词小写，后续单词首字母大写
    /// 4. 拼接：前导下划线 + 转换后字符串 + 尾随下划线
    static func _convertFromSnakeCase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        // 定位第一个非下划线字符
        guard let firstNonUnderscore = stringKey.firstIndex(where: { $0 != "_" }) else {
            // 全部是下划线，直接返回
            return stringKey
        }

        // 定位最后一个非下划线字符（排除尾部连续下划线）
        var lastNonUnderscore = stringKey.index(before: stringKey.endIndex)
        while lastNonUnderscore > firstNonUnderscore && stringKey[lastNonUnderscore] == "_" {
            stringKey.formIndex(before: &lastNonUnderscore)
        }

        let keyRange = firstNonUnderscore...lastNonUnderscore
        let leadingUnderscoreRange = stringKey.startIndex..<firstNonUnderscore
        let trailingUnderscoreRange = stringKey.index(after: lastNonUnderscore)..<stringKey.endIndex

        // 按下划线分割，首词小写，后续首字母大写
        let components = stringKey[keyRange].split(separator: "_")
        let joinedString: String
        if components.count == 1 {
            // 无下划线，直接保留（可能已经是驼峰）
            joinedString = String(stringKey[keyRange])
        } else {
            joinedString = ([components[0].lowercased()] + components[1...].map { $0.capitalized }).joined()
        }

        // 拼接前导/尾随下划线（避免创建空字符串的优化）
        let result: String
        if leadingUnderscoreRange.isEmpty && trailingUnderscoreRange.isEmpty {
            result = joinedString
        } else if !leadingUnderscoreRange.isEmpty && !trailingUnderscoreRange.isEmpty {
            // 首尾都有下划线
            result = String(stringKey[leadingUnderscoreRange]) + joinedString + String(stringKey[trailingUnderscoreRange])
        } else if !leadingUnderscoreRange.isEmpty {
            // 仅有前导下划线
            result = String(stringKey[leadingUnderscoreRange]) + joinedString
        } else {
            // 仅有尾随下划线
            result = joinedString + String(stringKey[trailingUnderscoreRange])
        }
        return result
    }
}

