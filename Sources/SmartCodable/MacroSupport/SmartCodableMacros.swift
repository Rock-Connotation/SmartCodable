// MARK: - @SmartSubclass 宏声明

/// 向子类自动生成 Codable 继承代码的 member macro。
///
/// **WHAT**: 在编译期为 class 子类生成 4 个成员：
/// - `CodingKeys` — 只含子类新增属性
/// - `required init(from:)` — 先调 `super.init(from:)` 再解子类属性
/// - `override func encode(to:)` — 先调 `super.encode(to:)` 再编子类属性
/// - `required init()` — 仅当子类未定义空 init 时才生成
///
/// **WHY**: 手写 class 继承的 Codable 容易遗漏 `override`、漏调 `super`、
/// 对可选类型误用 `encode` 等方法。宏在编译期保证正确性。
///
/// **HOW**: `#externalMacro` 将实现委托给独立 target `SmartCodableMacros`，
/// 运行时层（SmartCodable）不依赖 SwiftSyntax，编译快且无宏依赖。
///
/// - SeeAlso: `Document/SmartCodable-Learning/03-Advanced-Features/Encoding-And-Macros.md`

@attached(member, names: named(init(from:)), named(encode(to:)), named(CodingKeys), named(init))
public macro SmartSubclass() = #externalMacro(module: "SmartCodableMacros", type: "SmartSubclassMacro")
