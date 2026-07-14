#!/usr/bin/env python
from __future__ import print_function

import json
import sys

try:
    string_types = (basestring,)
except NameError:
    string_types = (str,)


def iter_descriptors(node):
    if isinstance(node, dict):
        platform = node.get("platform")
        digest = node.get("digest")
        if isinstance(platform, dict) and isinstance(digest, string_types):
            yield node
        for value in node.values():
            for descriptor in iter_descriptors(value):
                yield descriptor
    elif isinstance(node, list):
        for value in node:
            for descriptor in iter_descriptors(value):
                yield descriptor


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: manifest-select.py <manifest.json|-> <os/architecture>\n")
        return 2

    source, platform_name = sys.argv[1:]
    try:
        target_os, target_architecture = platform_name.split("/", 1)
    except ValueError:
        sys.stderr.write("Platform must be os/architecture.\n")
        return 2

    handle = sys.stdin if source == "-" else open(source)
    try:
        document = json.load(handle)
    finally:
        if handle is not sys.stdin:
            handle.close()

    for descriptor in iter_descriptors(document):
        descriptor_platform = descriptor["platform"]
        if (descriptor_platform.get("os") == target_os and
                descriptor_platform.get("architecture") == target_architecture):
            print(descriptor["digest"])
            return 0

    sys.stderr.write("No matching descriptor for %s.\n" % platform_name)
    return 1


if __name__ == "__main__":
    sys.exit(main())
