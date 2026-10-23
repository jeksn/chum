import ChumCore
import Foundation

struct TextTransformTests {
    static func runAll(_ t: TestRunner) {
        let input = "hello WORLD foo_bar"

        t.run("TextTransform.basicCases") {
            t.check(TextTransform.uppercase.apply(to: input) == "HELLO WORLD FOO_BAR", "uppercase")
            t.check(TextTransform.lowercase.apply(to: input) == "hello world foo_bar", "lowercase")
            t.check(TextTransform.titleCase.apply(to: "hello WORLD") == "Hello World", "title case")
            t.check(TextTransform.titleCase.apply(to: "  hello   world.  ") == "  Hello   World.  ", "title case preserves separators")
        }

        t.run("TextTransform.sentenceCase") {
            t.check(TextTransform.sentenceCase.apply(to: "HELLO WORLD. foo BAR? BAZ") == "Hello world. Foo bar? Baz", "sentences")
            t.check(TextTransform.sentenceCase.apply(to: "3.14 IS a NUMBER") == "3.14 is a number", "decimals stay lowercase")
            t.check(TextTransform.sentenceCase.apply(to: "one\ntwo") == "One\nTwo", "newline starts a sentence")
        }

        t.run("TextTransform.programmingCases") {
            let mixed = "hello world"
            t.check(TextTransform.camelCase.apply(to: mixed) == "helloWorld", "camel")
            t.check(TextTransform.pascalCase.apply(to: mixed) == "HelloWorld", "pascal")
            t.check(TextTransform.snakeCase.apply(to: mixed) == "hello_world", "snake")
            t.check(TextTransform.kebabCase.apply(to: mixed) == "hello-world", "kebab")
            t.check(TextTransform.constantCase.apply(to: mixed) == "HELLO_WORLD", "constant")

            // Word extraction across shapes: separators, humps, digits.
            t.check(TextTransform.snakeCase.apply(to: "fooBarBaz") == "foo_bar_baz", "camel input")
            t.check(TextTransform.snakeCase.apply(to: "error 404-handled") == "error_404_handled", "mixed separators and digits")
            t.check(TextTransform.snakeCase.apply(to: "XMLHttpRequest") == "xml_http_request", "acronym input")
            t.check(TextTransform.snakeCase.apply(to: "already_snake_case") == "already_snake_case", "already snake")
            t.check(TextTransform.camelCase.apply(to: "ALREADY_CONST_CASE") == "alreadyConstCase", "const input")
        }

        t.run("TextTransform.toggleCase") {
            t.check(TextTransform.toggleCase.apply(to: "Hello World") == "hELLO wORLD", "swap")
            t.check(TextTransform.toggleCase.apply(to: "123 !!") == "123 !!", "non-letters unchanged")
        }

        t.run("TextTransform.edgeCases") {
            t.check(TextTransform.camelCase.apply(to: "") == "", "empty")
            t.check(TextTransform.snakeCase.apply(to: "   ") == "", "whitespace only")
            t.check(TextTransform.uppercase.apply(to: "über ångström") == "ÜBER ÅNGSTRÖM", "non-ascii upper")
        }
    }
}
