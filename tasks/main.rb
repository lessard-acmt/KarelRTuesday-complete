#!/opt/local/bin/ruby
#Copyright 2012 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

$graphical = true

require_relative "stair_sweeper"
require_relative "../karel/robota"

# a task for a stair sweeper
def task()
  world = Robota::World
  #world.read_world("worlds/fig1-2a.kwld")
  
  karel = StairSweeper.new(1, 1, Robota::EAST, 0)

  while true
    4.times do
      karel.move
    end
    karel.turn_left
  end



end

if __FILE__ == $0
  if $graphical
     screen = window(20, 40) # (size, speed)
     screen.run do
       task
     end
   else
     task
   end
end