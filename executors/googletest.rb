#!/usr/bin/env ruby

p ENV['BUNDLE_GEMFILE']=File.expand_path(File.dirname(__FILE__)) + "/Gemfile"

require 'bundler/setup'
require 'awesome_print'
require 'typhoeus'
require_relative '../config.rb'
require_relative '../helpers.rb'
require 'active_support/core_ext/hash'
require 'jsonclient'
require 'nokogiri'
require 'erb'


task = File.read('task.json')

##where should i go
module Ethon
	class Easy
		module Queryable
			def mime_type(filename)
				if defined?(MIME) && t = MIME::Types.type_for(filename).first
					t.to_s
				else
					'text/plain'
				end
			end
		end
	end
end

def parse_task_config(task_raw)
	p "Parsing task configuration"
	#<variables-in-config>
	test_name = JSON.parse(task_raw)["test_name"]
	task = JSON.parse(task_raw)
	task_dir = Dir.pwd
	#</variables-in-config>
	## some stuff to keep json format sane.
	task_evaluated = JSON.parse(ERB.new(JSON.dump(JSON.parse(task_raw))).result(binding))
	task_evaluated
end

def execute_google_tests(task)
	p ["Executing google tests",task["test_name"]].join(': ')
	current_directory = Dir.pwd
	environment_variables = task["environment_variables"]
	google_command = task["command_line"]
	command_line = [environment_variables,google_command].join(' ')
	puts command_line
	puts `#{command_line}`
end

def get_google_tests(task)
	p ["Fetching google tests",task["test_name"]].join(': ')
	google_tests = SchedyHelper.fetch_package(target_url: task["test_package"])
	SchedyHelper.extract_to_worker_storage(google_tests)
	SchedyHelper.link_archive_to_task_folder(google_tests,task["id"])
end

#INFO: Post processing function for google framework results.
def self.google_post_processing(task,task_directory)
	p ["Post processing google tests",task["test_name"],task_directory].join(': ')
	$scheduler_uri ||= 'http://scheduler-server'
	google_file_path = [task_directory,'googletest_result.xml'].join('/')
	value_endpoint = [$scheduler_uri,'tasks/',task["id"],"/tags"].join('/')
	gemfile_path = [SCHEDULER_WORKER_ROOT,'project','bin','Gemfile'].join('/')
	if not File.file?(google_file_path)
		puts 'googletest_result.xml not found ! no result will be reported.'
		return 0
	end
	stats_json = JSON.parse(parse_googletest_xml(google_file_path))[0]
	if stats_json["result"] == "passed" then result = "PASS" end
	if stats_json["result"] == "failed" then result = "FAIL" end
	reason = stats_json["message"]
	puts ["Results JSON:",stats_json,'Uploading to server.'].join(' ')
	result_res = Typhoeus.post(value_endpoint,body: {task_id: task["id"], property: "result", value: result })
	reason_res = Typhoeus.post(value_endpoint,body: {task_id: task["id"], property: "reason", value: reason })
	return 0
end

def parse_googletest_xml(source_path)
	outgoing = []
	File.open(source_path) { |f|
		document = Nokogiri::XML(f)
		document.xpath("testsuites/testsuite").each { |suite|
			suite.xpath("testcase").each { |testcase|
				result = :passed
				message = ""
				output = ""
				testcase.xpath("failure|error|skipped").each { |failure|
					result = failure.node_name == "skipped" ? :skipped : :failed
					message = failure["message"]
					output  = failure.text
				}
				outgoing.push({
					"name"=> testcase["name"],
					"status" => testcase["status"],
					"time" => testcase["time"],
					"result" => result,
					"message" => message,
					"output" => output
				})
			}
		}
	}
	puts JSON.generate(outgoing)

	return JSON.generate(outgoing)
end

task = parse_task_config(task)
task_id = task["id"]
task_directory = [SCHEDULER_WORKER_ROOT,'storage','tasks',task_id].join('/')

Dir.chdir(task_directory)
get_google_tests(task)
Dir.chdir(task_directory)
execute_google_tests(task)
Dir.chdir(task_directory)
google_post_processing(task,task_directory)
