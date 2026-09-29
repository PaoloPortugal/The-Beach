extends Control
## Throwaway: compares ways of writing nested lists in RichTextLabel BBCode.

const LONG := "a long item that should wrap onto a second line so we can see whether the wrapped text hangs under the text or under the marker"

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1e242d")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	grid.add_theme_constant_override("h_separation", 16)
	add_child(grid)
	var variants := {
		"A indent+ul": "[ul bullet=•]top one[/ul]\n[indent][ul bullet=◦]%s[/ul][/indent]\n[indent][ul bullet=◦]nested two[/ul][/indent]\n[ul bullet=•]top two[/ul]" % LONG,
		"B nested ul": "[ul bullet=•]top one\n[ul bullet=◦]%s\nnested two[/ul]\ntop two[/ul]" % LONG,
		"C ul in ul": "[ul bullet=•]top one[/ul]\n[ul bullet= ][ul bullet=◦]%s[/ul][/ul]\n[ul bullet=•]top two[/ul]" % LONG,
		"D indent text": "[indent]• top one[/indent]\n[indent][indent]◦ %s[/indent][/indent]\n[indent]• top two[/indent]" % LONG,
		"E table": "[table=2][cell]• [/cell][cell]top one[/cell][/table]\n[indent][table=2][cell]◦ [/cell][cell]%s[/cell][/table][/indent]\n[table=2][cell]• [/cell][cell]top two[/cell][/table]" % LONG,
		"G per-item, nested, \\n": "[ul bullet=•]top one\n[ul bullet=◦]child one[/ul]\n[ul bullet=☐]child two[/ul][/ul]\n[ul bullet=•]top two[/ul]",
		"H per-item, no \\n": "[ul bullet=•]top one\n[ul bullet=◦]child one[/ul][ul bullet=☐]child two[/ul][/ul]\n[ul bullet=•]top two[/ul]",
		"I numbers 3., 4.": "[ul bullet=3.]three %s\n[ul bullet=◦]child[/ul][/ul]\n[ul bullet=4.]four[/ul]" % LONG,
		"F ul nested, ol": "[ol type=1]step\n[ul bullet=◦]%s\n[ul bullet=▪]deeper[/ul]\nback[/ul]\nnext step[/ol]" % LONG,
	}
	for name in variants:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 360
		var title := Label.new()
		title.text = name
		title.modulate = Color(1, 0.8, 0.4)
		box.add_child(title)
		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.text = variants[name]
		box.add_child(rtl)
		grid.add_child(box)
