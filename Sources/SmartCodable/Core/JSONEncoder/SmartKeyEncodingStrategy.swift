//
//  SmartKeyEncodingStrategy.swift
//  SmartCodable
//
//  Created by Mccc on 2024/9/26.
//

import Foundation

extension JSONEncoder {
    /// Data 编码策略：将 Data 转换为 JSON 兼容格式
    /// JSON 标准不支持二进制数据，只能使用 base64 编码为字符串
    /// 与 SmartDataDecodingStrategy 对称
    public enum SmartDataEncodingStrategy: Sendable {
        case base64
    }
}


extension JSONEncoder {

    /// 键名编码策略：控制编码时如何转换键名
    /// 与 SmartKeyDecodingStrategy 对称（方向相反：解码是 JSON→模型，编码是模型→JSON）
    /// 学习文档：键名策略 - 编码端策略
    public enum SmartKeyEncodingStrategy : Sendable {

        /// 使用模型定义的原始键名（默认策略）
        /// 不进行任何转换，直接使用 CodingKeys 中的值
        case useDefaultKeys

        /// 将驼峰命名转换为蛇形命名（camelCase → snake_case）
        /// 方向：从模型键名到 JSON 键名（与解码端 fromSnakeCase 相反）
        ///
        /// 转换算法：
        /// 1. 在小写到大写的边界拆分单词
        /// 2. 在单词之间插入下划线
        /// 3. 整个字符串转为小写
        /// 4. 保留首尾的下划线
        ///
        /// 示例：`oneTwoThree` → `one_two_three`、`myURLProperty` → `my_url_property`
        /// 特殊处理：连续大写字母视为一个单词（如 URL 不会拆分为 U_R_L）
        /// 学习文档：键名策略 - 蛇形转换算法
        case toSnakeCase

        /// 将首字母转换为小写（PascalCase → camelCase）
        /// 示例：`OneTwoThree` → `oneTwoThree`
        ///
        /// 注意：谨慎使用，首字母大小写可能用于区分不同含义的键
        /// 学习文档：键名策略 - 首字母转换
        case firstLetterLower

        /// 将首字母转换为大写（camelCase → PascalCase）
        /// 示例：`oneTwoThree` → `OneTwoThree`
        ///
        /// 注意：适用于 JSON 键名需要首字母大写的场景
        /// 学习文档：键名策略 - 首字母转换
        case firstLetterUpper
    }
}


extension JSONEncoder.SmartKeyEncodingStrategy {

    /// 首字母转小写实现
    /// 使用 prefix 和 dropFirst 避免字符串复制，提高性能
    /// 学习文档：键名策略 - 首字母转换实现
    static func _convertFirstLetterToLowercase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        return stringKey.prefix(1).lowercased() + stringKey.dropFirst()
    }
    
    /// 首字母转大写实现
    /// 与 _convertFirstLetterToLowercase 对称
    /// 学习文档：键名策略 - 首字母转换实现
    static func _convertFirstLetterToUppercase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        return stringKey.prefix(1).uppercased() + stringKey.dropFirst()
    }
    
    /// 驼峰转蛇形核心算法（与解码端 _convertFromSnakeCase 对称）
    /// 处理复杂场景：连续大写字母（如 URL）、混合大小写
    /// 算法步骤：
    /// 1. 在小写→大写边界拆分（myProperty → my / Property）
    /// 2. 在连续大写→小写边界拆分（myURLProperty → my / URL / Property）
    /// 3. 用下划线连接并小写
    /// 学习文档：键名策略 - 蛇形转换算法详解
    static func _convertToSnakeCase(_ stringKey: String) -> String {
        guard !stringKey.isEmpty else { return stringKey }

        var words: [Range<String.Index>] = []
        // 算法核心：在小写→大写边界拆分单词，然后在连续大写→小写边界再次拆分
        // myProperty → my_property
        // myURLProperty → my_url_property
        // 假设首字母小写（Swift 命名约定）
        //
        // myProperty -> my_property
        // myURLProperty -> my_url_property
        //
        // We assume, per Swift naming conventions, that the first character of the key is lowercase.
        var wordStart = stringKey.startIndex
        var searchRange = stringKey.index(after: wordStart)..<stringKey.endIndex

        // 查找下一个大写字母（单词边界）
        while let upperCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.uppercaseLetters, options: [], range: searchRange) {
            let untilUpperCase = wordStart..<upperCaseRange.lowerBound
            words.append(untilUpperCase)

            // 查找下一个小写字母（用于检测连续大写字母）
            searchRange = upperCaseRange.lowerBound..<searchRange.upperBound
            guard let lowerCaseRange = stringKey.rangeOfCharacter(from: CharacterSet.lowercaseLetters, options: [], range: searchRange) else {
                // 没有更多小写字母，直接结束
                wordStart = searchRange.lowerBound
                break
            }

            // 大写字母后紧接小写字母，说明不是连续大写（如 Property 中的 P 不是单独单词）
            let nextCharacterAfterCapital = stringKey.index(after: upperCaseRange.lowerBound)
            if lowerCaseRange.lowerBound == nextCharacterAfterCapital {
                // 大写后是小写，不是单词边界（如 myProperty 中的 P）
                // 继续查找下一个大写字母作为边界
                wordStart = upperCaseRange.lowerBound
            } else {
                // 连续大写字母（如 URL），在最后一个大写字母前拆分
                // 将连续大写视为一个单词（URL → url）
                let beforeLowerIndex = stringKey.index(before: lowerCaseRange.lowerBound)
                words.append(upperCaseRange.lowerBound..<beforeLowerIndex)

                // 下一个单词从最后一个大写字母开始
                wordStart = beforeLowerIndex
            }
            searchRange = lowerCaseRange.upperBound..<searchRange.upperBound
        }
        // 添加最后一个单词
        words.append(wordStart..<searchRange.upperBound)

        // 用下划线连接所有单词并转为小写
        let result = words.map({ (range) in
            return stringKey[range].lowercased()
        }).joined(separator: "_")
        return result
    }
}
