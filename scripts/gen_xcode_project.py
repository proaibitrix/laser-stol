#!/usr/bin/env python3
"""Generate LaserStol.xcodeproj and macOS app icons (Xcode 14.2 / objectVersion 56)."""
from __future__ import annotations

import hashlib
import struct
import zlib
from pathlib import Path

ROOT = Path("/workspace/LaserStol")
APP = ROOT / "LaserStol"
TESTS = ROOT / "LaserStolTests"
PROJ = ROOT / "LaserStol.xcodeproj"


def hid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def png_rgba(width: int, height: int, pixels: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b""
    stride = width * 4
    for y in range(height):
        raw += b"\x00" + pixels[y * stride : (y + 1) * stride]
    return b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)),
            chunk(b"IDAT", zlib.compress(raw, 9)),
            chunk(b"IEND", b""),
        ]
    )


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def icon_pixels(size: int) -> bytes:
    cream = (250, 246, 239)
    terra = (197, 116, 93)
    wood = (216, 176, 128)
    ink = (44, 37, 32)
    out = bytearray(size * size * 4)
    r = size / 2
    for y in range(size):
        for x in range(size):
            nx = (x + 0.5) / size
            ny = (y + 0.5) / size
            dx = nx - 0.5
            dy = ny - 0.5
            i = (y * size + x) * 4
            # rounded square alpha
            ax = min(nx, 1 - nx)
            ay = min(ny, 1 - ny)
            rad = 0.16
            if ax < 0 or ay < 0:
                a = 0
            elif ax < rad and ay < rad:
                d = ((rad - ax) ** 2 + (rad - ay) ** 2) ** 0.5
                a = 255 if d <= rad else 0
            else:
                a = 255
            if a == 0:
                out[i : i + 4] = b"\x00\x00\x00\x00"
                continue
            # wood plaque
            plaque = 0.18 < nx < 0.82 and 0.30 < ny < 0.78
            col = cream
            if plaque:
                g = 0.08 * ((x * 3 + y) % 7) / 7
                col = (
                    int(wood[0] * (1 - g)),
                    int(wood[1] * (1 - g)),
                    int(wood[2] * (1 - g)),
                )
                # monogram-like A
                if abs((nx - 0.42) * 1.6 + (0.72 - ny)) < 0.035 and 0.38 < ny < 0.70:
                    col = ink
                if abs((nx - 0.58) * 1.6 - (0.72 - ny)) < 0.035 and 0.38 < ny < 0.70:
                    col = ink
            # laser head
            if 0.46 < nx < 0.54 and 0.12 < ny < 0.30:
                col = terra
            if abs(nx - 0.5) < 0.012 and 0.28 < ny < 0.42:
                col = terra
            out[i] = col[0]
            out[i + 1] = col[1]
            out[i + 2] = col[2]
            out[i + 3] = a
    return bytes(out)


def write_icons() -> None:
    icon_dir = APP / "Assets.xcassets" / "AppIcon.appiconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    specs = [
        ("icon_16.png", 16, "16x16", "1x"),
        ("icon_16@2x.png", 32, "16x16", "2x"),
        ("icon_32.png", 32, "32x32", "1x"),
        ("icon_32@2x.png", 64, "32x32", "2x"),
        ("icon_128.png", 128, "128x128", "1x"),
        ("icon_128@2x.png", 256, "128x128", "2x"),
        ("icon_256.png", 256, "256x256", "1x"),
        ("icon_256@2x.png", 512, "256x256", "2x"),
        ("icon_512.png", 512, "512x512", "1x"),
        ("icon_512@2x.png", 1024, "512x512", "2x"),
    ]
    images = []
    for name, px, idiom_size, scale in specs:
        (icon_dir / name).write_bytes(png_rgba(px, px, icon_pixels(px)))
        images.append(
            f"""    {{
      "filename" : "{name}",
      "idiom" : "mac",
      "scale" : "{scale}",
      "size" : "{idiom_size}"
    }}"""
        )
    (icon_dir / "Contents.json").write_text(
        "{\n  \"images\" : [\n" + ",\n".join(images) + "\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n",
        encoding="utf-8",
    )


