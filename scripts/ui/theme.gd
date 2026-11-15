extends RefCounted
class_name EdTheme

# 统一的深色主题 + 常用控件工厂

const BG := Color("#0b1220")
const PANEL := Color("#111a2b")
const PANEL2 := Color("#16223a")
const LINE := Color("#243149")
const ACCENT := Color("#38bdf8")
const ORANGE := Color("#f97316")
const TEXT := Color("#e2e8f0")
const MUTED := Color("#94a3b8")
const GOOD := Color("#34d399")
const BAD := Color("#f87171")
const WARN := Color("#fbbf24")
const TONE_COLORS := {
	"info": Color("#94a3b8"), "hit": Color("#fca5a5"), "heal": Color("#6ee7b7"),
	"kill": Color("#f87171"), "round": Color("#38bdf8"), "win": Color("#34d399"),
	"lose": Color("#f87171"), "warn": Color("#fbbf24"), "ok": Color("#34d399"),
}


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	sb.border_color = LINE
	sb.set_border_width_all(1)
	th.set_stylebox("panel", "PanelContainer", sb)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#1f2d47")
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	btn.border_color = Color("#31425f")
	btn.set_border_width_all(1)
	th.set_stylebox("normal", "Button", btn)
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color("#2a3c5c")
	hov.border_color = ACCENT
	th.set_stylebox("hover", "Button", hov)
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = Color("#0e7490")
	prs.border_color = ACCENT
	th.set_stylebox("pressed", "Button", prs)
	var dis := btn.duplicate() as StyleBoxFlat
	dis.bg_color = Color("#1a2233")
	th.set_stylebox("disabled", "Button", dis)
	var foc := StyleBoxFlat.new()
	foc.draw_center = false
	foc.border_color = ACCENT
	foc.set_border_width_all(1)
	foc.set_corner_radius_all(6)
	th.set_stylebox("focus", "Button", foc)
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color("#5b6b85"))

	var le := StyleBoxFlat.new()
	le.bg_color = Color("#0d1626")
	le.set_corner_radius_all(5)
	le.set_content_margin_all(5)
	le.border_color = LINE
	le.set_border_width_all(1)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", hov)
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", ACCENT)

	var sp := StyleBoxFlat.new()
	sp.bg_color = Color("#0d1626")
	sp.set_corner_radius_all(5)
	sp.border_color = LINE
	sp.set_border_width_all(1)
	th.set_stylebox("normal", "SpinBox", sp)

	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_color", "OptionButton", TEXT)
	th.set_color("font_color", "CheckBox", TEXT)
	th.set_color("font_color", "CheckButton", TEXT)
	th.set_color("font_color", "RichTextLabel", TEXT)

	var tab := StyleBoxFlat.new()
	tab.bg_color = Color("#1f2d47")
	tab.set_corner_radius_all(5)
	tab.set_content_margin_all(6)
	th.set_stylebox("tab_selected", "TabContainer", tab)
	th.set_stylebox("panel", "TabContainer", sb)
	return th


static func label(text: String, size: int = 14, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func hint(text: String, size: int = 12) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", MUTED)
	return l


static func button(text: String, size: int = 14, min_w: float = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	return b


static func sep(vertical: bool = false) -> Control:
	var c := ColorRect.new()
	c.color = LINE
	if vertical:
		c.custom_minimum_size = Vector2(1, 0)
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.custom_minimum_size = Vector2(0, 1)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
