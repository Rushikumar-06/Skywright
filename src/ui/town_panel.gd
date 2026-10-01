class_name TownPanel
extends CanvasLayer
## A town's business, opened with T at its dock: its market, buying and selling
## crates aboard the ship you're on and filling her spares, its contract board, and
## hiring hands for her.
## Everything goes through
## the Ledger; the panel only shows what the server last said, and rebuilds its rows
## when that changes.

signal close_requested

const CHECK_EVERY := 0.25  ## s between looks at whether the rows need rebuilding.

var market_rows: Dictionary = {}  ## Good -> its row's Label, for tests.

var _ledger: Ledger
var _town: int
var _ship_aboard: Callable  ## Returns the ship you're aboard, or null.
var _section := "market"
var _money: Label
var _note: Label
var _rows: VBoxContainer
var _shown := ""            ## A summary of what the rows show.
var _check_left := 0.0


func _init(world_ledger: Ledger, town_index: int, ship_aboard: Callable) -> void:
	_ledger = world_ledger
	_town = town_index
	_ship_aboard = ship_aboard


func _ready() -> void:
	var center := CenterContainer.new()
	center.theme = UiTheme.build()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := Label.new()
	title.text = _ledger.sync.gen.towns[_town]["name"]
	top.add_child(title)
	_money = UiTheme.caption("")
	top.add_child(_money)
	top.add_child(UiTheme.button("Market", show_section.bind("market")))
	top.add_child(UiTheme.button("Contracts", show_section.bind("contracts")))
	top.add_child(UiTheme.button("Crew", show_section.bind("crew")))
	top.add_child(UiTheme.button("Close (T)", close_requested.emit))
	_note = UiTheme.caption("")
	column.add_child(_note)
	_rows = VBoxContainer.new()
	column.add_child(_rows)
	refresh()


## Shows section: "market", "contracts" or "crew".
func show_section(section: String) -> void:
	_section = section
	if section == "contracts":
		_ledger.ask_board()
	refresh()


## Shows text in the note: the server's answer to something you asked.
func say(text: String) -> void:
	_note.text = text


## Rebuilds the rows from what the server last said.
func refresh() -> void:
	_shown = _summary()
	_money.text = "%d crowns" % _ledger.mine["money"]
	for child in _rows.get_children():
		child.free()
	market_rows.clear()
	match _section:
		"market":
			_build_market()
		"contracts":
			_build_contracts()
		"crew":
			_build_crew()


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_EVERY
		if _summary() != _shown:
			refresh()
		elif market_rows.has("fuel"):  # burning at the dock changes it in place, not the rows
			var ship := _trading_ship()
			if ship != null:
				(market_rows["fuel"] as Label).text = _fuel_text(ship)


## What the rows show, to see when it changes: your account and the ship you trade from.
func _summary() -> String:
	var ship := _trading_ship()
	return var_to_str([_ledger.mine, _section, ship.grid.cargo_list() if ship != null else null, ship.spares if ship != null else 0,
			_ledger.boards.get(_town), _crew_of(ship)])


static func _fuel_text(ship: Ship) -> String:
	return "Fuel      %d/%d   %d units a crown" % [roundi(ship.fuel), roundi(ship.fuel_capacity()), Economy.FUEL_PER_CROWN]


## Who's aboard ship, without where they stand: a walking repairer mustn't rebuild the
## rows under your mouse.
static func _crew_of(ship: Ship) -> Array:
	if ship == null:
		return []
	return ship.hands.map(func(hand: Dictionary) -> Array: return [hand["id"], hand["name"], hand["role"]])


## The ship you're aboard, when she's at this town's dock; else null.
func _trading_ship() -> Ship:
	var ship: Ship = _ship_aboard.call()
	if ship == null or not is_instance_valid(ship) or _ledger.sync.town_at(ship.global_position) != _town:
		return null
	return ship


func _build_market() -> void:
	var ship := _trading_ship()
	var me := _ledger.sync.name_of(multiplayer.get_unique_id())
	var gen := _ledger.sync.gen
	for good: String in Economy.GOODS:
		if Economy.GOODS[good]["price"] == 0:
			continue
		var aboard := 0
		if ship != null:
			for crate: Dictionary in ship.grid.cargo.values():
				if crate["good"] == good and crate["owner"] == me:
					aboard += 1
		var line := HBoxContainer.new()
		var label := _mono("%-8s buy %3d   sell %3d   aboard %d" % [Economy.GOODS[good]["name"], Economy.price(gen, _town, good),
				Economy.sell_price(gen, _town, good), aboard])
		line.add_child(label)
		market_rows[good] = label
		if ship != null:
			line.add_child(UiTheme.button("Buy", _ledger.trade.bind(good, 1)))
			line.add_child(UiTheme.button("Sell", _ledger.trade.bind(good, -1)))
		_rows.add_child(line)
	if ship == null:
		_rows.add_child(UiTheme.caption("Come aboard a ship at the dock to trade."))
		return
	var spares := HBoxContainer.new()
	spares.add_child(_mono("Spares    %d/%d   %d crowns each" % [ship.spares, Damage.SPARES_MAX, Economy.SPARE_PRICE]))
	spares.add_child(UiTheme.button("Fill", _ledger.buy_spares))
	_rows.add_child(spares)
	var fuel := HBoxContainer.new()
	var gauge := _mono(_fuel_text(ship))
	fuel.add_child(gauge)
	market_rows["fuel"] = gauge
	fuel.add_child(UiTheme.button("Fill", _ledger.buy_fuel))
	_rows.add_child(fuel)
	_rows.add_child(_mono("Hold      %d/%d crates" % [ship.grid.cargo.size(), ship.grid.cells_of("cargo_bay").size()]))


func _build_contracts() -> void:
	for offer: Dictionary in _ledger.boards.get(_town, []):
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s   %d crowns" % [offer["title"], offer["reward"]]
		line.add_child(label)
		line.add_child(UiTheme.button("Take", _ledger.take_contract.bind(offer["id"])))
		_rows.add_child(line)
	_rows.add_child(UiTheme.caption("Your contracts"))
	for contract: Dictionary in _ledger.mine["contracts"]:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s   %d crowns" % [contract["title"], contract["reward"]]
		if contract["kind"] == "bounty":
			label.text += "   %d/%d" % [contract["done"], contract["count"]]
		line.add_child(label)
		line.add_child(UiTheme.button("Drop", _ledger.drop_contract.bind(contract["id"])))
		_rows.add_child(line)


func _build_crew() -> void:
	var ship := _trading_ship()
	if ship == null:
		_rows.add_child(UiTheme.caption("Come aboard a ship at the dock to hire crew."))
		return
	_rows.add_child(_mono("Hands     %d/%d bunks" % [ship.hands.size(), ship.grid.cells_of("bunk").size()]))
	for role: String in Economy.HANDS:
		_rows.add_child(UiTheme.button("Hire %s   %d crowns" % [Economy.a_hand(role), Economy.HANDS[role]["fee"]], _ledger.hire.bind(role)))
	for hand in ship.hands:
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s, %s" % [hand["name"], hand["role"]]
		line.add_child(label)
		line.add_child(UiTheme.button("Dismiss", _ledger.dismiss.bind(hand["id"])))
		_rows.add_child(line)


static func _mono(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Hud.monospace())
	return label
