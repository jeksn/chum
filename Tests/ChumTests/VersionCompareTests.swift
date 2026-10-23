import Foundation
import ChumCore

enum VersionCompareTests {
    static func runAll(_ t: TestRunner) {
        t.run("VersionCompare.majorBump") {
            t.check(VersionCompare.isNewer("v0.2.0", than: "0.1.0"), "0.2.0 should be newer than 0.1.0")
            t.check(!VersionCompare.isNewer("0.1.0", than: "v0.2.0"), "0.1.0 should not be newer than 0.2.0")
        }

        t.run("VersionCompare.equal") {
            t.check(!VersionCompare.isNewer("v0.1.0", than: "0.1.0"), "same version is not newer")
            t.check(!VersionCompare.isNewer("0.1.0", than: "0.1.0"), "same version is not newer")
            t.check(VersionCompare.compare("v0.1.0", "0.1.0") == 0, "v prefix should be ignored")
        }

        t.run("VersionCompare.patchBump") {
            t.check(VersionCompare.isNewer("0.1.1", than: "0.1.0"), "patch bump is newer")
        }

        t.run("VersionCompare.numericNotLexicographic") {
            t.check(VersionCompare.isNewer("0.10.0", than: "0.9.0"), "0.10.0 should be newer than 0.9.0")
t.check(!VersionCompare.isNewer("0.9.0", than: "0.10.0"), "0.9.0 should not be newer than 0.10.0")
        }

        t.run("VersionCompare.missingComponents") {
            t.check(!VersionCompare.isNewer("0.1", than: "0.1.0"), "0.1 equals 0.1.0")
            t.check(VersionCompare.isNewer("0.2", than: "0.1.9"), "0.2 is newer than 0.1.9")
        }

        t.run("VersionCompare.suffixesIgnored") {
            t.check(VersionCompare.isNewer("0.2.0-rc1", than: "0.1.0"), "numeric prefix is compared")
t.check(!VersionCompare.isNewer("0.1.0-beta", than: "0.1.0"), "same numeric prefix is not newer")
        }
    }
}
