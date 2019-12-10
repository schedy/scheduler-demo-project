require 'ostruct'
require 'rest_client'
require "awesome_print"
require 'json'

require '../common-server.rb'

def alm_wi_parser(wi)
	wi = JSON.parse(wi)
	description = OpenStruct.new
	if wi["payload"]
		payload = wi["payload"]
		description.package = payload["package"].to_s
		description.project = payload["project"].to_s
		description.test_name = payload["test_name"].to_s    					
		description.event_type = "alm"
		description.author = payload["username"]
		description.multiplier = (payload["multiplier"] or "1").to_i
	end
	return description		
end

begin
	#Parse workitem, create tasks and add tags.
	execution = ExecutionCreator.create_execution(alm_wi_parser(STDIN.read))
	execution["data"] = workitem
	puts JSON.dump(execution)
end
