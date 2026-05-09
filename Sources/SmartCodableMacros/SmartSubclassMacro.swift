//
//  SmartSubclassMacro.swift
//  Mccc
//
//  Created by qixin on 2025/4/24.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros


// MARK: - @SmartSubclass 宏实现

/// 自动生成 class 继承场景下 Codable 代码的 MemberMacro 实现。
///
/// **WHAT**: 8 步处理管线——
/// 1. 断言宿主是 class（否则抛 MacroError）
/// 2. 断言有父类（否则抛 MacroError）
/// 3. extractProperties 提取所有存储属性（跳过 let/lazy/计算属性）
/// 4. 判断 public/open 决定生成成员的可见性
/// 5. generateCodingKeysEnum 生成 CodingKeys（仅含子类属性）
/// 6. generateInitFromDecoder 生成 required init(from:)（decodeIfPresent + 默认值回退）
/// 7. generateEncodeToEncoder 生成 override encode(to:)（可选用 encodeIfPresent）
/// 8. 无 required init() 时生成
///
/// **HOW (属性包装器识别)**: extractProperties 遍历 VarDecl 的 attributes，
/// 发现 @SmartAny 等包装器时将属性设为 isWrapped，accessName 变成 `_propertyName`，
/// 类型变成 `SmartAny<BaseType>`。容器按包装器类型解码，而不是按业务类型解码。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Encoding-And-Macros.md`
public struct SmartSubclassMacro: MemberMacro {
    private enum SynthesizedMemberAccess {
        case inheritedDefault
        case publicVisible

        var prefix: String {
            switch self {
            case .inheritedDefault:
                return ""
            case .publicVisible:
                return "public "
            }
        }
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansionImpl(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansionImpl(of: node, providingMembersOf: declaration, in: context)
    }

    /// 宏展开核心：8 步管线生成子类 Codable 代码。
    private static func expansionImpl(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // 1. 断言是 class
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw MacroError("@SmartSubclassMacro can only be applied to class declarations")
        }

        // 2. 断言有父类
        guard let inheritedNames = classDecl.inheritanceClause?.inheritedTypes,
              !inheritedNames.isEmpty else {
            throw MacroError("@SmartSubclassMacro requires the class to inherit from a parent class")
        }

        // 3. 提取存储属性（跳过 let/lazy/计算属性）
        let properties = try extractProperties(from: classDecl)
        // 4. 判断访问控制
        let memberAccess = synthesizedMemberAccess(for: classDecl)

        var members: [DeclSyntax] = []

        // 5. CodingKeys
        members.append(generateCodingKeysEnum(for: properties))
        // 6. required init(from:)
        members.append(generateInitFromDecoder(for: properties, access: memberAccess))
        // 7. override encode(to:)
        members.append(generateEncodeToEncoder(for: properties, access: memberAccess))

        // 8. required init() — 仅当不存在时生成
        if hasRequiredInitializer(classDecl) {
            return members
        } else {
            members.append(generateRequiredInit(access: memberAccess))
            return members
        }
    }
      
    /// 提取类的所有存储属性。跳过 let、lazy、计算属性，识别属性包装器。
    /// lazy 跳过原因：lazy 首次访问才初始化，解码写入破坏此语义。
    /// 属性包装器识别：遍历 attributes 找 @SmartAny 等标记，accessName 变 `_name`。
    private static func extractProperties(from classDecl: ClassDeclSyntax) throws -> [ModelMemberProperty] {
        var properties: [ModelMemberProperty] = []

        for member in classDecl.memberBlock.members {
            // 只处理 var 声明
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.text == "var" else {
                continue
            }

            // 跳过 lazy：解码赋值会绕过 lazy 的惰性初始化语义
            let isLazy = varDecl.modifiers.contains { $0.name.text == "lazy" }
            if isLazy {
                continue
            }

            for binding in varDecl.bindings {
                let identifier = try binding.getIdentifierPattern()
                let baseType = try binding.getVariableType()

                let name = identifier.identifier.text

                // 存储属性判定：无 accessor block 或 accessor 为空
                let isStored = binding.accessorBlock == nil ||
                               (binding.accessorBlock?.accessors.as(AccessorDeclListSyntax.self) == nil &&
                                binding.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self) == nil)

                if isStored {

                    // 属性包装器识别：遍历 attributes，将类型变为 Wrapper<BaseType>
                    var effectiveType = baseType
                    var isWrapped = false
                    let attrs = varDecl.attributes
                    if !attrs.isEmpty {
                        for attr in attrs {
                            if let attrSyntax = attr.as(AttributeSyntax.self),
                               let wrapperName = attrSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text {

                                if wrapperName == "objc" { continue }

                                effectiveType = "\(wrapperName)<\(baseType)>"
                                isWrapped = true
                                break
                            }
                        }
                    }

                    properties.append(ModelMemberProperty(name: name, type: effectiveType, isWrapped: isWrapped, isStored: true))
                }
            }
        }

