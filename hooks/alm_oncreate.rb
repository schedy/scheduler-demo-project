#!/bin/env ruby

require 'bundler/setup'

require 'ostruct'
require 'rest_client'
require "awesome_print"
require 'json'
require 'fcntl'
output_stream = IO.for_fd(STDOUT.fcntl(Fcntl::F_DUPFD))
STDOUT.reopen("/dev/null","w")

def manual_wi_parser(wi)
	wi = JSON.parse(wi)
	description = OpenStruct.new
	if wi
		payload = wi
		description.default_project = "obsprojectname"#payload["default_project"].to_s
		description.event_type = payload["event_type"] || "manual"
		description.author = payload["tester_name"]
		#               description.url_gerrit = payload["url_gerrit"].to_s
		description.package_project = payload["package_project"] ? {payload["package_name"].to_s => payload["package_project"]} : {payload["package_name"].to_s => "obsprojectname"}
		description.package_arch = payload["package_arch"] ? {payload["package_name"].to_s => payload["target_arch"]} : {payload["package_name"].to_s => "i586"}
		description.package_repository = payload["package_repository"] ? {payload["package_name"].to_s => payload["target_repository"]} : {payload["package_name"].to_s => "dut"}
		description.triggered_by_package = payload["package_name"]#payload["package"].to_s
		description.project = payload["target_project"] ? payload["target_project"] : "obsprojectname"
		description.multiplier = 1#payload["multiplier"].to_i
		#description.target_tag = [payload["target_tag"]]
		description.run_id = payload["run_id"]
		description.target_name = [payload["target_name"]]
		description.hooks = {"finished":["alm_onfinish.rb"]}
		#description.target_resources = payload["target_resources"]
	end
	return description
end

begin
	#Parse workitem, create tasks and add tags.
	i = STDIN.read
	workitem_description = manual_wi_parser(i)
	Dir.chdir("project/creator")

	require_relative '../creator/schedy-execution-creator.rb'
	require_relative '../helpers.rb'

	execution = workitem_description_to_execution_description(workitem_description)
	execution["data"] = i
	output_stream.puts JSON.dump(execution)
end
