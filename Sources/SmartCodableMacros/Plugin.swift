// MARK: - Swift 编译器插件入口

/// SmartCodable 宏的编译器插件注册点。
///
/// **WHAT**: 遵循 `CompilerPlugin`，向 Swift 编译器暴露 `SmartSubclassMacro`。
/// `@main` 标记表示这是唯一的插件入口，编译器在编译期加载此 target。
///
/// **WHY**: Swift 宏必须在独立的可执行 target 中注册，通过 `CompilerPlugin` 协议
/// 向编译器声明提供哪些宏实现。这与运行时 target（SmartCodable）完全隔离，
/// 保证不引入 SwiftSyntax 运行时依赖。
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SmartCodablePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SmartSubclassMacro.self
    ]
}