        return properties
    }

    
    /// 生成 CodingKeys 枚举，仅含子类属性（父类属性由父类自己的 CodingKeys 处理）
    private static func generateCodingKeysEnum(for properties: [ModelMemberProperty]) -> DeclSyntax {
        let caseDeclarations = properties.map { property in
            "case \(property.codingKeyName)"
        }.joined(separator: "\n")
          
        return """
        enum CodingKeys: CodingKey {
            \(raw: caseDeclarations)
        }
        """
    }
      
    /// 生成 required init(from:)。先 super.init(from: decoder) 解码父类字段，
    /// 再用 decodeIfPresent + ?? default 模式解码子类属性（保证容错）。
    private static func generateInitFromDecoder(
        for properties: [ModelMemberProperty],
        access: SynthesizedMemberAccess
    ) -> DeclSyntax {
        let decodingStatements = properties.map { property in
            let propertyName = property.accessName
            let propertyType = property.type
              
            // 处理可选类型
            if propertyType.hasSuffix("?") {
                let baseType = propertyType.dropLast()
                return "self.\(propertyName) = try container.decodeIfPresent(\(baseType).self, forKey: .\(property.codingKeyName)) ?? self.\(propertyName)"
            } else {
                return "self.\(propertyName) = try container.decodeIfPresent(\(propertyType).self, forKey: .\(property.codingKeyName)) ?? self.\(propertyName)"
            }
        }.joined(separator: "\n")
          
        return """
        \(raw: access.prefix)required init(from decoder: Decoder) throws {
            try super.init(from: decoder)
              
            let container = try decoder.container(keyedBy: CodingKeys.self)
            \(raw: decodingStatements)
        }
        """
    }
      
    /// 生成 override func encode(to:)。先 super.encode(to:) 编码父类，
    /// 子类属性可选类型用 encodeIfPresent，非可选用 encode。
    private static func generateEncodeToEncoder(
        for properties: [ModelMemberProperty],
        access: SynthesizedMemberAccess
    ) -> DeclSyntax {
        let encodingStatements = properties.map { property in
            if property.type.hasSuffix("?") {
                return "try container.encodeIfPresent(\(property.accessName), forKey: .\(property.codingKeyName))"
            } else {
                return "try container.encode(\(property.accessName), forKey: .\(property.codingKeyName))"
            }
        }.joined(separator: "\n")
          
        return """
        \(raw: access.prefix)override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
              
            var container = encoder.container(keyedBy: CodingKeys.self)
            \(raw: encodingStatements)
        }
        """
    }
      

    /// 检查是否已有 required init()，避免重复生成
    private static func hasRequiredInitializer(_ classDecl: ClassDeclSyntax) -> Bool {
        for member in classDecl.memberBlock.members {
            if let initializer = member.decl.as(InitializerDeclSyntax.self),
               initializer.signature.parameterClause.parameters.isEmpty,
               initializer.modifiers.contains(where: { $0.name.text == "required" }) == true {
                return true
            }
        }
        return false
    }
    
    /// 生成 required init()，仅调 super.init()
    private static func generateRequiredInit(access: SynthesizedMemberAccess) -> DeclSyntax {
        return """
        \(raw: access.prefix)required init() {
            super.init()
        }
        """
    }

    private static func synthesizedMemberAccess(for classDecl: ClassDeclSyntax) -> SynthesizedMemberAccess {
        if classDecl.modifiers.contains(where: { modifier in
            let name = modifier.name.text
            return name == "public" || name == "open"
        }) {
            return .publicVisible
        }

        return .inheritedDefault
    }
}
