#!/usr/bin/env ruby

p ENV['BUNDLE_GEMFILE']=File.expand_path(File.dirname(__FILE__)) + "/Gemfile"

require 'bundler/setup'
require 'awesome_print'
require 'typhoeus'
require_relative '../config.rb'
require_relative '../helpers.rb'
require 'active_support/core_ext/hash'
require 'jsonclient'

#require_relative './robot_config_creator.rb' #createConfigFile

require 'erb'

#is this cheating ?

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
	#File.open('task.json') { |f| JSON.load(ERB.new(File.read(f)).result(binding)) }
end

def create_robot_resource_file(task)
	p ["Creating resource file for",task["test_name"]].join(': ')

	File.open("resource_ci.robot","w") { |file|

		file.write("*** Variables ***\n")

		file.write(task["actors"].map { |actor_name, actor_data|
					   #Define a resource row, use database description of actors.
					   resource_row = "&{#{actor_name}}    id=#{actor_name}   " +actor_data['description'].map{ |key, value| "#{key}=#{value}" }.join("    ")
					   #Check if actors with matching roles have 'options' field in test-config.json
					   options = task["requirements"].find{|req| req["role"] == actor_name}["options"]
					   #If options exist, append them to resource row.
					   if not options.nil?
						   resource_row = [resource_row,options].join("   ")
					   end
					   #Return the final resource row.
					   resource_row
				   }.join("\n"))

		file.write("\n")
		#If this task has resource groups defined in its test-config.json, use some arcane magic of data wrangling to group those resources. Arrays of [role,group_key,group_value] are grouped by group_value and then mapped to create rows of 'group_key   group_value=role'.
		if task["has_resource_groups"] == "true"
			grouped_resources = {}
			task["requirements"].map { |requirement|
				requirement["resource-groups"].map { |resource_group| [requirement["role"],resource_group[0],resource_group[1]] }.group_by { |arr| arr[2] } }.map { |resources| resources.map { |resource_info| (grouped_resources[resource_info[0]] ||= []) << resource_info[1] }}
			file.write(grouped_resources.map { |resource_group,resource_info| "&{#{resource_group}}    "+resource_info.flatten(1).map{ |info| "#{info[1]}=&{#{info[0]}}"}.join("    ") }.join("\n"))
		end

		file.write("\n")
	}
end


def execute_robot_tests(task)
	p ["Executing robot tests",task["test_name"]].join(': ')
	current_directory = Dir.pwd
	environment_variables = task["environment_variables"]
	robot_command = task["command_line"]
	command_line = [environment_variables,robot_command].join(' ')
	puts command_line
	puts `#{command_line}`
end

def get_robot_tests(task)
	p ["Fetching robot tests",task["test_name"]].join(': ')
	robot_tests = SchedyHelper.fetch_package(target_url: task["test_package"])
	SchedyHelper.extract_to_worker_storage(robot_tests)
	SchedyHelper.link_archive_to_task_folder(robot_tests,task["id"])
end

#INFO: Post processing function for robot framework results.
#Uses result_parser -which uses Teresa gem- for parsing XUnit files produced by pybot.

def self.robot_post_processing(task,task_directory)
	p ["Post processing robot tests",task["test_name"],task_directory].join(': ')
	$scheduler_uri ||= 'http://scheduler-server'
	robot_file_path = [task_directory,'xunit.xml'].join('/')
	value_endpoint = [$scheduler_uri,'tasks/',task["id"],"/tags"].join('/')
	#thanks mr. bundler
	gemfile_path = [SCHEDULER_WORKER_ROOT,'project','bin','Gemfile'].join('/')
	if not File.file?(robot_file_path)
		puts 'xunit.xml not found ! no result will be reported.'
		return 0
	end
	result_parser_path = [SCHEDULER_WORKER_ROOT,'project','bin','result_parser'].join('/')
	robot_result_parser_script = ["BUNDLE_GEMFILE='#{gemfile_path}'",result_parser_path].join(' ')
	test_parse_command = [robot_result_parser_script,robot_file_path].join(' ')
	puts "Parsing robot test results, executing command : #{test_parse_command}"
	stats_json = JSON.parse(`#{test_parse_command}`)[0]
	if stats_json["result"] == "passed" then result = "PASS" end
	if stats_json["result"] == "failed" then result = "FAIL" end
	reason = stats_json["reason"]
	puts ["Results JSON:",stats_json,'Uploading to server.'].join(' ')
	result_res = Typhoeus.post(value_endpoint,body: {task_id: task["id"], property: "result", value: result })
	reason_res = Typhoeus.post(value_endpoint,body: {task_id: task["id"], property: "reason", value: reason })
	return 0
end

task = parse_task_config(task)
task_id = task["id"]
task_directory = [SCHEDULER_WORKER_ROOT,'storage','tasks',task_id].join('/')
Dir.chdir(task_directory)
get_robot_tests(task)
Dir.chdir(task_directory)
create_robot_resource_file(task)
Dir.chdir(task_directory)
execute_robot_tests(task)
Dir.chdir(task_directory)
robot_post_processing(task,task_directory)
