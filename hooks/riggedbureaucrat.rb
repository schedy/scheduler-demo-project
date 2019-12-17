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
source_project = target_execution["data"]["payload"]["pr"]["source_project"]
workitem = target_execution.data

gating_tag = if !Property.where(name:'gating_tag').empty? and target_execution.execution_values.find { |v| v.value.property.name == "gating_tag" } then target_execution.execution_values.find { |v| v.value.property.name == "gating_tag" }.value.value else nil end

gating_threshold = if !Property.where(name:'threshold').empty? and target_execution.execution_values.find { |v| v.value.property.name == "threshold" } then target_execution.execution_values.find { |v| v.value.property.name == "threshold" }.value.value else 0 end


total_test_results = target_execution.tasks.map { |t| t.task_values }.flatten.select { |tv| tv.value.value== "PASS" or tv.value.value == "FAIL" }.map { |z| if z.value.value == "PASS" then 100 else 0 end }

all_test_count = target_execution.tasks.length

executed_test_count = target_execution.tasks.map { |t| t.task_values }.flatten.select { |tv| tv.value.value== "PASS" or tv.value.value == "FAIL" }.length


if total_test_results.sum.is_a?(Numeric)

	total_test_results_average = if not (total_test_results.sum.to_f/total_test_results.size.to_f).nan? then (total_test_results.sum.to_f/total_test_results.size.to_f).floor else 0 end

	((total_test_results_average/100.0).to_f >= gating_threshold.to_f) ? result = 1 : result = -1

else
	total_test_results_average = 0
	result = 1
end

	if gating_tag

		gating_tests = target_execution.tasks.select { |t| t.description["tags"].values.flatten.find { |e| e =~ (/#{gating_tag}/) } }

		if gating_tests.size == 0 then gating_tests = target_execution.tasks end

		gating_tag_all_test_count = gating_tests.size

		gating_task_value_template = Hash.new { |hash,key| hash[key] = gating_tests.map { |t| t.task_values }.flatten.select { |tv| tv.value.value =~ /#{key}/ } }
		gating_pass_count = gating_task_value_template["PASS"].size
		gating_fail_count = gating_task_value_template["FAIL"].size

		gating_tag_success_rate = (gating_pass_count.to_f/gating_tag_all_test_count.to_f)
		p "Success rate: #{gating_tag_success_rate}"
		#Result below is subject to change.
		((gating_tag_success_rate.to_f >= gating_threshold.to_f) ? result = 1 : result = 1)


		#gating_tag_test_results = target_execution.tasks.select { |t| t.description["tags"].values.flatten.find { |e| e =~ (/#{gating_tag}/) } }.map { |t| t.task_values }.flatten.select { |tv| tv.value.value== "PASS" or tv.value.value == "FAIL" }.map { |z| if z.value.value == "PASS" then 100 else 0 end }
		#gating_tag_test_results_average = if not (gating_tag_test_results.sum.to_f/gating_tag_test_results.size.to_f).nan? then (gating_tag_test_results.sum.to_f/gating_tag_test_results.size.to_f).floor else 0 end
		#Result below is subject to change.
		#((gating_tag_test_results_average/100.0).to_f >= gating_threshold.to_f) ? result = 1 : result = -1
	end


execution_uri = EXTERNAL_SCHEDULER_URI+'/a?show=execution&execution_id='+execution_id.to_s+'&~executions_filter~limit=50'

tested_packages = Execution.find(execution_id).tasks.map { |t| t["description"]["test_package"] }.uniq.flatten.map { |e| "* "+File.basename(e) }.join("\n")

description = [workitem["payload"]["package"].to_s," robot tests: ",total_test_results_average.to_s," % of executed tests passed. #{all_test_count} tests available, #{executed_test_count} successfully executed. ",execution_uri,". Package used for testing in this execution: ",tested_packages,"."].join('')


if gating_tag
	description = [description,"Also, ", gating_tag_success_rate.to_f*100 ," % of gating tests passed."].join(' ')
end

#Merge/Append results to incoming workitem.
if workitem["payload"]["results"]
	workitem["payload"]["results"].append({"label": "Tested","vote": result,"reported": false,"type":"Testing","desc": description, "package": source_project})
else
	workitem["payload"]["results"] = [{"label": "Tested","vote": result,"reported": false,"type":"Testing","desc": description, "package": source_project}]
end
#Dispatch new workitem to queue.
bureaucrat_hook(execution_id,status,workitem)
