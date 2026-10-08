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
        directory = os.path.join(ROOT, fs_path)
        for filename in sorted(os.listdir(directory)):
            name, class_name = kind(filename)
            if not name:
                continue
            source = open(os.path.join(directory, filename), encoding="utf-8").read().replace("\r\n", "\n")
            out.append('\tensure(node, "%s", "%s").Source = %s' % (name, class_name, long_string(source)))
            out.append("\tcount += 1")
        out.append("end")
    out.append('print(("synced %d scripts"):format(count))')
    sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
