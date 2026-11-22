import json, io, collections, os

p = r'F:\dsh-output\wujiang_editor\data\editor\skills.json'
sk = json.load(io.open(p, encoding='utf-8'))

rows = []
for sid, v in sk.items():
    if not isinstance(v, dict):
        continue
    for fx in v.get('ed_fx_list', []):
        if isinstance(fx, dict) and fx.get('type') == 'fixed':
            rows.append({
                'id': sid,
                'name': v.get('name', sid),
                'kind': v.get('kind', ''),
                'value': fx.get('value', 0),
                'by_max_hp': fx.get('by_max_hp', False),
                'value_pct': fx.get('value_pct', 0),
                'min_lv': fx.get('min_lv', 1),
                'desc': str(v.get('desc', ''))[:80],
            })

out = r'F:\dsh-output\所有固伤技能清单.xlsx'
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = '固定伤害清单'
hdr = ['技能ID', '技能名', '类型', '固定值', '按最大兵力%', '兵力%', '起始阶', '描述']
ws.append(hdr)
for r in sorted(rows, key=lambda x: (str(x['name']), int(x['min_lv']) if isinstance(x['min_lv'], (int, float)) else 1)):
    ws.append([r['id'], r['name'], r['kind'], r['value'],
               '是' if r['by_max_hp'] else '否', r['value_pct'], r['min_lv'], r['desc']])

note = wb.create_sheet('说明')
for n in [
    ['项目', '说明'],
    ['固定伤害', 'fixed 效果块：无视防御与常规增减伤，只吃固伤增伤'],
    ['按最大兵力%', 'by_max_hp=true 时，固伤=目标最大兵力×value_pct，会随目标血量放大'],
    ['牵招', '剿杀殆尽等技能含 fixed 块，详见清单'],
    ['DOT', '溃逃为固定每层2000点（DOT_STATUS.溃逃.fixed），不吃等级/属性'],
]:
    note.append(n)

for sheet in (ws, note):
    for c in sheet[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='4472C4')
        c.alignment = Alignment(horizontal='center')
    for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']:
        sheet.column_dimensions[col].width = {'A': 18, 'B': 16, 'C': 10, 'D': 10, 'E': 14, 'F': 10, 'G': 10, 'H': 60}[col]
    sheet.freeze_panes = 'A2'

wb.save(out)
print('固伤效果块总数:', len(rows))
print('涉及技能数:', len(set(r['id'] for r in rows)))
print('已保存:', out)
# 打印牵招相关
print('\n牵招相关:')
for r in rows:
    if 'qian' in r['id'] or '牵' in str(r['name']):
        print(' ', r)
