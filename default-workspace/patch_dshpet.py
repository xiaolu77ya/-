#!/usr/bin/env python3
"""给 dsh-pet 的对话加一层「动作解析」（打开文件/文件夹/应用、在访达显示），
执行前先问一句，用户回「好」才真的执行。

用法：
  python3 patch_dshpet.py --apply     # 打补丁（幂等：已打过会跳过）
  python3 patch_dshpet.py --revert    # 还原成 .dshpet-orig
  python3 patch_dshpet.py --check     # 只看状态
插件升级会覆盖 lib/index.js，升级后重新 --apply 即可。
"""
import argparse
import os
import shutil
import sys

PET_DIR = os.path.expanduser("~/.dsh/profiles/desktop/node_modules/dsh-pet")
TARGET = os.path.join(PET_DIR, "lib", "index.js")
BACKUP = TARGET + ".dshpet-orig"
MARK = "// >>> dsh-pet 动作层（本地补丁） >>>"

ANCHOR_FUNC = "\tconst chatWithPet = async (petId, text) => withMemoryLock(async () => {"
ANCHOR_CALL = (
    "\t\tconst generated = await generateChat(ctx, system, list, text, pool, "
    'configuredModel(found.conf, "chatModel"));'
)

LAYER = r"""// >>> dsh-pet 动作层（本地补丁） >>>
// 识别「打开 X / 在访达里显示 X」，先确认再执行；其余对话照旧走人设模型。
const PET_PENDING = new Map();
const PET_YES = /^(好|好的|行|可以|确认|确定|嗯|是的|ok|OK|Ok|yes|👍)$/;
const PET_NO = /^(取消|不用了|算了|别|不要|no|NO)$/;

async function petResolveTarget(raw, withLoose) {
	const fs = await import("node:fs/promises");
	const path = await import("node:path");
	const os = await import("node:os");
	let q = String(raw || "").trim().replace(/^[「"'"'《\s]+|[」"'"'》\s]+$/g, "");
	q = q.replace(/^(一下|这个|那个|我的)/, "").trim();
	if (q.startsWith("~/")) q = path.join(os.homedir(), q.slice(2));
	const candidates = [];
	if (path.isAbsolute(q)) candidates.push(q);
	const roots = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
		.map((d) => path.join(os.homedir(), d));
	const needle = q.toLowerCase();
	const exact = [], loose = [];
	let seen = 0;
	const walk = async (dir, depth) => {
		if (seen > 30000) return;
		let ents = [];
		try { ents = await fs.readdir(dir, { withFileTypes: true }); } catch { return; }
		for (const e of ents) {
			if (e.name.startsWith(".")) continue;
			seen++;
			const full = path.join(dir, e.name);
			const name = e.name.toLowerCase();
			const stem = name.replace(/\.[^.]+$/, "");
			if (name === needle || stem === needle || name === needle + ".app") exact.push(full);
			else if (name.includes(needle)) loose.push(full);
			if (e.isDirectory() && depth > 0) await walk(full, depth - 1);
		}
	};
	for (const r of roots) await walk(r, 6);
	candidates.push(...exact);
	if (withLoose) candidates.push(...loose);
	for (const c of candidates) { try { await fs.access(c); return c; } catch {} }
	return null;
}

/** 常见应用别名：中文口语 -> 实际 .app 名 */
const PET_APP_ALIAS = {
	"微信": "WeChat", "访达": "Finder", "浏览器": "Safari", "safari": "Safari",
	"终端": "Terminal", "计算器": "Calculator", "备忘录": "Notes", "日历": "Calendar",
	"邮件": "Mail", "音乐": "Music", "照片": "Photos", "预览": "Preview",
	"系统设置": "System Settings", "访达窗口": "Finder", "活动监视器": "Activity Monitor",
	"截图": "Screenshot", "打字": "TextEdit", "文本编辑": "TextEdit"
};

/** 返回可传给 open -a 的应用名，找不到返回 null */
async function petAppTarget(q) {
	const fs = await import("node:fs/promises");
	const path = await import("node:path");
	const os = await import("node:os");
	const key = String(q || "").trim().toLowerCase();
	const alias = PET_APP_ALIAS[key] || PET_APP_ALIAS[q];
	if (alias) return alias;
	const dirs = ["/Applications", path.join(os.homedir(), "Applications"), "/System/Applications",
		"/System/Library/CoreServices"];
	for (const name of [q]) {
		for (const dir of dirs) {
			try { await fs.access(path.join(dir, name + ".app")); return name; } catch {}
		}
	}
	return null;
}

async function petActionLayer(petId, text) {
	const { execFile } = await import("node:child_process");
	const t = String(text || "").trim();
	if (!t) return null;
	const pending = PET_PENDING.get(petId);
	if (pending) {
		if (PET_NO.test(t)) { PET_PENDING.delete(petId); return "行吧，那不干了。"; }
		if (PET_YES.test(t)) {
			PET_PENDING.delete(petId);
			return await new Promise((resolve) => {
				execFile("open", pending.args, (err) => {
					if (err) resolve("没打开成功：" + err.message);
					else resolve(pending.kind === "reveal"
						? "已经在访达里给你标出来了：" + pending.label
						: "打开了：" + pending.label);
				});
			});
		}
		PET_PENDING.delete(petId);
	}
	const mReveal = t.match(/(?:在)?访达(?:里|中)?(?:显示|定位|找到|打开)\s*[:：]?\s*(.+)$/);
	const mOpen = t.match(/^(?:请|帮我|麻烦你?)?\s*(?:打开|启动|开启)(?:一下)?\s*[:：]?\s*(.+)$/);
	const kind = mReveal ? "reveal" : mOpen ? "open" : null;
	if (!kind) return null;
	const raw = (mReveal ? mReveal[1] : mOpen[1]).trim();
	let p = await petResolveTarget(raw, false);
	const app = kind === "open" && !p ? await petAppTarget(raw) : null;
	if (!p && !app) p = await petResolveTarget(raw, true);
	let args, label;
	if (p && !app) {
		label = p.split("/").pop();
		args = kind === "reveal" ? ["-R", p] : [p];
	} else if (app) {
		label = raw;
		args = ["-a", app];
	} else {
		return "我找了一圈没找到「" + raw + "」，要不你说个更准的名字？";
	}
	PET_PENDING.set(petId, { kind, args, label });
	return "要" + (kind === "reveal" ? "在访达里显示" : "打开") + "「" + label + "」吗？回「好」我就动手。";
}
// <<< dsh-pet 动作层（本地补丁） <<<

"""

