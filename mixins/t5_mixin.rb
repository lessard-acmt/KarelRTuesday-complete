#Copyright 2012 Joseph Bergin
#License: Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License

=begin
 The beginnings of a student defined module to be mixed in to other classes to provide
 auxiliary methods that are generally useful.  
=end
module T5Mixin

  def diag_droit
    move
    turn_right
    move
    turn_left
  end

  def diag_gauche
    move
    turn_left
    move
    turn_right
  end

  def move_et_put_beeper
    move
    put_beeper
  end

  def move_et_put_6_beepers
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
  end

  def move_et_put_7_beepers
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
    move_et_put_beeper
  end

  def move_et_pick_beeper
    move
    pick_beeper
  end

  def move_et_pick_2_beepers
    move_et_pick_beeper
    move
    move_et_pick_beeper
  end

  def move_et_pick_3_beepers
    move_et_pick_beeper
    move
    move_et_pick_beeper
    move
    move_et_pick_beeper
  end

  def move_et_pick_4_beepers
    move_et_pick_beeper
    move
    move_et_pick_beeper
    move
    move_et_pick_beeper
    move
    move_et_pick_beeper
  end

end