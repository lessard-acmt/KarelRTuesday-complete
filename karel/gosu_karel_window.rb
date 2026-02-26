# karel/gosu_karel_window.rb
require "gosu"
require_relative "robota"
require "monitor"

NORTH = NorthDirection.instance
WEST  = WestDirection.instance
SOUTH = SouthDirection.instance
EAST  = EastDirection.instance

$inset = 30 if $inset.nil?
$window_bottom = 800 if $window_bottom.nil?
$window_bottom = 600 if defined?($small_window) && $small_window

# Match the old direction semantics used in the Tk version:
# RobotImage#move did:
#   @street -= dy
#   @avenue += dx
# with these deltas:
#   NORTH => [0, -1], WEST => [-1, 0], SOUTH => [0, 1], EAST => [1, 0]
# => NORTH increases street, EAST increases avenue.
$moveParameters = {
  NORTH => [0, -1],
  WEST  => [-1, 0],
  SOUTH => [0, 1],
  EAST  => [1, 0]
}
$directions = [NORTH, WEST, SOUTH, EAST]

class KarelWindow < Gosu::Window
  RobotVisual = Struct.new(:street, :avenue, :direction, :color, :active) do
    def pick_put
      # No-op placeholder for compatibility with tk_robot_world.rb
      # Tk version used this to refresh the background color when beepers changed.
      # In Gosu, draw reads world state every frame, so nothing is needed here.
    end
  end

  attr_reader :canvas # compatibility (not used)
  attr_reader :number_of_streets

  def initialize(streets, avenues, size = $window_bottom)
    @world_px = size
    super(size + 60, size + 60, update_interval: 16.666666) # ~60fps
    self.caption = "Karel's World (Gosu)"

    @main_thread = Thread.current
    @ui_queue = Queue.new

    @_streets = streets
    @_avenues = avenues # unlike old Tk code "sic", keep both
    @height = size
    @oldHeight = size

    @_bottom = size - $inset
    @_left   = $inset
    @_top    = $inset
    @_right  = size

    @inset = $inset

    @robots = []
    @beepers = {}        # {[street, avenue] => number}
    @walls_north = {}    # east-west wall segment north of this corner
    @walls_east  = {}    # north-south wall segment east of this corner

    @mutex = Mutex.new

    @speed_amount = 40
    @debug_step_flush = true # enable debugger-friendly redraws by default

    @font_small = Gosu::Font.new(16)
    @font_beeper = Gosu::Font.new(14)

    # Compatibility values used by old code paths
    @canvas = nil

    # Robot sprite images (on/off per direction)
    images_dir = File.expand_path("images", __dir__)

    @robot_images = {
      on: {
        EAST  => Gosu::Image.new(File.join(images_dir, "karele.png")),
        NORTH => Gosu::Image.new(File.join(images_dir, "kareln.png")),
        SOUTH => Gosu::Image.new(File.join(images_dir, "karels.png")),
        WEST  => Gosu::Image.new(File.join(images_dir, "karelw.png"))
      },
      off: {
        EAST  => Gosu::Image.new(File.join(images_dir, "kareleOff.png")),
        NORTH => Gosu::Image.new(File.join(images_dir, "karelnOff.png")),
        SOUTH => Gosu::Image.new(File.join(images_dir, "karelsOff.png")),
        WEST  => Gosu::Image.new(File.join(images_dir, "karelwOff.png"))
      }
    }
  end

  def badge_color_for(color_symbol, active: true)
    c =
      case color_symbol
      when :red    then Gosu::Color::RED
      when :green  then Gosu::Color::GREEN
      when :blue   then Gosu::Color::BLUE
      when :yellow then Gosu::Color::YELLOW
      when :black  then Gosu::Color::BLACK
      when :white  then Gosu::Color::WHITE
      when :orange then Gosu::Color.rgb(255, 140, 0)
      when :purple then Gosu::Color.rgb(140, 80, 220)
      when :pink   then Gosu::Color.rgb(255, 105, 180)
      when :cyan   then Gosu::Color::CYAN
      else
        Gosu::Color.rgb(180, 180, 180)
      end

    return c if active

    # Dim badge when robot is off
    Gosu::Color.rgba(c.red, c.green, c.blue, 140)
  end

  def draw_robot_badge(robot, x, y, sprite_size_px)
    badge_color = badge_color_for(robot.color, active: robot.active)

    # Position badge near top-right of robot sprite
    # Tweak these offsets if your PNG has extra transparent padding.
    offset = sprite_size_px * 0
    bx = x + offset
    by = y - offset

    badge_r = [[sprite_size_px * 0.14, 4].max, 10].min

    # Badge fill + outline
    draw_circle(bx, by, badge_r, 18, badge_color, 24)
    draw_circle_outline(bx, by, badge_r, 18, Gosu::Color::BLACK, 25)
  end
  # -----------------------------
  # Compatibility / world API
  # -----------------------------
  def cursor(_which)
    # No-op in this first Gosu version
  end

  def number_of_streets
    @_streets
  end

  def set_size(streets)
    @_streets = streets
  end

  def clear
    @mutex.synchronize do
      @robots.clear
      @beepers.clear
      @walls_north.clear
      @walls_east.clear
    end
  end

  def geometry(height)
    @oldHeight = @height
    @height = height
    @_bottom = height - $inset
    @_left   = $inset
    @_top    = $inset
    @_right  = height
  end

  def scale_factor
    geometry(@height)
    ((@_bottom - @_top) * 1.0) / @_streets
  end

  def scale_to_pixels(street, avenue)
    scale = scale_factor
    [@_left + avenue * scale, @_bottom - street * scale]
  end

  def place_beeper(street, avenue, number)
    sync_ui do
      @mutex.synchronize do
        @beepers[[street, avenue]] = number
      end
    end
    flush_step_frame
  end

  def delete_beeper(beeper_location)
    sync_ui do
      @mutex.synchronize do
        @beepers.delete(beeper_location)
      end
    end
    flush_step_frame
  end

  def place_wall_north_of(street, avenue)
    sync_ui do
      @mutex.synchronize do
        @walls_north[[street, avenue]] = true
      end
    end
    flush_step_frame
  end

  def place_wall_east_of(street, avenue)
    sync_ui do
      @mutex.synchronize do
        @walls_east[[street, avenue]] = true
      end
    end
    flush_step_frame
  end

  def remove_wall_north_of(street, avenue)
    sync_ui do
      @mutex.synchronize do
        @walls_north.delete([street, avenue])
      end
    end
    flush_step_frame
  end

  def remove_wall_east_of(street, avenue)
    sync_ui do
      @mutex.synchronize do
        @walls_east.delete([street, avenue])
      end
    end
    flush_step_frame
  end

  def add_robot(street, avenue, direction, color)
    robot = RobotVisual.new(street, avenue, direction, color, true)
    sync_ui do
      @mutex.synchronize { @robots << robot }
    end
    flush_step_frame
    robot
  end

  def turn_off_robot(robot)
    sync_ui do
      @mutex.synchronize do
        robot.active = false
      end
    end
    flush_step_frame
  end

  def move_robot(robot, amount = -1)
    amount = 1 unless amount > 1
    dx, dy = $moveParameters[robot.direction]
    sync_ui do
      @mutex.synchronize do
        robot.street -= dy * amount
        robot.avenue += dx * amount
      end
    end
    flush_step_frame
  end

  def turn_left_robot(robot)
    sync_ui do
      @mutex.synchronize do
        idx = $directions.index(robot.direction) || 0
        robot.direction = $directions[(idx + 1) % 4]
      end
    end
    flush_step_frame
  end

  def set_speed(amount)
    @speed_amount = [[amount, 0].max, 100].min

    # Push the new speed into RobotWorld if available.
    # RobotWorld controls @@delay (actual sleep timing).
    if defined?(RobotWorld) && RobotWorld.respond_to?(:set_speed)
      RobotWorld.set_speed(@speed_amount)
    end

    @speed_amount
  end

  # On macOS, Gosu/AppKit event pumping must stay on the main thread.
  # We keep this as a no-op and instead synchronize world mutations through
  # a small main-thread command queue so the visible state stays in sync
  # without calling tick from the worker thread.
  def flush_step_frame
    # no-op
  end

  def on_main_thread?
    Thread.current == @main_thread
  end

  def sync_ui(&block)
    if on_main_thread?
      block.call
    else
      done = Queue.new
      @ui_queue << [block, done]
      done.pop
    end
  end

  def drain_ui_queue
    loop do
      block, done = @ui_queue.pop(true)
      begin
        block.call
      ensure
        done << true if done
      end
    end
  rescue ThreadError
    # queue empty
  end

  def enable_debug_step_flush!
    @debug_step_flush = true
  end

  def disable_debug_step_flush!
    @debug_step_flush = false
  end

  # Preserve the old style: window.run(lambda { task })
  def run(task_proc = nil, &block)
    work = block || task_proc

    if work
      Thread.new do
        begin
          sleep 0.05 # let window initialize
          work.respond_to?(:call) ? work.call : nil
        rescue Exception => e
          warn "[Karel task thread] #{e.class}: #{e.message}"
          warn e.backtrace.join("\n")
        end
      end
    end

    show
  end

  # -----------------------------
  # Gosu callbacks
  # -----------------------------
  def update
    drain_ui_queue

    # Simulation logic remains in RobotWorld / task thread
    # Keyboard shortcuts (optional)
    if button_down?(Gosu::KB_ESCAPE)
      close
    end
  end

  def draw
    # Snapshot under mutex to avoid mid-draw mutation issues
    robots, beepers, walls_north, walls_east = nil
    @mutex.synchronize do
      robots = @robots.map(&:dup)
      beepers = @beepers.dup
      walls_north = @walls_north.dup
      walls_east = @walls_east.dup
    end

    draw_background
    draw_grid
    draw_axis_labels
    draw_boundary
    draw_walls(walls_north, walls_east)
    draw_beepers(beepers)
    draw_robots(robots)
    draw_hud
  end

  # -----------------------------
  # Drawing helpers
  # -----------------------------
  def draw_background
    Gosu.draw_rect(0, 0, width, height, Gosu::Color::WHITE, 0)
  end

  def draw_grid
    line_color = Gosu::Color.rgb(220, 220, 220)
    (1..@_streets).each do |i|
      x1, y1 = scale_to_pixels(i, 0.5)
      x2, y2 = scale_to_pixels(i, @_avenues + 0.5)
      Gosu.draw_line(x1, y1, line_color, x2, y2, line_color, 1)

      x3, y3 = scale_to_pixels(0.5, i)
      x4, y4 = scale_to_pixels(@_streets + 0.5, i)
      Gosu.draw_line(x3, y3, line_color, x4, y4, line_color, 1)
    end
  end

  def draw_boundary
    c = Gosu::Color::BLACK
    # Roughly match old Tk boundary style (left + bottom)
    x, y = scale_to_pixels(0.5, 0.5)
    Gosu.draw_line(x, 0, c, x, y, c, 3)
    Gosu.draw_line(x, y, c, @_right + $inset, y, c, 3)
  end

  def draw_axis_labels
    (1..@_streets).each do |i|
      x1, y1 = scale_to_pixels(i, 0.2)
      @font_small.draw_text(i.to_s, x1 - 6, y1 - 8, 5, 1.0, 1.0, Gosu::Color::BLACK)

      x2, y2 = scale_to_pixels(0.2, i)
      @font_small.draw_text(i.to_s, x2 - 6, y2 - 8, 5, 1.0, 1.0, Gosu::Color::BLACK)
    end
  end

  def draw_walls(walls_north, walls_east)
    c = Gosu::Color::BLACK
    thickness = 4

    walls_north.each_key do |(street, avenue)|
      # Horizontal wall: shift one block LEFT from current drawing
      # Old version used avenue .. avenue+1 at street+0.5
      # New version uses avenue-1 .. avenue at street+0.5
      x1, y1 = scale_to_pixels(street + 0.5, avenue - 0.5)
      x2, y2 = scale_to_pixels(street + 0.5, avenue + 0.5)
      draw_thick_line(x1, y1, x2, y2, thickness, c, 6)
    end

    walls_east.each_key do |(street, avenue)|
      # Vertical wall: shift 1/2 block LOWER from current drawing
      # Old version used street .. street+1 at avenue+0.5
      # New version uses street-0.5 .. street+0.5 at avenue+0.5
      x1, y1 = scale_to_pixels(street - 0.5, avenue + 0.5)
      x2, y2 = scale_to_pixels(street + 0.5, avenue + 0.5)
      draw_thick_line(x1, y1, x2, y2, thickness, c, 6)
    end
  end

  def draw_beepers(beepers)
    beepers.each do |(street, avenue), number|
      x, y = scale_to_pixels(street, avenue)

      # Draw a black disk (or square if you prefer)
      r = [scale_factor * 0.16, 10].min
      draw_circle(x, y, r, 18, Gosu::Color::BLACK, 10)

      label =
        if number == $INFINITY || number.to_i < 0
          "∞"
        else
          number.to_i.to_s
        end

      text_color = Gosu::Color::WHITE
      @font_beeper.draw_text(label, x - 5, y - 8, 11, 1.0, 1.0, text_color)
    end
  end

  def draw_robots(robots)
    robots.each do |robot|
      x, y = scale_to_pixels(robot.street, robot.avenue)

      img = robot_image_for(robot)
      if img
        # Scale sprite to fit in cell
        target_size = [scale_factor * 0.70, 40].min
        sx = target_size / img.width.to_f
        sy = target_size / img.height.to_f

        img.draw_rot(x, y, 20, 0, 0.5, 0.5, sx, sy)

        # Draw color badge on top of robot
        draw_robot_badge(robot, x, y, target_size)
      else
        # Fallback vector robot if image missing
        draw_robot_fallback(robot, x, y)
      end
    end
  end

  def robot_image_for(robot)
    state_key = robot.active ? :on : :off
    dir_images = @robot_images[state_key]
    return nil unless dir_images

    dir_images[robot.direction]
  end

  def draw_hud
    @font_small.draw_text("Speed #{@speed_amount}", 10, 8, 50, 1.0, 1.0, Gosu::Color::BLACK)
    @font_small.draw_text("ESC to close", 110, 8, 50, 1.0, 1.0, Gosu::Color.rgb(80, 80, 80))
  end

  # -----------------------------
  # Geometry utilities
  # -----------------------------
  def draw_circle(cx, cy, radius, segments, color, z)
    angle_step = Math::PI * 2.0 / segments
    segments.times do |i|
      a1 = i * angle_step
      a2 = (i + 1) * angle_step
      x1 = cx + Math.cos(a1) * radius
      y1 = cy + Math.sin(a1) * radius
      x2 = cx + Math.cos(a2) * radius
      y2 = cy + Math.sin(a2) * radius
      Gosu.draw_triangle(cx, cy, color, x1, y1, color, x2, y2, color, z)
    end
  end

  def draw_circle_outline(cx, cy, radius, segments, color, z)
    angle_step = Math::PI * 2.0 / segments
    points = (0...segments).map do |i|
      a = i * angle_step
      [cx + Math.cos(a) * radius, cy + Math.sin(a) * radius]
    end
    points.each_with_index do |p1, i|
      p2 = points[(i + 1) % points.length]
      Gosu.draw_line(p1[0], p1[1], color, p2[0], p2[1], color, z)
    end
  end

  def draw_thick_line(x1, y1, x2, y2, thickness, color, z)
    if (x1 - x2).abs < 0.001
      # vertical
      left = x1 - thickness / 2.0
      top = [y1, y2].min
      h = (y2 - y1).abs
      Gosu.draw_rect(left, top, thickness, h, color, z)
    elsif (y1 - y2).abs < 0.001
      # horizontal
      left = [x1, x2].min
      top = y1 - thickness / 2.0
      w = (x2 - x1).abs
      Gosu.draw_rect(left, top, w, thickness, color, z)
    else
      Gosu.draw_line(x1, y1, color, x2, y2, color, z)
    end
  end

  def direction_triangle_points(direction, x, y, r)
    case direction
    when NORTH
      [[x, y - r], [x - 6, y + 2], [x + 6, y + 2]]
    when SOUTH
      [[x, y + r], [x - 6, y - 2], [x + 6, y - 2]]
    when EAST
      [[x + r, y], [x - 2, y - 6], [x - 2, y + 6]]
    when WEST
      [[x - r, y], [x + 2, y - 6], [x + 2, y + 6]]
    else
      [[x, y - r], [x - 6, y + 2], [x + 6, y + 2]]
    end
  end

  def gosu_color_for(color)
    case color
    when :red    then Gosu::Color::RED
    when :green  then Gosu::Color::GREEN
    when :blue   then Gosu::Color::BLUE
    when :yellow then Gosu::Color::YELLOW
    when :black  then Gosu::Color::BLACK
    when :white  then Gosu::Color::WHITE
    when nil     then Gosu::Color.rgb(240, 240, 240)
    else
      Gosu::Color.rgb(240, 240, 240)
    end
  end

  def button_down(id)
    case id
    when Gosu::KB_ESCAPE
      close
    when Gosu::KB_LEFT_BRACKET
      # slower
      set_speed(@speed_amount - 10)
    when Gosu::KB_RIGHT_BRACKET
      # faster
      set_speed(@speed_amount + 10)
    end
    super
  end
end
