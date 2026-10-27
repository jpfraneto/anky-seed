#!/usr/bin/env python3
"""Add Swift sources (and the RevenueCat package) to the Anky app target.

Idempotent: files already referenced are skipped. IDs use the 8A0000E7
prefix and are derived from the path, so re-running never duplicates.

usage: scripts/pbx_add_sources.py [--revenuecat] Features/X/Y.swift Core/A/B.swift ...
(paths are relative to apps/ios/Anky)
"""
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PBX = ROOT / "Anky.xcodeproj" / "project.pbxproj"
ANKY_GROUP = "8A0000010000000000003002"
ANKY_SOURCES = "8A0000010000000000005001"
ANKY_FRAMEWORKS_ANCHOR = "8A0000080000000000000001 /* secp256k1 in Frameworks */,"
ANKY_PACKAGE_DEPS_ANCHOR = "8A0000080000000000009002 /* secp256k1 */,\n"


def ident(kind: str, path: str) -> str:
    digest = hashlib.sha1(f"{kind}:{path}".encode()).hexdigest().upper()[:16]
    return "8A0000E7" + digest


def insert_after(text: str, marker: str, addition: str) -> str:
    index = text.index(marker) + len(marker)
    return text[:index] + addition + text[index:]


def add_file(text: str, path: str) -> str:
    if f"path = {path};" in text or f'path = "{path}";' in text:
        print(f"skip   {path}")
        return text
    file_ref = ident("ref", path)
    build = ident("build", path)
    quoted = f'"{path}"' if re.search(r"[^A-Za-z0-9_./-]", path) else path
    text = insert_after(
        text,
        "/* Begin PBXBuildFile section */\n",
        f"\t\t{build} /* {path} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref} /* {path} */; }};\n",
    )
    text = insert_after(
        text,
        "/* Begin PBXFileReference section */\n",
        f"\t\t{file_ref} /* {path} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        f"path = {quoted}; sourceTree = \"<group>\"; }};\n",
    )
    group_marker = f"\t\t{ANKY_GROUP} /* Anky */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
    text = insert_after(text, group_marker, f"\t\t\t\t{file_ref} /* {path} */,\n")
    sources_marker = f"\t\t{ANKY_SOURCES} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
    text = insert_after(text, sources_marker, f"\t\t\t\t{build} /* {path} in Sources */,\n")
    print(f"added  {path}")
    return text


def add_revenuecat(text: str) -> str:
    if "purchases-ios-spm" in text:
        print("skip   RevenueCat package")
        return text
    pkg, product, build = "8A0000060000000000009001", "8A0000060000000000009002", "8A0000060000000000000002"
    text = insert_after(
        text,
        "/* Begin PBXBuildFile section */\n",
        f"\t\t{build} /* RevenueCat in Frameworks */ = {{isa = PBXBuildFile; productRef = {product} /* RevenueCat */; }};\n",
    )
    # The app target's Frameworks phase (next to secp256k1).
    text = text.replace(
        f"\t\t\t\t{ANKY_FRAMEWORKS_ANCHOR}\n",
        f"\t\t\t\t{ANKY_FRAMEWORKS_ANCHOR}\n\t\t\t\t{build} /* RevenueCat in Frameworks */,\n",
        1,
    )
    # The app target's package product dependencies (first occurrence is Anky).
    text = text.replace(
        f"\t\t\t\t{ANKY_PACKAGE_DEPS_ANCHOR}",
        f"\t\t\t\t{ANKY_PACKAGE_DEPS_ANCHOR}\t\t\t\t{product} /* RevenueCat */,\n",
        1,
    )
    text = text.replace(
        '\t\t\t\t8A0000080000000000009001 /* XCRemoteSwiftPackageReference "secp256k1.swift" */,\n\t\t\t);',
        f'\t\t\t\t8A0000080000000000009001 /* XCRemoteSwiftPackageReference "secp256k1.swift" */,\n'
        f'\t\t\t\t{pkg} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */,\n\t\t\t);',
        1,
    )
    text = insert_after(
        text,
        "/* Begin XCRemoteSwiftPackageReference section */\n",
        f'\t\t{pkg} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */ = {{\n'
        "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
        '\t\t\trepositoryURL = "https://github.com/RevenueCat/purchases-ios-spm.git";\n'
        "\t\t\trequirement = {\n\t\t\t\tkind = upToNextMajorVersion;\n\t\t\t\tminimumVersion = 5.0.0;\n\t\t\t};\n\t\t};\n",
    )
    text = insert_after(
        text,
        "/* Begin XCSwiftPackageProductDependency section */\n",
        f"\t\t{product} /* RevenueCat */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f'\t\t\tpackage = {pkg} /* XCRemoteSwiftPackageReference "purchases-ios-spm" */;\n'
        "\t\t\tproductName = RevenueCat;\n\t\t};\n",
    )
    print("added  RevenueCat package")
    return text


def main() -> None:
    args = sys.argv[1:]
    text = PBX.read_text()
    if "--revenuecat" in args:
        args.remove("--revenuecat")
        text = add_revenuecat(text)
    for path in args:
        if not (ROOT / "Anky" / path).exists():
            sys.exit(f"missing file: Anky/{path}")
        text = add_file(text, path)
    PBX.write_text(text)


if __name__ == "__main__":
    main()
