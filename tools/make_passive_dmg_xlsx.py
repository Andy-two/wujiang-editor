import io, os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

base = r'F:\dsh-output\wujiang_editor'
tsv = os.path.join(base, 'data', 'stats', 'passive_damage_all.tsv')
out = r'F:\dsh-output\全武将普攻伤害_有无被动对比.xlsx'

rows = []
with io.open(tsv, encoding='utf-8') as f:
    header = f.readline().rstrip('\n').split('\t')
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 6:
            continue
        rows.append([parts[0], parts[1], int(parts[2]), int(parts[3]), int(parts[4]), parts[5]])

wb = Workbook()
# 全量明细
ws = wb.active
ws.title = '全量明细'
ws.append(header)
for r in rows:
    ws.append(r)
# 被动有差异
ws2 = wb.create_sheet('被动有差异')
ws2.append(header)
for r in rows:
    if r[4] != 0:
        ws2.append(r)

# 样式
for sheet in (ws, ws2):
    for c in sheet[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='4472C4')
        c.alignment = Alignment(horizontal='center')
    widths = {'A': 20, 'B': 16, 'C': 14, 'D': 14, 'E': 10, 'F': 16}
    for col, w in widths.items():
        sheet.column_dimensions[col].width = w
    sheet.freeze_panes = 'A2'
    # 差值标色
    for row in sheet.iter_rows(min_row=2):
        d = row[4].value
        if isinstance(d, int) and d > 0:
            row[4].font = Font(color='C00000', bold=True)
        elif isinstance(d, int) and d < 0:
            row[4].font = Font(color='008000', bold=True)

wb.save(out)
print('已保存:', out)
print('全量', len(rows), '行，有差异', sum(1 for r in rows if r[4] != 0), '行')

# 校验
wb2 = __import__('openpyxl').load_workbook(out)
print('工作表:', wb2.sheetnames)
print('明细行数:', wb2['全量明细'].max_row - 1)
print('差异行数:', wb2['被动有差异'].max_row - 1)
