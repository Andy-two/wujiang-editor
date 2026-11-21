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
        r = [parts[0], parts[1], int(parts[2]), int(parts[3]), int(parts[4]),
             parts[5], parts[6], int(parts[7]), int(parts[8]), int(parts[9])]
        rows.append(r)

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

ws3 = wb.create_sheet('张飞专项')
ws3.append(['武将', '普攻有被动', '普攻无被动', '普攻差值', '技能名', '技能有被动', '技能无被动', '技能差值', '说明'])
for r in rows:
    if r[0] == 'zhang_fei':
        ws3.append([r[1], r[2], r[3], r[4], r[6], r[7], r[8], r[9],
                    '之前测出 -31 是靶子用了张飞模板（自带坚壁减伤）造成的假象；换中立靶后为正常正增益'])

for sheet in (ws, ws2, ws3):
    for c in sheet[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='4472C4')
        c.alignment = Alignment(horizontal='center')
    widths = {'A': 18, 'B': 14, 'C': 12, 'D': 12, 'E': 10,
              'F': 20, 'G': 14, 'H': 14, 'I': 12, 'J': 10}
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

wb.save(out)
wb2 = __import__('openpyxl').load_workbook(out)
print('已保存:', out)
print('工作表:', wb2.sheetnames)
print('全量:', wb2['全量对比'].max_row - 1, '差异:', wb2['有被动差异'].max_row - 1)
