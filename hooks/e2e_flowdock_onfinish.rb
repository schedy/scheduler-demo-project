#!/bin/env ruby

#Docs for Flowdock Messages API: https://www.flowdock.com/api/messages

require 'bundler/setup'

require '../../config/environment.rb'
require 'rest-client'
require '../config.rb'
require 'logger'

def post_flowdock_message(params)

	payload = {
		'event': 'message',
		'flow_token': params["flowdock_token"],
		'content': params["message"],
		'external_user_name': 'nightly-reporter'
		}
	p payload.to_json
	RestClient::Request.execute( method: :post, url: params["flowdock_url"],
				     payload: payload, proxy: params["proxy"]
	) { |response,request,result|
		case response.code
		when 202
			@log.info("SUCCESS : #{response.code}")
		else
			@log.error("CODE : #{response.code} - REQUEST : #{request.inspect} - RESPONSE BODY : #{response.body}")
		end
	  }

end

@log = Logger.new(STDOUT)

execution_id = ARGV[0]
status = ARGV[1]

params = Hash.new("")

@log.info "Received event from Execution ID: #{execution_id}, Status: #{status}"

target_execution = Execution.find(execution_id)
event_type = target_execution["data"]["payload"]["eventtype"]
pass_rate = 0
execution_uri = EXTERNAL_SCHEDULER_URI+'/a?show=execution&execution_id='+execution_id.to_s

total_test_results = target_execution.tasks.map { |t| t.task_values }.flatten.select { |tv| tv.value.value== "PASS" or tv.value.value == "FAIL" }.map { |z| if z.value.value == "PASS" then 100 else 0 end }

all_test_count = target_execution.tasks.length

executed_test_count = target_execution.tasks.map { |t| t.task_values }.flatten.select { |tv| tv.value.value== "PASS" or tv.value.value == "FAIL" }.length

if total_test_results.sum.is_a?(Numeric)
	        total_test_results_average = if not (total_test_results.sum.to_f/total_test_results.size.to_f).nan? then (total_test_results.sum.to_f/total_test_results.size.to_f).floor else 0 end
		pass_rate = (total_test_results_average/100.0).to_f
end

params["proxy"] = "https://http-proxy"
params["flowdock_url"] = 'https://api.flowdock.com/messages'
params["flowdock_token"] = TESTRESULTS_FLOWDOCK_TOKEN
params["message"] = "#{event_type} tests in execution #{execution_id} has been completed. \n Total number of tests: #{all_test_count}. Number of executed test cases: #{executed_test_count}. \n Reported pass rate: #{pass_rate}. \n Test execution can be found at: #{execution_uri}"
@log.info "Sending message: #{params.to_s}"
post_flowdock_message(params)
