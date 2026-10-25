#!/usr/bin/env python3
"""Generate a native macOS/iOS Xcode project using only Python's standard library.

Run again after adding/removing Swift files. IDs and ordering remain deterministic.
The app links and embeds a separate VoiceMemosCore framework; it does not depend
on the Swift package executable. Full Xcode is required to build/test iOS targets.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "VoiceMemosReplica"
PROJECT = ROOT / f"{PROJECT_NAME}.xcodeproj"
OBJECTS: dict[str, dict] = {}


def identifier(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def add(key: str, isa: str, **fields) -> str:
    value = identifier(key)
    assert value not in OBJECTS, f"Duplicate project object: {key}"
    OBJECTS[value] = {"isa": isa, **fields}
    return value


def serialize(value, depth: int = 0) -> str:
    tab = "\t" * depth
    if isinstance(value, dict):
        lines = [f"{tab}\t{serialize(key)} = {serialize(item, depth + 1)};"
                 for key, item in value.items()]
        return "{\n" + "\n".join(lines) + f"\n{tab}" + "}"
    if isinstance(value, list):
        lines = [f"{tab}\t{serialize(item, depth + 1)}," for item in value]
        return "(\n" + "\n".join(lines) + f"\n{tab})"
    if isinstance(value, int):
        return str(value)
    text = str(value)
    if re.fullmatch(r"[A-Za-z0-9_./]+", text):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def file_reference(path: Path, relative_to: Path, file_type: str) -> str:
    return add(
        f"file:{path.relative_to(ROOT).as_posix()}",
        "PBXFileReference",
        lastKnownFileType=file_type,
        path=path.relative_to(relative_to).as_posix(),
        sourceTree="<group>",
    )


def source_group(directory: str) -> tuple[str, list[str]]:
    folder = ROOT / directory
    files = sorted(folder.rglob("*.swift"))
    if not files:
        raise SystemExit(f"No Swift source files found in {folder}")
    references = [file_reference(path, folder, "sourcecode.swift") for path in files]
    group = add(f"group:{directory}", "PBXGroup", children=references,
                path=directory, sourceTree="<group>")
    return group, references


def source_phase(target: str, references: list[str]) -> str:
    builds = [add(f"source-build:{target}:{ref}", "PBXBuildFile", fileRef=ref)
              for ref in references]
    return add(f"sources:{target}", "PBXSourcesBuildPhase",
               buildActionMask=2147483647, files=builds,
               runOnlyForDeploymentPostprocessing=0)


def framework_phase(target: str, framework: str | None = None) -> str:
    builds = []
    if framework:
        builds.append(add(f"framework-build:{target}", "PBXBuildFile", fileRef=framework))
    return add(f"frameworks:{target}", "PBXFrameworksBuildPhase",
               buildActionMask=2147483647, files=builds,
               runOnlyForDeploymentPostprocessing=0)


def resource_phase(target: str, references: list[str] | None = None) -> str:
    builds = [add(f"resource-build:{target}:{ref}", "PBXBuildFile", fileRef=ref)
              for ref in references or []]
    return add(f"resources:{target}", "PBXResourcesBuildPhase",
               buildActionMask=2147483647, files=builds,
               runOnlyForDeploymentPostprocessing=0)


def configurations(target: str, common: dict, debug: dict | None = None,
                   release: dict | None = None) -> str:
    ids = []
    for name, overrides in [("Debug", debug), ("Release", release)]:
        settings = dict(common)
        settings.update(overrides or {})
        ids.append(add(f"configuration:{target}:{name}", "XCBuildConfiguration",
                       buildSettings=settings, name=name))
    return add(f"configuration-list:{target}", "XCConfigurationList",
               buildConfigurations=ids, defaultConfigurationIsVisible=0,
               defaultConfigurationName="Release")


def dependency(owner: str, target: str, name: str) -> str:
    proxy = add(f"proxy:{owner}:{target}", "PBXContainerItemProxy",
                containerPortal=identifier("project"), proxyType=1,
                remoteGlobalIDString=target, remoteInfo=name)
    return add(f"dependency:{owner}:{target}", "PBXTargetDependency",
               target=target, targetProxy=proxy)


app_group, app_sources = source_group("Sources/VoiceMemosApp")
core_group, core_sources = source_group("Sources/VoiceMemosCore")
tests_group, test_sources = source_group("Tests/VoiceMemosCoreTests")

resource_references = []
bundled_resources = []
resource_folder = ROOT / "Resources"
file_types = {".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements",
              ".xcassets": "folder.assetcatalog", ".icns": "image.icns",
              ".png": "image.png", ".pdf": "image.pdf"}
for path in sorted(resource_folder.iterdir()):
    if path.name.startswith("."):
        continue
    kind = file_types.get(path.suffix, "folder" if path.is_dir() else "file")
    ref = file_reference(path, resource_folder, kind)
    resource_references.append(ref)
    # actool generates the Mac AppIcon.icns. The pre-rendered copy is only for
    # the Command Line Tools bundler, which has no actool.
    if path.name not in ("Info.plist", "AppIcon.icns") and path.suffix != ".entitlements":
        bundled_resources.append(ref)
resources_group = add("group:Resources", "PBXGroup", children=resource_references,
                      path="Resources", sourceTree="<group>")
script_references = [
    file_reference(ROOT / "Scripts" / name, ROOT / "Scripts", kind)
    for name, kind in [("build-macos.sh", "text.script.sh"),
                       ("generate-xcode-project.py", "text.script.python")]
]
scripts_group = add("group:Scripts", "PBXGroup", children=script_references,
                    path="Scripts", sourceTree="<group>")

app_product = add("product:app", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex=0, path="Voice Memos Replica.app", sourceTree="BUILT_PRODUCTS_DIR")
core_product = add("product:core", "PBXFileReference", explicitFileType="wrapper.framework",
                   includeInIndex=0, path="VoiceMemosCore.framework", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("product:tests", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex=0, path="VoiceMemosCoreTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add("group:Products", "PBXGroup",
                     children=[app_product, core_product, test_product],
                     name="Products", sourceTree="<group>")
main_group = add("group:main", "PBXGroup", sourceTree="<group>",
                 children=[app_group, core_group, tests_group, resources_group,
                           scripts_group, products_group])

project_configuration = configurations("project", {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator macosx",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "SWIFT_VERSION": "5.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "TARGETED_DEVICE_FAMILY": "1,2",
}, debug={
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}, release={
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})

signing = {
    "CODE_SIGN_STYLE": "Automatic",
    "CODE_SIGN_IDENTITY[sdk=macosx*]": "-",
    "CURRENT_PROJECT_VERSION": "1",
    "MARKETING_VERSION": "0.1.0",
}
app_configuration = configurations("app", {
    **signing,
    "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]": "Resources/VoiceMemos.entitlements",
    "ENABLE_HARDENED_RUNTIME": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "Resources/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.recreation.VoiceMemos",
    "PRODUCT_MODULE_NAME": "VoiceMemosApp",
    "PRODUCT_NAME": "Voice Memos Replica",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
})
core_configuration = configurations("core", {
    **signing,
    "DEFINES_MODULE": "YES",
    "DYLIB_COMPATIBILITY_VERSION": "1",
    "DYLIB_CURRENT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../Frameworks @loader_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.recreation.VoiceMemos.Core",
    "PRODUCT_NAME": "VoiceMemosCore",
    "SKIP_INSTALL": "YES",
})
test_configuration = configurations("tests", {
    **signing,
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../Frameworks @loader_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.recreation.VoiceMemos.CoreTests",
    "PRODUCT_NAME": "VoiceMemosCoreTests",
    "SKIP_INSTALL": "YES",
    "TEST_HOST[sdk=macosx*]": "$(BUILT_PRODUCTS_DIR)/Voice Memos Replica.app/Contents/MacOS/Voice Memos Replica",
    "TEST_HOST[sdk=iphone*]": "$(BUILT_PRODUCTS_DIR)/Voice Memos Replica.app/Voice Memos Replica",
})

core_target = add("target:core", "PBXNativeTarget",
                  buildConfigurationList=core_configuration,
                  buildPhases=[source_phase("core", core_sources), framework_phase("core"),
                               resource_phase("core")],
                  buildRules=[], dependencies=[], name="VoiceMemosCore",
                  productName="VoiceMemosCore", productReference=core_product,
                  productType="com.apple.product-type.framework")
embed_build = add("embed-build:core", "PBXBuildFile", fileRef=core_product,
                  settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]})
embed_phase = add("embed-phase:app", "PBXCopyFilesBuildPhase",
                  buildActionMask=2147483647, dstPath="", dstSubfolderSpec=10,
                  files=[embed_build], name="Embed Frameworks",
                  runOnlyForDeploymentPostprocessing=0)
app_target = add("target:app", "PBXNativeTarget",
                 buildConfigurationList=app_configuration,
                 buildPhases=[source_phase("app", app_sources),
                              framework_phase("app", core_product),
                              resource_phase("app", bundled_resources), embed_phase],
                 buildRules=[], dependencies=[dependency("app", core_target, "VoiceMemosCore")],
                 name="VoiceMemosReplica", productName="Voice Memos Replica",
                 productReference=app_product, productType="com.apple.product-type.application")
test_target = add("target:tests", "PBXNativeTarget",
                  buildConfigurationList=test_configuration,
                  buildPhases=[source_phase("tests", test_sources),
                               framework_phase("tests", core_product), resource_phase("tests")],
                  buildRules=[], dependencies=[dependency("tests", app_target, "VoiceMemosReplica"),
                                               dependency("tests", core_target, "VoiceMemosCore")],
                  name="VoiceMemosCoreTests", productName="VoiceMemosCoreTests",
                  productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
project_id = add("project", "PBXProject", attributes={
    "BuildIndependentTargetsInParallel": "YES",
    "LastSwiftUpdateCheck": "1600",
    "LastUpgradeCheck": "1600",
    "TargetAttributes": {
        app_target: {
            "CreatedOnToolsVersion": "16.0",
            "SystemCapabilities": {
                "com.apple.Sandbox": {"enabled": 1},
                "com.apple.BackgroundModes": {"enabled": 1},
            },
        },
        core_target: {"CreatedOnToolsVersion": "16.0"},
        test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target},
    },
}, buildConfigurationList=project_configuration,
    compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
    knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products_group,
    projectDirPath="", projectRoot="", targets=[app_target, core_target, test_target])

project_document = {
    "archiveVersion": 1,
    "classes": {},
    "objectVersion": 56,
    "objects": OBJECTS,
    "rootObject": project_id,
}
PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text(
    "// !$*UTF8*$!\n" + serialize(project_document) + "\n", encoding="utf-8")

workspace = PROJECT / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n',
    encoding="utf-8")


def buildable(parent, target_id: str, name: str, product: str):
    return ET.SubElement(parent, "BuildableReference", {
        "BuildableIdentifier": "primary", "BlueprintIdentifier": target_id,
        "BuildableName": product, "BlueprintName": name,
        "ReferencedContainer": f"container:{PROJECT_NAME}.xcodeproj",
    })


scheme = ET.Element("Scheme", {"LastUpgradeVersion": "1600", "version": "1.3"})
build = ET.SubElement(scheme, "BuildAction",
                      {"parallelizeBuildables": "YES", "buildImplicitDependencies": "YES"})
entries = ET.SubElement(build, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", {
    "buildForTesting": "YES", "buildForRunning": "YES", "buildForProfiling": "YES",
    "buildForArchiving": "YES", "buildForAnalyzing": "YES",
})
buildable(entry, app_target, "VoiceMemosReplica", "Voice Memos Replica.app")
entry = ET.SubElement(entries, "BuildActionEntry", {
    "buildForTesting": "YES", "buildForRunning": "NO", "buildForProfiling": "NO",
    "buildForArchiving": "NO", "buildForAnalyzing": "YES",
})
buildable(entry, test_target, "VoiceMemosCoreTests", "VoiceMemosCoreTests.xctest")
test = ET.SubElement(scheme, "TestAction", {
    "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
    "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB",
    "shouldUseLaunchSchemeArgsEnv": "YES",
})
testables = ET.SubElement(test, "Testables")
testable = ET.SubElement(testables, "TestableReference", {"skipped": "NO", "parallelizable": "NO"})
buildable(testable, test_target, "VoiceMemosCoreTests", "VoiceMemosCoreTests.xctest")
expansion = ET.SubElement(test, "MacroExpansion")
buildable(expansion, app_target, "VoiceMemosReplica", "Voice Memos Replica.app")
launch = ET.SubElement(scheme, "LaunchAction", {
    "buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
    "selectedLauncherIdentifier": "Xcode.IDEFoundation.Launcher.LLDB", "launchStyle": "0",
    "useCustomWorkingDirectory": "NO", "ignoresPersistentStateOnLaunch": "NO",
    "debugDocumentVersioning": "YES", "debugServiceExtension": "internal",
    "allowLocationSimulation": "YES",
})
runnable = ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"})
buildable(runnable, app_target, "VoiceMemosReplica", "Voice Memos Replica.app")
profile = ET.SubElement(scheme, "ProfileAction", {
    "buildConfiguration": "Release", "shouldUseLaunchSchemeArgsEnv": "YES",
    "savedToolIdentifier": "", "useCustomWorkingDirectory": "NO", "debugDocumentVersioning": "YES",
})
runnable = ET.SubElement(profile, "BuildableProductRunnable", {"runnableDebuggingMode": "0"})
buildable(runnable, app_target, "VoiceMemosReplica", "Voice Memos Replica.app")
ET.SubElement(scheme, "AnalyzeAction", {"buildConfiguration": "Debug"})
ET.SubElement(scheme, "ArchiveAction", {"buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"})
ET.indent(scheme, space="   ")
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_dir / f"{PROJECT_NAME}.xcscheme",
                             encoding="UTF-8", xml_declaration=True)
print(f"Generated {PROJECT}")
print(f"Sources: {len(app_sources)} app, {len(core_sources)} core, {len(test_sources)} tests.")
