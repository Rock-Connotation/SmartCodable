//
//  MacroError.swift
//  SmartCodable
//
//  Created by qixin on 2025/5/14.
//

// MARK: - 宏编译期错误类型

/// SmartCodable 宏的编译期错误，遵循 CustomStringConvertible 使诊断信息可读。
/// 宏展开阶段无法抛运行时 Error，只能用此类型生成编译器诊断（红色错误/黄色警告）。
import Foundation

struct MacroError: CustomStringConvertible, Error {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var description: String {
        text
    }
}


extension MacroError {
    /// 属性缺少显式类型注解时的错误（如 `var name` 没有 `: String`）
    static func requiresExplicitType(for name: String, inferredFrom reason: String) -> MacroError {
        .init("Property '\(name)' requires an explicit type annotation; type cannot be inferred from \(reason) ")
    }
}
