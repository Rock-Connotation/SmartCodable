////
////  PatternBindingSyntax+Extension.swift
////  SmartCodable
////
////  Created by qixin on 2025/5/14.
////
//
// MARK: - PatternBindingSyntax 扩展

/// 宏辅助：从 SwiftSyntax AST 中提取属性名和类型。
///
/// **类型推断**: 有显式类型注解（如 `var name: String`）直接返回类型字符串；
/// 无注解时通过初始值表达式推断（如 `var name = "hello"` → String）。
/// 数组/字典字面量强制要求显式类型注解（如 `var items: [Int] = []`），
/// 因为宏无法从空字面量推断泛型参数。
import SwiftSyntax

extension PatternBindingSyntax {

    /// 从 pattern 中提取变量名（IdentifierPatternSyntax）
    func getIdentifierPattern() throws -> IdentifierPatternSyntax {
        guard let identifier = pattern.as(IdentifierPatternSyntax.self) else {
            throw MacroError("Property '\(pattern.description)' must be an identifier (e.g., 'var name = ...').")
        }
        return identifier
    }

    /// 获取变量类型。有显式注解直接返回，无注解走 inferType 推断。
    func getVariableType() throws -> String {
        if let explicitType = self.typeAnnotation?.type.trimmedDescription {
            return explicitType
        }

        return try inferType()
    }

    /// 从初始值表达式推断类型：整数字面量→Int，浮点→Double，布尔→Bool，字符串→String。
    /// 支持 Date/UUID/Data 函数调用表达式。数组/字典字面量抛错要求显式注解。
    private func inferType() throws -> String {
        guard let expr = self.initializer?.value else {
            throw MacroError.requiresExplicitType(for: pattern.trimmedDescription, inferredFrom: "missing initializer")
        }

        if expr.is(IntegerLiteralExprSyntax.self) {
            return "Int"
        } else if expr.is(FloatLiteralExprSyntax.self) {
            return "Double"
        } else if expr.is(BooleanLiteralExprSyntax.self) {
            return "Bool"
        } else if expr.is(StringLiteralExprSyntax.self) {
            return "String"
        } else if expr.is(ArrayExprSyntax.self) {
            throw MacroError.requiresExplicitType(for: pattern.trimmedDescription, inferredFrom: "array literal")
        } else if expr.is(DictionaryExprSyntax.self) {
            throw MacroError.requiresExplicitType(for: pattern.trimmedDescription, inferredFrom: "dictionary literal")

        } else if let callExpr = expr.as(FunctionCallExprSyntax.self) {
            let called = callExpr.calledExpression.trimmed.description
            switch called {
            case "Date": return "Date"
            case "UUID": return "UUID"
            case "Data": return "Data"
            default: break
            }
        }

        throw MacroError.requiresExplicitType(for: pattern.trimmedDescription, inferredFrom: "unrecognized expression")
    }
}
