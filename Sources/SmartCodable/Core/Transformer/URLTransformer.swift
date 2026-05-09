//
//  URLTransformer.swift
//  SmartCodable
//
//  Created by Mccc on 2024/4/9.
//

import Foundation
/// URL 转换器：处理字符串到 URL 的转换，支持中文编码和前缀拼接
/// - WHAT：将 JSON 字符串转换为 Swift URL 类型
/// - HOW：自动对中文字符进行百分比编码，可选添加 URL 前缀
/// - WHY：处理 API 返回的中文 URL，确保 URL 初始化成功
public struct SmartURLTransformer: ValueTransformable {

    public typealias JSON = String
    public typealias Object = URL
    private let shouldEncodeURLString: Bool
    private let prefix: String?

    /// 初始化 URL 转换器
    /// - WHAT：配置 URL 转换行为
    /// - HOW：存储前缀和编码开关，在转换时应用
    /// - WHY：支持相对路径转绝对路径，处理中文 URL 编码问题
    /// - Parameters:
    ///   - prefix: URL 前缀，如 "https://api.example.com/"，自动拼接到相对路径
    ///   - shouldEncodeURLString: 是否对 URL 字符串进行百分比编码（默认 true，处理中文）
    /// - Returns: 初始化后的转换器实例
    public init(prefix: String? = nil, shouldEncodeURLString: Bool = true) {
        self.shouldEncodeURLString = shouldEncodeURLString
        self.prefix = prefix
    }


    /// 从 JSON 字符串转换为 URL
    /// - WHAT：解析 JSON 字符串为 URL 对象
    /// - HOW：1）可选添加前缀 2）可选进行百分比编码 3）初始化 URL
    /// - WHY：处理相对路径和中文 URL，确保 URL 可用
    public func transformFromJSON(_ value: Any) -> URL? {
        guard var URLString = value as? String else { return nil }
        if let prefix = prefix, !URLString.hasPrefix(prefix) {
            URLString = prefix + URLString
        }

        if !shouldEncodeURLString {
            return URL(string: URLString)
        }

        guard let escapedURLString = URLString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            return nil
        }
        return URL(string: escapedURLString)
    }

    /// 将 URL 转换为 JSON 字符串
    /// - WHAT：序列化 URL 为绝对路径字符串
    /// - HOW：直接返回 URL.absoluteString
    /// - WHY：确保编码后 URL 能正确序列化回 JSON
    public func transformToJSON(_ value: URL) -> String? {
        return value.absoluteString
    }
}
