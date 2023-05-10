#Copyright 2010 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

require_relative "../karel/ur_robot"
# A class whose robots know how to sweep a short staircase of beepers
class T4aQ25BeepersRobot < UrRobot

  def turn_right
    turn_left
    turn_left
    turn_left
  end

  def mettre_5_beepers
    put_beeper
    move
    put_beeper
    move
    put_beeper
    move
    put_beeper
    move
    put_beeper
    move
  end

  def mettre_5_rangees_de_5_beepers
    mettre_5_beepers
    turn_right
    move
    turn_right
    move
    mettre_5_beepers
    turn_left
    move
    turn_left
    move
    mettre_5_beepers
    turn_right
    move
    turn_right
    move
    mettre_5_beepers
    turn_left
    move
    turn_left
    move
    mettre_5_beepers
  end

end