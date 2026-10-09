"""Emit Luau that mirrors this repo's scripts into the open Studio place (for MCP execute_luau).

    python tools/mcp_sync.py [default|trial] > sync.luau

Prefer `rojo serve` + the Rojo plugin for day-to-day work; this exists for agent-driven sessions
where the Rojo plugin isn't connected. Reads the $path mappings from the Rojo project file.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def mappings(node, path):
    for key, child in node.items():
        if key.startswith("$") or not isinstance(child, dict):
            continue
        if "$path" in child:
            yield path + [key], child["$path"]
        yield from mappings(child, path + [key])


def kind(filename):
    if filename.endswith(".server.luau"):
        return filename[: -len(".server.luau")], "Script"
    if filename.endswith(".client.luau"):
        return filename[: -len(".client.luau")], "LocalScript"
    if filename.endswith(".luau"):
        return filename[: -len(".luau")], "ModuleScript"
    return None, None


def long_string(text):
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def emit_directory(out, directory, var, depth):
    """Mirror one directory's scripts into the instance `var`; subdirectories become Folders (as in Rojo)."""
    indent = "\t" * depth
    for filename in sorted(os.listdir(directory)):
        path = os.path.join(directory, filename)
        if os.path.isdir(path):
            # a directory with an init script becomes that script, its other files its children (Rojo)
            child = "dir%d" % depth
            init_name = next((f for f in sorted(os.listdir(path)) if kind(f)[0] == "init"), None)
            if init_name:
                source = open(os.path.join(path, init_name), encoding="utf-8").read().replace("\r\n", "\n")
                out.append(
                    '%sdo local %s = ensure(%s, "%s", "%s")' % (indent, child, var, filename, kind(init_name)[1])
                )
                out.append("%s\t%s.Source = %s" % (indent, child, long_string(source)))
                out.append("%s\tcount += 1" % indent)
            else:
                out.append('%sdo local %s = ensure(%s, "%s", "Folder")' % (indent, child, var, filename))
            emit_directory(out, path, child, depth + 1)
            out.append("%send" % indent)
            continue
        name, class_name = kind(filename)
        if not name or name == "init":
            continue
        source = open(path, encoding="utf-8").read().replace("\r\n", "\n")
        out.append('%sensure(%s, "%s", "%s").Source = %s' % (indent, var, name, class_name, long_string(source)))
        out.append("%scount += 1" % indent)


def main():
    project = sys.argv[1] if len(sys.argv) > 1 else "default"
    tree = json.load(open(os.path.join(ROOT, project + ".project.json"), encoding="utf-8"))["tree"]
    out = [
        "local function ensure(parent, name, className)",
        "\tlocal inst = parent:FindFirstChild(name)",
        "\tif inst and inst.ClassName ~= className then inst:Destroy() inst = nil end",
        "\tif not inst then inst = Instance.new(className) inst.Name = name inst.Parent = parent end",
        "\treturn inst",
        "end",
        "local count = 0",
    ]
    for inst_path, fs_path in mappings(tree, []):
        service = inst_path[0]
        out.append("do")
        out.append('\tlocal node = game:GetService("%s")' % service)
        for name in inst_path[1:]:
            out.append('\tnode = node:FindFirstChild("%s") or ensure(node, "%s", "Folder")' % (name, name))
        emit_directory(out, os.path.join(ROOT, fs_path), "node", 1)
        out.append("end")
    out.append('print(("synced %d scripts"):format(count))')
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to a legacy codepage
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
