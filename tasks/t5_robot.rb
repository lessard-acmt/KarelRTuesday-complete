#Copyright 2010 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License


require_relative "../karel/ur_robot"
require_relative "../mixins/turner"
require_relative "../mixins/t5_mixin"
# A class whose robots know how to sweep a short staircase of beepers
class T5Robot < UrRobot
  include Turner
  include T5Mixin

  def mettre_lhorloge
    put_beeper
    diag_droit
    put_beeper
    move_et_put_beeper
    diag_gauche
    put_beeper
    diag_gauche
    put_beeper
    turn_left
    put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    diag_gauche
    put_beeper
    diag_gauche
    put_beeper
    turn_left
    move_et_put_beeper
    diag_gauche
    put_beeper
    diag_gauche
    turn_left
    put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
  end


  def mettre_le_beton
    move_et_put_6_beepers
    turn_right
    move_et_put_7_beepers
    turn_right
    move_et_put_6_beepers
    turn_right
    move_et_put_7_beepers
    turn_off
  end

  def ranger_le_broccoli
    move_et_pick_beeper
    turn_right
    move
    move
    turn_left
    move
    turn_left
    move_et_pick_2_beepers
    move
    move
    turn_right
    move
    turn_right
    move_et_pick_3_beepers
    move
    move
    turn_left
    move
    turn_left
    move_et_pick_4_beepers
    turn_right
    move
    turn_right
    move_et_pick_3_beepers
    turn_left
    move
    turn_left
    move_et_pick_2_beepers
    turn_right
    move
    turn_right
    move_et_pick_beeper
    turn_left
    move
    turn_off
  end

  def mettre_les_quilles
    move_et_put_beeper
    turn_left
    move
    turn_right
    move_et_put_beeper
    turn_right
    move
    move_et_put_beeper
    move
    turn_left
    move_et_put_beeper
    turn_left
    move
    move_et_put_beeper
    move
    move_et_put_beeper
    move
    turn_right
    move_et_put_beeper
    turn_right
    move
    move_et_put_beeper
    move
    move_et_put_beeper
    move
    move_et_put_beeper
    turn_around
    move
    move
    move
    turn_right
    move
    turn_off
  end

end