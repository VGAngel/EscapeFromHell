extends GutTest

# Tests for TopBar — the persistent header that appears when UIRouter
# has at least one screen open. We instantiate a fresh router and a
# fresh TopBar so we don't depend on the autoload state.

const TopBarScript := preload("res://scripts/ui/TopBar.gd")
const RouterScript := preload("res://scripts/managers/UIRouter.gd")

# ── Fake overlay with router_title ────────────────────────────────────────────

class FakeScreen extends CanvasLayer:
	signal closed
	var title_text: String = "Test"

	func open() -> void:
		visible = true

	func close() -> void:
		visible = false
		closed.emit()

	func router_title() -> String:
		return title_text


# Variant that lacks router_title — used to test the empty-title fallback.
class TitlelessScreen extends CanvasLayer:
	signal closed

	func open() -> void:
		visible = true

	func close() -> void:
		visible = false
		closed.emit()


var router: Node
var top_bar: CanvasLayer

func before_each() -> void:
	# Inject the router as a child node — TopBar looks it up at /root/UIRouter.
	# Easier: stub its lookup by using the autoload if registered, else the
	# tests fall back to a free-standing instance and we re-wire signals
	# manually below.
	router = RouterScript.new()
	router.name = "UIRouter"
	# Try to reach /root: if the autoload is registered, use it; otherwise add
	# our local instance to the tree's root so /root/UIRouter resolves.
	var root_node: Node = get_tree().root
	if root_node.has_node("UIRouter"):
		router = root_node.get_node("UIRouter")
	else:
		root_node.add_child(router)
	top_bar = TopBarScript.new()
	add_child_autofree(top_bar)

func after_each() -> void:
	# Drain anything still on the stack so test order doesn't matter.
	if is_instance_valid(router) and router.has_method("pop_all"):
		router.pop_all()

# ── Initial state ─────────────────────────────────────────────────────────────

func test_topbar_starts_hidden() -> void:
	# Internal _root Control should be invisible after _ready.
	assert_false(top_bar._root.visible, "should be hidden when no overlay open")

# ── Visibility on push ────────────────────────────────────────────────────────

func test_topbar_shows_when_screen_pushed() -> void:
	var s := FakeScreen.new()
	add_child_autofree(s)
	router.push(s)
	# Show is immediate; modulate fades over FADE seconds.
	assert_true(top_bar._root.visible, "should be visible after push")
	router.pop()

# ── Title ─────────────────────────────────────────────────────────────────────

func test_topbar_shows_title_from_router_title() -> void:
	var s := FakeScreen.new()
	s.title_text = "Колекція"
	add_child_autofree(s)
	router.push(s)
	assert_eq(top_bar._title_lbl.text, "Колекція")
	router.pop()

func test_topbar_clears_title_when_top_lacks_router_title() -> void:
	var s := TitlelessScreen.new()
	add_child_autofree(s)
	router.push(s)
	assert_eq(top_bar._title_lbl.text, "")
	router.pop()

# ── Back button ───────────────────────────────────────────────────────────────

func test_back_button_calls_pop() -> void:
	var s := FakeScreen.new()
	add_child_autofree(s)
	router.push(s)
	top_bar._on_back_pressed()
	# After pop, FakeScreen.close() emits closed → router removes from stack.
	assert_eq(router.depth(), 0, "router should be empty after back press")

# ── Resources ─────────────────────────────────────────────────────────────────

func test_resources_render_when_save_manager_present() -> void:
	# SaveManager autoload should be live in the test environment.
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		pending("SaveManager autoload not available in this test run")
		return
	top_bar._refresh_resources()
	# Labels should at least be populated (non-empty string with prefix).
	assert_true(top_bar._light_lbl.text.begins_with("💡"))
	assert_true(top_bar._souls_lbl.text.begins_with("👻"))
	assert_true(top_bar._sin_lbl.text.begins_with("😈"))
