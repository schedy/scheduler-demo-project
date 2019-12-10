#!/bin/env ruby

require 'bundler/setup'

require '../../config/environment.rb'
require 'rest-client'
require 'awesome_print'
require 'json'
require 'bunny'
require '../config.rb'

## ARGV = [execution_id,status,workitem]

def bureaucrat_hook(execution_id,status,workitem)
	#Get a bunny connection, create channel and queue, and publish a message
	#to default exchange. bureaucrat_msgs routing key will help CIBot for
	#identifying message.
	STDOUT.sync = true
	conn = Bunny.new(:host => (RABBIT_HOST or 'localhost'), :vhost => "/", :user => RABBIT_USER, :password => RABBIT_PASS)
	conn.start
	puts "Getting a new channel."
	ch=conn.create_channel
	q=ch.queue("",:durable => true,:exclusive => true)
	x=ch.default_exchange
	puts "Execution ID: #{execution_id} - Status: #{status}"
	puts "Publishing workitem with bureaucrat_msgs key."
	x.publish(workitem.to_json,:routing_key => 'bureaucrat_msgs',:delivery_mode => 2, :content_type => 'application/x-bureaucrat-message' )
	conn.close
end

execution_id = ARGV[0]
status = ARGV[1]
puts "#{execution_id} - #{status}"
#Find related execution's data.
target_execution = Execution.find(execution_id)
workitem = target_execution.data

test_results =	
	target_execution.tasks.map { |task|
		if not task.artifacts.find_by(name: 'artifacts.zip') then next end
	actors_info = JSON.parse(task.artifacts.find_by(name: "task.json").data)["actors"].map { |k,v|
		#{"Role"=> k, "Board"=> v["description"]["board_name"], "Identifier"=> v["description"]["identifier"], "Image"=> v["description"]["image"]} }
		["* ",k,"@",v["description"]["board_name"] || v["description"]["sn"],"as",v["description"]["identifier"], "with software", v["description"]["image"]].join(' ')
	}.join("\n")
	
	[
		"------",
		"Test Name: "+task["description"]["tags"]["name"].first,
		"Result: "+task.task_values.find_by(property_id: 4).value.value,
		"Report: "+ EXTERNAL_SCHEDULER_URI+'/tasks/'+task["id"].to_s+'/artifacts/artifacts.zip',
		"Setup: ",
		actors_info
	].join("\n\n")
}.join("\n\n")

execution_uri = EXTERNAL_SCHEDULER_URI+'/a?show=execution&execution_id='+execution_id.to_s

description =
	[
		": E2E testing for commit #{workitem["commit_sha"]} has been completed and test execution can be found at #{execution_uri}. Test results and reports are given below.",
		test_results,
	].join("\n\n")

#Merge/Append results to incoming workitem.
if workitem["payload"]["results"]
	workitem["payload"]["results"].append({"label": "Tested","vote": 1,"reported": false,"type":"Testing","desc": description})
else
	workitem["payload"]["results"] = [{"label": "Tested","vote": 1,"reported": false,"type":"Testing","desc": description}]
end
#Dispatch new workitem to queue.
bureaucrat_hook(execution_id,status,workitem)
