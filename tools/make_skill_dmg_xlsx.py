import io, os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

base = r'F:\dsh-output\wujiang_editor'
tsv = os.path.join(base, 'data', 'stats', 'passive_damage_skill.tsv')
out = r'F:\dsh-output\全武将伤害_满级满阶_有无被动对比.xlsx'

header = None
rows = []
with io.open(tsv, encoding='utf-8') as f:
    header = f.readline().rstrip('\n').split('\t')
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 10:
            continue
        rows.append([parts[0], parts[1], int(parts[2]), int(parts[3]), int(parts[4]),
                     parts[5], parts[6], int(parts[7]), int(parts[8]), int(parts[9])])

wb = Workbook()
ws = wb.active
ws.title = '全量对比'
ws.append(header)
for r in rows:
    ws.append(r)

ws2 = wb.create_sheet('有被动差异')
ws2.append(header)
for r in rows:
    if r[4] != 0 or r[9] != 0:
        ws2.append(r)

# 异常澄清表
ws3 = wb.create_sheet('异常原因说明')
ws3.append(['武将', '现象', '原因', '结论'])
notes = [
    ['张飞', '首轮普攻曾测出 -31', '靶子误用了张飞自己（自带坚壁减伤15%），攻击被靶子减免',
     '换中立靶后 普攻 478/324(+154)、技能 351/324(+27)，正常正增益'],
    ['吕布', '技能伤害曾达 100万', '辕门射戟 Lv2 有「按目标最大兵力10%」的固伤块；当时靶子血量设成999万',
     '靶子改为3万后为 3442，正常；被动袭扰加成体现在普攻(+39)'],
    ['吕布', '技能差值 0', '固伤(3000)占大头，普攻部分的被动+8%差异被淹没',
     '非异常；如要看纯倍率差异可看普攻列'],
    ['赵云', '技能曾用 0/-1', '敌胆寒是组合技(形态切换)，脚本原先跳过组合技',
     '已改为施放子技能「斩千军」，现为 1450/1450'],
    ['赵云', '技能差值 0', '被动「阻敌」是防御型(物防+10%/zoc)，不增强该技能输出', '非异常'],
    ['马超', '技能曾用 0/-1', '百合鏖战是组合技，脚本原先跳过', '已改为施放子技能，现为 834/758(+76)'],
    ['魏延', '技能列为空', '主动技「铁索横江」只有 fixed 固伤无 damage 块；伤害技能(拒王吞将/万人敌)都是被动，无法主动施放',
     '非异常；被动伤害已体现在普攻列(+203)'],
    ['牵招', '技能曾为 0', '剿杀殆尽是 AOE，作用范围不含落点中心，靶子放在落点没被打中',
     '已改为在作用格上放靶，现为 3214/3214'],
    ['孙策', '技能曾为 0', '原先选到「质玺谋兵」是 self 型，damage 为响应式，主动施放打不到靶子',
     '已改为选主动伤害技「重击」，现为 960/873(+87)'],
]
for n in notes:
    ws3.append(n)

for sheet in (ws, ws2):
    for c in sheet[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='4472C4')
        c.alignment = Alignment(horizontal='center')
    widths = {'A': 18, 'B': 14, 'C': 12, 'D': 12, 'E': 10,
              'F': 22, 'G': 14, 'H': 14, 'I': 12, 'J': 10}
    for col, w in widths.items():
        sheet.column_dimensions[col].width = w
    sheet.freeze_panes = 'A2'
    for row in sheet.iter_rows(min_row=2):
        for idx in (4, 9):
            if idx < len(row):
                d = row[idx].value
                if isinstance(d, int) and d > 0:
                    row[idx].font = Font(color='C00000', bold=True)
                elif isinstance(d, int) and d < 0:
                    row[idx].font = Font(color='008000', bold=True)

# 异常表列宽
for col, w in {'A': 12, 'B': 22, 'C': 60, 'D': 55}.items():
    ws3.column_dimensions[col].width = w
for c in ws3[1]:
    c.font = Font(bold=True, color='FFFFFF')
    c.fill = PatternFill('solid', fgColor='C00000')
    c.alignment = Alignment(horizontal='center')
for row in ws3.iter_rows(min_row=2):
    for cell in row:
        cell.alignment = Alignment(wrap_text=True, vertical='top')

wb.save(out)
wb2 = __import__('openpyxl').load_workbook(out)
print('已保存:', out)
print('工作表:', wb2.sheetnames)
print('全量:', wb2['全量对比'].max_row - 1,
      '差异:', wb2['有被动差异'].max_row - 1,
      '异常说明:', wb2['异常原因说明'].max_row - 1)
