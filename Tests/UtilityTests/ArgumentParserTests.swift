/*
 This source file is part of the Swift.org open source project

 Copyright 2016 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Basic
import Utility

enum SampleEnum: String {
    case Foo
    case Bar
}

extension SampleEnum: StringEnumArgument {}

struct Options {
    struct Flags {
        let xswiftc: [String]
        let xlinker: [String]
    }
    var branch: String?
    var package: String!
    var verbose: Bool = false
    var xld = [String]()
    var flags = Flags(xswiftc: [], xlinker: [])
}

class ArgumentParserTests: XCTestCase {

    func testBasics() throws {
        let parser = ArgumentParser(commandName:"SomeBinary", usage: "sample parser", overview: "Sample overview")

        let package = parser.add(positional: "package name of the year", kind: String.self, usage: "The name of the package")
        let revision = parser.add(option: "--revision", kind: String.self, usage: "The revision")
        let branch = parser.add(option: "--branch", shortName:"-b", kind: String.self, usage: "The branch to checkout")
        let xld = parser.add(option: "-Xld", kind: Array<String>.self, usage: "The xld arguments")
        let verbosity = parser.add(option: "--verbose", kind: Int.self, usage: "The verbosity level")
        let noFly = parser.add(option: "--no-fly", kind: Bool.self, usage: "If should fly")
        let sampleEnum = parser.add(positional: "enum", kind: SampleEnum.self)

        let args = try parser.parse(["Foo", "-b", "bugfix", "--verbose", "2", "-Xld", "foo", "-Xld", "bar",  "--no-fly", "Bar"])

        XCTAssertEqual(args.get(package), "Foo")
        XCTAssert(args.get(revision) == nil)
        XCTAssertEqual(args.get(branch), "bugfix")
        XCTAssertEqual(args.get(xld) ?? [], ["foo", "bar"])
        XCTAssertEqual(args.get(verbosity), 2)
        XCTAssertEqual(args.get(noFly), true)
        XCTAssertEqual(args.get(sampleEnum), .Bar)

        let stream = BufferedOutputByteStream()
        parser.printUsage(on: stream)
        let usage = stream.bytes.asString!
        XCTAssert(usage.contains("OVERVIEW: Sample overview"))
        XCTAssert(usage.contains("USAGE: SomeBinary sample parser"))
        XCTAssert(usage.contains("  package name of the year\n                          The name of the package"))
        XCTAssert(usage.contains(" -Xld                    The xld arguments"))
    }

    func testErrors() throws {
        let parser = ArgumentParser(usage: "sample", overview: "sample")
        _ = parser.add(positional: "package", kind: String.self, usage: "The name of the package")
        _ = parser.add(option: "--verbosity", kind: Int.self, usage: "The revision")

        do {
            _ = try parser.parse()
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedArguments(let args) {
            XCTAssertEqual(args, ["package"])
        }

        do {
            _ = try parser.parse(["foo", "bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unexpectedArgument(let arg) {
            XCTAssertEqual(arg, "bar")
        }

        do {
            _ = try parser.parse(["foo", "--bar"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.unknown(let option) {
            XCTAssertEqual(option, "--bar")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.expectedValue(let option) {
            XCTAssertEqual(option, "--verbosity")
        }

        do {
            _ = try parser.parse(["foo", "--verbosity", "yes"])
            XCTFail("unexpected success")
        } catch ArgumentParserError.typeMismatch(let error) {
            XCTAssertEqual(error, "yes is not convertible to Int")
        }
    }

    func testOptions() throws {
        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")
        let binder = ArgumentBinder<Options>()

        binder.bind(
            positional: parser.add(positional: "package", kind: String.self),
            to: { $0.package = $1 })

        binder.bind(
            option: parser.add(option: "--branch", shortName:"-b", kind: String.self),
            to: { $0.branch = $1 })

        binder.bind(
            option: parser.add(option: "--verbose", kind: Bool.self),
            to: { $0.verbose = $1 })

        binder.bindArray(
            option: parser.add(option: "-Xld", kind: Array<String>.self),
            to: { $0.xld = $1 })

        binder.bindArray(
            parser.add(option: "-xlinker", kind: [String].self),
            parser.add(option: "-xswiftc", kind: [String].self),
            to: { $0.flags = Options.Flags(xswiftc: $2, xlinker: $1) })

        let result = try parser.parse(["MyPkg", "-b", "bugfix", "--verbose", "-Xld", "foo", "-Xld", "bar", "-xlinker", "a", "-xswiftc", "b"])

        var options = Options()
        binder.fill(result, into: &options)

        XCTAssertEqual(options.branch, "bugfix")
        XCTAssertEqual(options.package, "MyPkg")
        XCTAssertEqual(options.verbose, true)
        XCTAssertEqual(options.xld, ["foo", "bar"])
        XCTAssertEqual(options.flags.xlinker, ["a"])
        XCTAssertEqual(options.flags.xswiftc, ["b"])
    }

    func testSubparser() throws {
        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")
        let foo = parser.add(option: "--foo", kind: String.self, usage: "The foo option")

        let parserA = parser.add(subparser: "a", overview: "A!")
        let branchOption = parserA.add(option: "--branch", kind: String.self)

        let parserB = parser.add(subparser: "b", overview: "B!")
        let noFlyOption = parserB.add(option: "--no-fly", kind: Bool.self)

        var args = try parser.parse(["--foo", "foo", "a", "--branch", "bugfix"])
        XCTAssertEqual(args.get(foo), "foo")
        XCTAssertEqual(args.get(branchOption), "bugfix")
        XCTAssertEqual(args.get(noFlyOption), nil)
        XCTAssertEqual(args.subparser(parser), "a")

        args = try parser.parse(["--foo", "foo", "b", "--no-fly"])

        XCTAssertEqual(args.get(foo), "foo")
        XCTAssertEqual(args.get(branchOption), nil)
        XCTAssertEqual(args.get(noFlyOption), true)
        XCTAssertEqual(args.subparser(parser), "b")

        do {
            args = try parser.parse(["c"])
        } catch ArgumentParserError.expectedArguments(let args) {
            XCTAssertEqual(args.sorted(), ["a", "b"])
        }

        do {
            args = try parser.parse(["--foo", "foo", "b", "--no-fly", "--branch", "bugfix"])
        } catch ArgumentParserError.unknown(let arg) {
            XCTAssertEqual(arg, "--branch")
        }

        do {
            args = try parser.parse(["--foo", "foo", "a", "--branch", "bugfix", "--no-fly"])
        } catch ArgumentParserError.unknown(let arg) {
            XCTAssertEqual(arg, "--no-fly")
        }

        do {
            args = try parser.parse(["a", "--branch", "bugfix", "--foo"])
        } catch ArgumentParserError.unknown(let arg) {
            XCTAssertEqual(arg, "--foo")
        }
    }

    func testSubsubparser() throws {
        let parser = ArgumentParser(usage: "sample parser", overview: "Sample overview")

        let parserA = parser.add(subparser: "foo", overview: "A!")
        let branchOption = parserA.add(option: "--branch", kind: String.self)

        _ = parserA.add(subparser: "bar", overview: "Bar!")
        let parserAB = parserA.add(subparser: "baz", overview: "Baz!")
        let noFlyOption = parserAB.add(option: "--no-fly", kind: Bool.self)

        var args = try parser.parse(["foo", "--branch", "bugfix", "baz", "--no-fly"])

        XCTAssertEqual(args.get(branchOption), "bugfix")
        XCTAssertEqual(args.get(noFlyOption), true)
        XCTAssertEqual(args.subparser(parserA), "baz")
        XCTAssertEqual(args.subparser(parser), "foo")

        args = try parser.parse(["foo", "bar"])

        XCTAssertEqual(args.get(branchOption), nil)
        XCTAssertEqual(args.get(noFlyOption), nil)
        XCTAssertEqual(args.subparser(parserA), "bar")
        XCTAssertEqual(args.subparser(parser), "foo")

        do {
            args = try parser.parse(["c"])
        } catch ArgumentParserError.expectedArguments(let args) {
            XCTAssertEqual(args.sorted(), ["foo"])
        }

        do {
            args = try parser.parse(["foo", "--branch", "b", "foo"])
        } catch ArgumentParserError.expectedArguments(let args) {
            XCTAssertEqual(args.sorted(), ["bar", "baz"])
        }

        do {
            args = try parser.parse(["foo", "bar", "--no-fly"])
        } catch ArgumentParserError.unknown(let arg) {
            XCTAssertEqual(arg, "--no-fly")
        }
    }

    static var allTests = [
        ("testBasics", testBasics),
        ("testErrors", testErrors),
        ("testOptions", testOptions),
        ("testSubparser", testSubparser),
        ("testSubsubparser", testSubsubparser),
    ]
}