HOOK = (
    "\t\tconst petAct = await petActionLayer(petId, text);\n"
    "\t\tconst generated = petAct ? { ok: true, text: petAct } : await generateChat(ctx, system, list, text, pool, "
    'configuredModel(found.conf, "chatModel"));'
)


def read():
    with open(TARGET, "r", encoding="utf-8") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--revert", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(TARGET):
        print("找不到插件入口：" + TARGET)
        return 1

    src = read()
    patched = MARK in src

    if a.check or (not a.apply and not a.revert):
        print(("已打补丁" if patched else "未打补丁") + "：" + TARGET)
        print(("有备份：" if os.path.exists(BACKUP) else "无备份：") + BACKUP)
        return 0

    if a.revert:
        if not os.path.exists(BACKUP):
            print("没有备份，无法还原")
            return 1
        shutil.copyfile(BACKUP, TARGET)
        print("已还原")
        return 0

    if patched:
        print("已经是打过补丁的状态，跳过")
        return 0

    if ANCHOR_FUNC not in src or ANCHOR_CALL not in src:
        print("锚点没找到，插件版本可能变了：")
        print("  func anchor:", ANCHOR_FUNC in src)
        print("  call anchor:", ANCHOR_CALL in src)
        return 2

    if not os.path.exists(BACKUP):
        shutil.copyfile(TARGET, BACKUP)
        print("已备份 -> " + BACKUP)

    out = src.replace(ANCHOR_FUNC, LAYER + ANCHOR_FUNC, 1)
    out = out.replace(ANCHOR_CALL, HOOK, 1)
    with open(TARGET, "w", encoding="utf-8") as f:
        f.write(out)
    print("补丁已写入：" + TARGET)
    print("重启 DeepSeek Harness 后生效")
    return 0


if __name__ == "__main__":
    sys.exit(main())
