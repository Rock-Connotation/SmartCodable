//
//  JSONDecoderImpl.swift
//  SmartCodable
//
//  Created by Mccc on 2024/5/17.
//

import Foundation


/// JSON 解码器实现：Decoder 协议的核心实现，持有 JSON 值和配置选项
/// 参见 Decoding-Pipeline.md §4 - 解码器层次结构
struct JSONDecoderImpl {
    /// 编码路径：记录当前解码位置，用于错误定位和缓存管理
    let codingPath: [CodingKey]
    /// 用户信息：传递自定义配置（如解析标记、上下文信息）
    let userInfo: [CodingUserInfoKey: Any]

    /// 当前 JSON 值：要解码的 JSON 节点（object/array/string/number/bool/null）
    let json: JSONValue
    /// 解码选项：包含日期/数据/键名等策略配置
    let options: SmartJSONDecoder._Options


    /// 解码缓存：记录键值容器的属性初始化值，支持循环引用检测
    var cache: DecodingCache

    /// 初始化解码器：接收 JSON 值、路径和配置，创建解码上下文
    init(userInfo: [CodingUserInfoKey: Any], from json: JSONValue, codingPath: [CodingKey], options: SmartJSONDecoder._Options) {
        self.userInfo = userInfo
        self.codingPath = codingPath
        self.json = json
        self.options = options
        self.cache = DecodingCache()
    }
}


/// 容器生成策略：类型不匹配时直接抛异常，由上层捕获并提供默认值
/// 参见 Decoding-Pipeline.md §5 - 容器层次结构
extension JSONDecoderImpl: Decoder {
    /// 创建键值容器：支持 .object 和 .string 自解析两种路径
    /// 字符串自解析是 SmartCodable 独有特性，解决服务端 JSON 被字符串包装的问题
    /// 参见 Decoding-Pipeline.md §5.1 - 字符串自解析机制
    func container<Key>(keyedBy key: Key.Type) throws ->
    KeyedDecodingContainer<Key> where Key: CodingKey {

        switch self.json {
        case .object(let dictionary):
            // 路径1：正常 JSON 对象，直接创建容器
            let container = KeyedContainer<Key>(
                impl: self,
                codingPath: codingPath,
                dictionary: dictionary
            )
            return KeyedDecodingContainer(container)
        case .string(let string): // 路径2：字符串自解析 - 兼容服务端返回的字符串化 JSON
            if let dict = string.toJSONObject() as? [String: Any],
               let dictionary = JSONValue.make(dict)?.object {
                let container = KeyedContainer<Key>(
                    impl: self,
                    codingPath: codingPath,
                    dictionary: dictionary
                )
                return KeyedDecodingContainer(container)
            }
        case .null:
            throw DecodingError.valueNotFound([String: JSONValue].self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Cannot get keyed decoding container -- found null value instead"
            ))
        default:
            break
        }
        throw DecodingError._typeMismatch(at: codingPath, expectation: [String: JSONValue].self, desc: json.debugDataTypeDescription)
    }


    /// 创建无键容器：支持 .array 和 .string 自解析两种路径
    /// 字符串自解析适用于服务端返回的字符串化数组
    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        switch self.json {
        case .array(let array):
            // 路径1：正常 JSON 数组
            return UnkeyedContainer(
                impl: self,
                codingPath: self.codingPath,
                array: array
            )
        case .string(let string): // 路径2：字符串自解析 - 兼容服务端返回的字符串化 JSON 数组
            if let arr = string.toJSONObject() as? [Any],
               let array = JSONValue.make(arr)?.array {
                return UnkeyedContainer(
                    impl: self,
                    codingPath: self.codingPath,
                    array: array
                )
            }
        case .null:
            throw DecodingError.valueNotFound([String: JSONValue].self, DecodingError.Context(
                codingPath: self.codingPath,
                debugDescription: "Cannot get unkeyed decoding container -- found null value instead"
            ))
        default:
            break
        }
        throw DecodingError.typeMismatch([JSONValue].self, DecodingError.Context(
            codingPath: self.codingPath,
            debugDescription: "Expected to decode \([JSONValue].self) but found \(self.json.debugDataTypeDescription) instead."
        ))
    }

    /// 创建单值容器：永不抛异常，任何 JSON 值都可以作为单值处理
    func singleValueContainer() throws -> SingleValueDecodingContainer {
        SingleValueContainer(
            impl: self,
            codingPath: self.codingPath,
            json: self.json
        )
    }
}




/// 内部 CodingKey 实现：提供统一的键名/索引访问方式
/// 用于构建编码路径（codingPath）和访问 JSON 键值
internal struct _JSONKey: CodingKey {
    public var stringValue: String
    public var intValue: Int?

    /// 通过字符串创建键（对象属性名）
    public init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    /// 通过整数创建键（数组索引）
    public init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    /// 同时指定字符串和整数值（用于特殊场景）
    public init(stringValue: String, intValue: Int?) {
        self.stringValue = stringValue
        self.intValue = intValue
    }

    /// 通过数组索引创建键（用于无键容器中的元素访问）
    internal init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    /// 超类键：用于继承场景下的父类访问
    internal static let `super` = _JSONKey(stringValue: "super")!
}


