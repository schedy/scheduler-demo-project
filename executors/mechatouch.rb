#!/bin/env ruby
#
# Ensure mechatouch-server and scheduler-server names resolve to an IP
#

p ENV['BUNDLE_GEMFILE']=File.expand_path(File.dirname(__FILE__)) + "/Gemfile"

require 'bundler/setup'
require 'jsonclient'
require 'httpclient'

task = File.open('task.json') { |f| JSON.parse(f.read) }

mechatouch = task["actors"]["dut"]["description"]["mechatouch"]
branch = task["executor"][1]
test_uuid = task["executor"][2]

execution = JSONClient.post("http://mechatouch-server/branches/name:#{branch}/scenarios/#{test_uuid}/scenario_version_executions.json?device_uuid=#{mechatouch}", {}).body["uuid"]

p execution

p HTTPClient.post("http://scheduler-server/tasks/#{task["id"]}/tags", {task_id: task["id"], property: "mechatouch", value: "http://mechatouch-server/mechatouch/scenario_version_executions/#{execution}" })

result = loop{
	stat = JSONClient.get("http://mechatouch-server/scenario_version_executions/#{execution}.json").body
	break stat["result"] if stat["status"] == "finished"
	break "fail" if stat["status"] == "crashed"
	sleep 5
}

p result

stat = JSONClient.get("http://mechatouch-server/scenario_version_executions/#{execution}.json?artifacts=.tar.").body
stat["artifacts"].each { |artifact_path|
	`curl http://mechatouch-server#{artifact_path} > artifact.tar.noidea`
	`tar xf artifact.tar.noidea`
	`rm script artifact.tar.noidea`
}
stat["measurements"].each_pair { |label, values|
	values.each_with_index { |v,i|
		open("measurement_"+label.to_s+"_"+i.to_s, "w") { |f| f.write(v.to_s) }
	}
}




p HTTPClient.post("http://scheduler-server/tasks/#{task["id"]}/tags", {task_id: task["id"], property: "result", value: result.upcase })
