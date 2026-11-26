"""
用 GitHub Git Data API 推送（这台设备 git push 会超时）。
用法: python3 push_repo.py <repo-name> <local-dir>
"""
import base64
import json
import os
import sys
import urllib.request

API = "https://api.github.com"
TOKEN = os.environ.get("GITHUB_E2") or os.environ.get("GITHUB_TOKEN")


def request(method, path, data=None):
    url = path if path.startswith("http") else API + path
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "minis")
    if body:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        print(f"HTTP {e.code}: {detail[:500]}")
        raise


def main():
    repo = sys.argv[1]
    local = sys.argv[2]
    full = f"qweQ-1/{repo}"

    # 1. 确保仓库存在
    try:
        request("GET", f"/repos/{full}")
        print(f"仓库已存在: {full}")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        request("POST", "/user/repos", {
            "name": repo,
            "description": "Phira 谱面编辑器 for iOS —— 制作/导入/导出 Phira 谱面包",
            "private": False,
            "auto_init": False,
        })
        print(f"已创建仓库: {full}")

    # 2. 收集文件
    files = []
    for root, dirs, names in os.walk(local):
        dirs[:] = [d for d in dirs if d not in (".git", ".build", "build", "DerivedData")]
        for name in sorted(names):
            if name.endswith((".png", ".jpg")) and ".DS_Store" in name:
                continue
            full_path = os.path.join(root, name)
            rel = os.path.relpath(full_path, local).replace(os.sep, "/")
            if rel.startswith("."):
                continue
            with open(full_path, "rb") as f:
                content = f.read()
            mode = "100755" if os.access(full_path, os.X_OK) else "100644"
            files.append({
                "path": rel,
                "mode": mode,
                "type": "blob",
                "content": base64.b64encode(content).decode(),
            })
    print(f"待推送 {len(files)} 个文件")

    # 3. 读现有 ref
    try:
        ref = request("GET", f"/repos/{full}/git/ref/heads/main")
        head_sha = ref["object"]["sha"]
        base_commit = request("GET", f"/repos/{full}/git/commits/{head_sha}")
        base_tree = base_commit["tree"]["sha"]
        print(f"已有 HEAD: {head_sha[:8]} tree={base_tree[:8]}")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        head_sha = None
        base_tree = None
        print("新仓库，无基线")

    # 4. 建 tree
    tree_payload = {"tree": [{"path": f["path"], "mode": f["mode"],
                               "type": "blob", "sha": f["content"]} for f in files]}
    # content 要先 create blob
    blobs = []
    for f in files:
        blob = request("POST", f"/repos/{full}/git/blobs",
                       {"content": f["content"], "encoding": "base64"})
        f["sha"] = blob["sha"]
        blobs.append(f["sha"])
    tree_payload = {"tree": [{"path": f["path"], "mode": f["mode"],
                               "type": "blob", "sha": f["sha"]} for f in files]}
    tree = request("POST", f"/repos/{full}/git/trees", tree_payload)
    print(f"tree: {tree['sha'][:8]}")

    # 5. commit
    message = sys.argv[3] if len(sys.argv) > 3 else "feat: Phira 谱面编辑器 iOS"
    commit_payload = {"message": message, "tree": tree["sha"]}
    if base_commit:
        commit_payload["parents"] = [head_sha]
    commit = request("POST", f"/repos/{full}/git/commits", commit_payload)
    print(f"commit: {commit['sha'][:8]}")

    # 6. 更新 ref
    if head_sha:
        request("PATCH", f"/repos/{full}/git/refs/heads/main",
                {"sha": commit["sha"], "force": True})
    else:
        request("POST", f"/repos/{full}/git/refs",
                {"ref": "refs/heads/main", "sha": commit["sha"]})
    print(f"✅ 已推送到 {full}@{commit['sha'][:8]}")


if __name__ == "__main__":
    main()
