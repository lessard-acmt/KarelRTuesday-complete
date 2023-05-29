#!/opt/local/bin/ruby
#Copyright 2012 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

$graphical = true

require_relative "t5_robot"
require_relative "../karel/robota"

# a task for a stair sweeper
def task()
  karel = T5Robot.new(1, 5, Robota::NORTH, 15)
  karel.mettre_les_quilles
end

if __FILE__ == $0
  if $graphical
     screen = window(15, 90) # (size, speed)
     screen.run do
       task
     end
   else
     task
   end
end