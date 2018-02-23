class CPU < Resource
	def self.estimate(candidate, required)
    estimated_transition = 0
    step = { resource: candidate,required: required,steps: [] }
	{ transition_duration: estimated_transition, actors: {}, steps: step }
	end
	def self.transition(owned, required, steps)
    return true
  end
end
