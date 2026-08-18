local Element = require('elements/Element')

---@alias MenuAction {name: string; icon: string; label?: string; filter_hidden?: boolean;}

-- Menu data structure accepted by `Menu:open(menu)`.
---@alias MenuData {id?: string; type?: string; title?: string; hint?: string; footnote: string; search_style?: 'on_demand' | 'palette' | 'disabled';  item_actions?: MenuAction[]; item_actions_place?: 'inside' | 'outside'; callback?: string[]; keep_open?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; items?: MenuDataChild[]; selected_index?: integer; on_search?: string|string[]; on_paste?: string|string[]; on_move?: string|string[]; on_close?: string|string[]; search_debounce?: number|string; search_submenus?: boolean; search_suggestion?: string; search_submit?: boolean; bind_keys?: string[]}
---@alias MenuDataChild MenuDataItem|MenuData
---@alias MenuDataItem {title?: string; hint?: string; icon?: string; value: any; actions?: MenuAction[]; actions_place?: 'inside' | 'outside'; active?: boolean; keep_open?: boolean; selectable?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'}
---@alias MenuOptions {mouse_nav?: boolean;}

-- Internal data structure created from `MenuData`.
---@alias MenuStack {id?: string; type?: string; title?: string; hint?: string; footnote: string; search_style?: 'on_demand' | 'palette' | 'disabled';  item_actions?: MenuAction[]; item_actions_place?: 'inside' | 'outside'; callback?: string[]; selected_index?: number; action_index?: number; keep_open?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; items: MenuStackChild[]; on_search?: string|string[]; on_paste?: string|string[]; on_move?: string|string[]; on_close?: string|string[]; search_debounce?: number|string; search_submenus?: boolean; search_suggestion?: string; search_submit?: boolean; bind_keys?: string[]; parent_menu?: MenuStack; submenu_path: integer[]; active?: boolean; width: number; height: number; top: number; scroll_y: number; scroll_height: number; title_width: number; hint_width: number; max_width: number; is_root?: boolean; fling?: Fling, search?: Search, ass_safe_title?: string}
---@alias MenuStackChild MenuStackItem|MenuStack
---@alias MenuStackItem {title?: string; hint?: string; icon?: string; value: any; actions?: MenuAction[]; actions_place?: 'inside' | 'outside'; active?: boolean; keep_open?: boolean; selectable?: boolean; bold?: boolean; italic?: boolean; muted?: boolean; separator?: boolean; align?: 'left'|'center'|'right'; title_width: number; hint_width: number; ass_safe_hint?: string}
---@alias Fling {y: number, distance: number, time: number, easing: fun(x: number), duration: number, update_cursor?: boolean}
---@alias Search {query: string; cursor: number; timeout: unknown; min_top: number; max_width: number; source: {width: number; top: number; scroll_y: number; selected_index?: integer; items?: MenuStackChild[]}}

---@alias MenuEventActivate {type: 'activate'; index: number; value: any; action?: string; modifiers?: string; alt: boolean; ctrl: boolean; shift: boolean; is_pointer: boolean; keep_open?: boolean; menu_id: string;}
---@alias MenuEventMove {type: 'move'; from_index: number; to_index: number; menu_id: string;}
---@alias MenuEventSearch {type: 'search'; query: string; menu_id: string;}
---@alias MenuEventKey {type: 'key'; id: string; key: string; modifiers?: string; alt: boolean; ctrl: boolean; shift: boolean; menu_id: string; selected_item?: {index: number; value: any; action?: string;}}
---@alias MenuEventPaste {type: 'paste'; value: string; menu_id: string; selected_item?: {index: number; value: any; action?: string;}}
---@alias MenuEventBack {type: 'back';}
---@alias MenuEventClose {type: 'close';}
---@alias MenuEvent MenuEventActivate | MenuEventMove | MenuEventSearch | MenuEventKey | MenuEventPaste | MenuEventBack | MenuEventClose
---@alias MenuCallback fun(data: MenuEvent)

---@class Menu : Element
local Menu = class(Element)

---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
function Menu:open(data, callback, opts)
	local open_menu = Menu:is_open()
	if open_menu then
		open_menu.is_being_replaced = true
		open_menu:close(true)
	end
	return Menu:new(data, callback, opts)
end

---@param menu_type? string
---@return Menu|nil
function Menu:is_open(menu_type)
	return Elements.menu and (not menu_type or Elements.menu.type == menu_type) and Elements.menu or nil
end

---@param immediate? boolean Close immediately without fadeout animation.
---@param callback? fun() Called after the animation (if any) ends and element is removed and destroyed.
---@overload fun(callback: fun())
function Menu:close(immediate, callback)
	if type(immediate) ~= 'boolean' then callback = immediate end

	local menu = self == Menu and Elements.menu or self

	if state.ime_active == false and mp.get_property_bool('input-ime') then
		mp.set_property_bool('input-ime', false)
	end

	if menu and not menu.destroyed then
		if menu.is_closing then
			menu:tween_stop()
			return
		end

		local function close()
			local on_close = menu.root.on_close -- removed in menu:destroy()
			Elements:remove('menu') -- calls menu:destroy() under the hood
			Elements:update_proximities()
			cursor:queue_autohide()

			-- Call :close() callback
			if callback then callback() end

			-- Call callbacks/events defined on menu config
			local close_event = {type = 'close'}
			if not on_close or menu:command_or_event(on_close, {}, close_event) ~= 'event' then
				menu.callback(close_event)
			end

			request_render()
		end

		menu.is_closing = true

		if immediate then
			close()
		else
			menu:fadeout(close)
		end
	end
end

---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
---@return Menu
function Menu:new(data, callback, opts) return Class.new(self, data, callback, opts) --[[@as Menu]] end
---@param data MenuData
---@param callback MenuCallback
---@param opts? MenuOptions
function Menu:init(data, callback, opts)
	Element.init(self, 'menu', {render_order = 1001})

	-----@type fun()
	self.callback = callback
	self.opts = opts or {}
	self.offset_x = 0 -- Used for submenu transition animation.
	self.mouse_nav = self.opts.mouse_nav -- Stops pre-selecting items
	self.item_height = nil
	self.min_width = nil
	self.item_spacing = 1
	self.item_padding = nil
	self.separator_size = nil
	self.padding = nil
	self.gap = nil
	self.font_size = nil
	self.font_size_hint = nil
	self.scroll_step = nil -- Item height + item spacing.
	self.scroll_height = nil -- Items + spacings - container height.
	self.opacity = 0 -- Used to fade in/out.
	self.type = data.type
	---@type MenuStack Root MenuStack.
	self.root = nil
	---@type MenuStack Current MenuStack.
	self.current = nil
	---@type MenuStack[] All menus in a flat array.
	self.all = nil
	---@type table<string, MenuStack> Map of submenus by their ids, such as `'Tools > Aspect ratio'`.
	self.by_id = {}
	self.type_to_search = options.menu_type_to_search
	self.is_being_replaced = false
	self.is_closing = false
	self.drag_last_y = nil
	self.is_dragging = false

	if utils.shared_script_property_set then
		utils.shared_script_property_set('uosc-menu-type', self.type or 'undefined')
	end
	mp.set_property_native('user-data/uosc/menu/type', self.type or 'undefined')
	self:update(data)

	for _, menu in ipairs(self.all) do self:scroll_to_index(menu.selected_index, menu.id) end
	if self.mouse_nav then self.current.selected_index = nil end

	self:tween_property('opacity', 0, 1)
	self:enable_key_bindings()
	Elements:maybe('curtain', 'register', self.id)

	if data.search_submit then
		-- We have to defer this so that menu callbacks don't fire before the menu
		-- instance we're constructing here is returned, as they might depend on it.
		mp.add_timeout(0.01, function()
			self:search_submit()
		end)
	end
end

function Menu:destroy()
	Element.destroy(self)
	self.is_closing = false
	if not self.is_being_replaced then Elements:maybe('curtain', 'unregister', self.id) end
	if utils.shared_script_property_set then
		utils.shared_script_property_set('uosc-menu-type', nil)
	end
	mp.set_property_native('user-data/uosc/menu/type', nil)
end

---@param data MenuData
function Menu:update(data)
	local new_root = {is_root = true, submenu_path = {}}
	local new_all = {}
	local new_menus = {} -- menus that didn't exist before this `update()`
	local new_by_id = {}
	local menus_to_serialize = {{new_root, data}}
	local old_current_id = self.current and self.current.id
	local menu_state_props = {'selected_index', 'action_index', 'scroll_y', 'fling', 'search'}
	local internal_props_set = create_set(itable_append({'is_root', 'submenu_path', 'id', 'items'}, menu_state_props))

	table_assign_exclude(new_root, data, internal_props_set)

	local i = 0
	while i < #menus_to_serialize do
		i = i + 1
		local menu, menu_data = menus_to_serialize[i][1], menus_to_serialize[i][2]
		local parent_id = menu.parent_menu and not menu.parent_menu.is_root and menu.parent_menu.id
		if menu_data.id then
			menu.id = menu_data.id
		elseif not menu.is_root then
			menu.id = (parent_id and parent_id .. ' > ' or '') .. (menu_data.title or i)
		else
			menu.id = '{root}'
		end
		menu.icon = 'chevron_right'

		-- Normalize `search_debounce`
		if type(menu_data.search_debounce) == 'number' then
			menu.search_debounce = math.max(0, menu_data.search_debounce --[[@as number]])
		elseif menu_data.search_debounce == 'submit' then
			menu.search_debounce = 'submit'
		else
			menu.search_debounce = menu.on_search and 300 or 0
		end

		-- Update items
		local first_active_index = nil
		menu.items = {
			{title = t('Empty'), value = 'ignore', italic = 'true', muted = 'true', selectable = false, align = 'center'},
		}

		for i, item_data in ipairs(menu_data.items or {}) do
			if item_data.active and not first_active_index then first_active_index = i end

			local item = {}
			table_assign_exclude(item, item_data, internal_props_set)
			if item.keep_open == nil then item.keep_open = menu.keep_open end

			-- Submenu
			if item_data.items then
				item.parent_menu = menu
				item.submenu_path = itable_join(menu.submenu_path, {i})
				menus_to_serialize[#menus_to_serialize + 1] = {item, item_data}
			end

			menu.items[i] = item
		end

		if menu.is_root then menu.selected_index = menu_data.selected_index or first_active_index end

		-- Retain old state
		local old_menu = self.by_id[menu.id]
		if old_menu then
			table_assign_props(menu, old_menu, menu_state_props)
		else
			new_menus[#new_menus + 1] = menu
		end

		new_all[#new_all + 1] = menu
		new_by_id[menu.id] = menu
	end

	self.root, self.all, self.by_id = new_root, new_all, new_by_id
	self.current = self.by_id[old_current_id] or self.root

	self:update_content_dimensions()
	self:reset_navigation()

	-- Ensure palette menus have active searches, and clean empty searches from menus that lost the `palette` flag
	local update_dimensions_again = false
	for _, menu in ipairs(self.all) do
		local is_palette = menu.search_style == 'palette'
		if not menu.search and (is_palette or (menu.search_suggestion and itable_index_of(new_menus, menu))) then
			update_dimensions_again = true
			self:search_init(menu.id)
		elseif not is_palette and menu.search and menu.search.query == '' then
			update_dimensions_again = true
			menu.search = nil
		end
	end
	-- We update before _and_ after because search_inits need the initial un-searched
	-- menu's position and scroll state to save on the `search.source` table.
	if update_dimensions_again then
		self:update_content_dimensions()
		self:reset_navigation()
	end
	-- Apply search suggestions
	for _, menu in ipairs(new_menus) do
		if menu.search_suggestion then
			menu.search.query = menu.search_suggestion
			menu.search.cursor = #menu.search_suggestion
		end
	end
	for _, menu in ipairs(self.all) do
		if menu.search then
			-- the menu items are new objects and the search needs to contain those
			menu.search.source.items = not menu.on_search and menu.items or nil
			-- Only internal searches are immediately submitted
			if not menu.on_search then self:search_internal(menu.id, true) end
		end

		if menu.selected_index then self:select_by_offset(0, menu) end
	end

	self:search_ensure_key_bindings()
end

---@param items MenuDataChild[]
function Menu:update_items(items)
	local data = table_assign({}, self.root)
	data.items = items
	self:update(data)
end

-- DinaPlayer: size of the iOS-style switch drawn in place of the hint on rows
-- that carry a boolean `toggle`. 1.7:1 is the proportion of the iOS control.
function Menu:toggle_size()
	local h = round(self.font_size * 1.15)
	return round(h * 1.7), h
end

-- DinaPlayer: x bounds of column `index` (1 or 2) inside a `columns` menu.
function Menu:column_rect(menu, index, ax, bx)
	local width = (bx - ax - self.gap) / 2
	local cell_ax = ax + (index - 1) * (width + self.gap)
	return round(cell_ax), round(cell_ax + width)
end

function Menu:update_content_dimensions()
	-- DinaPlayer: `item_hint_below` (set on the menu data) stacks each item's hint
	-- under its title on a second line, so the row is taller. Font sizes/padding
	-- stay based on the normal height so the title text isn't enlarged.
	local base = round(fullscreen_size('menu_item_height') * state.scale)
	-- DinaPlayer: normal (non-inflated) row height, used for the screen-edge margin
	-- so two-line menus (item_hint_below) keep the same outer margins as normal ones.
	self.item_base_height = base
	self.item_height = (self.root and self.root.item_hint_below) and round(base * 1.5) or base
	self.min_width = round(fullscreen_size('menu_min_width') * state.scale)
	self.separator_size = round(1 * state.scale)
	self.scrollbar_size = round(2 * state.scale)
	self.padding = round(fullscreen_size('menu_padding') * state.scale)
	self.gap = round(4 * state.scale)
	self.font_size = round(base * 0.48 * options.font_scale)
	self.font_size_hint = self.font_size - 1
	self.item_padding = round((base - self.font_size) * 0.6)
	self.scroll_step = self.item_height + self.item_spacing

	local title_opts = {size = self.font_size, italic = false, bold = false}
	local hint_opts = {size = self.font_size_hint}

	for _, menu in ipairs(self.all) do
		title_opts.bold, title_opts.italic = true, false
		local max_width = text_width(menu.title, title_opts) + 2 * self.item_padding

		-- Reserve the icon column for every row when the menu has any icon OR forces
		-- it via reserve_icons. Forcing keeps the layout identical even when the list
		-- currently has zero icons, so a "no icon" cell equals an invisible icon and
		-- nothing shifts when one is toggled on/off.
		menu.has_icons = menu.reserve_icons or false
		for _, item in ipairs(menu.items) do
			if item.icon then menu.has_icons = true break end
		end

		-- DinaPlayer: fixed-width number column. Its width is the widest item.number,
		-- so every title starts at the same x regardless of the number (rendered
		-- right-aligned in the item loop).
		menu.number_width = 0
		for _, item in ipairs(menu.items) do
			if item.number then
				menu.number_width = math.max(menu.number_width, text_width(item.number, title_opts))
			end
		end

		-- Estimate width of a widest item
		local number_width = menu.number_width > 0 and (menu.number_width + self.item_padding) or 0
		for _, item in ipairs(menu.items) do
			local icon_width = (item.icon or menu.has_icons) and self.font_size or 0
			item.title_width = text_width(item.title, title_opts)
			-- DinaPlayer: a switch occupies the hint's slot, so it reserves its width.
			item.hint_width = item.toggle ~= nil
				and select(1, self:toggle_size())
				or text_width(item.hint, hint_opts)
			local estimated_width
			if menu.item_hint_below then
				-- DinaPlayer: two-line items stack title over hint, so the width is
				-- the wider of the two lines, not their sum.
				local line_width = math.max(item.title_width, item.hint_width) + icon_width
				local spacings_in_item = 1 + (line_width > 0 and 1 or 0)
				estimated_width = line_width + (self.item_padding * spacings_in_item)
			else
				local spacings_in_item = 1 + (item.title_width > 0 and 1 or 0)
					+ (item.hint_width > 0 and 1 or 0) + (icon_width > 0 and 1 or 0)
				estimated_width = item.title_width + item.hint_width + icon_width
					+ (self.item_padding * spacings_in_item)
			end
			estimated_width = estimated_width + number_width
			-- DinaPlayer: `columns` renders every row twice, side by side.
			if menu.columns then estimated_width = estimated_width * 2 + self.gap end
			if estimated_width > max_width then max_width = estimated_width end
		end

		menu.max_width = max_width
	end

	self:update_dimensions()
end

-- DinaPlayer: which side a bottom-anchored popup opens on. The playlist/files
-- menu (opened by the left-side `items` control) opens on the LEFT; every other
-- menu follows the global bottom_right anchor. Returns 'left' | 'right' | 'center'.
function Menu:anchor_side()
	if options.menu_anchor ~= 'bottom_right' then return 'center' end
	if self.type == 'playlist' or self.type == 'open-file' then return 'left' end
	return 'right'
end

function Menu:update_dimensions()
	-- Coordinates and sizes are of the scrollable area. Title is rendered
	-- above it, so we need to account for that in max_height and ay position.
	-- This is a debt from an era where we had different cursor event handling,
	-- and dumb titles with no search inputs. It could use a refactor.
	local margin = round((self.item_base_height or self.item_height) / 2)
	local external_buttons_reserve = display.width / self.item_height > 14 and self.scroll_step * 6 - margin * 2 or 0
	local width_available = display.width - margin * 2 - self.padding * 2 - external_buttons_reserve
	local height_available = display.height - margin * 2 - self.padding * 2
	local min_width = math.min(self.min_width, width_available)

	for _, menu in ipairs(self.all) do
		local width = math.max(menu.search and menu.search.max_width or 0, menu.max_width)
		-- DinaPlayer: `menu_min_width` is the minimum for the popup, not per column —
		-- doubling it for a two-column menu only bought empty space, since the
		-- content estimate above already accounts for both cells.
		menu.width = round(clamp(min_width, width, width_available))
		-- DinaPlayer: the extra `self.padding` is the gap below the header text (before
		-- the separator), mirroring the top gap so the header matches a normal item's
		-- padding on both sides. bg_rect.ay below reserves the matching top space.
		local title_height = (menu.is_root and (menu.title or menu.segments or menu.columns) or menu.search) and
			self.scroll_step + self.padding + self.separator_size + 1 or 0
		-- DinaPlayer: footnotes and the "?" action hint are removed, so no bottom
		-- space is reserved.
		local footnote_height = 0
		-- DinaPlayer: optionally anchor the menu's bottom edge above the control
		-- bar (YouTube-style popup) instead of centering it vertically.
		local bottom_anchored = self:anchor_side() ~= 'center'
		local bottom_limit = height_available
		if bottom_anchored then
			local controls = Elements.controls
			if controls and controls.enabled and controls.ay and controls.ay > 0 then
				bottom_limit = math.min(bottom_limit, controls.ay - margin)
			end
		end
		local max_height = bottom_limit - title_height - footnote_height
		-- DinaPlayer: optional cap on visible rows (data.max_visible); extra rows
		-- scroll. The fixed title/header is separate and not counted here.
		if menu.max_visible then
			max_height = math.min(max_height, self.scroll_step * menu.max_visible - self.item_spacing)
		end
		local content_height = self.scroll_step * #menu.items
		menu.height = math.min(content_height - self.item_spacing, max_height)
		if bottom_anchored then
			menu.top = math.max(
				title_height + margin + self.padding,
				round(bottom_limit - footnote_height - menu.height)
			)
		else
			menu.top = clamp(
				title_height + margin + self.padding,
				menu.search and math.min(menu.search.min_top, menu.search.source.top) or height_available,
				round((height_available - menu.height + title_height) / 2)
			)
		end
		if menu.search then
			menu.search.min_top = math.min(menu.search.min_top, menu.top)
			menu.search.max_width = math.max(menu.search.max_width, menu.width)
		end
		menu.scroll_height = math.max(content_height - menu.height - self.item_spacing, 0)
		self:set_scroll_to(menu.scroll_y, menu.id) -- clamps scroll_y to scroll limits
	end

	self:update_coordinates()
end

-- Updates element coordinates to match padding box of currently open (sub)menu.
function Menu:update_coordinates()
	local ax
	local side = self:anchor_side()
	local margin = round((self.item_base_height or self.item_height) / 2)
	if side == 'right' then
		-- DinaPlayer: right-align the popup near the window edge (YouTube-style)
		ax = round(display.width - margin - self.current.width - self.padding * 2) + self.offset_x
	elseif side == 'left' then
		-- DinaPlayer: left-align (mirror of right) for the playlist/files menu
		ax = round(margin) + self.offset_x
	else
		ax = round((display.width - self.current.width) / 2 - self.padding) + self.offset_x
	end
	self:set_coordinates(
		ax, self.current.top - self.padding,
		ax + self.current.width + self.padding * 2, self.current.top + self.current.height + self.padding
	)
end

function Menu:reset_navigation()
	local menu = self.current

	-- Reset indexes and scroll
	self:set_scroll_to(menu.scroll_y) -- clamps scroll_y to scroll limits
	if menu.items and #menu.items > 0 then
		-- Normalize existing selected_index always, and force it only in keyboard navigation
		if not self.mouse_nav then
			self:select_by_offset(0)
		end
	else
		self:select_index(nil)
	end

	-- Walk up the parent menu chain and activate items that lead to current menu
	local parent = menu.parent_menu
	while parent do
		parent.selected_index = itable_index_of(parent.items, menu)
		menu, parent = parent, parent.parent_menu
	end

	request_render()
end

function Menu:set_offset_x(offset)
	local delta = offset - self.offset_x
	self.offset_x = offset
	self:set_coordinates(self.ax + delta, self.ay, self.bx + delta, self.by)
end

function Menu:fadeout(callback) self:tween_property('opacity', 1, 0, callback) end

-- If `menu_id` is provided, will return menu with that id or `nil`. If `menu_id` is `nil`, will return current menu.
---@param menu_id? string
---@return MenuStack | nil
function Menu:get_menu(menu_id) return menu_id == nil and self.current or self.by_id[menu_id] end

function Menu:get_first_active_index(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	for index, item in ipairs(menu.items) do
		if item.active then return index end
	end
end

---@param pos? number
---@param menu_id? string
function Menu:set_scroll_to(pos, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	menu.scroll_y = clamp(0, pos or 0, menu.scroll_height)
	request_render()
end

---@param delta? number
---@param menu_id? string
function Menu:set_scroll_by(delta, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	self:set_scroll_to(menu.scroll_y + delta, menu_id)
end

---@param pos? number
---@param menu_id? string
---@param fling_options? table
function Menu:scroll_to(pos, menu_id, fling_options)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	menu.fling = {
		y = menu.scroll_y,
		distance = clamp(-menu.scroll_y, pos - menu.scroll_y, menu.scroll_height - menu.scroll_y),
		time = mp.get_time(),
		duration = 0.1,
		easing = ease_out_sext,
	}
	if fling_options then table_assign(menu.fling, fling_options) end
	request_render()
end

---@param delta? number
---@param menu_id? string
---@param fling_options? Fling
function Menu:scroll_by(delta, menu_id, fling_options)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	self:scroll_to((menu.fling and (menu.fling.y + menu.fling.distance) or menu.scroll_y) + delta, menu_id, fling_options)
end

---@param index? integer
---@param menu_id? string
---@param immediate? boolean
function Menu:scroll_to_index(index, menu_id, immediate)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	if (index and index >= 1 and index <= #menu.items) then
		local position = round((self.scroll_step * (index - 1)) - ((menu.height - self.scroll_step) / 2))
		if immediate then
			self:set_scroll_to(position, menu_id)
		else
			self:scroll_to(position, menu_id)
		end
	end
end

---@param index? integer
---@param menu_id? string
function Menu:select_index(index, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	menu.selected_index = (index and index >= 1 and index <= #menu.items) and index or nil
	self:select_action(menu.action_index, menu_id) -- normalize selected action index
	request_render()
end

---@param index? integer
---@param menu_id? string
function Menu:select_action(index, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local actions = menu.items[menu.selected_index] and menu.items[menu.selected_index].actions or menu.item_actions
	if not index or not actions or type(actions) ~= 'table' or index < 1 or index > #actions then
		menu.action_index = nil
		return
	end
	menu.action_index = index
	request_render()
end

---@param delta? integer
---@param menu_id? string
function Menu:navigate_action(delta, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local actions = menu.items[menu.selected_index] and menu.items[menu.selected_index].actions or menu.item_actions
	if actions and delta ~= 0 then
		-- Circular navigation where zero gets converted to nil
		local index = (menu.action_index or (delta > 0 and 0 or #actions + 1)) + delta
		self:select_action(index <= #actions and index > 0 and (index - 1) % #actions + 1 or nil, menu_id)
	else
		self:select_action(nil, menu_id)
	end
	request_render()
end

function Menu:next_action() self:navigate_action(1) end
function Menu:prev_action() self:navigate_action(-1) end

---@param value? any
---@param menu_id? string
function Menu:select_value(value, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:select_index(index)
end

---@param menu_id? string
function Menu:deactivate_items(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	for _, item in ipairs(menu.items) do item.active = false end
	request_render()
end

---@param index? integer
---@param menu_id? string
function Menu:activate_index(index, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	if index and index >= 1 and index <= #menu.items then menu.items[index].active = true end
	request_render()
end

---@param value? any
---@param menu_id? string
function Menu:activate_value(value, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:activate_index(index, menu_id)
end

---@param value? any
---@param menu_id? string
function Menu:activate_one_value(value, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:activate_index(index, menu_id)
end

---@param id string One of menus in `self.all`.
function Menu:activate_menu(id)
	local menu = self:get_menu(id)
	if menu then
		self.current = menu
		self:update_coordinates()
		self:reset_navigation()
		self:search_ensure_key_bindings()
		local parent = menu.parent_menu
		while parent do
			parent.selected_index = itable_index_of(parent.items, menu)
			self:scroll_to_index(parent.selected_index, parent)
			menu, parent = parent, parent.parent_menu
		end
		request_render()
	end
end

---@param index? integer
---@param menu_id? string
function Menu:delete_index(index, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	if (index and index >= 1 and index <= #menu.items) then
		table.remove(menu.items, index)
		self:update_content_dimensions()
		self:scroll_to_index(menu.selected_index, menu_id)
	end
end

---@param value? any
---@param menu_id? string
function Menu:delete_value(value, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local index = itable_find(menu.items, function(item) return item.value == value end)
	self:delete_index(index)
end

---@param id string Menu id.
---@param x number `x` coordinate to slide from.
function Menu:slide_in_menu(id, x)
	local menu = self:get_menu(id)
	if not menu then return end
	self:activate_menu(id)
	self:tween(-(display.width / 2 - menu.width / 2 - x), 0, function(offset) self:set_offset_x(offset) end)
	self.opacity = 1 -- in case tween above canceled fade in animation
end

function Menu:back()
	if not self:is_alive() then return end

	local current = self.current
	local parent = current.parent_menu

	if parent then
		self:slide_in_menu(parent.id, display.width / 2 - current.width / 2 - parent.width / 2 + self.offset_x)
	else
		self.callback({type = 'back'})
	end
end

---@param shortcut? Shortcut
---@param is_pointer? boolean Whether this was called by a pointer.
function Menu:activate_selected_item(shortcut, is_pointer)
	local menu = self.current
	local item = menu.items[menu.selected_index]
	if item then
		-- Is submenu
		if item.items then
			if not self.mouse_nav then
				self:select_index(1, item.id)
			end
			self:activate_menu(item.id)
			self:tween(self.offset_x + menu.width / 2, 0, function(offset) self:set_offset_x(offset) end)
			self.opacity = 1 -- in case tween above canceled fade in animation
		else
			local actions = item.actions or menu.item_actions
			local action = actions and actions[menu.action_index]
			self.callback({
				type = 'activate',
				index = menu.selected_index,
				value = item.value,
				is_pointer = is_pointer == true,
				action = action and action.name,
				keep_open = item.keep_open or menu.keep_open,
				modifiers = shortcut and shortcut.modifiers or nil,
				alt = shortcut and shortcut.alt or false,
				ctrl = shortcut and shortcut.ctrl or false,
				shift = shortcut and shortcut.shift or false,
				menu_id = menu.id,
			})
		end
	end
end

---@param index integer
function Menu:move_selected_item_to(index)
	if self.current.search then return end -- Moving filtered items is an undefined behavior
	local callback = self.current.on_move
	local from, items_count = self.current.selected_index, self.current.items and #self.current.items or 0
	if callback and from and from ~= index and index >= 1 and index <= items_count then
		local event = {type = 'move', from_index = from, to_index = index, menu_id = self.current.id}
		self:command_or_event(callback, {from, index, self.current.id}, event)
		self:select_index(index, self.current.id)
		self:scroll_to_index(index, self.current.id, true)
	end
end

---@param delta number
function Menu:move_selected_item_by(delta)
	local current_index, items_count = self.current.selected_index, self.current.items and #self.current.items or 0
	if current_index and items_count > 1 then
		local new_index = clamp(1, current_index + delta, items_count)
		if current_index ~= new_index then
			self:move_selected_item_to(new_index)
		end
	end
end

function Menu:on_display() self:update_dimensions() end
function Menu:on_prop_fullormaxed() self:update_content_dimensions() end
function Menu:on_options() self:update_content_dimensions() end

function Menu:handle_cursor_down()
	if self.proximity_raw <= 0 then
		self.drag_last_y = cursor.y
		self.current.fling = nil
	else
		-- DinaPlayer: a click outside the menu that lands on a control-bar button
		-- should act on that button instead of only closing the menu. Menu buttons
		-- (subtitles/audio/settings/playlist) then switch the popup — Menu:open()
		-- replaces the currently open one — instead of just dismissing it. Clicks
		-- on empty space still close the menu as before. Without this, the menu's
		-- display-wide close zone (registered last, so it wins hit-testing) swallows
		-- the click and only the current menu closes.
		local button = self:hovered_control_button()
		if button then
			button:handle_cursor_click()
		else
			-- DinaPlayer: a click on a top-bar window control (close/max/min) both
			-- closes the menu and fires the action, like the control-bar buttons.
			local top_bar = Elements.top_bar
			local win_button = top_bar and top_bar:window_button_at_cursor()
			self:close()
			if win_button then win_button.command() end
		end
	end
end

-- DinaPlayer: the clickable control-bar button currently under the cursor, if any.
---@return Element|nil
function Menu:hovered_control_button()
	for _, el in Elements:ipairs() do
		if el.anchor_id == 'controls' and el.enabled and el.is_clickable and el.on_click
			and el.proximity_raw <= 0 and el:get_visibility() > 0 then
			return el
		end
	end
	return nil
end

---@param shortcut? Shortcut
function Menu:handle_cursor_up(shortcut)
	if self.proximity_raw <= -self.padding and self.drag_last_y and not self.is_dragging then
		self:activate_selected_item(shortcut, true)
	end
	if self.is_dragging then
		local distance = cursor:get_velocity().y / -3
		if math.abs(distance) > 50 then
			self.current.fling = {
				y = self.current.scroll_y,
				distance = distance,
				time = cursor.history:head().time,
				easing = ease_out_quart,
				duration = 0.5,
				update_cursor = true,
			}
			request_render()
		end
	end
	self.is_dragging = false
	self.drag_last_y = nil
end

function Menu:on_global_mouse_move()
	self.mouse_nav = true
	if self.drag_last_y then
		self.is_dragging = self.is_dragging or math.abs(cursor.y - self.drag_last_y) >= 10
		if self.is_dragging then
			local distance = self.drag_last_y - cursor.y
			if distance ~= 0 then self:set_scroll_by(distance) end
			self.drag_last_y = cursor.y
		end
	end
	request_render()
end

function Menu:handle_wheel_up() self:scroll_by(self.scroll_step * -3, nil, {update_cursor = true}) end
function Menu:handle_wheel_down() self:scroll_by(self.scroll_step * 3, nil, {update_cursor = true}) end

---@param offset integer
---@param menu? MenuStack
function Menu:select_by_offset(offset, menu)
	menu = menu or self.current

	-- Blur selected_index when navigating off bounds and submittable search is active.
	-- Blurred selected_index is an implied focused input, so enter can submit it.
	if menu.search and menu.search_debounce == 'submit' and (
			(menu.selected_index == 1 and offset < 0) or (menu.selected_index == #menu.items and offset > 0)
		) then
		self:select_index(nil, menu.id)
	else
		local index = clamp(1, (menu.selected_index or offset >= 0 and 0 or #menu.items + 1) + offset, #menu.items)
		local prev_index = itable_find(menu.items, function(item) return item.selectable ~= false end, index, 1)
		local next_index = itable_find(menu.items, function(item) return item.selectable ~= false end, index)
		if prev_index and next_index then
			if offset == 0 then
				self:select_index(index - prev_index <= next_index - index and prev_index or next_index, menu.id)
			elseif offset > 0 then
				self:select_index(next_index, menu.id)
			else
				self:select_index(prev_index, menu.id)
			end
		else
			self:select_index(prev_index or next_index or nil, menu.id)
		end
	end

	request_render()
end

---@param offset integer
---@param immediate? boolean
function Menu:navigate_by_items(offset, immediate)
	self:select_by_offset(offset)
	if self.current.selected_index then
		self:scroll_to_index(self.current.selected_index, self.current.id, immediate)
	end
end

---@param offset integer
---@param immediate? boolean
function Menu:navigate_by_page(offset, immediate)
	local items_per_page = round((self.current.height / self.scroll_step) * 0.4)
	self:navigate_by_items(items_per_page * offset, immediate)
end

function Menu:paste()
	local menu = self.current
	local payload = get_clipboard()
	if not payload then return end
	if menu.search then
		self:search_query_insert(payload)
	elseif menu.on_paste then
		local selected_item = menu.items and menu.selected_index and menu.items[menu.selected_index]
		local actions = selected_item and selected_item.actions or menu.item_actions
		local selected_action = actions and menu.action_index and actions[menu.action_index]
		self:command_or_event(menu.on_paste, {payload, menu.id}, {
			type = 'paste',
			value = payload,
			menu_id = menu.id,
			selected_item = selected_item and {
				index = menu.selected_index, value = selected_item.value, action = selected_action,
			},
		})
	elseif menu.search_style ~= 'disabled' then
		self:search_start(menu.id)
		self:search_query_replace(payload, menu.id)
	end
end

---@param menu_id string
---@param no_select_first? boolean
function Menu:search_internal(menu_id, no_select_first)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	local query = menu.search.query:lower()
	if query == '' then
		-- Reset menu state to what it was before search
		for key, value in pairs(menu.search.source) do menu[key] = value end
	else
		-- Inherit `search_submenus` from parent menus
		local search_submenus, parent_menu = menu.search_submenus, menu.parent_menu
		while not search_submenus and parent_menu do
			search_submenus, parent_menu = parent_menu.search_submenus, parent_menu.parent_menu
		end
		menu.items = search_items(menu.search.source.items, query, search_submenus)
		-- Select 1st item in search results
		if not no_select_first then
			menu.scroll_y = 0
			self:select_index(1, menu_id)
		end
	end
	self:update_content_dimensions()
end

---@param items MenuStackChild[]
---@param query string
---@param recursive? boolean
---@param prefix? string
---@return MenuStackChild[]
function search_items(items, query, recursive, prefix)
	local result = {}
	local haystacks = {}
	local flat_items = {}
	local concat = table.concat
	local romanization = need_romanization()

	for _, item in ipairs(items) do
		if item.selectable ~= false then
			local prefixed_title = prefix and prefix .. ' / ' .. (item.title or '') or item.title
			haystacks[#haystacks + 1] = item.title
			flat_items[#flat_items + 1] = item

			if item.items and recursive then
				itable_append(result, search_items(item.items, query, recursive, prefixed_title))
			end
		end
	end

	local seen = {}

	local fuzzy = fzy.filter(query, haystacks, false)
	for _, match in ipairs(fuzzy) do
		local idx, positions, score = match[1], match[2], match[3]
		local matched_title = haystacks[idx]
		local item = flat_items[idx]
		local prefixed_title = prefix and prefix .. ' / ' .. (item.title or '') or item.title

		if item.selectable ~= false and not (item.items and recursive) and not seen[item] then
			local bold = item.bold or options.font_bold
			local font_color = item.active and fgt or bgt
			local ass_safe_title = highlight_match(matched_title, positions, font_color, bold) or nil
			local new_item = table_assign({}, item)
			new_item.title = prefixed_title
			new_item.ass_safe_title = prefix and prefix .. ' / ' .. (ass_safe_title or '') or ass_safe_title
			new_item.score = score
			result[#result + 1] = new_item
			seen[item] = true
		end
	end

	for _, item in ipairs(items) do
		local title = item.title and item.title:lower()
		local hint = item.hint and item.hint:lower()
		local bold = item.bold or options.font_bold
		local font_color = item.active and fgt or bgt
		local ass_safe_title = nil
		local prefixed_title = prefix and prefix .. ' / ' .. (item.title or '') or item.title
		if item.selectable ~= false and not (item.items and recursive) and not seen[item] then
			local score = 0
			local match = false

			if title and romanization then
				local ligature_conv_title, ligature_roman = char_conv(title, true)
				local initials_arr_conv, initials_roman = char_conv(title, false)
				local initials_conv_title = concat(initials(initials_arr_conv))
				if ligature_conv_title:find(query, 1, true) then
					match = true
					score = 1000
					local pos = get_roman_match_positions(title, query, 'ligature', ligature_roman)
					if pos then
						ass_safe_title = highlight_match(item.title, pos, font_color, bold)
					end
				elseif initials_conv_title:find(query, 1, true) then
					match = true
					score = 900
					local pos = get_roman_match_positions(title, query, 'initial', initials_roman)
					if pos then
						ass_safe_title = highlight_match(item.title, pos, font_color, bold)
					end
				end
			end

			if hint and not match then
				if hint:find(query, 1, true) then
					match = true
					score = 100
				elseif concat(initials(hint)):find(query, 1, true) then
					match = true
					score = 90
				end
			end

			if match then
				local new_item = table_assign({}, item)
				new_item.title = prefixed_title
				new_item.ass_safe_title = prefix and prefix .. ' / ' .. (ass_safe_title or '') or ass_safe_title
				new_item.score = score
				result[#result + 1] = new_item
			end
		end
	end

	table.sort(result, function(a, b) return a.score > b.score end)

	return result
end

---@param menu_id? string
function Menu:search_submit(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu or not menu.search then return end
	local callback, query = menu.on_search, menu.search.query
	if callback then
		self:command_or_event(callback, {query, menu.id}, {type = 'search', query = query, menu_id = menu.id})
	else
		self:search_internal(menu.id)
	end
end

-- Move search query cursor by an amount.
---@param amount number `<0` for left, `>0` for right.
---@param word_mode? boolean Move by words/segments. Overwrites amount, but respects its direction.
function Menu:search_cursor_move(amount, word_mode)
	local menu = self:get_menu()
	if not menu or not menu.search then return end
	local query, cursor = menu.search.query, menu.search.cursor
	if word_mode then
		menu.search.cursor = find_string_segment_bound(query, cursor, amount) + (amount < 0 and -1 or 0)
	else
		local move = amount > 0 and utf8_next or utf8_prev
		local step_count = 0
		local limit = math.abs(amount)

		while step_count < limit do
			local next_cursor = move(query, cursor)
			if next_cursor == cursor then break end
			cursor = next_cursor
			step_count = step_count + 1
		end

		menu.search.cursor = clamp(0, cursor, #query)
	end
	request_render()
end

---@param query string
---@param menu_id? string
---@param immediate? boolean
function Menu:search_query_replace(query, menu_id, immediate)
	local menu = self:get_menu(menu_id)
	if not menu or not menu.search then return end
	menu.search.query = query
	menu.search.cursor = #query
	self:search_trigger(menu_id, immediate)
end

-- Insert string into search query at cursor.
---@param str string
---@param menu_id? string
function Menu:search_query_insert(str, menu_id)
	local menu = self:get_menu(menu_id)
	if not menu or not menu.search then return end
	local query, cursor = menu.search.query, menu.search.cursor
	local head, tail = string.sub(query, 1, cursor), string.sub(query, cursor + 1)
	menu.search.query = head .. str .. tail
	menu.search.cursor = cursor + #str
	self:search_trigger(menu_id)
end

-- Trigger menu search callbacks, should be called after any query changes.
function Menu:search_trigger(menu_id, immediate)
	local menu = self:get_menu(menu_id)
	if not menu or not menu.search then return end
	if menu.search_debounce ~= 'submit' then
		if menu.search.timeout then menu.search.timeout:kill() end
		if menu.search.timeout and not immediate then
			menu.search.timeout:resume()
		else
			self:search_submit(menu_id)
		end
	else
		-- `search_debounce='submit'` behavior: We blur selected item when query
		-- changes to let [enter] key submit searches instead of activating items.
		self:select_index(nil, menu.id)
	end
	request_render()
end

---@param event? string
---@param word_mode? boolean Delete by words.
function Menu:search_query_backspace(event, word_mode)
	local search = self.current.search
	if not search then return end

	local cursor, old_query = search.cursor, search.query
	local head, tail = string.sub(old_query, 1, cursor), string.sub(old_query, cursor + 1)

	if word_mode then
		cursor = find_string_segment_bound(head, cursor, -1) - 1
	elseif cursor > 0 then
		-- The while loop is for skipping utf8 continuation bytes
		while cursor > 1 and old_query:byte(cursor) >= 0x80 and old_query:byte(cursor) <= 0xbf do
			cursor = cursor - 1
		end
		cursor = cursor - 1
	end

	local new_query = head:sub(1, cursor) .. tail
	if new_query ~= old_query then
		search.query = new_query
		search.cursor = math.max(0, cursor)
		self:search_trigger()
	end

	if #new_query == 0 then
		local is_palette = self.current.search_style == 'palette'
		if not is_palette and self.type_to_search then
			self:search_cancel()
		elseif is_palette and event ~= 'repeat' then
			self:back()
		end
	end
end

---@param event? string
---@param word_mode? boolean Delete by words.
function Menu:search_query_delete(event, word_mode)
	local search = self.current.search
	if not search then return end

	local cursor, old_query = search.cursor, search.query
	local head, tail = string.sub(old_query, 1, cursor), string.sub(old_query, cursor + 1)
	local tail_cursor = 1

	if word_mode then
		tail_cursor = find_string_segment_bound(tail, 0, 1) + 1
	else
		-- The while loop is for skipping utf8 continuation bytes
		while tail_cursor < #tail and tail:byte(tail_cursor) >= 0x80 and tail:byte(tail_cursor) <= 0xbf do
			tail_cursor = tail_cursor + 1
		end
		tail_cursor = tail_cursor + 1
	end

	local new_query = head .. tail:sub(tail_cursor)
	if new_query ~= old_query then
		search.query = new_query
		search.cursor = #head
		self:search_trigger()
	end

	if #new_query == 0 then
		local is_palette = self.current.search_style == 'palette'
		if not is_palette and self.type_to_search then
			self:search_cancel()
		elseif is_palette and event ~= 'repeat' then
			self:back()
		end
	end
end

function Menu:search_text_input(info)
	local menu = self.current
	if not menu.search and menu.search_style == 'disabled' then return end
	if info.event ~= 'up' then
		local key_text = info.key_text
		if not key_text then
			-- might be KP0 to KP9 or KP_DEC
			key_text = info.key_name:match('KP_?(.+)')
			if not key_text then return end
			if key_text == 'DEC' then key_text = '.' end
		end
		if not menu.search then self:search_start() end
		self:search_query_insert(key_text)
	end
end

---@param menu_id? string
function Menu:search_cancel(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu or not menu.search or menu.search_style == 'palette' then
		self:search_query_replace('', menu_id)
		return
	end
	if state.ime_active == false then
		mp.set_property_bool('input-ime', false)
	end
	self:search_query_replace('', menu_id, true)
	menu.search = nil
	self:search_ensure_key_bindings()
	self:update_dimensions()
	self:reset_navigation()
end

---@param menu_id? string
function Menu:search_init(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	if menu.search then return end
	if state.ime_active == false then
		mp.set_property_bool('input-ime', true)
	end
	local timeout
	if menu.search_debounce ~= 'submit' and menu.search_debounce > 0 then
		timeout = mp.add_timeout(menu.search_debounce / 1000, self:create_action(function()
			self:search_submit(menu.id)
		end))
		timeout:kill()
	end
	menu.search = {
		query = '',
		cursor = 0,
		timeout = timeout,
		min_top = menu.top,
		max_width = menu.width,
		source = {
			width = menu.width,
			top = menu.top,
			scroll_y = menu.scroll_y,
			selected_index = menu.selected_index,
			items = not menu.on_search and menu.items or nil,
		},
	}
end

---@param menu_id? string
function Menu:search_start(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu or menu.search_style == 'disabled' then return end
	self:search_init(menu_id)
	self:search_ensure_key_bindings()
	self:update_dimensions()
end

---@param menu_id? string
function Menu:search_clear_query(menu_id)
	local menu = self:get_menu(menu_id)
	if not menu then return end
	if not self.current.search_style == 'palette' and self.type_to_search then
		self:search_cancel(menu_id)
	else
		self:search_query_replace('', menu_id)
	end
end

function Menu:search_enable_key_bindings()
	if self:has_keybindings('search') then return end
	local flags = {repeatable = true, complex = true}
	self:add_key_binding('any_unicode', {self:create_key_handler('search_text_input'), flags}, 'search')
	-- KP0 to KP9 and KP_DEC are not included in any_unicode
	-- despite typically producing characters, they don't have a info.key_text
	self:add_key_binding('kp_dec', {self:create_key_handler('search_text_input'), flags}, 'search')
	for i = 0, 9 do
		self:add_key_binding('kp' .. i, {self:create_key_handler('search_text_input'), flags}, 'search')
	end
end

function Menu:search_ensure_key_bindings()
	if self.current.search or (self.type_to_search and self.current.search_style ~= 'disabled') then
		self:search_enable_key_bindings()
	else
		self:remove_key_bindings('search')
	end
end

function Menu:enable_key_bindings()
	-- DinaPlayer: dropped the search shortcuts ('/', 'kp_divide', 'ctrl+f') and
	-- paste ('ctrl+v') so no key opens a search in menus.
	local standalone_keys = {'mbtn_back', 'ctrl+c'}
	if type(self.root.bind_keys) == 'table' then itable_append(standalone_keys, self.root.bind_keys) end
	-- `+` at the end enables `repeatable` flag
	local modifiable_keys = {'up+', 'down+', 'left', 'right', 'enter', 'kp_enter', 'bs', 'tab', 'esc', 'pgup+',
		'pgdwn+', 'home', 'end', 'del'}
	local modifiers = {nil, 'alt', 'alt+ctrl', 'alt+shift', 'alt+ctrl+shift', 'ctrl', 'ctrl+shift', 'shift'}

	---@param shortcut Shortcut
	---@param flags table<string, boolean>
	local function bind(shortcut, flags)
		local handler = self:create_action(function(info) self:handle_shortcut(shortcut, info) end)
		self:add_key_binding(shortcut.id, {handler, flags})
	end

	for i, key in ipairs(standalone_keys) do
		bind(create_shortcut(key), {repeatable = false, complex = true})
	end

	for i, key in ipairs(modifiable_keys) do
		local flags = {repeatable = false, complex = true}

		if key:sub(-1) == '+' then
			key = key:sub(1, -2)
			flags.repeatable = true
		end

		for j = 1, #modifiers do
			bind(create_shortcut(key, modifiers[j]), flags)
		end
	end

	self:search_ensure_key_bindings()
end

-- Handles all key and mouse button shortcuts, except unicode inputs.
---@param shortcut Shortcut
---@param info ComplexBindingInfo
function Menu:handle_shortcut(shortcut, info)
	if not self:is_alive() then return end

	self.mouse_nav = info.is_mouse
	local menu, id, key, modifiers = self.current, shortcut.id, shortcut.key, shortcut.modifiers
	local selected_index = menu.selected_index
	local selected_item = menu and selected_index and menu.items[selected_index]
	local is_submenu = selected_item and selected_item.items ~= nil
	local actions = selected_item and selected_item.actions or menu.item_actions
	local selected_action = actions and menu.action_index and actions[menu.action_index]

	if info.event == 'up' then return end

	function trigger_shortcut(shortcut)
		self.callback(table_assign({}, shortcut, {
			type = 'key',
			menu_id = menu.id,
			selected_item = selected_item and {
				index = selected_index, value = selected_item.value, action = selected_action,
			},
		}))
	end

	if (key == 'enter' and selected_item) or (id == 'right' and is_submenu and not menu.search) then
		self:activate_selected_item(shortcut)
	elseif id == 'enter' and menu.search and menu.search_debounce == 'submit' then
		self:search_submit()
	elseif id == 'up' or id == 'down' then
		self:navigate_by_items(id == 'up' and -1 or 1, true)
	elseif id == 'pgup' or id == 'pgdwn' then
		self:navigate_by_page(id == 'pgup' and -1 or 1)
	elseif menu.search and (id == 'left' or id == 'ctrl+left') then
		self:search_cursor_move(-1, modifiers == 'ctrl')
	elseif menu.search and (id == 'right' or id == 'ctrl+right') then
		self:search_cursor_move(1, modifiers == 'ctrl')
	elseif menu.search and id == 'home' then
		self:search_cursor_move(-math.huge)
	elseif menu.search and id == 'end' then
		self:search_cursor_move(math.huge)
	elseif id == 'home' or id == 'end' then
		self:navigate_by_items(id == 'home' and -math.huge or math.huge)
	elseif id == 'shift+tab' then
		self:prev_action()
	elseif id == 'tab' then
		self:next_action()
	elseif id == 'ctrl+up' then
		self:move_selected_item_by(-1)
	elseif id == 'ctrl+down' then
		self:move_selected_item_by(1)
	elseif id == 'ctrl+pgup' then
		self:move_selected_item_by(-round((menu.height / self.scroll_step) * 0.4))
	elseif id == 'ctrl+pgdwn' then
		self:move_selected_item_by(round((menu.height / self.scroll_step) * 0.4))
	elseif id == 'ctrl+home' then
		self:move_selected_item_by(-math.huge)
	elseif id == 'ctrl+end' then
		self:move_selected_item_by(math.huge)
	elseif id == '/' or id == 'kp_divide' or id == 'ctrl+f' then
		self:search_start()
	elseif key == 'esc' then
		if menu.search and menu.search_style ~= 'palette' then
			self:search_cancel()
		else
			self:close()
		end
	elseif id == 'left' and menu.parent_menu then
		self:back()
	elseif key == 'bs' then
		if menu.search then
			if modifiers == 'shift' then
				self:search_clear_query()
			elseif not modifiers or modifiers == 'ctrl' then
				self:search_query_backspace(info.event, modifiers == 'ctrl')
			end
		elseif not modifiers and info.event ~= 'repeat' then
			self:back()
		end
	elseif menu.search and (id == 'del' or id == 'ctrl+del' or id == 'shift+del') then
		if id == 'shift+del' then
			-- During search `del` edits the string. We convert `shift+del` to
			-- `del` to have a way to trigger menu callbacks bound to `del`.
			trigger_shortcut(create_shortcut('del'))
		else
			self:search_query_delete(info.event, modifiers == 'ctrl')
		end
	elseif key == 'mbtn_back' then
		self:back()
	elseif id == 'ctrl+v' then
		self:paste()
	else
		trigger_shortcut(shortcut)
	end
end

-- Check if menu is not closed or closing.
function Menu:is_alive() return not self.is_closing and not self.destroyed end

---@param name string
function Menu:create_key_handler(name)
	return self:create_action(function(...)
		self.mouse_nav = false
		self:maybe(name, ...)
	end)
end

-- Sends command with params, or triggers a callback event if `command == 'callback'`.
-- Intended to handle `on_{event}: 'callback' | string | string[]` events.
-- Returns what happened.
---@param command string|number|string[]|number[]
---@param params string[]|number[]
---@param event MenuEvent
---@return 'event' | 'command' | nil
function Menu:command_or_event(command, params, event)
	if command == 'callback' then
		self.callback(event)
		return 'event'
	elseif type(command) == 'table' then
		---@diagnostic disable-next-line: deprecated
		mp.command_native(itable_join(command, params))
		return 'command'
	elseif type(command) == 'string' then
		mp.command(command .. ' ' .. table.concat(params, ' '))
		return 'command'
	end
	return nil
end

function Menu:render()
	for _, menu in ipairs(self.all) do
		if menu.fling then
			local time_delta = state.render_last_time - menu.fling.time
			local progress = menu.fling.easing(math.min(time_delta / menu.fling.duration, 1))
			self:set_scroll_to(round(menu.fling.y + menu.fling.distance * progress), menu.id)
			if progress < 1 then request_render() else menu.fling = nil end
		end
	end

	cursor:zone('primary_down', display, self:create_action(function() self:handle_cursor_down() end))
	cursor:zone('primary_up', display, self:create_action(function(shortcut) self:handle_cursor_up(shortcut) end))
	cursor:zone('wheel_down', self, function() self:handle_wheel_down() end)
	cursor:zone('wheel_up', self, function() self:handle_wheel_up() end)

	local ass = assdraw.ass_new()
	local icon_size = self.font_size

	---@param menu MenuStack
	---@param x number
	---@param pos number Horizontal position index. 0 = current menu, <0 parent menus, >1 submenu.
	local function draw_menu(menu, x, pos)
		local is_current, is_parent, is_submenu = pos == 0, pos < 0, pos > 0
		local menu_opacity = (pos == 0 and 1 or config.opacity.submenu ^ math.abs(pos)) * self.opacity
		-- Scrollable content area coordinates
		local content_rect = {
			ax = x + self.padding,
			ay = menu.top,
			bx = x + self.padding + menu.width,
			by = menu.top + menu.height,
		}
		-- local ax, ay, bx, by = x + self.padding, menu.top, x + menu.width + self.padding, menu.top + menu.height
		local draw_title = menu.is_root and (menu.title or menu.segments or menu.columns) or menu.search
		local scroll_clip = '\\clip(0,' .. content_rect.ay .. ',' .. display.width .. ',' .. content_rect.by .. ')'
		local start_index = math.floor(menu.scroll_y / self.scroll_step) + 1
		local end_index = math.ceil((menu.scroll_y + menu.height) / self.scroll_step)
		local bg_rect = {
			ax = x,
			-- DinaPlayer: reserve the full header region (text + bottom gap + separator)
			-- above the top padding, so the header keeps a normal item's top padding.
			ay = content_rect.ay
				- (draw_title and (self.scroll_step + self.padding + self.separator_size + 1) or 0)
				- self.padding,
			bx = content_rect.bx + self.padding,
			by = content_rect.by + self.padding,
		}
		local blur_action_index = self.mouse_nav and menu.action_index ~= nil

		-- Background
		ass:rect(bg_rect.ax, bg_rect.ay, bg_rect.bx, bg_rect.by, {
			color = bg,
			opacity = menu_opacity * config.opacity.menu,
			radius = state.radius > 0 and math.min(state.radius + self.padding, state.radius * 3) or 0,
		})

		if is_parent then
			cursor:zone('primary_down', bg_rect, self:create_action(function() self:slide_in_menu(menu.id, x) end))
		end

		-- Scrollbar
		if menu.scroll_height > 0 then
			-- DinaPlayer: inset the scrollbar from the top/bottom edges (pad) so the
			-- thumb doesn't run all the way to the corners.
			local pad = round(12 * state.scale)
			local groove_height = menu.height - pad * 2
			local thumb_height = clamp(40, (menu.height / (menu.scroll_height + menu.height)) * groove_height, groove_height)
			local thumb_y = content_rect.ay + pad + ((menu.scroll_y / menu.scroll_height) * (groove_height - thumb_height))
			-- DinaPlayer: sit the scrollbar in the right padding gutter instead of
			-- straddling the content edge, so it doesn't overlap a row's chevron/hint.
			local sax = content_rect.bx + round((self.padding - self.scrollbar_size) / 2)
			local sbx = sax + self.scrollbar_size
			-- DinaPlayer: rounded (capsule) ends — radius = half the bar's width.
			-- Faint white (opacity 0.2).
			ass:rect(sax, thumb_y, sbx, thumb_y + thumb_height,
				{color = fg, opacity = menu_opacity * 0.2, radius = round(self.scrollbar_size / 2)})
		end

		-- Draw submenu if selected
		local submenu_rect, current_item = nil, is_current and menu.selected_index and menu.items[menu.selected_index]
		local submenu_is_hovered = false
		if current_item and current_item.items then
			submenu_rect = draw_menu(current_item --[[@as MenuStack]], bg_rect.bx + self.gap, 1)
			cursor:zone('primary_down', submenu_rect, self:create_action(function(shortcut)
				self:activate_selected_item(shortcut, true)
			end))
		end

		-- DinaPlayer: in mouse mode, highlight exactly the row under the cursor (or
		-- none), computed once per render so the hover clears when the cursor moves
		-- off a row or onto the header, instead of sticking.
		if is_current and self.mouse_nav then
			local hovered
			if not (submenu_rect and cursor:direction_to_rectangle_distance(submenu_rect)) then
				for i = start_index, end_index do
					local it = menu.items[i]
					if it and it.selectable ~= false then
						local ay = content_rect.ay - menu.scroll_y + self.scroll_step * (i - 1)
						local hb = {
							ax = content_rect.ax, ay = math.max(ay, bg_rect.ay),
							bx = bg_rect.bx - self.padding, by = math.min(ay + self.scroll_step, bg_rect.by),
						}
						if get_point_to_rectangle_proximity(cursor, hb) <= 0 then hovered = i break end
					end
				end
			end
			if menu.selected_index ~= hovered then
				menu.selected_index = hovered
				request_render()
			end
		end

		---@type MenuAction|nil
		local selected_action
		for index = start_index, end_index, 1 do
			local item = menu.items[index]

			if not item then break end

			local item_ay = content_rect.ay - menu.scroll_y + self.scroll_step * (index - 1)
			local item_by = item_ay + self.item_height
			local item_center_y = item_ay + (self.item_height / 2)
			local item_clip = (item_ay < content_rect.ay or item_by > content_rect.by) and scroll_clip or nil
			local content_ax, content_bx = content_rect.ax + self.item_padding,
				content_rect.bx - self.item_padding
			local is_selected = menu.selected_index == index
			local item_rect_hitbox = {
				ax = content_rect.ax,
				ay = math.max(item_ay, bg_rect.ay),
				bx = bg_rect.bx + (item.items and self.gap or -self.padding), -- to bridge the submenu gap with cursor
				by = math.min(item_ay + self.scroll_step, bg_rect.by),
			}

			-- DinaPlayer: hovered row is computed once before the loop (see above).

			local has_background = is_selected or item.active
			local next_item = menu.items[index + 1]
			local next_is_active = next_item and next_item.active
			local next_has_background = menu.selected_index == index + 1 or next_is_active
			local font_color = item.active and fgt or bgt
			local actions = is_selected and (item.actions or menu.item_actions) -- not nil = actions are visible
			local action = actions and actions[menu.action_index] -- not nil = action is selected

			if action then selected_action = action end

			-- Separator — a deliberate group break (`separator` on the item, used by
			-- the settings menu). DinaPlayer: restored at 8% opacity (was 5%).
			if item.separator and item_by < content_rect.by then
				local ay, by = item_by, item_by + self.separator_size
				if has_background then
					ay, by = ay + self.separator_size, by + self.separator_size
				elseif next_has_background then
					ay, by = ay - self.separator_size, by - self.separator_size
				end
				-- DinaPlayer: full panel width (edge to edge), no left/right padding.
				ass:rect(
					bg_rect.ax, ay, bg_rect.bx, by,
					{color = fg, opacity = menu_opacity * 0.08}
				)
			end

			-- DinaPlayer: `columns` draws the row once per column. Every cell is its own
			-- button: its own fill when that slot holds this track, its own hover, and its
			-- own click zone reporting which column was hit — so both slots stay visible
			-- and settable without switching views.
			if menu.columns then
				for col = 1, 2 do
					local cax, cbx = self:column_rect(menu, col, content_rect.ax, content_rect.bx)
					local cell_active = item.slots and item.slots[col]
					local cell_rect = {ax = cax, ay = item_ay, bx = cbx, by = item_by}
					local cell_hover = is_current and item.selectable ~= false
						and get_point_to_rectangle_proximity(cursor, cell_rect) <= 0
					if cell_active or cell_hover then
						ass:rect(cax, item_ay, cbx, item_by, {
							radius = state.radius, color = fg, clip = item_clip,
							opacity = menu_opacity * (cell_active and 0.8 or 0.15),
						})
					end
					local cell_color = cell_active and fgt or bgt
					local cell_clip = '\\clip(' .. cax .. ',' .. math.max(item_ay, content_rect.ay)
						.. ',' .. cbx .. ',' .. math.min(item_by, content_rect.by) .. ')'
					if item.hint then
						item.ass_safe_hint = item.ass_safe_hint or ass_escape(item.hint)
						ass:txt(cbx - self.item_padding, item_center_y, 6, item.ass_safe_hint, {
							size = self.font_size_hint, color = cell_color, wrap = 2,
							opacity = menu_opacity * (cell_active and 0.6 or 0.5), clip = cell_clip,
						})
					end
					if item.title then
						item.ass_safe_title = item.ass_safe_title or ass_escape(item.title)
						ass:txt(cax + self.item_padding, item_center_y, 4, item.ass_safe_title, {
							size = self.font_size, color = cell_color, wrap = 2,
							opacity = menu_opacity, clip = cell_clip,
						})
					end
					if is_current and item.selectable ~= false then
						local idx, column = index, col
						cursor:zone('primary_down', cell_rect, self:create_action(function()
							if self.callback then
								self.callback({
									type = 'activate', index = idx, value = item.value,
									column = column, keep_open = true, menu_id = menu.id,
								})
							end
						end))
					end
				end
			end

			-- Background
			local highlight_opacity = menu.columns and 0
				or (0 + (item.active and 0.8 or 0) + (is_selected and 0.15 or 0))
			if highlight_opacity > 0 then
				ass:rect(content_rect.ax, item_ay, content_rect.bx, item_by, {
					radius = state.radius,
					color = fg,
					opacity = highlight_opacity * menu_opacity,
					clip = item_clip,
				})
			end

			local title_clip_bx = content_bx

			-- DinaPlayer: fixed-width number column (right-aligned) at the start, so the
			-- title always begins at the same x regardless of the number's digits.
			if item.number and menu.number_width and menu.number_width > 0 then
				ass:txt(content_ax + menu.number_width, item_center_y, 6, item.number, {
					size = self.font_size,
					color = font_color,
					opacity = menu_opacity * (item.muted and 0.5 or 1),
					clip = item_clip,
				})
				content_ax = content_ax + menu.number_width + self.item_padding
			end

			-- Actions
			local actions_rect
			if is_selected and actions and #actions > 0 and not item.items then
				local place = item.actions_place or menu.item_actions_place
				local margin = self.gap * 2
				local size = item_by - item_ay - margin * 2
				local rect_width = size * #actions + margin * (#actions - 1)

				-- Place actions outside of menu when requested and there's enough space for it
				actions_rect = {
					ay = item_ay + margin,
					by = item_by - margin,
					is_outside = place == 'outside' and display.width - bg_rect.bx + margin * 2 > rect_width,
				}
				actions_rect.bx = actions_rect.is_outside and bg_rect.bx + margin + rect_width or
					content_rect.bx - margin
				actions_rect.ax = actions_rect.bx

				for i = 1, #actions, 1 do
					local action_index = #actions - (i - 1)
					local action = actions[action_index]

					-- Hide when the action shouldn't be displayed when the item is a result of a search/filter
					if not (action.filter_hidden and menu.search) then
						local is_active = action_index == menu.action_index
						local bx = actions_rect.ax - (i == 1 and 0 or margin)
						local rect = {
							ay = actions_rect.ay,
							by = actions_rect.by,
							ax = bx - size,
							bx = bx,
						}
						actions_rect.ax = rect.ax

						ass:rect(rect.ax, rect.ay, rect.bx, rect.by, {
							radius = state.radius > 2 and state.radius - 1 or state.radius,
							color = is_active and fg or bg,
							border = is_active and self.gap or nil,
							border_color = bg,
							opacity = menu_opacity,
							clip = item_clip,
						})
						ass:icon(rect.ax + size / 2, rect.ay + size / 2, size * 0.66, action.icon, {
							color = is_active and bg or fg, opacity = menu_opacity, clip = item_clip,
						})

						-- Re-use rect as a hitbox by growing it so it bridges gaps to prevent flickering
						rect.ay, rect.by, rect.bx = item_ay, item_ay + self.scroll_step, rect.bx + margin

						-- Select action on cursor hover
						if self.mouse_nav and get_point_to_rectangle_proximity(cursor, rect) <= 0 then
							cursor:zone('primary_down', rect, self:create_action(function(shortcut)
								self:activate_selected_item(shortcut, true)
							end))
							blur_action_index = false
							if not is_active then
								menu.action_index = action_index
								selected_action = actions[action_index]
								request_render()
							end
						end
					end
				end

				title_clip_bx = actions_rect.ax - self.gap * 2
			end

			-- DinaPlayer: removed the white left-edge indicator line on the
			-- selected/hovered item — the subtle background highlight is enough.

			-- Icon
			if item.icon or (menu.icon_action and menu.has_icons) then
				local icon_x = (not item.title and not item.hint and item.align == 'center')
					and bg_rect.ax + (bg_rect.bx - bg_rect.ax) / 2
					or content_bx - (icon_size / 2)
				-- DinaPlayer: clickable icon button (menu.icon_action). Always visible;
				-- clicking fires that action without activating (playing) the row — this
				-- zone is registered after the display-wide one, so handle_cursor_down
				-- never runs for it and the row is not selected/played.
				local icon_clickable = menu.icon_action and is_current
				if icon_clickable then
					local icon_hb = {
						ax = content_bx - icon_size - self.item_padding,
						ay = math.max(item_ay, bg_rect.ay),
						bx = content_rect.bx,
						by = math.min(item_by, bg_rect.by),
					}
					if get_point_to_rectangle_proximity(cursor, icon_hb) <= 0 then
						-- DinaPlayer: square hover chip (side = row inner height), grey
						-- instead of white, centered on the state icon. Was a slightly
						-- taller-than-wide rectangle in white.
						local chip_ay, chip_by = item_ay + self.gap, item_by - self.gap
						local chip_half = (chip_by - chip_ay) / 2
						local chip_cx = content_bx - icon_size / 2
						ass:rect(chip_cx - chip_half, chip_ay, chip_cx + chip_half, chip_by,
							{radius = state.radius, color = '636363', opacity = menu_opacity * 0.4, clip = item_clip})
					end
					cursor:zone('primary_down', icon_hb, self:create_action(function()
						self.callback({
							type = 'activate', index = index, value = item.value,
							action = menu.icon_action, keep_open = true, menu_id = menu.id,
						})
					end))
				end
				if item.icon and (not actions_rect or actions_rect.is_outside) then
					-- DinaPlayer: on the active (highlighted white) row the icon would be
					-- pure black (foreground_text); for clickable state icons use the menu
					-- grey (bg) instead so it matches the rest, not total black.
					local icon_color = (item.active and menu.icon_action) and bg or font_color
					if item.icon == 'spinner' then
						ass:spinner(icon_x, item_center_y, icon_size * 1.5, {color = icon_color, opacity = menu_opacity * 0.8})
					else
						ass:icon(icon_x, item_center_y, icon_size * 1.5, item.icon, {
							-- DinaPlayer: item.icon_opacity dims a single icon (e.g. the
							-- faint "not watched" check); nil = full opacity.
							color = icon_color, opacity = menu_opacity * (item.icon_opacity or 1), clip = item_clip,
						})
					end
				end
			end
			-- DinaPlayer: reserve the icon column for every row when the menu has any
			-- icon, so toggling an item's icon (e.g. the playlist watched checkmark)
			-- doesn't resize the row or make the text/hint jump.
			if item.icon or menu.has_icons then
				content_bx = content_bx - icon_size - self.item_padding
				title_clip_bx = math.min(content_bx, title_clip_bx)
			end

			-- DinaPlayer: reserve room on the right for an enlarged submenu chevron
			-- ("›" at 1.5x the hint size, drawn below). chevron_x is the row's right
			-- edge captured before the reserve so the glyph sits flush right.
			local chevron_size, chevron_x
			if item.chevron then
				chevron_size = self.font_size_hint * 1.5
				chevron_x = content_bx
				content_bx = content_bx - round(text_width('›', {size = chevron_size}) + self.item_padding)
				title_clip_bx = math.min(content_bx, title_clip_bx)
			end

			local hint_clip_bx = title_clip_bx
			if item.hint_width > 0 and not menu.item_hint_below then
				-- controls title & hint clipping proportional to the ratio of their widths
				-- both title and hint get at least 50% of the width, unless they are smaller then that
				local width = content_bx - content_ax - self.item_padding
				local title_min = math.min(item.title_width, width * 0.5)
				local hint_min = math.min(item.hint_width, width * 0.5)
				local title_ratio = item.title_width / (item.title_width + item.hint_width)
				title_clip_bx = math.min(
					title_clip_bx,
					round(content_ax + clamp(title_min, width * title_ratio, width - hint_min))
				)
			end

			if menu.columns then -- title and hint already drawn per column above
			elseif menu.item_hint_below then
				-- DinaPlayer: two-line item — title on top, hint (details) below, smaller.
				local clip = '\\clip(' .. content_rect.ax .. ',' .. math.max(item_ay, content_rect.ay) .. ','
					.. title_clip_bx .. ',' .. math.min(item_by, content_rect.by) .. ')'
				if item.title then
					item.ass_safe_title = item.ass_safe_title or ass_escape(item.title)
					ass:txt(content_ax, item_ay + round(self.item_height * 0.34), 4, item.ass_safe_title, {
						size = self.font_size,
						color = font_color,
						italic = item.italic,
						bold = item.bold,
						wrap = 2,
						opacity = menu_opacity * (item.muted and 0.5 or 1),
						clip = clip,
					})
				end
				if item.hint then
					item.ass_safe_hint = item.ass_safe_hint or ass_escape(item.hint)
					ass:txt(content_ax, item_ay + round(self.item_height * 0.66), 4, item.ass_safe_hint, {
						size = self.font_size_hint,
						color = font_color,
						wrap = 2,
						opacity = 0.5 * menu_opacity,
						clip = clip,
					})
				end
			else
				-- DinaPlayer: rows carrying a boolean `toggle` draw an iOS-style switch
				-- where the hint text would sit, instead of "On"/"Off". Colors derive
				-- from `font_color`, so the switch inverts along with the text on an
				-- active (light) row.
				if item.toggle ~= nil then
					local on = item.toggle
					local tw, th = self:toggle_size()
					local tax = content_bx - tw
					local tay = item_center_y - round(th / 2)
					local r = th / 2
					ass:rect(tax, tay, tax + tw, tay + th, {
						color = font_color, radius = r, clip = item_clip,
						opacity = menu_opacity * (on and 1 or 0.16),
					})
					ass:circle(on and (tax + tw - r) or (tax + r), tay + r,
						r - math.max(1, round(th * 0.13)), {
							color = on and (item.active and fg or bg) or font_color,
							opacity = menu_opacity * (on and 1 or 0.5), clip = item_clip, -- off knob = white 50%, same as muted text
						})

				-- Hint
				elseif item.hint then
					item.ass_safe_hint = item.ass_safe_hint or ass_escape(item.hint)
					local clip = '\\clip(' .. title_clip_bx + self.item_padding .. ','
						.. math.max(item_ay, content_rect.ay) .. ',' .. hint_clip_bx .. ','
						.. math.min(item_by, content_rect.by) .. ')'
					ass:txt(content_bx, item_center_y, 6, item.ass_safe_hint, {
						size = self.font_size_hint,
						color = font_color,
						wrap = 2,
						opacity = 0.5 * menu_opacity,
						clip = clip,
					})
				end

				-- DinaPlayer: enlarged submenu chevron ("›") on the right, at 1.5x the
				-- hint size. Reserved above so it sits right of any hint text.
				if item.chevron then
					ass:txt(chevron_x, item_center_y, 6, '›', {
						size = chevron_size,
						color = font_color,
						wrap = 2,
						opacity = 0.5 * menu_opacity,
						clip = item_clip,
					})
				end

				-- Title
				if item.title then
					item.ass_safe_title = item.ass_safe_title or ass_escape(item.title)
					local clip = '\\clip(' .. content_rect.ax .. ',' .. math.max(item_ay, content_rect.ay) .. ','
						.. title_clip_bx .. ',' .. math.min(item_by, content_rect.by) .. ')'
					local title_x, align = content_ax, 4
					if item.align == 'right' then
						title_x, align = title_clip_bx, 6
					elseif item.align == 'center' then
						title_x, align = content_ax + (title_clip_bx - content_ax) / 2, 5
					end
					ass:txt(title_x, item_center_y, align, item.ass_safe_title, {
						size = self.font_size,
						color = font_color,
						italic = item.italic,
						bold = item.bold,
						wrap = 2,
						opacity = menu_opacity * (item.muted and 0.5 or 1),
						clip = clip,
					})
				end
			end
		end

		-- DinaPlayer: removed the "?" footnote / action-label hint entirely.

		-- Menu title
		if draw_title then
			local requires_submit = menu.search_debounce == 'submit'
			-- DinaPlayer: separator sits just above the content; the header text is one
			-- `padding` above the separator, and bg_rect reserves a matching `padding`
			-- above the header — so its top gap equals a normal item's top padding.
			local sep_top = content_rect.ay - self.separator_size - 1
			local rect = {
				ax = content_rect.ax,
				ay = sep_top - self.padding - self.scroll_step,
				bx = content_rect.bx,
				by = sep_top - self.padding,
			}
			-- Centers
			rect.cx, rect.cy = round(rect.ax + (rect.bx - rect.ax) / 2), round(rect.ay + (rect.by - rect.ay) / 2)

			if menu.title and not menu.ass_safe_title then
				menu.ass_safe_title = ass_escape(menu.title)
			end

			-- Separator under the header (Primary/Secondary, submenu back-titles),
			-- skipped under the segmented control. DinaPlayer: restored at 8% (was 5%).
			if not menu.segments then
				-- DinaPlayer: full panel width (edge to edge), no left/right padding.
				ass:rect(
					bg_rect.ax, sep_top, bg_rect.bx, sep_top + self.separator_size, {color = fg, opacity = menu_opacity * 0.08}
				)
			end

			-- Click on title: DinaPlayer back-header (title_back) goes back; otherwise
			-- blur selection (which also activates the search input). Segmented
			-- headers register their own per-segment zones below.
			if is_current and not menu.segments then
				if menu.title_back then
					cursor:zone('primary_down', rect, self:create_action(function() self:back() end))
				else
					cursor:zone('primary_down', rect, function()
						self:select_index(nil)
					end)
				end
			end

			-- Title
			if menu.search then
				-- Icon
				local icon_size, icon_opacity = self.font_size * 1.3, menu_opacity * (requires_submit and 0.5 or 1)
				local icon_rect = {
					ax = rect.ax,
					ay = rect.ay,
					bx = content_rect.ax + icon_size + self.item_padding * 1.5,
					by = rect.by,
				}

				if is_current and requires_submit then
					cursor:zone('primary_down', icon_rect, function() self:search_submit() end)
					if get_point_to_rectangle_proximity(cursor, icon_rect) <= 0 then
						icon_opacity = menu_opacity
					end
				end

				ass:icon(rect.ax + icon_size / 2, rect.cy, icon_size, 'search', {
					color = fg,
					opacity = icon_opacity,
					clip = '\\clip(' ..
						icon_rect.ax .. ',' .. icon_rect.ay .. ',' .. icon_rect.bx .. ',' .. icon_rect.by .. ')',
				})

				-- Query/Placeholder
				local cursor_height_half, cursor_thickness = round(self.font_size * 0.6), round(self.font_size / 12)
				local cursor_ax = rect.bx + 1
				if menu.search.query ~= '' then
					local opts = {
						size = self.font_size,
						color = bgt,
						wrap = 2,
						opacity = menu_opacity,
						clip = '\\clip(' .. icon_rect.bx .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
					}
					local query, cursor = menu.search.query, menu.search.cursor
					-- Add a ZWNBSP suffix to prevent libass from trimming trailing spaces
					local head = ass_escape(string.sub(query, 1, cursor)) .. '\239\187\191'
					local tail_no_escape = string.sub(query, cursor + 1)
					local tail = ass_escape(tail_no_escape) .. '\239\187\191'
					cursor_ax = math.max(round(cursor_ax - text_width(tail_no_escape, opts)), rect.cx)
					ass:txt(cursor_ax, rect.cy, 6, head, opts)
					ass:txt(cursor_ax, rect.cy, 4, tail, opts)
				else
					local placeholder = (menu.search_style == 'palette' and menu.ass_safe_title)
						and menu.ass_safe_title
						or (requires_submit and t('type & ctrl+enter to search') or t('type to search'))
					ass:txt(rect.bx, rect.cy, 6, placeholder, {
						size = self.font_size,
						italic = true,
						color = bgt,
						wrap = 2,
						opacity = menu_opacity * 0.4,
						clip = '\\clip(' .. rect.ax .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
					})
				end

				-- Selected input indicator for submittable searches.
				-- (input is selected when `selected_index` is `nil`)
				if menu.search_debounce == 'submit' and not menu.selected_index then
					local size_half = round(1 * state.scale)
					ass:rect(
						content_rect.ax, rect.by - size_half, content_rect.bx, rect.by + size_half,
						{color = fg, opacity = menu_opacity}
					)
				end
				local input_is_blurred = menu.search_debounce == 'submit' and menu.selected_index

				-- Cursor
				local cursor_bx = cursor_ax + cursor_thickness
				ass:rect(cursor_ax, rect.cy - cursor_height_half, cursor_bx, rect.cy + cursor_height_half, {
					color = fg,
					opacity = menu_opacity * (input_is_blurred and 0.5 or 1),
					clip = '\\clip(' .. cursor_ax .. ',' .. rect.ay .. ',' .. cursor_bx .. ',' .. rect.by .. ')',
				})
			elseif menu.columns then
				-- DinaPlayer: static column labels for a two-column menu, sitting above
				-- the list at exactly the x where the cells they head begin.
				for i = 1, 2 do
					local cax = self:column_rect(menu, i, rect.ax, rect.bx)
					ass:txt(cax + self.item_padding, rect.cy, 4, menu.columns[i] or '', {
						size = self.font_size, bold = true, color = bgt, wrap = 2,
						opacity = menu_opacity * 0.4,
					})
				end
			elseif menu.segments then
				-- DinaPlayer: segmented control header (e.g. Primary | Secondary).
				-- Active segment filled; others muted; each clickable, firing a
				-- {type='segment', index} event through the menu callback.
				local n = #menu.segments
				local inset = round(3 * state.scale)
				local gap = round(2 * state.scale)
				-- DinaPlayer: top gap = padding (same as the left/right gap), instead of
				-- rect.ay + inset which left a slightly larger gap above the control.
				local sy, sby = bg_rect.ay + self.padding, rect.by - inset
				local seg_w = (rect.bx - rect.ax - gap * (n - 1)) / n
				ass:rect(rect.ax, sy, rect.bx, sby, {radius = state.radius, color = fg, opacity = menu_opacity * 0.08})
				for i = 1, n do
					local sx = round(rect.ax + (seg_w + gap) * (i - 1))
					local sbx = round(sx + seg_w)
					local seg_rect = {ax = sx, ay = sy, bx = sbx, by = sby}
					local is_active = i == menu.active_segment
					-- DinaPlayer: only the active segment gets a filled chip; hovering an
					-- inactive one adds no background, just brightens its label below.
					local is_hover = is_current and get_point_to_rectangle_proximity(cursor, seg_rect) <= 0
					if is_active then
						ass:rect(sx, sy, sbx, sby, {radius = state.radius, color = fg, opacity = menu_opacity})
					end
					ass:txt(round(sx + seg_w / 2), rect.cy, 5, menu.segments[i], {
						size = self.font_size,
						bold = true,
						color = is_active and fgt or bgt,
						opacity = menu_opacity * (is_active and 1 or (is_hover and 0.95 or 0.7)),
					})
					if is_current then
						local idx = i
						cursor:zone('primary_down', seg_rect, self:create_action(function()
							if self.callback then self.callback({type = 'segment', index = idx, menu_id = self.current.id}) end
						end))
					end
				end
			elseif menu.title_back then
				-- DinaPlayer: left-aligned "‹ Title" clickable back header (YouTube-style),
				-- with a hover highlight so it's clearly interactive.
				if is_current and get_point_to_rectangle_proximity(cursor, rect) <= 0 then
					ass:rect(rect.ax, rect.ay, rect.bx, rect.by,
						{radius = state.radius, color = fg, opacity = menu_opacity * 0.15})
				end
				-- DinaPlayer: back arrow "‹" drawn separately at 1.5x the title size; the
				-- title is shifted right past it so it doesn't overlap.
				local back_clip = '\\clip(' .. rect.ax .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')'
				local back_size = self.font_size * 1.5
				local back_x = rect.ax + self.item_padding
				ass:txt(back_x, rect.cy, 4, '‹', {
					size = back_size, bold = true, color = bgt, opacity = menu_opacity, clip = back_clip,
				})
				local back_w = round(text_width('‹', {size = back_size, bold = true}) + self.item_padding)
				ass:txt(back_x + back_w, rect.cy, 4, menu.ass_safe_title, {
					size = self.font_size,
					bold = true,
					color = bgt,
					wrap = 2,
					opacity = menu_opacity,
					clip = back_clip,
				})
			else
				ass:txt(rect.cx, rect.cy, 5, menu.ass_safe_title, {
					size = self.font_size,
					bold = true,
					color = bgt,
					wrap = 2,
					opacity = menu_opacity,
					clip = '\\clip(' .. rect.ax .. ',' .. rect.ay .. ',' .. rect.bx .. ',' .. rect.by .. ')',
				})
			end
		end

		if blur_action_index then
			menu.action_index = nil
			request_render()
		end

		return bg_rect
	end

	-- Active menu
	draw_menu(self.current, self.ax, 0)

	-- Parent menus
	local parent_menu = self.current.parent_menu
	local parent_offset_x, parent_horizontal_index = self.ax, -1

	while parent_menu do
		parent_offset_x = parent_offset_x - parent_menu.width - self.padding * 2 - self.gap
		draw_menu(parent_menu, parent_offset_x, parent_horizontal_index)
		parent_horizontal_index = parent_horizontal_index - 1
		parent_menu = parent_menu.parent_menu
	end

	return ass
end

return Menu
