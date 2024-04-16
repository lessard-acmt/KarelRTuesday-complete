require_relative "../karel/ur_robot"

# MON premier robot
class Mark2Robot < UrRobot

	def turn_right
		turn_left
		turn_left
		turn_left
	end

end