#!/opt/local/bin/ruby
#Copyright 2012 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

$graphical = true

require_relative "mark2_robot"

# a task for a stair sweeper
def task()
  karel = Mark2Robot.new(1, 1, Robota::NORTH, 0)
  karel.move
  karel.move
  karel.turn_right
  karel.move
  karel.move
  karel.turn_right
  karel.move
  karel.move
  karel.turn_right
  karel.move
  karel.move
  karel.turn_right
end

if __FILE__ == $0
  if $graphical
     screen = window(8, 40) # (size, speed)
     screen.run do
       task
     end
   else
     task
   end
end