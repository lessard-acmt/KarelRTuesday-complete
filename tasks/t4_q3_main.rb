#!/opt/local/bin/ruby
#Copyright 2012 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

$graphical = true

require_relative "t4a_q2_5_beepers_robot"
require_relative "../karel/robota"

# a task for a stair sweeper
def task()
  karel = T4aQ25BeepersRobot.new(3, 3, Robota::NORTH, 25, :magenta)

  karel.mettre_5_rangees_de_5_beepers
  
end

if __FILE__ == $0
  if $graphical
     screen = window(15, 40) # (size, speed)
     screen.run do
       task
     end
   else
     task
   end
end