def pbx() -> str:
    sources = sorted(p.relative_to(APP) for p in APP.rglob("*.swift"))
    test_sources = sorted(p.relative_to(TESTS) for p in TESTS.rglob("*.swift"))

    ids = {
        "project": hid("project"),
        "app_target": hid("app_target"),
        "test_target": hid("test_target"),
        "app_sources": hid("app_sources"),
        "test_sources": hid("test_sources"),
        "app_resources": hid("app_resources"),
        "frameworks": hid("frameworks_phase"),
        "test_frameworks": hid("test_frameworks_phase"),
        "app_group": hid("group_app"),
        "test_group": hid("group_tests"),
        "products": hid("group_products"),
        "main_group": hid("group_main"),
        "src_group": hid("group_src"),
        "frameworks_group": hid("group_fw"),
        "app_product": hid("product_app"),
        "test_product": hid("product_tests"),
        "assets_ref": hid("ref_assets"),
        "assets_build": hid("build_assets"),
        "plist_ref": hid("ref_plist"),
        "ent_ref": hid("ref_ent"),
        "iokit_ref": hid("ref_iokit"),
        "iokit_build": hid("build_iokit"),
        "proj_debug": hid("xc_proj_debug"),
        "proj_release": hid("xc_proj_release"),
        "app_debug": hid("xc_app_debug"),
        "app_release": hid("xc_app_release"),
        "test_debug": hid("xc_test_debug"),
        "test_release": hid("xc_test_release"),
        "proj_configs": hid("list_proj"),
        "app_configs": hid("list_app"),
        "test_configs": hid("list_test"),
        "app_proxy": hid("proxy_app"),
        "test_dep": hid("dep_tests_app"),
    }

    file_refs = []
    build_files = []
    source_builds = []
    test_builds = []
    group_children = []

    for rel in sources:
        key = f"src:{rel}"
        ref = hid(f"ref:{key}")
        build = hid(f"build:{key}")
        ids[key] = ref
        file_refs.append(
            f"\t\t{ref} /* {rel.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {rel.name}; sourceTree = \"<group>\"; }};"
        )
        build_files.append(
            f"\t\t{build} /* {rel.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {rel.name} */; }};"
        )
        source_builds.append(f"\t\t\t\t{build} /* {rel.name} in Sources */,")

    for rel in test_sources:
        key = f"test:{rel}"
        ref = hid(f"ref:{key}")
        build = hid(f"build:{key}")
        file_refs.append(
            f"\t\t{ref} /* {rel.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {rel.name}; sourceTree = \"<group>\"; }};"
        )
        build_files.append(
            f"\t\t{build} /* {rel.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {rel.name} */; }};"
        )
        test_builds.append(f"\t\t\t\t{build} /* {rel.name} in Sources */,")
        ids[key] = ref

    # Groups by folder (first component)
    folders: dict[str, list[tuple[str, str]]] = {}
    for rel in sources:
        folder = str(rel.parent) if rel.parent != Path(".") else "AppRoot"
        folders.setdefault(folder, []).append((rel.name, hid(f"ref:src:{rel}")))

    folder_groups = []
    folder_ids = []
    for folder, children in sorted(folders.items()):
        gid = hid(f"group:{folder}")
        folder_ids.append((folder, gid))
        child_lines = "\n".join(f"\t\t\t\t{cid} /* {name} */," for name, cid in children)
        path_line = f'\n\t\t\tpath = "{folder}";' if folder != "AppRoot" else ""
        folder_groups.append(
            f"\t\t{gid} /* {folder} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{child_lines}\n\t\t\t);{path_line}\n\t\t\tsourceTree = \"<group>\";\n\t\t}};"
        )

    app_children = "\n".join(f"\t\t\t\t{gid} /* {folder} */," for folder, gid in folder_ids)
    app_children += f"\n\t\t\t\t{ids['assets_ref']} /* Assets.xcassets */,"
    app_children += f"\n\t\t\t\t{ids['plist_ref']} /* Info.plist */,"
    app_children += f"\n\t\t\t\t{ids['ent_ref']} /* LaserStol.entitlements */,"

    test_child = "\n".join(
        f"\t\t\t\t{hid(f'ref:test:{rel}')} /* {rel.name} */," for rel in test_sources
    )

    file_refs.extend(
        [
            f"\t\t{ids['app_product']} /* LaserStol.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LaserStol.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
            f"\t\t{ids['test_product']} /* LaserStolTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LaserStolTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};",
            f"\t\t{ids['assets_ref']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};",
            f"\t\t{ids['plist_ref']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};",
            f"\t\t{ids['ent_ref']} /* LaserStol.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = LaserStol.entitlements; sourceTree = \"<group>\"; }};",
            f"\t\t{ids['iokit_ref']} /* IOKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = IOKit.framework; path = System/Library/Frameworks/IOKit.framework; sourceTree = SDKROOT; }};",
        ]
    )
    build_files.append(
        f"\t\t{ids['assets_build']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['assets_ref']} /* Assets.xcassets */; }};"
    )
    build_files.append(
        f"\t\t{ids['iokit_build']} /* IOKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {ids['iokit_ref']} /* IOKit.framework */; }};"
    )

    common_debug = r"""
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 12.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
"""

    common_release = r"""
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				MACOSX_DEPLOYMENT_TARGET = 12.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
"""

    app_settings = r"""
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = LaserStol/LaserStol.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = LaserStol/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = ru.proaibitrix.LaserStol;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
"""

    test_settings = r"""
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 12.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = ru.proaibitrix.LaserStolTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/LaserStol.app/Contents/MacOS/LaserStol";
"""

    return f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		{ids['app_proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {ids['project']} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {ids['app_target']};
			remoteInfo = LaserStol;
		}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['iokit_build']} /* IOKit.framework in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['test_frameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['main_group']} = {{
			isa = PBXGroup;
			children = (
				{ids['app_group']} /* LaserStol */,
				{ids['test_group']} /* LaserStolTests */,
				{ids['products']} /* Products */,
				{ids['frameworks_group']} /* Frameworks */,
			);
			sourceTree = "<group>";
		}};
		{ids['products']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['app_product']} /* LaserStol.app */,
				{ids['test_product']} /* LaserStolTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{ids['frameworks_group']} /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
				{ids['iokit_ref']} /* IOKit.framework */,
			);
			name = Frameworks;
			sourceTree = "<group>";
		}};
		{ids['app_group']} /* LaserStol */ = {{
			isa = PBXGroup;
			children = (
{app_children}
			);
			path = LaserStol;
			sourceTree = "<group>";
		}};
		{ids['test_group']} /* LaserStolTests */ = {{
			isa = PBXGroup;
			children = (
{test_child}
			);
			path = LaserStolTests;
			sourceTree = "<group>";
		}};
{chr(10).join(folder_groups)}
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['app_target']} /* LaserStol */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['app_configs']} /* Build configuration list for PBXNativeTarget "LaserStol" */;
			buildPhases = (
				{ids['app_sources']} /* Sources */,
				{ids['frameworks']} /* Frameworks */,
				{ids['app_resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = LaserStol;
			productName = LaserStol;
			productReference = {ids['app_product']} /* LaserStol.app */;
			productType = "com.apple.product-type.application";
		}};
		{ids['test_target']} /* LaserStolTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['test_configs']} /* Build configuration list for PBXNativeTarget "LaserStolTests" */;
			buildPhases = (
				{ids['test_sources']} /* Sources */,
				{ids['test_frameworks']} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				{ids['test_dep']} /* PBXTargetDependency */,
			);
			name = LaserStolTests;
			productName = LaserStolTests;
			productReference = {ids['test_product']} /* LaserStolTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1420;
				LastUpgradeCheck = 1420;
				TargetAttributes = {{
					{ids['app_target']} = {{
						CreatedOnToolsVersion = 14.2;
					}};
					{ids['test_target']} = {{
						CreatedOnToolsVersion = 14.2;
						TestTargetID = {ids['app_target']};
					}};
				}};
			}};
			buildConfigurationList = {ids['proj_configs']} /* Build configuration list for PBXProject "LaserStol" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = ru;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				ru,
				Base,
			);
			mainGroup = {ids['main_group']};
			productRefGroup = {ids['products']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['app_target']} /* LaserStol */,
				{ids['test_target']} /* LaserStolTests */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['app_resources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['assets_build']} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['app_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(source_builds)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{ids['test_sources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(test_builds)}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		{ids['test_dep']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {ids['app_target']} /* LaserStol */;
			targetProxy = {ids['app_proxy']} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		{ids['proj_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{common_debug}
			}};
			name = Debug;
		}};
		{ids['proj_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{common_release}
			}};
			name = Release;
		}};
		{ids['app_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{app_settings}
			}};
			name = Debug;
		}};
		{ids['app_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{app_settings}
			}};
			name = Release;
		}};
		{ids['test_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{test_settings}
			}};
			name = Debug;
		}};
		{ids['test_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{{test_settings}
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['proj_configs']} /* Build configuration list for PBXProject "LaserStol" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['proj_debug']} /* Debug */,
				{ids['proj_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['app_configs']} /* Build configuration list for PBXNativeTarget "LaserStol" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['app_debug']} /* Debug */,
				{ids['app_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['test_configs']} /* Build configuration list for PBXNativeTarget "LaserStolTests" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['test_debug']} /* Debug */,
				{ids['test_release']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""


def write_scheme() -> None:
    app_id = hid("app_target")
    test_id = hid("test_target")
    text = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1420"
   version = "1.3">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_id}"
               BuildableName = "LaserStol.app"
               BlueprintName = "LaserStol"
               ReferencedContainer = "container:LaserStol.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_id}"
               BuildableName = "LaserStolTests.xctest"
               BlueprintName = "LaserStolTests"
               ReferencedContainer = "container:LaserStol.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "LaserStol.app"
            BlueprintName = "LaserStol"
            ReferencedContainer = "container:LaserStol.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "LaserStol.app"
            BlueprintName = "LaserStol"
            ReferencedContainer = "container:LaserStol.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    path = PROJ / "xcshareddata" / "xcschemes" / "LaserStol.xcscheme"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def main() -> None:
    write_icons()
    (PROJ / "project.pbxproj").write_text(pbx(), encoding="utf-8")
    write_scheme()
    print("generated project + icons")


if __name__ == "__main__":
    main()
