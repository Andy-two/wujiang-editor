import json, io, os, shutil, datetime

repo = r'F:\dsh-output\wujiang_editor'
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
backup = os.path.join(r'F:\dsh-output', '武将数据备份_' + stamp)
os.makedirs(backup, exist_ok=True)

# 备份所有编辑器数据（不只是武将，防止引用丢失）
files = [
    'data/editor/generals.json',
    'data/editor/skills.json',
    'data/editor/talents.json',
    'data/editor/bonds.json',
    'data/editor/shenbing.json',
    'data/editor/shapes.json',
    'data/editor/settings.json',
    'data/editor/art_library.json',
    'data/vice_generals.json',
]
for f in files:
    src = os.path.join(repo, f)
    if os.path.exists(src):
        dst = os.path.join(backup, os.path.basename(f))
        shutil.copy2(src, dst)
        print('备份:', os.path.basename(f))

# 统计
g = json.load(io.open(os.path.join(repo, 'data/editor/generals.json'), encoding='utf-8'))
meta = {
    'backup_time': stamp,
    'general_count': len(g),
    'skill_count': len(json.load(io.open(os.path.join(repo, 'data/editor/skills.json'), encoding='utf-8'))),
    'talent_count': len(json.load(io.open(os.path.join(repo, 'data/editor/talents.json'), encoding='utf-8'))),
    'note': '清空项目武将前的完整备份。恢复时把 generals.json 等复制回 data/editor/ 即可。',
}
json.dump(meta, io.open(os.path.join(backup, '备份说明.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=2)
print()
print('备份目录:', backup)
print('武将数:', meta['general_count'])
