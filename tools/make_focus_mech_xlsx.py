import io, os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

base = r'F:\dsh-output\wujiang_editor'
tsv = os.path.join(base, 'data', 'stats', 'focus_mechanics.tsv')
out = r'F:\dsh-output\七机制专项测试_等级阶级星级副将天赋神兵被动.xlsx'

# 读数据
rows = []
with io.open(tsv, encoding='utf-8') as f:
    header = f.readline().rstrip('\n').split('\t')
    for line in f:
        p = line.rstrip('\n').split('\t')
        if len(p) >= 5:
            rows.append(p)

wb = Workbook()
ws = wb.active
ws.title = '全量数据'
ws.append(['机制', '变量', '取值', '指标', '结果', '说明'])
for r in rows:
    ws.append(r[:6])

# 按机制分表
mechs = []
for r in rows:
    if r[0] not in mechs:
        mechs.append(r[0])
for m in mechs:
    s = wb.create_sheet(m[:31])
    s.append(['变量', '取值', '指标', '结果', '说明'])
    for r in rows:
        if r[0] == m:
            s.append([r[1], r[2], r[3], r[4], r[5]])

# 说明表
note = wb.create_sheet('测试说明')
notes = [
    ['项目', '说明'],
    ['测试时间', '2026-11-22'],
    ['配置基准', '等级60 / 技能Lv4 / 天赋Lv4 / 5星 / 无副将 / 无神兵 / 带被动'],
    ['测试方法', '基准 + 每次只改一个维度，观察该维度对结果的影响'],
    ['等级维度', '1/20/40/60；官方面板线性插值，1级与60级属性来自官网'],
    ['阶级维度', '技能/天赋 1/2/3/4 阶；部分技能升级只加状态不加倍率，故 1→2 或 3→4 可能相同'],
    ['星级维度', '1/3/5/7/10 星；每星按比例放大属性'],
    ['副将维度', '无(0) vs 有(董袭1335，Lv25)，验证副将属性/韬略加成'],
    ['天赋阶维度', '1/2/3/4 阶；天赋效果按 min_lv 过滤'],
    ['神兵维度', '0/11/14/17/20；神兵 11/14/17 升技能4阶、20 升天赋4阶'],
    ['神兵专项', '因基准已是Lv4，另加「Lv1技+神兵」专项体现升阶效果'],
    ['被动维度', '带全部被动 vs 去掉所有被动技能'],
    ['吕布群伤', '鬼哭神嚎(guiku) AOE 多靶总伤害'],
    ['关羽单伤', '青龙斩月 单体总伤害'],
    ['诸葛亮追击', '石兵八阵(zhuge_shibing) 的 pursuit 追击伤害（该阵法含追击效果块）'],
    ['阵法效果', '偃月阵光环：3格内友军谋略减伤率（唯一已实装的阵法）'],
    ['贾诩DOT', '四胜决机(jia_xu_s3) 施加溃逃后，结算一回合的持续伤害'],
    ['蔡文姬治疗', '善哉行(10274031) 给伤血友军的回血量'],
    ['马超暴击', '暴击率=crit_chance_of，暴伤=crit_mult_of（直接读公式）'],
    ['说明1', '石兵八阵/雾锁江天的描述是「友军受伤时追击」，但引擎实现是「施法瞬间对范围内敌军追击」，描述与实现有出入'],
    ['说明2', '蔡文姬神兵维度无变化：神兵只升特定技能，善哉行不在其升阶列表'],
    ['说明3', '关羽/诸葛亮被动维度无变化：偃月阵是给友军减伤、阻敌是防御型，不影响自身输出'],
]
for n in notes:
    note.append(n)

for sheet in wb.worksheets:
    for c in sheet[1]:
        c.font = Font(bold=True, color='FFFFFF')
        c.fill = PatternFill('solid', fgColor='4472C4')
        c.alignment = Alignment(horizontal='center')
    for col in ['A', 'B', 'C', 'D', 'E', 'F']:
        sheet.column_dimensions[col].width = {'A': 20, 'B': 12, 'C': 12, 'D': 16, 'E': 14, 'F': 40}[col]
    sheet.freeze_panes = 'A2'

wb.save(out)
wb2 = __import__('openpyxl').load_workbook(out)
print('已保存:', out)
print('工作表:', wb2.sheetnames)
print('数据行:', len(rows))
