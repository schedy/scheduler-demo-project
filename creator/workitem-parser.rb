require 'ostruct'


def workitem_parse(workitem)
	description = OpenStruct.new

	if workitem["payload"]
		payload = workitem["payload"]
		description.default_project = payload["project"]

		case payload["eventtype"].to_s
			when /SRCSRV_REQUEST_CREATE/i
				description.event_type = "obs_submit_request"
				description.url_obs = "https://obs/build/request/show/#{payload["id"]}"
				description.author = payload["author"]
			when /VCSCOMMIT_REF/i
				description.event_type = "master_merge"
			when /VCSCOMMIT_REVIEW/i
				description.event_type = "gerrit_pull_request"
				description.default_project = payload["parent_project"].to_s
				if payload and payload["pr"] and payload["pr"]["testtype"] == "e2e"
					payload["hooks"] = {"finished"=>["e2e_bureaucrat.rb"]}
					if payload["pr"]["test_args"].length > 0
						arguments = payload["pr"]["test_args"].split("%")
						if arguments.length > 0
							args_obj = arguments[1..-1].map{|var| var.strip.split(':') }.to_h
							if (args_obj and args_obj["multiplier"]) then workitem["multiplier"] = args_obj["multiplier"] end
						end
					end
					description.event_type = "e2e"
					if payload["pr"]["test_args"].length > 0
						arguments = payload["pr"]["test_args"].split("%")
						if arguments.length > 0
							args_obj = arguments[1..-1].map{|var| var.strip.split(':') }.to_h
							workitem["multiplier"] = if args_obj and args_obj["multiplier"] then args_obj["multiplier"] end
						end
					end
				end
				if payload and payload["pr"] and payload["pr"]["testtype"] == "mechatouch"
					description.event_type = "mechatouch"
					payload["hooks"] = {"finished"=>["mecha_bureaucrat.rb"]}
				end
			when /MANUAL/i
				description.event_type = "manual"
			when /E2E|CHALLEN/i
				description.event_type = payload['eventtype']
				payload["hooks"] = {"finished"=>["data_exporter_2.rb","data_exporter.rb","e2e_flowdock_onfinish.rb"]}
			else
				description.event_type = payload['eventtype']
				puts "Unknown event type: #{payload['eventtype'].to_s}"
		end

		if pr = payload["pr"]    #FIXME: what does "pr" stand for?
			description.author = pr["username"]
			description.url_gerrit = pr["url"]
			#description.test_type = pr["testtype"]
		end

		if payload_payload = payload["payload"] and not description.url_gerrit
			description.url_gerrit = payload_payload["url"]
		end

		description.package_project = Hash.new()
		if payload["results"]
			payload["results"].each { |result|
				# TODO: think is if needed? should we raise?
				if result["project"] and result["package"]
					description.package_project[result["package"]] = result["project"]
				end
			}
		end

		description.package_arch = (payload["results"] or []).map { |result| [result["package"], result["arch"]] }.to_h
		description.package_repository = (payload["results"] or []).map { |result| [result["package"], result["repository"]] }.to_h

		if payload["actions"]
			changed = {}
			payload["actions"].each { |action|
				# TODO: think is if needed? should we raise?
				if action["type"] == "submit" and action["targetproject"] and action["sourceproject"]
					changed[action["targetpackage"]] = {source: action["sourceproject"], target: action["targetproject"]}
				end
			}
			description.changed = changed
		end

		if not payload["package"].to_s.empty? then description.triggered_by_package = payload["package"].to_s    end
		if not payload["project"].to_s.empty? then description.project              = payload["project"].to_s    end
		if not payload["hooks"].to_s.empty? then description.hooks = payload["hooks"].to_s    end
		#if not payload["project"].to_s.empty? then description.target_project       = payload["project"].to_s    end
	end

	if payload["pr"] and payload["pr"]["test_args"] and payload["pr"]["test_args"].length > 0
		arguments = payload["pr"]["test_args"].split("%")
	        if arguments.length > 0
			args_obj = arguments[1..-1].map{|var| var.strip.split(':') }.to_h
			workitem["multiplier"] = if args_obj and args_obj["multiplier"] then args_obj["multiplier"] end
		end
	end
	description.multiplier = (workitem["multiplier"] or "1").to_i

	puts "Parsed workitem:"
	puts description.to_s
	return description
end
