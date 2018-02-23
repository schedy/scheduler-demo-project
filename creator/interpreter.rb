require 'ostruct'
require 'rest_client'
require "awesome_print"
require 'json'
require 'bunny'

require "./execution_creator.rb"
require '../config.rb'
require '../helpers.rb'

queue_name = "testing"
if ARGV[0] then queue_name=ARGV[0] end
if ARGV[1] then RABBIT_HOST=ARGV[1] end
if ARGV[2] then RABBIT_USER=ARGV[2] end
if ARGV[3] then RABBIT_PASS=ARGV[3] end

STDOUT.sync = true
	require 'active_support/core_ext/hash'
	class NotOnOBS < Exception; end

def wi_parser(wi)
	description = OpenStruct.new
	if wi["payload"]
		payload = wi["payload"]
		description.default_project = payload["project"]
		case payload["eventtype"].to_s
			when /SRCSRV_REQUEST_CREATE/i
				description.event_type = "obs_submit_request"
				description.url_obs = "https://obs-server/build/request/show/#{payload["id"]}"
				description.author = payload["author"]
			when /VCSCOMMIT_REF/i
				description.event_type = "master_merge"
			when /VCSCOMMIT_REVIEW/i
				description.event_type = "gerrit_pull_request"
				description.default_project = payload["parent_project"].to_s
			when /NIGHTLY/i
				description.event_type = "nightly"
			when /MANUAL/i
				description.event_type = "manual"
			else
				puts "Unknown event type: #{payload["eventtype"].to_s}"
		end

		if pr = payload["pr"]
			description.author = pr["username"]
			description.url_gerrit = pr["url"]
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
		#if not payload["project"].to_s.empty? then description.target_project       = payload["project"].to_s    end
	end

	description.multiplier = (wi["multiplier"] or "1").to_i
	return description
end


#Create a new bunny connection and initialize it.
puts RABBIT_HOST
conn = Bunny.new(:host => (RABBIT_HOST or 'localhost'), :vhost => "/", :user => RABBIT_USER, :password => RABBIT_PASS)
conn.start


#Create a new channel and queue
ch = conn.create_channel
q  = ch.queue(queue_name,:durable => true)
ch.prefetch(1)

#Create an exchange for the bindings
exchange = Bunny::Exchange.new(ch, :direct, queue_name, {:durable => true})

#Create the bindings
q.bind(queue_name)
q.bind(queue_name, :routing_key => queue_name)

#Validate if queue exists.
ap conn.queue_exists?(queue_name)
#Subscribe and wait for a message from testing queue.
q.subscribe(:block => true,:manual_ack => true) do |delivery_info, metadata, payload|
	begin
		#Parse workitem, create tasks and add tags.
		puts "Incoming payload wi-#{delivery_info.delivery_tag}:"
		puts payload
		workitem = JSON.parse(payload)["args"][0]
		ack_flag = true
		
		execution = ExecutionCreator.create_execution(wi_parser(workitem))
		execution["data"] = workitem
		post_response = RestClient.post(SCHEDULER_URI+'/executions',JSON.dump({execution: execution}), :content_type => :json, :accept => :json)
		if post_response.code.to_s != "200"
			ack_flag = false
		else
			puts "Execution for workitem wi-#{delivery_info.delivery_tag} created!"
		end
		if ack_flag then ch.ack(delivery_info.delivery_tag, false) end
	rescue NotOnOBS => e1
		ch.ack(delivery_info.delivery_tag, false)
		puts e1.to_s
		exit
	rescue => e2
		if e2.kind_of?(Exception)
			puts e2.backtrace
		end
		puts e2.to_s
		exit
	end
end
