# karel/world_maker.rb
require "gosu"
require_relative "gosu_karel_window"

# Interactive editor for Karel worlds using Gosu.
# Assumes KarelWindow from gosu_karel_window.rb provides:
# - scale_factor
# - scale_to_pixels(street, avenue)
# - place_beeper / delete_beeper
# - place_wall_north_of / remove_wall_north_of
# - place_wall_east_of / remove_wall_east_of
# - clear
#
# This class subclasses KarelWindow so it can reuse your existing grid/world drawing.

class WorldMaker < KarelWindow
  MODE_SINGLE_BEEPER = :single_beeper
  MODE_INFINITY      = :infinity_beeper
  MODE_VERTICAL_WALL = :vertical_wall
  MODE_HORIZONTAL    = :horizontal_wall

  attr_reader :mode

  def initialize(streets, avenues, size = $window_bottom)
    super(streets, avenues, size)

    self.caption = "Karel World Maker (Gosu)"
    @mode = MODE_SINGLE_BEEPER

    # Local editable state (mirrors what KarelWindow draws)
    # We manage state directly here so save/load is straightforward.
    @editor_beepers = {}      # {[street, avenue] => count or $INFINITY}
    @editor_walls_north = {}  # {[street, avenue] => true}
    @editor_walls_east  = {}  # {[street, avenue] => true}

    @overlay_font = Gosu::Font.new(18)
    @status_font  = Gosu::Font.new(20)
    @help_font    = Gosu::Font.new(16)

    @message = "Mode: beepers (single)"
    @message_until = Gosu.milliseconds + 2500

    @left_mouse_was_down = false
    @right_mouse_was_down = false

    @legend_visible = true

    disable_debug_step_flush! if respond_to?(:disable_debug_step_flush!)

    @hover_cell = nil              # [street, avenue]
    @hover_vertical_wall = nil     # [street, avenue]
    @hover_horizontal_wall = nil   # [street, avenue]

  end

  # ----------------------------
  # Gosu input
  # ----------------------------
  def button_down(id)
    case id
    when Gosu::KB_ESCAPE
      close
    when Gosu::KB_X
      toggle_legend
    when Gosu::KB_B
      set_mode(MODE_SINGLE_BEEPER, "Mode: b — single beepers")
    when Gosu::KB_G
      set_mode(MODE_INFINITY, "Mode: g — infinity beepers / clear")
    when Gosu::KB_V
      set_mode(MODE_VERTICAL_WALL, "Mode: v — vertical walls")
    when Gosu::KB_H
      set_mode(MODE_HORIZONTAL, "Mode: h — horizontal walls")

    when Gosu::KB_O
      prompt_open_world
    when Gosu::KB_S
      prompt_save_world
    end

    super
  end

  def update_hover_target
    @hover_cell = nil
    @hover_vertical_wall = nil
    @hover_horizontal_wall = nil

    case @mode
    when MODE_SINGLE_BEEPER, MODE_INFINITY
      @hover_cell = mouse_to_cell(mouse_x, mouse_y)

    when MODE_VERTICAL_WALL
      @hover_vertical_wall = wall_key_vertical_from_mouse(mouse_x, mouse_y)

    when MODE_HORIZONTAL
      @hover_horizontal_wall = wall_key_horizontal_from_mouse(mouse_x, mouse_y)
    end
  end

  def toggle_legend
    @legend_visible = !@legend_visible
  end

  def update
    super

    update_hover_target

    left_now  = button_down?(Gosu::MS_LEFT)
    right_now = button_down?(Gosu::MS_RIGHT)

    # React only once per click (rising edge)
    if left_now && !@left_mouse_was_down
      handle_mouse_click(:left)
    end

    if right_now && !@right_mouse_was_down
      handle_mouse_click(:right)
    end

    @left_mouse_was_down  = left_now
    @right_mouse_was_down = right_now
  end
  # ----------------------------
  # Mouse editing
  # ----------------------------
  def handle_mouse_click(which_button)
    cell = mouse_to_cell(mouse_x, mouse_y)
    return unless cell

    street, avenue = cell

    case @mode
    when MODE_SINGLE_BEEPER
      if which_button == :left
        add_single_beeper(street, avenue)
      else
        remove_single_beeper(street, avenue)
      end

    when MODE_INFINITY
      if which_button == :left
        add_infinity_beeper(street, avenue)
      else
        clear_beepers(street, avenue)
      end

    when MODE_VERTICAL_WALL
      key = wall_key_vertical_from_mouse(mouse_x, mouse_y)
      return unless key
      s, a = key
      if which_button == :left
        @editor_walls_east[[s, a]] = true
        place_wall_east_of(s, a)
      else
        @editor_walls_east.delete([s, a])
        remove_wall_east_of(s, a)
      end

    when MODE_HORIZONTAL
      key = wall_key_horizontal_from_mouse(mouse_x, mouse_y)
      return unless key
      s, a = key
      if which_button == :left
        @editor_walls_north[[s, a]] = true
        place_wall_north_of(s, a)
      else
        @editor_walls_north.delete([s, a])
        remove_wall_north_of(s, a)
      end
    end

    #flush_step_frame
  end

  # Cell center selection (for beepers)
  def mouse_to_cell(mx, my)
    sf = scale_factor
    return nil if sf <= 0

    # Search nearest valid cell center.
    best = nil
    best_dist2 = Float::INFINITY

    (1..@_streets).each do |street|
      (1..@_avenues).each do |avenue|
        cx, cy = scale_to_pixels(street, avenue)
        dx = mx - cx
        dy = my - cy
        d2 = dx * dx + dy * dy
        if d2 < best_dist2
          best_dist2 = d2
          best = [street, avenue]
        end
      end
    end

    # Only accept if click is reasonably close to the center of a cell
    radius = sf * 0.40
    return nil if best_dist2 > radius * radius

    best
  end

  # Vertical wall hit-test (east wall of a cell/corner in your current coordinate scheme)
  def wall_key_vertical_from_mouse(mx, my)
    sf = scale_factor

    # Make vertical walls easier to click:
    # - wider horizontal grab zone
    # - slightly extended vertical zone
    half_width = [24, sf * 0.42].max     # clickable width on each side of wall line
    end_padding = [18, sf * 0.30].max     # extend beyond segment ends a little

    best = nil
    best_score = Float::INFINITY

    # Matches your corrected draw alignment:
    # east wall key [street, avenue] draws from (street - 0.5 .. street + 0.5, avenue + 0.5)
    (1..@_streets).each do |street|
      (0..@_avenues).each do |avenue|
        x1, y1 = scale_to_pixels(street - 0.5, avenue + 0.5)
        x2, y2 = scale_to_pixels(street + 0.5, avenue + 0.5)

        # This segment is vertical on screen (x1 ~= x2)
        x_line = (x1 + x2) / 2.0
        y_min = [y1, y2].min - end_padding
        y_max = [y1, y2].max + end_padding

        # Rectangular hit zone check first (much easier to click)
        inside =
          mx >= (x_line - half_width) &&
          mx <= (x_line + half_width) &&
          my >= y_min &&
          my <= y_max

        next unless inside

        # Score by horizontal distance to prefer the closest wall if overlapping zones exist
        score = (mx - x_line).abs
        if score < best_score
          best_score = score
          best = [street, avenue]
        end
      end
    end

    best
  end

  # Horizontal wall hit-test (north wall key)
  def wall_key_horizontal_from_mouse(mx, my)
    sf = scale_factor
    tolerance = [10, sf * 0.18].max

    best = nil
    best_dist = Float::INFINITY

    # Match your corrected drawing alignment:
    # north wall key [street, avenue] draws from (street + 0.5, avenue - 1 .. avenue)
    (0..@_streets).each do |street|
      (1..@_avenues + 1).each do |avenue|
        x1, y1 = scale_to_pixels(street + 0.5, avenue - 1)
        x2, y2 = scale_to_pixels(street + 0.5, avenue)
        dist = point_to_segment_distance(mx, my, x1, y1, x2, y2)
        if dist < best_dist
          best_dist = dist
          best = [street, avenue]
        end
      end
    end

    best_dist <= tolerance ? best : nil
  end

  # ----------------------------
  # Beeper editing
  # ----------------------------
  def add_single_beeper(street, avenue)
    current = @editor_beepers[[street, avenue]]
    if current == $INFINITY
      # keep infinity if already infinity
      return
    end

    new_count = (current || 0) + 1
    @editor_beepers[[street, avenue]] = new_count
    place_beeper(street, avenue, new_count)
  end

  def remove_single_beeper(street, avenue)
    current = @editor_beepers[[street, avenue]]
    return unless current

    if current == $INFINITY
      # right-click in single mode removes all
      @editor_beepers.delete([street, avenue])
      delete_beeper([street, avenue])
      return
    end

    new_count = current - 1
    if new_count <= 0
      @editor_beepers.delete([street, avenue])
      delete_beeper([street, avenue])
    else
      @editor_beepers[[street, avenue]] = new_count
      place_beeper(street, avenue, new_count)
    end
  end

  def add_infinity_beeper(street, avenue)
    @editor_beepers[[street, avenue]] = $INFINITY
    place_beeper(street, avenue, $INFINITY)
  end

  def clear_beepers(street, avenue)
    @editor_beepers.delete([street, avenue])
    delete_beeper([street, avenue])
  end

  # ----------------------------
  # File I/O (terminal prompt)
  # ----------------------------
  def prompt_open_world
    puts
    print "Open world file: "
    path = STDIN.gets&.strip
    return if path.nil? || path.empty?

    load_world_from_file(path)
  rescue => e
    set_message("Open failed: #{e.class} - #{e.message}", 5000)
  end

  def prompt_save_world
    puts
    print "Save world file in worlds/ as: "
    path = STDIN.gets&.strip
    return if path.nil? || path.empty?

    save_world_to_file("worlds/"+path)
  rescue => e
    set_message("Save failed: #{e.class} - #{e.message}", 5000)
  end

  # Simple, readable text format:
  #
  # world 10 10
  # beeper 3 2 1
  # beeper 5 5 inf
  # wall_east 2 4
  # wall_north 3 1
  #
  def save_world_to_file(path)
    File.open(path, "w") do |f|
      f.puts "KarelWorld"
      #f.puts "world #{@_streets} #{@_avenues}"

      @editor_beepers.sort.each do |(street, avenue), count|
        count_str = (count == $INFINITY ? "inf" : count.to_i.to_s)
        f.puts "beepers #{street} #{avenue} #{count_str}"
      end

      @editor_walls_east.keys.sort.each do |street, avenue|
        f.puts "eastwestwalls #{street} #{avenue}"
      end

      @editor_walls_north.keys.sort.each do |street, avenue|
        f.puts "northsouthwalls #{street} #{avenue}"
      end
    end

    set_message("Saved: #{path}")
  end

  def load_world_from_file(path)
    lines = File.readlines("worlds/"+path, chomp: true)

    reset_editor_world

    file_streets = nil
    file_avenues = nil

    lines.each do |line|
      line = line.strip
      next if line.empty?
      next if line.start_with?("#")

      parts = line.split(/\s+/)
      cmd = parts[0]

      case cmd
      when "world"
        file_streets = Integer(parts[1])
        file_avenues = Integer(parts[2])

      when "beepers"
        street = Integer(parts[1])
        avenue = Integer(parts[2])
        count  = parts[3] == "inf" ? $INFINITY : Integer(parts[3])

        @editor_beepers[[street, avenue]] = count
        place_beeper(street, avenue, count)

      when "eastwestwalls"
        street = Integer(parts[1])
        avenue = Integer(parts[2])

        @editor_walls_east[[street, avenue]] = true
        place_wall_east_of(street, avenue)

      when "northsouthwalls"
        street = Integer(parts[1])
        avenue = Integer(parts[2])

        @editor_walls_north[[street, avenue]] = true
        place_wall_north_of(street, avenue)

      else
        # ignore unknown lines for forward compatibility
      end
    end

    # If dimensions are in file and differ, notify (first version keeps current window dimensions)
    if file_streets && file_avenues && (file_streets != @_streets || file_avenues != @_avenues)
      set_message("Loaded #{path} (file world #{file_streets}x#{file_avenues}; current window #{@_streets}x#{@_avenues})", 5000)
    else
      set_message("Loaded: #{path}")
    end

    flush_step_frame
  end

  def reset_editor_world
    clear
    @editor_beepers.clear
    @editor_walls_east.clear
    @editor_walls_north.clear
  end

  # ----------------------------
  # Overlay / HUD
  # ----------------------------
  def draw
    super
    draw_overlay_menu
    draw_hover_overlay
    draw_mode_status_bar
    draw_transient_message
  end

  def current_mode_symbol
    @mode
  end

  def draw_overlay_menu
    if @legend_visible
      x = 10
      y = 36
      w = 470
      h = 150

      Gosu.draw_rect(x, y, w, h, Gosu::Color.rgba(255, 255, 255, 220), 100)
      # Border
      c = Gosu::Color::BLACK
      Gosu.draw_line(x, y, c, x + w, y, c, 101)
      Gosu.draw_line(x + w, y, c, x + w, y + h, c, 101)
      Gosu.draw_line(x + w, y + h, c, x, y + h, c, 101)
      Gosu.draw_line(x, y + h, c, x, y, c, 101)

      @overlay_font.draw_text("World Maker Controls (x to toggle)", x + 12, y + 8, 102, 1.0, 1.0, Gosu::Color::BLACK)

      help_lines = [
        "b (default): left/right click add/remove single beepers",
        "g: left add ∞ beeper, right remove all beepers",
        "v: left/right click add/remove vertical walls",
        "h: left/right click add/remove horizontal walls",
        "o: open world (filename entered in terminal)   s: save world"
      ]

      help_lines.each_with_index do |line, i|
        @help_font.draw_text(line, x + 12, y + 38 + i * 21, 102, 1.0, 1.0, Gosu::Color.rgb(20, 20, 20))
      end
    end
  end

  def draw_mode_status_bar
    bar_h = 28
    y = height - bar_h

    Gosu.draw_rect(0, y, width, bar_h, Gosu::Color.rgba(30, 30, 30, 230), 110)

    pointer_action = current_pointer_action
    extra = ""

    case @mode
    when MODE_SINGLE_BEEPER, MODE_INFINITY
      if @hover_cell
        action = beeper_hover_action(@hover_cell, pointer_action)
        extra = " | Hover #{@hover_cell.inspect}"
        extra += " | #{action}" if action
      end
    when MODE_VERTICAL_WALL
      if @hover_vertical_wall
        action = vertical_wall_hover_action(@hover_vertical_wall, pointer_action)
        extra = " | Hover V#{@hover_vertical_wall.inspect}"
        extra += " | #{action}" if action
      end
    when MODE_HORIZONTAL
      if @hover_horizontal_wall
        action = horizontal_wall_hover_action(@hover_horizontal_wall, pointer_action)
        extra = " | Hover H#{@hover_horizontal_wall.inspect}"
        extra += " | #{action}" if action
      end
    end

    text = "Current mode: #{mode_label(@mode)}#{extra}"
    @status_font.draw_text(text, 10, y + 3, 111, 1.0, 1.0, Gosu::Color::WHITE)
  end

  def draw_transient_message
    return if Gosu.milliseconds > @message_until
    return if @message.to_s.empty?

    y = height - 56
    Gosu.draw_rect(0, y, width, 24, Gosu::Color.rgba(240, 240, 200, 230), 112)
    @help_font.draw_text(@message, 10, y + 4, 113, 1.0, 1.0, Gosu::Color::BLACK)
  end

  def draw_hover_overlay
    pointer_action = current_pointer_action

    case @mode
    when MODE_SINGLE_BEEPER, MODE_INFINITY
      return unless @hover_cell
      action = beeper_hover_action(@hover_cell, pointer_action)
      draw_hover_cell(@hover_cell, action)

    when MODE_VERTICAL_WALL
      return unless @hover_vertical_wall
      action = vertical_wall_hover_action(@hover_vertical_wall, pointer_action)
      draw_hover_vertical_wall(@hover_vertical_wall, action)

    when MODE_HORIZONTAL
      return unless @hover_horizontal_wall
      action = horizontal_wall_hover_action(@hover_horizontal_wall, pointer_action)
      draw_hover_horizontal_wall(@hover_horizontal_wall, action)
    end
  end

  def draw_hover_cell(cell_key, action_type = nil)
    street, avenue = cell_key
    cx, cy = scale_to_pixels(street, avenue)
    sf = scale_factor

    size = sf * 0.55
    x = cx - size / 2.0
    y = cy - size / 2.0

    colors = ghost_colors_for(action_type)
    fill   = colors[:fill]
    border = colors[:border]

    Gosu.draw_rect(x, y, size, size, fill, 90)
    Gosu.draw_line(x, y, border, x + size, y, border, 91)
    Gosu.draw_line(x + size, y, border, x + size, y + size, border, 91)
    Gosu.draw_line(x + size, y + size, border, x, y + size, border, 91)
    Gosu.draw_line(x, y + size, border, x, y, border, 91)

    # tiny mode-aware glyph
    label =
      case action_type
      when :add then "+"
      when :remove then "-"
      when :set_infinity then "∞"
      when :clear then "×"
      when :noop then "·"
      else nil
      end

    if label
      @help_font.draw_text(label, cx - 4, cy - 10, 92, 1.0, 1.0, colors[:line])
    end
  end

  def draw_hover_horizontal_wall(key, action_type = nil)
    street, avenue = key

    x1, y1 = scale_to_pixels(street + 0.5, avenue - 1)
    x2, y2 = scale_to_pixels(street + 0.5, avenue)

    sf = scale_factor
    half_height = [14, sf * 0.22].max
    end_padding = [8, sf * 0.10].max

    y_line = (y1 + y2) / 2.0
    x_min = [x1, x2].min - end_padding
    x_max = [x1, x2].max + end_padding
    w = x_max - x_min

    colors = ghost_colors_for(action_type)

    Gosu.draw_rect(x_min, y_line - half_height, w, half_height * 2, colors[:fill], 90)
    draw_thick_line(x1, y1, x2, y2, 5, colors[:line], 91)

    label =
      case action_type
      when :add then "+H"
      when :remove then "-H"
      when :already_present then "H"
      when :noop then "·"
      else "H"
      end

    @help_font.draw_text(label, (x_min + x_max) / 2.0 - 8, y_line - half_height - 18, 92, 1.0, 1.0, colors[:line])
  end

  def draw_hover_vertical_wall(key, action_type = nil)
    street, avenue = key

    x1, y1 = scale_to_pixels(street - 0.5, avenue + 0.5)
    x2, y2 = scale_to_pixels(street + 0.5, avenue + 0.5)

    sf = scale_factor
    half_width = [14, sf * 0.22].max
    end_padding = [8, sf * 0.10].max

    x_line = (x1 + x2) / 2.0
    y_min = [y1, y2].min - end_padding
    y_max = [y1, y2].max + end_padding
    h = y_max - y_min

    colors = ghost_colors_for(action_type)

    Gosu.draw_rect(x_line - half_width, y_min, half_width * 2, h, colors[:fill], 90)
    draw_thick_line(x1, y1, x2, y2, 5, colors[:line], 91)

    label =
      case action_type
      when :add then "+V"
      when :remove then "-V"
      when :already_present then "V"
      when :noop then "·"
      else "V"
      end

    @help_font.draw_text(label, x_line + half_width + 4, (y_min + y_max) / 2.0 - 8, 92, 1.0, 1.0, colors[:line])
  end

  def beeper_hover_action(cell_key, pointer_action)
    return nil unless cell_key
    return nil unless pointer_action

    street, avenue = cell_key
    current = @editor_beepers[[street, avenue]]

    case @mode
    when MODE_SINGLE_BEEPER
      if pointer_action == :left
        :add
      else
        current ? :remove : :noop
      end

    when MODE_INFINITY
      if pointer_action == :left
        :set_infinity
      else
        current ? :clear : :noop
      end
    end
  end

  def current_pointer_action
    left_down  = button_down?(Gosu::MS_LEFT)
    right_down = button_down?(Gosu::MS_RIGHT)

    return :left  if left_down && !right_down
    return :right if right_down && !left_down
    nil
  end

  def vertical_wall_hover_action(key, pointer_action)
    return nil unless key
    return nil unless pointer_action

    exists = @editor_walls_east.key?(key)
    if pointer_action == :left
      exists ? :already_present : :add
    else
      exists ? :remove : :noop
    end
  end

  def horizontal_wall_hover_action(key, pointer_action)
    return nil unless key
    return nil unless pointer_action

    exists = @editor_walls_north.key?(key)
    if pointer_action == :left
      exists ? :already_present : :add
    else
      exists ? :remove : :noop
    end
  end

  def mode_label(mode)
    case mode
    when MODE_SINGLE_BEEPER then "b — single beepers"
    when MODE_INFINITY      then "g — infinity beepers"
    when MODE_VERTICAL_WALL then "v — vertical walls"
    when MODE_HORIZONTAL    then "h — horizontal walls"
    else mode.to_s
    end
  end

  def set_mode(mode, msg = nil)
    @mode = mode
    set_message(msg || "Mode: #{mode_label(mode)}")
  end

  def set_message(msg, duration_ms = 2500)
    @message = msg
    @message_until = Gosu.milliseconds + duration_ms
  end

  # ----------------------------
  # Math helpers
  # ----------------------------
  def point_to_segment_distance(px, py, x1, y1, x2, y2)
    vx = x2 - x1
    vy = y2 - y1
    wx = px - x1
    wy = py - y1

    c1 = vx * wx + vy * wy
    return Math.sqrt((px - x1)**2 + (py - y1)**2) if c1 <= 0

    c2 = vx * vx + vy * vy
    return Math.sqrt((px - x2)**2 + (py - y2)**2) if c2 <= c1

    t = c1.to_f / c2
    proj_x = x1 + t * vx
    proj_y = y1 + t * vy

    Math.sqrt((px - proj_x)**2 + (py - proj_y)**2)
  end

  def ghost_colors_for(action_type)
    case action_type
    when :add, :set_infinity
      {
        fill:   Gosu::Color.rgba(60, 200, 90, 70),
        border: Gosu::Color.rgba(30, 140, 55, 230),
        line:   Gosu::Color.rgba(20, 120, 45, 255)
      }
    when :remove, :clear
      {
        fill:   Gosu::Color.rgba(230, 80, 80, 70),
        border: Gosu::Color.rgba(170, 40, 40, 230),
        line:   Gosu::Color.rgba(160, 30, 30, 255)
      }
    when :already_present
      {
        fill:   Gosu::Color.rgba(255, 190, 60, 70),
        border: Gosu::Color.rgba(200, 130, 20, 230),
        line:   Gosu::Color.rgba(190, 120, 10, 255)
      }
    when :noop, nil
      {
        fill:   Gosu::Color.rgba(120, 120, 120, 40),
        border: Gosu::Color.rgba(100, 100, 100, 120),
        line:   Gosu::Color.rgba(100, 100, 100, 160)
      }
    else
      {
        fill:   Gosu::Color.rgba(80, 160, 255, 70),
        border: Gosu::Color.rgba(40, 90, 180, 220),
        line:   Gosu::Color.rgba(40, 90, 180, 255)
      }
    end
  end
end
