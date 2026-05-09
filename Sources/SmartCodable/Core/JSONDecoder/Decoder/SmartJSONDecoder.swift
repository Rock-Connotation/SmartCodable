// 
//  SmartJSONDecoder.swift
//  SmartCodable
//
//  Created by Mccc on 2024/3/4.
//

import Foundation

/// 智能解码器：继承自 Foundation.JSONDecoder，提供 drop-in replacement 增强功能
/// 通过自定义策略和智能归一化，解决服务端 JSON 格式不一致问题
open class SmartJSONDecoder: JSONDecoder, @unchecked Sendable {

    /// Data 解码策略：支持 Base64 等自定义编码格式
    open var smartDataDecodingStrategy: SmartDataDecodingStrategy = .base64

    /// 解码选项封装：将所有策略统一传递给解码层次结构
    /// 设计目的：避免向每个解码方法传递多个参数，保持接口简洁
    struct _Options {
        let dateDecodingStrategy: DateDecodingStrategy?
        let dataDecodingStrategy: SmartDataDecodingStrategy
        let nonConformingFloatDecodingStrategy: NonConformingFloatDecodingStrategy
        let keyDecodingStrategy: SmartKeyDecodingStrategy
        let userInfo: [CodingUserInfoKey : Any]
    }
    
    /// 选项访问器：将实例属性组合为 _Options 结构
    /// 每次解码时动态生成，确保策略更新及时生效
    var options: _Options {
        return _Options(
            dateDecodingStrategy: smartDateDecodingStrategy,
            dataDecodingStrategy: smartDataDecodingStrategy,
            nonConformingFloatDecodingStrategy: nonConformingFloatDecodingStrategy,
            keyDecodingStrategy: smartKeyDecodingStrategy,
            userInfo: userInfo
        )
    }

    /// Date 解码策略：可选配置，未设置时使用 DateParser 自动识别
    open var smartDateDecodingStrategy: DateDecodingStrategy?

    /// Key 解码策略：控制 JSON 键名转换（如 snake_case → camelCase）
    open var smartKeyDecodingStrategy: SmartKeyDecodingStrategy = .useDefaultKeys


    // MARK: - 解码核心方法

    /// 智能解码入口：支持多种输入格式（Data/Dict/Array/String），自动归一化处理
    /// 参见 Decoding-Pipeline.md §3
    ///
    /// 执行流程：
    /// 1. 生成解析标记（parsingMark）并通过 userInfo 传递，用于日志聚合
    /// 2. 输入归一化：将 Data/Dict/Array/String 统一转换为 Foundation.JSONObject
    /// 3. 类型转换：调用 JSONValue.make 将 JSONObject 转为内部 JSONValue 枚举
    /// 4. 解码执行：创建 JSONDecoderImpl 并调用 unwrap 方法
    /// 5. 日志输出：通过 SmartSentinel.monitorLogs 记录本次解析的诊断信息
    ///
    /// - parameter type: 要解码的目标类型
    /// - parameter input: 输入数据，支持 Data/[String:Any]/[Any]/String 四种格式
    /// - returns: 解码后的目标类型实例
    /// - throws: JSON 格式错误或解码过程中的类型不匹配错误
    public func smartDecode<T : Decodable>(_ type: T.Type, from input: Any) throws -> T {

        /// 生成解析标记：通过 userInfo 传递到解码层次，解决并发解析时日志混淆问题
        let mark = SmartSentinel.parsingMark()
        if let parsingMark = CodingUserInfoKey.parsingMark {
            userInfo.updateValue(mark, forKey: parsingMark)
        }


        // 第一步：输入归一化 - 将多种输入格式统一转换为 Foundation.JSONObject
        let jsonObject: Any
        switch input {
        case let data as Data:
            do {
                jsonObject = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
            } catch {
                SmartSentinel.monitorAndPrint(debugDescription: "The given data was not valid JSON.", error: error, in: type)
                throw error
            }

        case let dict as [String: Any]:
            jsonObject = dict

        case let arr as [Any]:
            jsonObject = arr

        case let json as String:
            guard let object = json.toJSONObject() else {
                let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "不支持的 JSON 值类型"))
                SmartSentinel.monitorAndPrint(debugDescription: "The given data was not valid JSON.", error: error, in: type)
                throw error
            }
            jsonObject = object
        default:
            let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "不支持的 JSON 值类型"))
            SmartSentinel.monitorAndPrint(debugDescription: "The given data was not valid JSON.", error: error, in: type)
            throw error
        }

        // 第二步：类型转换 - 将 Foundation.JSONObject 转换为内部 JSONValue 枚举
        guard let json = JSONValue.make(jsonObject) else {
            let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "不支持的 JSON 值类型"))
            SmartSentinel.monitorAndPrint(debugDescription: "The given data was not valid JSON.", error: error, in: type)
            throw error
        }

        // 第三步：创建解码器实现并执行解码
        let impl = JSONDecoderImpl(userInfo: userInfo, from: json, codingPath: [], options: options)
        do {
            let value = try impl.unwrap(as: type)
            // 第四步：记录诊断日志（仅在调试模式下）
            SmartSentinel.monitorLogs(in: "\(type)", parsingMark: mark, impl: impl)
            return value
        } catch {
            SmartSentinel.monitorAndPrint(debugDescription: "The given data was not valid JSON.", error: error, in: type)
            throw error
        }
    }
}


extension CodingUserInfoKey {
    /// 解析标记键：用于在并发场景下区分不同解析请求的日志
    /// 参见 Decoding-Pipeline.md §3 - 日志聚合机制
    static var parsingMark = CodingUserInfoKey.init(rawValue: "Stamrt.parsingMark")

    /// 日志上下文头部键：用于标记日志输出的起始位置
    static var logContextHeader = CodingUserInfoKey.init(rawValue: "Stamrt.logContext.header")
    /// 日志上下文尾部键：用于标记日志输出的结束位置
    static var logContextFooter = CodingUserInfoKey.init(rawValue: "Stamrt.logContext.footer")
}

